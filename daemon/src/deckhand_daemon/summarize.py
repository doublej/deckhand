"""What a session did while you were away, in four sentences a phone can show.

The transcript tail is far too long to read on a phone, so a small model reads it instead. This
module is only the writing of one: when a briefing is worth writing, and where the last one is
kept, is `briefings`. Auth comes from the Claude Code keychain, which the SDK reaches through
the `user` setting source — the daemon runs under launchd and has no API key.
"""

from __future__ import annotations

import asyncio

from . import tasks
from .log import log

MODEL = "claude-haiku-5"
TIMEOUT = 60
MAX_TURNS = 16
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

THE LIST. Separately from the briefing, this person keeps a list of the things they have asked
this session for. You do not write that list out, and nothing about it goes in the briefing. It is
shown to you below with an id on every line, and you change it only by calling these:

  add_task(text)              an ask of theirs that is not in the list yet
  set_task_state(id, state)   todo (nothing done yet) / doing (started) / done (finished)
  drop_task(id, reason)       only when they withdrew it — it warns, and the entry is lost

These are rules, not preferences:

  - Only their asks, in their own words, shortened to a few. Never a step you decided to take,
    never a check you ran, never two of their asks merged, never one broken into steps.
  - Never add what is already there. The list is in front of you.
  - Never reword, renumber or re-order what is there. The ids are the list's memory, and the
    person reads this list across days.
  - Finished is `done`, never dropped.
  - Work through the list once, then write the briefing.

Answer with the briefing alone: the tool calls are the list, the answer is the prose."""


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
    blob = f"{asks}\n\nSINCE THEY LAST SPOKE\n{activity}" if asks.strip() else activity
    summary, error, usage = await _run(f"THE LIST SO FAR\n{tasks.render(session_id)}\n\n{blob}",
                                      session_id)
    _count(session_id, usage)
    return summary, error


async def _run(activity: str, session_id: str) -> tuple[str | None, str | None, dict | None]:
    """Low effort, and the only tools it has are the three that manage this session's list.

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
        mcp_servers={"tasks": tasks.server(session_id)},
        allowed_tools=list(tasks.TOOLS),
        permission_mode="bypassPermissions",
        # Enough turns to work through a list and then write: one call per change, and a dozen
        # changes at once only happens on a session nobody has looked at all day.
        max_turns=MAX_TURNS,
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
