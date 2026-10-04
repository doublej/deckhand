"""The manager itself: one Claude Agent SDK conversation the daemon keeps going.

Three decisions are the whole of this file.

**One run per thing said, resumed rather than held open.** Nothing here keeps a `ClaudeSDKClient`
alive. Each turn is a `query()` carrying `resume=` the last run's session id, which is what makes
the conversation survive a daemon restart taken mid-sentence — and this daemon is restarted often
enough that a long-lived subprocess would be the thing that broke. The id lives in the
conversation file beside the entries, so a file that has the history also has the thread.

**The phone never waits for a model.** `ask` appends what was said and returns; the worker
answers into the same file and the panel reads it on its next poll. That is the shape `briefings`
settled on, for the reason its own module gives: a model run is seconds and an HTTP client has a
twenty-second timeout, and the two do not belong on one call.

**A resume that fails starts a new conversation rather than a dead manager.** An SDK session can
go — a machine restart, a pruned transcript — and a manager that answered every message with the
same resume error would be permanently broken with no way back from the phone. So a run that
fails *with* a resume is tried once more without one, and the panel is told in a line that the
thread was lost.
"""

from __future__ import annotations

import asyncio
import time

from .. import prompts, push
from ..config import data_dir
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
    """Answer what has been said, one run at a time, forever."""
    while True:
        if not _queue:
            await _sleep(IDLE)
            continue
        await _answer(_queue.pop(0))


async def _sleep(seconds: float) -> None:
    try:
        await asyncio.wait_for(_wake.wait(), timeout=seconds)
    except TimeoutError:
        pass
    _wake.clear()


async def _answer(text: str) -> None:
    global _working, _partial, _doing
    _working = True
    try:
        spoke, error = await _run(text, talk.resumes())
        if error and not spoke and talk.resumes():
            log.warning("the manager could not resume, starting a new conversation: %s", error)
            speak("note", "That conversation could not be picked up again, so this is a new "
                             "one. Nothing before this line is in front of me any more.")
            talk.resumes_at("")
            spoke, error = await _run(text, "")
        if error and not spoke:
            speak("note", error)
    finally:
        _working = False
        _partial = _doing = ""


async def _run(text: str, resume: str) -> tuple[bool, str | None]:
    """One turn. Returns whether anything was said, and the failure if there was one.

    Every text block is appended as it arrives rather than collected and written at the end, so
    the panel fills in while the model is still working — which for a run that calls four tools
    is the difference between a live conversation and a spinner.
    """
    try:
        from claude_agent_sdk import (
            AssistantMessage,
            ClaudeAgentOptions,
            ClaudeSDKError,
            ResultMessage,
            StreamEvent,
            TextBlock,
            ToolUseBlock,
            query,
        )
    except ImportError:
        return False, "claude-agent-sdk is not installed on this Mac."

    options = ClaudeAgentOptions(
        model=MODEL,
        # Decided once per run, when it starts. A run is seconds; a person who puts the phone
        # away halfway through still gets each message pushed, and `<lock_screen>` in the base
        # prompt is what makes the first line of every one of them fit there.
        system_prompt=SYSTEM_PROMPT if watched() else f"{SYSTEM_PROMPT}\n\n{AWAY.body}",
        # Token by token, so the panel can draw the sentence being written rather than a dot
        # until the whole block is done. Only `_partial` sees these; the file still gets blocks.
        include_partial_messages=True,
        # `allowed_tools` only auto-approves; `tools=[]` is what actually removes the built-ins.
        # Together they are the whole surface: twelve in-process functions and no shell, no
        # file access and no network. `bypassPermissions` is safe for exactly that reason —
        # there is nobody at the daemon to answer a permission prompt.
        tools=[],
        mcp_servers={"deckhand": doing.server(MANAGER.settings["tools"])},
        strict_mcp_config=True,
        allowed_tools=list(doing.TOOLS),
        permission_mode="bypassPermissions",
        max_turns=MAX_TURNS,
        thinking={"type": MANAGER.settings["thinking"]},
        # A stable folder that is not a repo: it is where the SDK files this conversation's own
        # transcript, and `resume` finds it by that key. The daemon's own working directory is
        # whatever launchd started it in, which is not something to hang a thread off.
        cwd=str(data_dir()),
        # No setting sources: loading the person's config would start every MCP server they have
        # configured, which cost more than a minute — measured once already, for the briefings.
        setting_sources=[],
        **({"resume": resume} if resume else {}),
    )

    async def collect() -> tuple[bool, str | None]:
        global _partial, _doing
        spoke = False
        async for message in query(prompt=text, options=options):
            if isinstance(message, StreamEvent):
                _follow(message.event)
                continue
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, ToolUseBlock):
                        _doing = _bare(block.name)
                    elif isinstance(block, TextBlock) and block.text.strip():
                        _partial = ""
                        await asyncio.to_thread(speak, "manager", block.text)
                        spoke = True
            session_id = getattr(message, "session_id", "")
            if session_id:
                talk.resumes_at(session_id)
            if isinstance(message, ResultMessage):
                if message.is_error:
                    return spoke, f"the model returned an error: {message.subtype}"
                if not spoke and (message.result or "").strip():
                    await asyncio.to_thread(speak, "manager", message.result)
                    spoke = True
                return spoke, None if spoke else "the model returned nothing."
        return spoke, None if spoke else "the model returned nothing."

    task = asyncio.create_task(collect())
    try:
        # Shielded for the reason `summarize` gives: on a timeout the task is dropped rather
        # than waited on while the CLI unwinds, which is what left the phone hanging.
        return await asyncio.wait_for(asyncio.shield(task), timeout=TIMEOUT)
    except TimeoutError:
        task.cancel()
        log.warning("the manager did not answer within %ss", TIMEOUT)
        return False, f"I did not get an answer back within {TIMEOUT} seconds."
    except (ClaudeSDKError, OSError) as error:
        log.warning("the manager failed: %s", error)
        return False, f"the model could not be reached: {error}"


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
