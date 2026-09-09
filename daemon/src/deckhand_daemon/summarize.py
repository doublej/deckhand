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
import re
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
or asking something, that belongs in the opening sentences, not in a bullet at the bottom.

TASKS. After the briefing, on a line of its own, write `:tasks` and then one line for each
thing this person has asked this session for, oldest first. This is their list, not yours: it
comes from what they asked for in their own words, shortened to a few. Never break an ask down
into steps, never merge two asks into one, and never add a task they did not ask for — not a
step you decided to take, not a check you ran, not something that seemed like a good idea.

Each line is a box and the ask, and the box is the only thing you have to judge:

  - [ ]   nothing has been done about it yet
  - [~]   work has started on it and it is not finished
  - [x]   finished, and nothing about it is still open

So a list looks like this, and like nothing else:

  :tasks
  - [x] delete the menu bar app
  - [~] the files tab
  - [ ] privacy policy URL

Nothing else goes on these lines: no status words, no explanations, no dates, no `code` or
**bold**. At most twelve, and if they have asked for nothing, write `:tasks` and stop.
Everything above `:tasks` is the briefing and follows the format above; nothing below it is."""

# `- [x] the ask`, in the three states the person cares about.
TASK_LINE = re.compile(r"^\s*[-*]?\s*\[([ x~×✓])\]\s*(.+?)\s*$", re.IGNORECASE)
TASK_STATES = {" ": "todo", "~": "doing", "x": "done", "×": "done", "✓": "done"}
MARKER = ":tasks"
MAX_TASKS = 12


def split_tasks(summary: str | None) -> tuple[str | None, list[dict]]:
    """The briefing and the task list, which arrive as one answer and are two things.

    One model run writes both: the transcript it needs to read to say what happened is the
    same transcript the list comes out of, so asking twice would be paying twice for one read.
    """
    if not summary or MARKER not in summary:
        return summary, []
    prose, _, block = summary.partition(MARKER)
    tasks = []
    for line in block.splitlines():
        if match := TASK_LINE.match(line):
            box, text = match.group(1).lower(), match.group(2)
            tasks.append({"text": text, "state": TASK_STATES.get(box, "todo")})
    return prose.strip() or None, tasks[:MAX_TASKS]


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

# What the briefings have cost since the daemon started, per session and in total. Kept in
# memory on purpose: it answers "is this thing expensive?", which is a question about now.
# A cache hit costs nothing and is counted as nothing, which is the point of the cache.
_spent: dict[str, dict[str, int]] = {}


def spent(session_id: str | None = None) -> dict[str, int]:
    """What the briefings have cost: for one session, or every session added up.

    Three numbers, because three is what anyone would ask: how many were written, what they
    were billed, and how much of the reading was already cached. Cache reads are counted apart
    from the rest — they are most of the traffic and almost none of the cost, and adding them
    in would make the whole thing look ten times more expensive than it is.
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
    """One run's usage, added to this session's running total.

    Cache reads are the whole point of the cache, so they are not counted — what is counted is
    what was actually asked of the model.
    """
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
    blob = f"{asks}\n\nSINCE THEY LAST SPOKE\n{activity}" if asks.strip() else activity
    key = (session_id, hashlib.sha256(blob.encode()).hexdigest())
    cached = _cached(key)
    if cached:
        return cached, None
    summary, error, usage = await _run(blob)
    _count(session_id, usage)
    if summary:
        _store(key, summary)
    return summary, error


async def _run(activity: str) -> tuple[str | None, str | None, dict | None]:
    """One turn, no tools, low effort. Every expected failure comes back as a sentence."""
    try:
        from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKError, ResultMessage, query
    except ImportError:
        log.warning("summary skipped: claude-agent-sdk is not installed")
        return None, "claude-agent-sdk is not installed", None

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
