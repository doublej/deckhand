"""The manager itself: one Claude Agent SDK conversation the daemon keeps going.

Three decisions are the whole of this file.

**Held open, so it is a session like any other.** One `ClaudeSDKClient` lives as long as the
daemon does. Claude Code lists a running process under `~/.claude/sessions/` with an inbox
socket, so while it is held other sessions find it by name (`deckhand-manager`) and message it;
the turn their message starts is read here like the panel's own. It used to be one `query()` per
thing said, which was alive for seconds and so could never be found. A daemon restart ends the
process and the next one reopens it with `resume=` the session id, which lives in the
conversation file beside the entries, so a file that has the history also has the thread.

**The phone never waits for a model.** `ask` appends what was said and returns; the worker
answers into the same file and the panel reads it on its next poll. That is the shape `briefings`
settled on, for the reason its own module gives: a model run is seconds and an HTTP client has a
twenty-second timeout, and the two do not belong on one call.

**A resume that fails starts a new conversation rather than a dead manager.** An SDK session can
go — a machine restart, a pruned transcript — and a manager that failed to reopen the same thread
forever would be permanently broken with no way back from the phone. So a session that never
answered *with* a resume is opened once more without one, and the panel is told in a line that
the thread was lost.
"""

from __future__ import annotations

import asyncio
import time

from .. import prompts, push, sessions
from ..config import claude_cli, data_dir
from ..log import log
from . import doing, talk

MANAGER = prompts.load("manager")
#: Added to the system prompt for a run nobody is watching the panel for: every word of it is
#: going to be read off a Lock Screen, so it is written for one.
AWAY = prompts.load("manager-away")
MODEL = MANAGER.settings["model"]
TIMEOUT = MANAGER.settings["timeout"]
MAX_TURNS = MANAGER.settings["max_turns"]
SYSTEM_PROMPT = MANAGER.body
#: What other sessions call it. Claude Code's own `ListAgents` lists it under this, and a
#: `SendMessage` to it lands in the conversation the panel shows.
NAME = "deckhand-manager"
#: How long the worker sleeps when nobody has said anything. It is woken by `ask`, so this is
#: only the ceiling on how late a wake-up that was somehow missed can be.
IDLE = 30.0

#: What has been said and not yet answered, oldest first. In memory rather than in the file: a
#: restart taken mid-run should leave the panel quiet, not answer a question from an hour ago.
_queue: list[str] = []
_wake = asyncio.Event()
_working = False
#: What the model is writing right now and has not finished, and the tool it is in. In memory
#: and never in the file: a half sentence is not an entry, and the next poll replaces it anyway.
_partial = ""
_doing = ""
#: Whether the turn in flight was started by the panel. A turn the session starts on its own is
#: another session's message arriving in its inbox, and its words are not pushed to the phone.
_asked = False
#: Set when a turn ends, so `_ask` knows when to hand over the next thing said.
_ended = asyncio.Event()
#: When the panel last asked for the conversation. The panel polls only while it is on screen,
#: so this is the whole of how the daemon knows whether anybody is reading it.
_seen = 0.0
#: How stale that may be and still count as watched. The panel polls every four seconds at rest.
WATCHED = 10.0


def working() -> bool:
    """Whether a run is in flight. What makes the panel poll fast and draw a thinking line."""
    return _working or bool(_queue)


def progress() -> dict:
    """The run in flight, as far as it has got: the sentence half-written and the tool it is in."""
    return {"partial": _partial, "doing": _doing}


def seen() -> None:
    """The panel just read the conversation."""
    global _seen
    _seen = time.monotonic()


def away() -> None:
    """The phone said it left the panel. Without this, a reply written in the seconds after the
    person put the phone away still counted as watched and was never pushed — measured: the first
    closed-app test sent nothing at all."""
    global _seen
    _seen = 0.0
    log.info("manager: the phone left the panel")


