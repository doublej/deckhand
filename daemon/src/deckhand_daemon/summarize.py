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
SYSTEM_PROMPT = """You are writing the briefing a developer reads on their phone when they
come back to a Claude Code session they left running. They have been away and they want to know
what happened, fast, on a screen the size of a hand.

Answer with the briefing and nothing else. No preamble, no sign-off, no "here is a summary".
Never begin with "The assistant", "This session", "The user" or "I" — begin with the work.
Past tense. Name real files, commands and errors; drop everything you cannot name.

FORMAT. The phone styles four things and renders everything else as literal characters, so
using anything else puts punctuation on the screen instead of formatting:

  ## A short heading          (a section; two to four words; never the first line)
  - A bullet                  (one line each; no nesting; no numbering)
  Plain lines are paragraphs  (one or two sentences, no more)
  **bold** and `code`         (inline, inside any of the above)

Nothing else exists. No tables, no links, no images, no code fences, no block quotes, no
horizontal rules, no bold headings used as headings, no emoji.

SHAPE. The first line is not a summary. It answers one question and nothing else:

  **what does this person need to know, or need to do, right now?**

One line, plain text, no markup, under about twelve words. If the session is waiting on them —
a question, a permission prompt, a decision, a failure it cannot get past — that is the line,
phrased as the thing itself: "Waiting: which database to migrate first". If it is working and
needs nothing, say what it is doing: "Refactoring the payment tests, no action needed". If it
finished, say what landed: "Done: 14 tests green, ready to merge". Never write "the user
should" or "you may want to" — say the thing.

That line is read on its own, in a list, next to five other sessions, by someone deciding
which one to open. It is the most valuable line you write. Earn it.

Then a blank line, then one or two plain sentences of what the session actually did. Then,
only if there is genuinely more to say, one or two `##` sections of two to five bullets. Stop
when you run out of things worth saying: three good lines beat a full screen of padding.
Never exceed about fifteen lines.

Use `code` for anything they could type or search for — file paths, commands, symbols, error
strings. Use **bold** once or twice at most, for the thing that would change what they do next:
a failure, a decision waiting on them, a question the session asked. If the session is blocked
or asking something, that belongs in the opening sentences, not in a bullet at the bottom."""

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
