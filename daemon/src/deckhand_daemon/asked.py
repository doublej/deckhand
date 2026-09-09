"""What the person asked this session for, and what it has not picked up yet.

Two readings of the same transcript, and both are about them rather than about the session.
`asks_of` is what the task list is written from; `queued` is the session's own inbox, which is
the one thing in here that is a fact and not a summary — Claude Code writes a `queue-operation`
line every time something joins or leaves it.
"""

from __future__ import annotations

import re

from .transcripts import (
    MAX_TEXT,
    TAIL_WINDOWS,
    describe,
    parse_line,
    tail_lines,
    text_of,
    transcript_path,
)

# One ask, kept whole enough that the task list is written from their words and not a gist.
MAX_ASK = 600
# Lines of work kept between one ask and the next — enough to tell how far it got.
MAX_TRACE = 10
# The envelope a queued message travels in: one session addressing another, or the daemon
# saying who spoke. Tags only — whatever they wrap is the message.
_WRAPPER = re.compile(r"</?[a-z][\w-]*(?:\s[^>]*)?>", re.IGNORECASE)


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
    blocks += [f"ASKED: {text[:MAX_ASK]}\n  not picked up yet" for text in queued(session_id)]
    return "\n\n".join(blocks)[-cap:]


def queued(session_id: str) -> list[str]:
    """What you have said to this session that it has not picked up yet.

    Claude Code keeps its own books: every time something joins or leaves a session's inbox it
    writes a `queue-operation` line. Replaying those says exactly what is still waiting, which
    is a fact rather than the guess you would make from the shape of the transcript — a message
    sent mid-turn never appears as a turn at all until the session absorbs it.

    Read over the tail like everything else here, so the replay can begin mid-queue. That is
    why a `remove` naming something not in hand drops the oldest instead: the queue is a queue,
    and a window that opened halfway through one still empties in the right order.
    """
    path = transcript_path(session_id)
    if path is None:
        return []
    waiting: list[str] = []
    for raw in tail_lines(path, TAIL_WINDOWS[1]):
        entry = parse_line(raw)
        if entry is None or entry.get("type") != "queue-operation":
            continue
        operation, content = entry.get("operation"), entry.get("content")
        if operation == "enqueue" and content:
            waiting.append(content)
        elif operation == "popAll":
            waiting.clear()
        elif content in waiting:
            waiting.remove(content)
        elif waiting:
            waiting.pop(0)
    return [_unwrap(text) for text in waiting]


def _unwrap(text: str) -> str:
    """The words themselves, out of whatever envelope carried them into the queue.

    Deckhand's own socket route labels what it delivers, and a message from another session
    arrives inside a tag. Neither is what the person said, and neither belongs on the phone.
    """
    body = _WRAPPER.sub("", text).strip()
    _, marker, spoken = body.partition("transcribed:")
    return " ".join((spoken if marker else body).split())[:MAX_TEXT]
