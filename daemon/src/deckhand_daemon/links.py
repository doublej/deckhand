"""Which sessions have been talking to each other, read off the receivers' transcripts.

When one Claude Code session messages another, the message lands in the **receiver's**
transcript as a queue-operation whose `content` opens with a `<cross-session-message …>`
header naming the sender's inbox socket:

    {"type":"queue-operation","operation":"enqueue","timestamp":"…","sessionId":"<receiver>",
     "content":"<cross-session-message from=\"uds:/tmp/cc-socks/99607.sock\" …>\\n…"}

That is a complete directed edge with a time on it. The sender is resolved by matching the
socket path against the `messagingSocketPath` in the live listing — the same record-and-`ps`
join the rest of the daemon is built on — which also means an edge only survives while both
ends are still running, and a link with one end nowhere has nothing to draw between.

This reads a transcript but does not live in `reading/`, because it carries an HTTP router and
that package is reading and nothing else. It borrows `reading.transcripts`' tail helpers rather
than opening the file its own way.

Four things about the header, measured against the ~950 peer messages on this Mac rather than
assumed. Each is a way to get this quietly wrong:

- **Only `enqueue` is an arrival.** `dequeue` is the session consuming one, `remove` a
  cancellation, and there are more of those than there are arrivals — counting them would draw
  every message two or three times.
- **The attributes are not in a fixed order and not a fixed set.** `hop-chain` sits between
  `from` and `from-name`, and a third of all messages carry one. A positional pattern silently
  drops that third, which is the worst outcome for a feature whose whole job is showing that
  something happened, so they are parsed by name.
- **`from` is always the immediate sender**, hop-chain or not, so every envelope is a truthful
  edge between exactly those two sessions. Never read the first hop-chain entry as the sender:
  it is frequently a different session.
- **The daemon's own deliveries cannot appear in this lane.** `deliver.py` writes a raw
  `{"type":"user"}` frame into the socket, so what arrives is an ordinary queued prompt with no
  header at all; the header is written by the *sender's* Claude Code, which the daemon is not.
  Verified across every transcript here: 952 peer enqueues, none of them from Deckhand. So
  there is no "is this really an agent?" exclusion here and none is needed — do not add one
  back on the strength of `deliver.PREAMBLE`, because it is the missing header that rules the
  daemon out, structurally, and a preamble that changed would not change that.
"""

from __future__ import annotations

import asyncio
import re
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, Query

from .reading.transcripts import TAIL_WINDOWS, parse_line, tail_lines, transcript_path
from .sessions import Session, live_sessions

# Cheap pre-filter, applied to the raw bytes before anything is parsed as JSON.
MENTION = b"cross-session-message"
HEADER = re.compile(r"^<cross-session-message\s([^>]*)>")
ATTRIBUTE = re.compile(r'([a-z][a-z-]*)="([^"]*)"')
# `from="uds:/tmp/cc-socks/99607.sock"`; the socket path is what a session record carries.
SOCKET = re.compile(r"^uds:(?P<path>/.+)$")
# The window the phone may ask for. Below a minute nothing would ever be on screen; above an
# hour the tail scan stops being cheap and the decay stops meaning anything.
MIN_WINDOW = 30.0
MAX_WINDOW = 3600.0

router = APIRouter(tags=["links"])


@dataclass(slots=True)
class SessionLink:
    """One direction of traffic between two live sessions, over the asked-for window."""

    source: str  # the sending session's id
    target: str  # the receiving session's id
    latest: float  # epoch seconds of the most recent message this way
    count: int  # how many went this way inside the window
    relayed: int  # how many were sent by a turn that was itself peer-driven (a hop-chain)

    def to_json(self) -> dict:
        return asdict(self)


@router.get("/sessions/links")
async def session_links(
    within: float = Query(
        default=300.0,
        ge=MIN_WINDOW,
        le=MAX_WINDOW,
        description="how many seconds back to look for messages between sessions",
    ),
) -> dict:
    """Which sessions have messaged which, lately. Both ends are always on the listing.

    The window is the phone's, not the Mac's: the same number decides how far back the scan
    reads and how far back the screen draws, so the two cannot drift apart.

    `/sessions/links` would only be ambiguous if some route were `/sessions/{id}` on its own.
    None is, so this cannot be swallowed as a session id.
    """
    live = await asyncio.to_thread(live_sessions)
    found = await asyncio.to_thread(read_links, live, within)
    return {"links": [link.to_json() for link in found], "within": within}


