"""What a session did, as plain text for a model to summarise. The briefing's reading of a
transcript, beside `transcripts`, which reads one for the phone."""

from __future__ import annotations

import json

from .entries import text_of, wrote_of
from .transcripts import TAIL_WINDOWS, parse_line, tail_lines, transcript_path

#: How much of one thing said reaches a briefing, and of the last thing, which carries the result.
SAID = 600
LAST_SAID = 2000


def activity_since_last_user(session_id: str, cap: int = 12_000) -> str:
    """What the session has done since the person last spoke, as plain text to summarise.

    Unlike `read_turns` this keeps the tool calls: what a session did is mostly what it ran.

    **Only the person starts it over.** Another agent's message, a background task's notice and
    a compaction summary arrive as `user` entries too — 40% of them, measured over this Mac's
    transcripts — and each one used to wipe the activity back to a few lines, which the
    briefing then summarised as the whole story. They are lines in it now, saying who.
    """
    path = transcript_path(session_id)
    if path is None:
        return ""
    lines = tail_lines(path, TAIL_WINDOWS[1])
    events: list[str] = []
    for raw in lines:
        entry = parse_line(raw)
        if entry is None or entry.get("isSidechain"):
            continue
        if entry.get("type") == "user" and (said := text_of(entry)) is not None:
            if who := wrote_of(entry):
                events.append(f"{who} said: {said.strip()[:SAID]}")
            else:
                events = []  # the person spoke: everything before that is old news
            continue
        events.extend(describe(entry, said=LAST_SAID))
    # The last thing it said is kept whole enough to carry its result; the rest are context.
    spoken = [i for i, line in enumerate(events) if line.startswith("said: ")]
    for i in spoken[:-1]:
        events[i] = events[i][: len("said: ") + SAID]
    return "\n".join(events)[-cap:]


def describe(entry: dict, said: int = 600) -> list[str]:
    """One line per thing the session did, in the order it did them.

    A tool is named by its own `description` where it wrote one: a Bash call's command comes
    first in its input, so cutting the input short always cut off the one readable part.
    """
    if entry.get("type") != "assistant":
        return []
    content = entry.get("message", {}).get("content")
    if not isinstance(content, list):
        return []
    lines = []
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "text" and block.get("text", "").strip():
            lines.append(f"said: {block['text'].strip()[:said]}")
        elif block.get("type") == "tool_use":
            given = block.get("input") if isinstance(block.get("input"), dict) else {}
            detail = str(given.get("description") or "")[:200] or json.dumps(given)[:200]
            lines.append(f"ran {block.get('name', 'a tool')}: {detail}")
    return lines
