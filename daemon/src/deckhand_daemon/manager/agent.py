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

from .. import prompts
from ..config import data_dir
from ..log import log
from . import doing, talk

MANAGER = prompts.load("manager")
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


def working() -> bool:
    """Whether a run is in flight. What makes the panel poll fast and draw a thinking line."""
    return _working or bool(_queue)


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
    global _working
    _working = True
    try:
        spoke, error = await _run(text, talk.resumes())
        if error and not spoke and talk.resumes():
            log.warning("the manager could not resume, starting a new conversation: %s", error)
            talk.say("note", "That conversation could not be picked up again, so this is a new "
                             "one. Nothing before this line is in front of me any more.")
            talk.resumes_at("")
            spoke, error = await _run(text, "")
        if error and not spoke:
            talk.say("note", error)
    finally:
        _working = False


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
            TextBlock,
            query,
        )
    except ImportError:
        return False, "claude-agent-sdk is not installed on this Mac."

    options = ClaudeAgentOptions(
        model=MODEL,
        system_prompt=SYSTEM_PROMPT,
        # `allowed_tools` only auto-approves; `tools=[]` is what actually removes the built-ins.
        # Together they are the whole surface: eleven in-process functions and no shell, no
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
        spoke = False
        async for message in query(prompt=text, options=options):
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock) and block.text.strip():
                        talk.say("manager", block.text)
                        spoke = True
            session_id = getattr(message, "session_id", "")
            if session_id:
                talk.resumes_at(session_id)
            if isinstance(message, ResultMessage):
                if message.is_error:
                    return spoke, f"the model returned an error: {message.subtype}"
                if not spoke and (message.result or "").strip():
                    talk.say("manager", message.result)
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
