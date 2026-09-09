"""What a session did while you were away, in four sentences a phone can show.

The transcript tail is far too long to read on a phone, so a small model reads it instead.
The phone polls, so the same activity blob arrives again and again; a short-lived cache keyed
on the blob's hash means only genuinely new activity costs a model run. Auth comes from the
Claude Code keychain, which the SDK reaches through the `user` setting source — the daemon
runs under launchd and has no API key.
"""

from __future__ import annotations

import asyncio
import hashlib
import time

from .log import log

MODEL = "claude-sonnet-5"
TIMEOUT = 60
TTL = 120
MAX_ENTRIES = 32
SYSTEM_PROMPT = """You summarise what a Claude Code session did since the user last spoke.

Write 2 to 4 short sentences of plain text. No markdown, no bullets, no headings, no preamble
such as "The assistant" or "This session" — start with the work itself, in the past tense.
Name the files and commands that matter, skip the rest. Answer with the summary and nothing
else."""

# (session_id, activity hash) -> (summary, written_at). Cleared by tests.
_cache: dict[tuple[str, str], tuple[str, float]] = {}


async def summarize(session_id: str, activity: str) -> tuple[str | None, str | None]:
    """Returns (summary, error). Never raises: a session without a summary is still usable."""
    if not activity.strip():
        return None, None
    key = (session_id, hashlib.sha256(activity.encode()).hexdigest())
    cached = _cached(key)
    if cached:
        return cached, None
    summary, error = await _run(activity)
    if summary:
        _store(key, summary)
    return summary, error


async def _run(activity: str) -> tuple[str | None, str | None]:
    """One turn, no tools, low effort. Every expected failure comes back as a sentence."""
    try:
        from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKError, ResultMessage, query
    except ImportError:
        log.warning("summary skipped: claude-agent-sdk is not installed")
        return None, "claude-agent-sdk is not installed"

    options = ClaudeAgentOptions(
        model=MODEL,
        system_prompt=SYSTEM_PROMPT,
        tools=[],
        allowed_tools=[],
        max_turns=1,
        effort="low",
        # No setting sources: loading the user's config would start every MCP server the
        # person has configured, which took longer than the whole summary is worth.
        setting_sources=[],
    )

    async def collect() -> tuple[str | None, str | None]:
        async for message in query(prompt=activity, options=options):
            if isinstance(message, ResultMessage):
                if message.is_error:
                    return None, f"the model returned an error: {message.subtype}"
                text = (message.result or "").strip()
                return text or None, None if text else "the model returned nothing"
        return None, "the model returned nothing"

    task = asyncio.create_task(collect())
    try:
        # Shielded: on a timeout we drop the task rather than wait for the CLI to unwind,
        # which is what left the phone hanging.
        return await asyncio.wait_for(asyncio.shield(task), timeout=TIMEOUT)
    except TimeoutError:
        task.cancel()
        log.warning("summary timed out after %ss", TIMEOUT)
        return None, f"the model did not answer within {TIMEOUT}s"
    except (ClaudeSDKError, OSError) as error:
        log.warning("summary failed: %s", error)
        return None, f"the model could not be reached: {error}"


def _cached(key: tuple[str, str]) -> str | None:
    entry = _cache.get(key)
    if not entry or time.monotonic() - entry[1] > TTL:
        return None
    return entry[0]


def _store(key: tuple[str, str], summary: str) -> None:
    """Drop the oldest entry when full — a phone watches a handful of sessions, not thousands."""
    if len(_cache) >= MAX_ENTRIES:
        del _cache[min(_cache, key=lambda k: _cache[k][1])]
    _cache[key] = (summary, time.monotonic())