def watched() -> bool:
    """Whether somebody has the panel open, judged by how recently it polled."""
    return time.monotonic() - _seen < WATCHED


def speak(role: str, text: str) -> dict:
    """Write one thing the person should hear, and push it when the panel is not on screen."""
    entry = talk.say(role, text)
    if entry and not watched():
        push.told(entry["text"])
    return entry


def ask(text: str) -> dict:
    """Say something to the manager. Returns the entry it was written as, at once."""
    entry = talk.say("person", text)
    if entry:
        _queue.append(entry["text"])
        _wake.set()
    return entry


def clear() -> dict:
    """Start over. Anything queued goes with it — it was said to a conversation that is gone."""
    _queue.clear()
    return talk.clear()


async def watch() -> None:
    """Hold the manager's session open, forever, and open it again when it goes."""
    while True:
        resume = talk.resumes()
        reached = await _hold(resume)
        if not reached and resume:
            log.warning("the manager could not resume, starting a new conversation")
            speak(
                "note",
                "That conversation could not be picked up again, so this is a new "
                "one. Nothing before this line is in front of me any more.",
            )
            talk.resumes_at("")
        elif not reached:
            await _sleep(IDLE)


async def _sleep(seconds: float) -> None:
    try:
        await asyncio.wait_for(_wake.wait(), timeout=seconds)
    except TimeoutError:
        pass
    _wake.clear()


async def _hold(resume: str) -> bool:
    """One life of the session. Returns whether it ever answered, which is how a dead resume is
    told apart from a session that ran and then went."""
    global _working
    try:
        from claude_agent_sdk import ClaudeSDKClient, ClaudeSDKError
    except ImportError:
        log.warning("claude-agent-sdk is not installed on this Mac; the manager is off")
        await asyncio.sleep(3600)
        return False
    reached = asyncio.Event()
    try:
        async with ClaudeSDKClient(options=_options(resume)) as client:
            reader = asyncio.create_task(_read(client, reached))
            while not reader.done():
                if not _queue:
                    await _sleep(IDLE)
                    continue
                await _ask(client, _queue.pop(0), reader)
            reader.result()
    except (ClaudeSDKError, OSError) as error:
        log.warning("the manager's session went: %s", error)
        if _queue or _working:
            speak("note", f"the model could not be reached: {error}")
    finally:
        _working = False
    return reached.is_set()


async def _ask(client, text: str, reader: asyncio.Task) -> None:
    """Hand one thing said to the session and wait for its turn to end, interrupting a hung one."""
    global _working, _asked
    _working = True
    _asked = True
    _ended.clear()
    # The system prompt is fixed for the life of the session, so a run nobody is watching the
    # panel for carries `<medium>` in front of the words instead — decided per run, as before.
    await client.query(text if watched() else f"{AWAY.body}\n\n{text}")
    ended = asyncio.create_task(_ended.wait())
    done, _ = await asyncio.wait(
        {ended, reader}, timeout=TIMEOUT, return_when=asyncio.FIRST_COMPLETED
    )
    ended.cancel()
    if not done:
        log.warning("the manager did not answer within %ss", TIMEOUT)
        await client.interrupt()
        speak("note", f"I did not get an answer back within {TIMEOUT} seconds.")


