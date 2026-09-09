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
# Not everything in the inbox is a person. Claude Code queues its own notices there — a finished
# background task, a reminder — and those are machinery, not something anybody said. Whatever is
# inside them is not a message either, so they are dropped whole rather than unwrapped.
_MACHINE = re.compile(r"^\s*<\s*(?:task-notification|system-reminder|local-command-\w+)\b", re.IGNORECASE)
# How many absorbed messages are worth keeping. One says "your words landed and no turn will ever
# show them", which is news for a minute; a window's worth of them is a second transcript.
MAX_TAKEN = 3


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
        f"ASKED: {item['text'][:MAX_ASK]}\n  "
        + ("picked up mid-run, so it appears nowhere in the transcript above"
           if item["state"] == "taken" else "not picked up yet")
        for item in queued(session_id)
    ]
    return "\n\n".join(blocks)[-cap:]


def queued(session_id: str) -> list[dict]:
    """What you have said to this session that has not come back as a turn, and where it stands.

    Claude Code keeps its own books: every time something joins or leaves a session's inbox it
    writes a `queue-operation` line. Replaying those says exactly what is still waiting, which is
    a fact rather than the guess you would make from the shape of the transcript.

    Two states, and the second one is the whole reason this returns more than text. A message
    picked up at the prompt (`dequeue`) becomes an ordinary user turn and is dropped from here —
    the transcript has it now. A message the running turn swallowed (`remove`, reason
    `absorbed_mid_turn`) is **never written to the transcript at all**: verified against a live
    session, where four messages absorbed that way left no user entry behind them. Dropping those
    too is what made a prompt disappear from the phone seconds after it was sent, with no trace
    anywhere. They stay here, marked `taken`.

    Read over the tail like everything else here, so the replay can begin mid-queue. That is why
    a leave naming something not in hand takes the oldest instead: the queue is a queue, and a
    window that opened halfway through one still empties in the right order.
    """
    path = transcript_path(session_id)
    if path is None:
        return []
    lane: list[dict] = []
    for raw in tail_lines(path, TAIL_WINDOWS[1]):
        entry = parse_line(raw)
        if entry is None or entry.get("type") != "queue-operation":
            continue
        operation, content = entry.get("operation"), entry.get("content")
        if content and _MACHINE.match(content):
            # Skipped on the way in *and* on the way out: a removal naming one of these would
            # otherwise fall through to "take the oldest" and eat a real message.
            continue
        if operation == "enqueue" and content:
            lane.append({"text": _unwrap(content), "state": "waiting"})
        elif operation == "popAll":
            # Nothing observed says whether these were read or thrown away, so the honest thing
            # is to stop claiming anything about them.
            lane.clear()
        elif (index := _waiting(lane, content)) is not None:
            if entry.get("reason") == "absorbed_mid_turn":
                lane[index]["state"] = "taken"
            else:
                lane.pop(index)
    return _recent(lane)


def _recent(lane: list[dict]) -> list[dict]:
    """Everything still waiting, and only the last few that were taken, in the order they came."""
    kept, taken = [], 0
    for item in reversed(lane):
        if item["state"] == "taken":
            taken += 1
            if taken > MAX_TAKEN:
                continue
        kept.append(item)
    return list(reversed(kept))


def _waiting(lane: list[dict], content: object) -> int | None:
    """Which entry this operation is about: the one it names, else the oldest still waiting.

    A `dequeue` names nothing at all, and a `remove` can name something enqueued before the tail
    window opened. Both mean the same thing to a queue: the front of it has gone.
    """
    wanted = _unwrap(content) if isinstance(content, str) and content else None
    oldest = None
    for index, item in enumerate(lane):
        if item["state"] != "waiting":
            continue
        if wanted is not None and item["text"] == wanted:
            return index
        oldest = index if oldest is None else oldest
    return oldest


def _unwrap(text: str) -> str:
    """The words themselves, out of whatever envelope carried them into the queue.

    Deckhand's own socket route labels what it delivers, and a message from another session
    arrives inside a tag. Neither is what the person said, and neither belongs on the phone.
    """
    body = _WRAPPER.sub("", text)
    # Control characters and all: the keyboard route types ctrl-U before the words to clear
    # whatever was half-written in the prompt, and that ctrl-U travels in the queued content.
    body = "".join(c for c in body if c.isprintable() or c.isspace()).strip()
    _, marker, spoken = body.partition("transcribed:")
    return " ".join((spoken if marker else body).split())[:MAX_TEXT]
