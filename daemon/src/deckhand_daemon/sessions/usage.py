"""What the session's last request filled, and what the week has spent.

Both are read rather than counted: the context number comes off the last assistant entry in the
transcript, and the week comes out of the statusline's own cache, so the phone and the Mac
cannot quote different numbers at each other.

The one exception is a compact, which empties the window without writing an assistant entry —
`last_request` reads the boundary Claude Code leaves instead, or the session goes on reading as
nearly full for as long as nobody speaks to it.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime

from ..reading.transcripts import TAIL_WINDOWS, parse_line, tail_lines, transcript_path
from .live import sessions_dir

# How far back to look for the last request's token usage. Small on purpose: it is the last
# assistant entry in the file, and this is read for every session on every listing.
USAGE_WINDOW = 256 * 1024
# What Claude Code compacts at when nothing says otherwise. The real number is
# `autoCompactWindow` in the person's own settings, which is what is read first — this is only
# the floor under a machine that has never set one.
DEFAULT_WINDOW = 200_000
# A turn Claude Code wrote itself — an interrupt, an API error. Its usage is all zeros, so
# stopping at one reports an empty window and `<synthetic>` as the model, not the real last one.
SYNTHETIC = "<synthetic>"


def _emptied(entry: dict) -> int | None:
    """What a compact left behind, if this entry is the line that recorded one.

    Claude Code writes `{"type":"system","subtype":"compact_boundary"}` with a `compactMetadata`
    carrying `preTokens` and `postTokens`. Measured across 613 boundaries here, every one had
    `postTokens`, and `preTokens` matched the last assistant entry before it to within 0.2%
    (417532 against 416740) — so the two numbers are in the same units and can be swapped in.
    """
    meta = entry.get("compactMetadata")
    post = meta.get("postTokens") if isinstance(meta, dict) else None
    return post if isinstance(post, int) else None


@dataclass(slots=True)
class LastRequest:
    """What the session's last request filled, and what answered it."""

    used: int = 0
    model: str = ""
    effort: str = ""

    def to_json(self, window: int) -> dict:
        """The fragment a listing entry carries. None, not "", for what the transcript has
        not said: a row with no model is a session nothing has answered yet."""
        return {
            "context": {"used": self.used, "limit": window},
            "model": self.model or None,
            "effort": self.effort or None,
        }


def last_request(session_id: str) -> LastRequest:
    """How much of the context window the session's last request filled, and what answered it.

    Every assistant entry carries the usage of the request that produced it, and the whole
    prompt is what was billed as input: what was newly written, what was newly cached, and what
    was read back from cache. Output is not in the window — it is what came out of it.

    The model and the effort are on that same entry, so they cost nothing — and a sidechain is
    skipped for all three alike, because a subagent runs the model it was given, not this one's.

    Read over a small window, because this is asked for every session on every listing and the
    answer is always in the last few entries of the file.

    **A compact is the one moment the last assistant entry stops being the answer.** After one,
    the newest entry in the file is still the request that filled the window right up — so a
    session that has just emptied reads as nearly full, and goes on reading that way for as long
    as nobody speaks to it. Measured on this transcript: 417k of a 450k window reported for 80
    minutes at a session actually holding 21k. So a boundary found before an assistant entry wins
    over it, and only the model and the effort are then read off the older one — those survive a
    compact, the number does not. `/clear` needs nothing of the kind: it starts a new transcript,
    which has no assistant entry to find and so already reads as empty.

    `postTokens` counts the conversation and not the preamble, so it understates by whatever the
    system prompt, the tools and the CLAUDE.md tree weigh — about 58k here, against the 79k the
    next real request reports. Left alone: it is one turn of understating a window with plenty of
    room, where the bug it replaces was telling a person to compact something he had just
    compacted.
    """
    path = transcript_path(session_id)
    if path is None:
        return LastRequest()
    for window in (USAGE_WINDOW, TAIL_WINDOWS[1]):
        emptied = None
        for raw in reversed(tail_lines(path, window)):
            entry = parse_line(raw)
            if entry is None:
                continue
            if emptied is None:
                emptied = _emptied(entry)
            if entry.get("type") != "assistant" or entry.get("isSidechain"):
                continue
            message = entry.get("message", {})
            usage = message.get("usage")
            if not isinstance(usage, dict) or message.get("model") == SYNTHETIC:
                continue
            billed = sum(
                value
                for key in ("input_tokens", "cache_creation_input_tokens",
                            "cache_read_input_tokens")
                if isinstance(value := usage.get(key), int)
            )
            return LastRequest(
                used=billed if emptied is None else emptied,
                model=message.get("model") or "",
                effort=entry.get("effort") or "",
            )
    return LastRequest()


def context_window() -> int:
    """The limit this Mac is configured to compact at, out of Claude Code's own settings."""
    settings = sessions_dir().parent / "settings.json"
    try:
        configured = json.loads(settings.read_text()).get("autoCompactWindow")
    except (OSError, json.JSONDecodeError, AttributeError):
        return DEFAULT_WINDOW
    return configured if isinstance(configured, int) and configured > 0 else DEFAULT_WINDOW


# The statusline's own cache, rewritten every minute by the `com.claude.statusline-cache` agent.
# Deckhand counts no tokens of its own: it reads the object the terminal statusline reads, so the
# phone and the Mac cannot quote different numbers at each other.
WEEK_CACHE = "statusline-cache.json"


def week_usage() -> dict | None:
    """What the week has spent, how far through the week that is, and how long until it resets.

    `pct_used` runs past 100 on a heavy week — the budget is an estimate, not a ceiling — so
    nothing here clamps it. `pct_elapsed` is what makes it mean anything: 152% spent at 51%
    through is the fact, and the 152 alone is not.

    None rather than zeros whenever there is nothing true to say: no cache (another Mac, or no
    agent here), no week in it, a missing field, or a window already closed — a frozen cache
    answering for a week that ended on Sunday is worse than answering nothing.
    """
    cache = sessions_dir().parent / WEEK_CACHE
    try:
        week = json.loads(cache.read_text())["week"]
        ends = datetime.fromisoformat(week["end"])
        spent = {
            "pct_used": round(week["pct_used"]),
            "pct_elapsed": round(week["pct_elapsed"]),
            "days_remaining": float(week["days_remaining"]),
        }
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError):
        return None
    return spent if ends > datetime.now(UTC) else None
