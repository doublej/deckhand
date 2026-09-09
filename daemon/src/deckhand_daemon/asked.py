"""What the person asked this session for, and what it has not picked up yet.

Two readings of the same transcript, and both are about them rather than about the session.
`asks_of` is what the task list is written from; `queued` is the session's own inbox, which is
the one thing in here that is a fact and not a summary — Claude Code writes a `queue-operation`
line every time something joins or leaves it.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime

from .config import data_dir
from .transcripts import (
    MACHINE,
    TAIL_WINDOWS,
    describe,
    parse_line,
    tail_lines,
    text_of,
    transcript_path,
    unwrap,
)

# One ask, kept whole enough that the task list is written from their words and not a gist.
MAX_ASK = 600
# Lines of work kept between one ask and the next — enough to tell how far it got.
MAX_TRACE = 10


def asks_of(session_id: str, cap: int = 8_000) -> str:
    """Every ask the person made in this session, with a trace of what followed each.

    The task list is theirs, not the session's plan, so their words are kept whole and
    everything between them is compressed to the shape of the work: what it ran, and anything
    it said about finishing. Enough to tell not-started from underway from done, no more.
    """
    path = transcript_path(session_id)
    if path is None:
        return ""
    asks: list[tuple[str, list[str]]] = []
    for raw in tail_lines(path, TAIL_WINDOWS[1]):
        entry = parse_line(raw)
        if entry is None or entry.get("isSidechain"):
            continue
        if entry.get("type") == "user" and (said := text_of(entry)):
            asks.append((said[:MAX_ASK], []))
        elif entry.get("type") == "assistant" and asks:
            asks[-1][1].extend(describe(entry))
    # Their words whole, the work between them trimmed to its tail: the list is written from
    # what they asked, and the trace only has to say how far each one got.
    blocks = [
        "\n".join([f"ASKED: {ask}"] + [f"  then {line[:160]}" for line in work[-MAX_TRACE:]])
        for ask, work in asks
    ]
    # Newest of all, and the only ones the session has certainly not started: still in its
    # inbox. They never appear as turns until it picks them up, so without this the list
    # would be missing exactly the asks the person is waiting on.
    blocks += [
        f"ASKED: {item['text'][:MAX_ASK]}\n  not picked up yet"
        for item in queued(session_id)
    ]
    return "\n\n".join(blocks)[-cap:]


def queued(session_id: str) -> list[dict]:
    """What is still sitting in this session's inbox, unread.

    Claude Code keeps its own books: every time something joins or leaves a session's inbox it
    writes a `queue-operation` line. Replaying those says exactly what is still waiting, which is
    a fact rather than the guess you would make from the shape of the transcript.

    Only what is still there. This used to keep the ones a running turn had swallowed too, on the
    belief that those were written down nowhere — they are, as a `queued_command` attachment at
    the moment they arrived, which `transcripts.absorbed` now reads as an ordinary turn. Keeping
    them here as well pinned three answered prompts to the end of the conversation, where the one
    thing they looked like was three prompts nobody had got to.

    Read over the tail like everything else here, so the replay can begin mid-queue. That is why
    a leave naming something not in hand takes the oldest instead: the queue is a queue, and a
    window that opened halfway through one still empties in the right order.
    """
    path = transcript_path(session_id)
    if path is None:
        return []
    since = cleared_at(session_id)
    lane: list[dict] = []
    for raw in tail_lines(path, TAIL_WINDOWS[1]):
        entry = parse_line(raw)
        if entry is None or entry.get("type") != "queue-operation":
            continue
        if since and str(entry.get("timestamp") or "") <= since:
            continue
        operation, content = entry.get("operation"), entry.get("content")
        if content and MACHINE.match(content):
            # Skipped on the way in *and* on the way out: a removal naming one of these would
            # otherwise fall through to "take the oldest" and eat a real message.
            continue
        if operation == "enqueue" and content:
            lane.append({"text": unwrap(content)})
        elif operation == "popAll":
            # Nothing observed says whether these were read or thrown away, so the honest thing
            # is to stop claiming anything about them.
            lane.clear()
        elif (index := _leaving(lane, content)) is not None:
            lane.pop(index)
    return lane


def clear(session_id: str) -> str:
    """Forget everything the lane says up to now. Returns the moment drawn under it.

    For the inbox that is not really an inbox any more: a session killed mid-queue leaves its
    enqueues with no matching removal, and the replay has no way to know the session that was
    going to read them is gone. Nothing in Claude Code's own transcript is touched — a line is
    drawn beside it, here, and the replay starts after that line.
    """
    when = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    path = _line_path(session_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"cleared": when}))
    return when


def cleared_at(session_id: str) -> str:
    """When the line was last drawn, as the transcript writes a time. Empty if it never was."""
    path = _line_path(session_id)
    if not path.exists():
        return ""
    try:
        return str(json.loads(path.read_text()).get("cleared") or "")
    except (OSError, json.JSONDecodeError):
        return ""


def _line_path(session_id: str):
    return data_dir() / "queue" / f"{session_id}.json"


def _leaving(lane: list[dict], content: object) -> int | None:
    """Which entry this operation is about: the one it names, else the oldest still in hand.

    A `dequeue` names nothing at all, and a `remove` can name something enqueued before the tail
    window opened. Both mean the same thing to a queue: the front of it has gone.
    """
    wanted = unwrap(content) if isinstance(content, str) and content else None
    if wanted is not None:
        for index, item in enumerate(lane):
            if item["text"] == wanted:
                return index
    return 0 if lane else None
