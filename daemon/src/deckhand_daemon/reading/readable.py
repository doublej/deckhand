"""The whole transcript, in order, as lines a person can read.

Not the same job as `transcripts.read_turns`, which shows the conversation and drops everything
else, and not the same as handing over the JSONL, which was the first attempt: a single entry in
a working session runs to tens of kilobytes of syntax, so half a megabyte of file came out as ten
lines on the phone, nine of them punctuation.

Everything is here — every prompt, every reply, every tool call and its result, the inbox, the
compactions, the mode changes — and the syntax is not. That is the whole difference: this is for
the moment when the app's reading of the transcript looks wrong and the only way to tell is to
see what the file actually says.
"""

from __future__ import annotations

import json

from .transcripts import (
    TAIL_WINDOWS,
    absorbed,
    describe,
    parse_line,
    tail_lines,
    text_of,
    transcript_path,
)

# One entry, on a phone. Long enough for a paragraph of prose or a stack trace's first frames.
MAX_LINE = 1_200
# How many lines are worth carrying to a phone at once. A busy day is a few hundred.
MAX_LINES = 1_500
# Entries that are Claude Code talking to itself about the session rather than anything that
# happened in it. They are in the file, they are not events, and one per turn is noise.
# `attachment` is the biggest of them by a mile — 654 of the 1,300 entries in one real day —
# and it is Claude Code stapling context onto a turn, not a thing that happened. The exception is
# the one attachment that *is* a thing that happened: a message that arrived mid-run, caught
# above by `absorbed` before this list is consulted.
DULL = {"last-prompt", "custom-title", "agent-name", "mode", "permission-mode", "atis-latch",
        "bridge-session", "file-history-snapshot", "file-history-delta", "attachment"}


def plain_tail(session_id: str, limit: int = MAX_LINES) -> list[str]:
    """Every event in the tail of this session's transcript, oldest first."""
    path = transcript_path(session_id)
    if path is None:
        return []
    lines: list[str] = []
    for raw in tail_lines(path, TAIL_WINDOWS[1]):
        entry = parse_line(raw)
        if entry is not None:
            lines.extend(_lines_of(entry))
    return lines[-limit:]


def _lines_of(entry: dict) -> list[str]:
    """One entry, as none, one or several lines. A reply and the tools it ran are several."""
    kind = entry.get("type")
    clock = _clock(entry)
    if (interjection := absorbed(entry)) is not None:
        return [f"{clock} YOU {_flat(interjection)}"]
    if kind in DULL:
        return []
    if kind == "user":
        return _said(clock, entry)
    if kind == "assistant":
        return _did(clock, entry)
    if kind == "queue-operation":
        content = _flat(entry.get("content") or "")
        return [f"{clock} INBOX {entry.get('operation')} {content}".rstrip()]
    if kind == "summary":
        return [f"{clock} COMPACTED {_flat(entry.get('summary') or '')}"]
    if kind == "system":
        return [f"{clock} SYSTEM {_flat(str(entry.get('content') or entry.get('subtype') or ''))}"]
    return [f"{clock} {str(kind).upper()}"]


def _said(clock: str, entry: dict) -> list[str]:
    """A user entry is either something the person said or the answer to a tool call."""
    if spoken := text_of(entry):
        return [f"{clock} YOU {_flat(spoken)}"]
    return [f"{clock}   → {_flat(text)}" for text in _results(entry)]


def _did(clock: str, entry: dict) -> list[str]:
    """A reply, and every tool it ran, in the order they are in the entry."""
    lines = []
    for line in describe(entry):
        if line.startswith("said: "):
            lines.append(f"{clock} CLAUDE {_flat(line.removeprefix('said: '))}")
        else:
            lines.append(f"{clock}   ← {_flat(line)}")
    return lines


def _results(entry: dict) -> list[str]:
    """What came back from the tools, out of the user entry that carries them."""
    content = entry.get("message", {}).get("content")
    if not isinstance(content, list):
        return []
    out = []
    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_result":
            continue
        mark = "error" if block.get("is_error") else "ok"
        out.append(f"{mark}: {_text(block.get('content'))}")
    return out


def _text(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(
            b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"
        )
    return json.dumps(content)[:MAX_LINE] if content else ""


def _flat(text: str) -> str:
    """One line per event. A wrapped paragraph is readable; a line that is secretly forty is not,
    and the phone draws one `Text` per line here."""
    return " ".join(str(text).split())[:MAX_LINE]


def _clock(entry: dict) -> str:
    """Just the time. The date is the same day nearly always, and it costs ten characters."""
    stamp = str(entry.get("timestamp") or "")
    return stamp[11:19] if len(stamp) >= 19 else "        "