async def _read(client, reached: asyncio.Event) -> None:
    """Everything the session says, whoever started the turn: the panel, or another session's
    message arriving in its inbox. Every text block is appended as it arrives, so the panel fills
    in while the model is still working."""
    global _working, _asked, _partial, _doing
    from claude_agent_sdk import (
        AssistantMessage,
        ResultMessage,
        StreamEvent,
        TextBlock,
        ToolUseBlock,
    )

    spoke = False
    async for message in client.receive_messages():
        if session_id := getattr(message, "session_id", "") or (
            getattr(message, "data", None) or {}
        ).get("session_id", ""):
            reached.set()
            if session_id != talk.resumes():
                talk.resumes_at(session_id)
        if isinstance(message, StreamEvent):
            _working = True
            _follow(message.event)
        elif isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, ToolUseBlock):
                    _doing = _bare(block.name)
                    if block.name == "SendMessage":
                        to, said = block.input.get("to", ""), block.input.get("message", "")
                        await asyncio.to_thread(_told, to, said)
                elif isinstance(block, TextBlock) and block.text.strip():
                    _partial = ""
                    # A turn another session started is between agents: it goes in the panel,
                    # never into the person's pocket.
                    say = speak if _asked else talk.say
                    await asyncio.to_thread(say, "manager", block.text)
                    spoke = True
        elif isinstance(message, ResultMessage):
            if message.is_error:
                await asyncio.to_thread(
                    speak, "note", f"the model returned an error: {message.subtype}"
                )
            elif not spoke and _asked:
                await asyncio.to_thread(speak, "note", "the model returned nothing.")
            spoke = _working = _asked = False
            _partial = _doing = ""
            _ended.set()


def _told(to: str, said: str) -> None:
    """The panel's line for a `SendMessage`. A reply goes to the `from` address, a socket path,
    which is named back to the session listening on it."""
    path = to.removeprefix("uds:")
    name = next(
        (s.name for s in sessions.live_sessions(paned_only=False) if s.socket_path == path), to
    )
    talk.say("act", f"told {name}: {said}")


def _options(resume: str):
    from claude_agent_sdk import ClaudeAgentOptions

    return ClaudeAgentOptions(
        model=MODEL,
        system_prompt=SYSTEM_PROMPT,
        # Token by token, so the panel can draw the sentence being written rather than a dot
        # until the whole block is done. Only `_partial` sees these; the file still gets blocks.
        include_partial_messages=True,
        # `allowed_tools` only auto-approves; `tools` is what actually limits the built-ins.
        # Together they are the whole surface: twelve in-process functions, and Claude Code's own
        # `SendMessage` to answer a session that wrote to this one — a socket, never a pane. No
        # shell, no file access and no network. `bypassPermissions` is safe for exactly that
        # reason, and it is also what lets another session's message in: a session that prompts
        # holds every message from one that bypasses, and every session on this Mac bypasses.
        tools=["SendMessage"],
        mcp_servers={"deckhand": doing.server(MANAGER.settings["tools"])},
        strict_mcp_config=True,
        allowed_tools=[*doing.TOOLS, "SendMessage"],
        permission_mode="bypassPermissions",
        max_turns=MAX_TURNS,
        thinking={"type": MANAGER.settings["thinking"]},
        # The installed Claude Code, so the `opus` alias is the newest Opus there is — and so the
        # session speaks the inbox protocol the sessions around it speak.
        cli_path=claude_cli(),
        # A stable folder that is not a repo: it is where the SDK files this conversation's own
        # transcript, and `resume` finds it by that key. The daemon's own working directory is
        # whatever launchd started it in, which is not something to hang a thread off.
        cwd=str(data_dir()),
        # No setting sources: loading the person's config would start every MCP server they have
        # configured, which cost more than a minute — measured once already, for the briefings.
        setting_sources=[],
        # The name other sessions find it by in Claude Code's own listing (`ListAgents`).
        extra_args={"name": NAME},
        **({"resume": resume} if resume else {}),
    )


def _follow(event: dict) -> None:
    """One streamed event: a tool starting, or more of the sentence being written."""
    global _partial, _doing
    kind = event.get("type")
    if kind == "content_block_start":
        block = event.get("content_block") or {}
        if block.get("type") == "tool_use":
            _doing = _bare(block.get("name", ""))
        elif block.get("type") == "text":
            _doing = ""
    elif kind == "content_block_delta":
        delta = event.get("delta") or {}
        if delta.get("type") == "text_delta":
            _partial += delta.get("text", "")


def _bare(name: str) -> str:
    """`mcp__deckhand__list_sessions` is `list_sessions` to anybody reading a phone."""
    return name.rsplit("__", 1)[-1]