def read_links(live: list[Session], within: float) -> list[SessionLink]:
    """Every directed edge between two sessions in `live` from the last `within` seconds."""
    within = max(MIN_WINDOW, min(MAX_WINDOW, within))
    cutoff = time.time() - within
    by_socket = {s.socket_path: s.session_id for s in live if s.socket_path}
    edges: dict[tuple[str, str], SessionLink] = {}
    for receiver in live:
        for socket_path, when, relayed in _arrivals(receiver.session_id, cutoff):
            source = by_socket.get(socket_path)
            if source is None or source == receiver.session_id:
                continue
            _record(edges, source, receiver.session_id, when, relayed)
    return sorted(edges.values(), key=lambda e: e.latest, reverse=True)


def _record(
    edges: dict[tuple[str, str], SessionLink],
    source: str,
    target: str,
    when: float,
    relayed: bool,
) -> None:
    edge = edges.get((source, target))
    if edge is None:
        edges[(source, target)] = SessionLink(source, target, when, 1, int(relayed))
        return
    edge.count += 1
    edge.relayed += int(relayed)
    edge.latest = max(edge.latest, when)


def _arrivals(session_id: str, cutoff: float) -> list[tuple[str, float, bool]]:
    """(sender socket path, epoch, relayed) for each peer message taken in since `cutoff`.

    Widens the tail the way the rest of `reading` does, and for the same reason: a fixed window
    is minutes of transcript for a quiet session and seconds of it for one mid-burst. It stops
    as soon as the chunk reaches back past the cutoff, so the usual cost is one read of the
    smallest window.
    """
    path = transcript_path(session_id)
    if path is None:
        return []
    found: list[tuple[str, float, bool]] = []
    for window in TAIL_WINDOWS:
        found, reached_back = _scan(path, window, cutoff)
        if reached_back:
            break
    return found


def _scan(path: Path, window: int, cutoff: float) -> tuple[list[tuple[str, float, bool]], bool]:
    """Peer arrivals in the last `window` bytes, and whether that reached back past `cutoff`.

    Only the handful of lines mentioning the header are parsed. Half a megabyte of transcript is
    a few thousand JSON objects and perhaps five of them are peer traffic, so parsing all of them
    cost more than the rest of the route put together — measured at 370 ms across nine live
    sessions against 38 ms for the same answer once the pre-filter went in, and this runs for
    every live session every time the phone asks.

    "Reached back" is decided on the oldest timestamped line in the chunk rather than on the
    oldest arrival, because a chunk with no peer traffic in it still proves the window is covered.
    """
    lines = tail_lines(path, window)
    found: list[tuple[str, float, bool]] = []
    for raw in lines:
        if MENTION not in raw:
            continue
        entry = parse_line(raw)
        when = _epoch(entry.get("timestamp")) if entry else None
        if when is None or when < cutoff or entry.get("operation") != "enqueue":
            continue
        arrival = _arrival(entry, when)
        if arrival is not None:
            found.append(arrival)
    return found, _oldest(lines) <= cutoff


def _oldest(lines: list[bytes]) -> float:
    """The time of the earliest line in the chunk.

    Transcripts are appended, so that is the first line carrying a timestamp at all and there is
    no need to read the rest.
    """
    for raw in lines:
        when = _epoch((parse_line(raw) or {}).get("timestamp"))
        if when is not None:
            return when
    return float("inf")  # nothing datable in the chunk: assume it does not reach back


def _arrival(entry: dict, when: float) -> tuple[str, float, bool] | None:
    """One enqueue as (socket path, epoch, relayed), or None when it is not peer traffic.

    A prompt the person queued enqueues too, and so does anything the daemon delivers. The
    header is what separates a message another session sent from one that was merely queued,
    and it is written by the sender rather than by whatever put the text in.
    """
    if entry.get("type") != "queue-operation":
        return None
    content = entry.get("content")
    if not isinstance(content, str):
        return None
    header = HEADER.match(content)
    if header is None:
        return None
    attributes = dict(ATTRIBUTE.findall(header.group(1)))
    origin = SOCKET.match(attributes.get("from", ""))
    if origin is None:
        return None
    return origin.group("path"), when, "hop-chain" in attributes


def _epoch(stamp: object) -> float | None:
    """`2026-09-10T13:37:23.094Z` as epoch seconds. None when there is no usable timestamp."""
    if not isinstance(stamp, str) or not stamp:
        return None
    try:
        return datetime.fromisoformat(stamp).timestamp()
    except ValueError:
        return None
