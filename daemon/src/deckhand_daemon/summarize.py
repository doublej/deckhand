"""What a session did while you were away, in a briefing a phone can show.

The transcript tail is far too long to read on a phone, so a small model reads it instead. This
module is only the running of one — what it says and which model says it is `prompts/briefing.md`: when a briefing is worth writing, and where the last one is
kept, is `briefings`. The daemon uses Claude Code's existing authentication without loading
user settings or their MCP servers.
"""

from __future__ import annotations

import asyncio

from . import prompts, tasks
from .log import log

BRIEFING = prompts.load("briefing")
MODEL = BRIEFING.settings["model"]
TIMEOUT = BRIEFING.settings["timeout"]
MAX_TURNS = BRIEFING.settings["max_turns"]
SYSTEM_PROMPT = BRIEFING.body


def headline(summary: str | None) -> str | None:
    """The first line: what this person needs to know or do, for the list of sessions.

    Taken from the briefing rather than asked for separately, because a second model run to
    restate the first line of the first one is a second run for nothing. The brief guarantees
    the line stands alone; this only has to survive a model that ignored it and opened with a
    heading or a bullet anyway.
    """
    for line in (summary or "").splitlines():
        stripped = line.strip().removeprefix("## ").removeprefix("- ").strip()
        if stripped:
            return stripped.replace("**", "").replace("`", "")
    return None


# What the briefings have cost since the daemon started, per session and in total. Kept in
# memory on purpose: it answers "is this thing expensive?", which is a question about now.
# A cache hit costs nothing and is counted as nothing, which is the point of the cache.
_spent: dict[str, dict[str, int]] = {}


def spent(session_id: str | None = None) -> dict[str, int]:
    """What the briefings have cost: for one session, or every session added up.

    Three numbers, because three is what anyone would ask: how many were written, what they
    were billed, and how much of the reading Anthropic served from its own prompt cache. Those
    reads are counted apart — they are most of the traffic and almost none of the cost, and
    adding them in would make the whole thing look ten times more expensive than it is.
    """
    counts = _spent.get(session_id, {}) if session_id is not None else _total()
    return {
        "runs": counts.get("runs", 0),
        "tokens": counts.get("input_tokens", 0) + counts.get("output_tokens", 0),
        "cached": counts.get("cache_read_input_tokens", 0),
    }


def _total() -> dict[str, int]:
    total: dict[str, int] = {}
    for counts in _spent.values():
        for name, count in counts.items():
            total[name] = total.get(name, 0) + count
    return total


def _count(session_id: str, usage: dict | None) -> None:
    """One run's usage, added to this session's running total."""
    if not isinstance(usage, dict):
        return
    counts = _spent.setdefault(session_id, {})
    for name in ("input_tokens", "output_tokens",
                 "cache_creation_input_tokens", "cache_read_input_tokens"):
        if isinstance(value := usage.get(name), int):
            counts[name] = counts.get(name, 0) + value
    counts["runs"] = counts.get("runs", 0) + 1


async def summarize(
    session_id: str, activity: str, asks: str = ""
) -> tuple[str | None, str | None]:
    """Returns (summary, error). Never raises: a session without a summary is still usable."""
    if not activity.strip() and not asks.strip():
        return None, None
    summary, error, usage = await _run(_prompt(session_id, activity, asks), session_id)
    _count(session_id, usage)
    return summary, error


def _prompt(session_id: str, activity: str, asks: str) -> str:
    """The evidence in tags the system prompt names, and the ask after it.

    Uppercase headings left the boundary between what to do and what to read implicit, which is
    the boundary that matters here: everything in `asks` and `activity` is another session's
    words, and some of them are instructions to somebody. Tags give the system prompt something
    to point at, and an empty `asks` no longer leaves the transcript unlabelled.
    """
    blocks = [f"<task_list>\n{tasks.render(session_id)}\n</task_list>"]
    if asks.strip():
        blocks.append(f"<asks>\n{asks}\n</asks>")
    if activity.strip():
        blocks.append(f"<activity>\n{activity}\n</activity>")
    blocks.append(BRIEFING.settings["ask"])
    return "\n\n".join(blocks)


async def _run(activity: str, session_id: str) -> tuple[str | None, str | None, dict | None]:
    """No extended thinking; only the three tools that manage this session's list.

    Every expected failure comes back as a sentence. `bypassPermissions` is safe precisely
    because of how short that list of tools is: three in-process functions that write one JSON
    file belonging to this session. There is nobody at the daemon to answer a prompt.
    """
    try:
        from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKError, ResultMessage, query
    except ImportError:
        log.warning("summary skipped: claude-agent-sdk is not installed")
        return None, "claude-agent-sdk is not installed", None

    options = ClaudeAgentOptions(
        model=MODEL,
        system_prompt=SYSTEM_PROMPT,
        # allowed_tools auto-approves calls; tools=[] actually removes built-in tools.
        tools=[],
        mcp_servers={"tasks": tasks.server(session_id, BRIEFING.settings["tools"])},
        strict_mcp_config=True,
        allowed_tools=list(tasks.TOOLS),
        permission_mode="bypassPermissions",
        # Enough turns to work through a list and then write: one call per change, and a dozen
        # changes at once only happens on a session nobody has looked at all day.
        max_turns=MAX_TURNS,
        # Haiku 4.5 has no effort control, so `thinking` in briefing.md is the only lever.
        thinking={"type": BRIEFING.settings["thinking"]},
        # No setting sources: loading the user's config would start every MCP server the
        # person has configured, which took longer than the whole summary is worth.
        setting_sources=[],
    )

    async def collect() -> tuple[str | None, str | None, dict | None]:
        async for message in query(prompt=activity, options=options):
            if isinstance(message, ResultMessage):
                used = message.usage if isinstance(message.usage, dict) else None
                if message.is_error:
                    return None, f"the model returned an error: {message.subtype}", used
                text = (message.result or "").strip()
                return text or None, None if text else "the model returned nothing", used
        return None, "the model returned nothing", None

    task = asyncio.create_task(collect())
    try:
        # Shielded: on a timeout we drop the task rather than wait for the CLI to unwind,
        # which is what left the phone hanging.
        return await asyncio.wait_for(asyncio.shield(task), timeout=TIMEOUT)
    except TimeoutError:
        task.cancel()
        log.warning("summary timed out after %ss", TIMEOUT)
        return None, f"the model did not answer within {TIMEOUT}s", None
    except (ClaudeSDKError, OSError) as error:
        log.warning("summary failed: %s", error)
        return None, f"the model could not be reached: {error}", None
