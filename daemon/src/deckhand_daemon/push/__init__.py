"""Puts a card on the phone's Lock Screen for one session that wants you.

`sending.py` is what goes over APNs; this is what decides there is anything to send.

Three events and no others. A slip nothing has answered, or an agent calling for you outright —
both `asking`, which may raise a card and may make a noise. A session's list of asks going from
something to nothing — `finished`, which is silent and may only ever update a card already up.
A turn merely ending is neither, and deleting it is what this half was rebuilt for: it was once
the only trigger here, at 294 cards in 28 hours. Measured over that same window, a turn ending is
10 an hour, one ask ticked off 12, and the list going empty 4 — and only the last is something a
person can act on.

The briefing's own status line is used for what a card *reads* and never for whether one is
raised: it is model-written and lags by a sweep or two, so it must not be what makes a noise.
"""

from __future__ import annotations

import asyncio
import time

from .. import artifacts, briefings, config, sessions, tasks
from ..log import log
from ..reading import transcripts
from ..settings import wants
from .sending import ASKING, FINISHED, NOTHING, Card, end, remember, shortened, show

__all__ = ["ASKING", "FINISHED", "Card", "called", "end", "remember", "spoke_to", "sweep",
           "watch"]

POLL = 5.0
#: Slips waiting per session last sweep. A *new* one is the event; one sitting there all
#: afternoon is not, and a drop back to none is that card's end.
_slips: dict[str, int] = {}
#: Asks still open on each session's list last sweep. Non-empty → empty is the `finished` event.
_open: dict[str, int] = {}
#: What an agent asked to be told, where one asked. Beats anything read out of a transcript,
#: because an agent that used its own words meant them.
_said: dict[str, str] = {}


async def watch() -> None:
    """Poll for the two things a session does quietly. Runs beside the plugin watcher."""
    while True:
        await asyncio.sleep(POLL)
        try:
            await asyncio.to_thread(sweep)
        except OSError as error:
            log.warning("lock screen sweep failed: %s", error)


def sweep() -> None:
    live = sessions.live_sessions()
    alive = {s.session_id for s in live}
    for session in live:
        _slipped(session)
        _cleared(session)
    for gone in (set(_slips) | set(_open)) - alive:
        _slips.pop(gone, None)
        _open.pop(gone, None)
        _said.pop(gone, None)
        # A card about a session that no longer exists can never be answered or cleared.
        end(gone)


def _slipped(session) -> None:
    """A slip this session put on the phone that nothing has answered — and the moment the last
    one is answered, which is a card with nothing left to ask about. A directory listing per
    session per sweep: the honest cost of noticing a file appear without a filesystem watcher,
    against a folder the session wrote to seconds ago, so it is warm.
    # ponytail: polled; a real watcher if this ever shows up in the log's timings."""
    waiting = int(artifacts.counted(session).get("artifacts_waiting", 0) or 0)
    was = _slips.get(session.session_id)
    _slips[session.session_id] = waiting
    # `was` is None the first time: slips already sitting there are not something that happened.
    if was is None:
        return
    if was and not waiting:
        end(session.session_id)
        return
    if waiting <= was:
        return
    # Per folder rather than once for the Mac: "not this one" is the shape that opinion takes.
    if not wants.resolved(session.cwd).slips:
        log.info("lock screen: %s has a slip waiting, but this folder is set quiet", session.name)
        return
    log.info("lock screen: %s is waiting on a slip", session.name)
    announce(session, ASKING)


def _cleared(session) -> None:
    """The one `finished` event: this session's list of asks going from something to nothing.

    `tasks.py` owns that list and the briefing agent moves the asks along, so this reads the file
    the phone reads. Polled rather than hooked into `tasks.set_state`, which would put the Lock
    Screen inside a model run and inside the three tools' only job.
    """
    still = len(tasks.outstanding(session.session_id))
    was = _open.get(session.session_id)
    _open[session.session_id] = still
    if was is None or still or not was:
        return
    if not wants.resolved(session.cwd).finished:
        log.info("lock screen: %s cleared its list, but this folder is set quiet", session.name)
        return
    log.info("lock screen: %s cleared its list", session.name)
    announce(session, FINISHED)


def called(session, line: str) -> str | None:
    """An agent asking for you outright, in its own words. Returns an error, or None.

    The one trigger a session decides for itself, which is why its folder switch can refuse it
    outright rather than merely stay quiet: everything else here is the Mac noticing something,
    and this is a program asking to interrupt you.
    """
    if not wants.resolved(session.cwd).called:
        log.info("lock screen: %s called for you, but this folder is set not to be interrupted",
                 session.name)
        return "this folder is set not to be interrupted"
    said = shortened(line, ASKING)
    _said[session.session_id] = said
    log.info("lock screen: %s called for you: %s", session.name, said)
    announce(session, ASKING)
    return None


def spoke_to(session_id: str) -> None:
    """You answered it, so it is no longer asking — whether or not you did it from the card."""
    _said.pop(session_id, None)
    end(session_id)


def announce(session, kind: str) -> None:
    card = Card(session=session.session_id, name=session.name, kind=kind,
                line=_line(session.session_id, kind), when=time.time())
    # The session's own machine rather than the one answering the phone. They are the same
    # thing on a one-machine network and different the moment they are not, and the card saying
    # "m2" over a session running on Ubuntu is the card lying about the only thing it adds.
    where = session.machine or config.base_url().removeprefix("http://").split(":")[0]
    if error := show(card, where):
        log.info("lock screen: %s", error)


def _line(session_id: str, kind: str) -> str:
    """The one line on the card, and it is never empty.

    In order of how much it was meant: what an agent asked to be told, then the briefing's own
    first line (`prompts/briefing.md` writes a standalone Waiting/Blocked/Done line for exactly
    this reading), then the first sentence of whatever was last said.
    """
    said = _said.get(session_id) if kind == ASKING else None
    found = said or briefings.load(session_id).get("headline") or _last_line(session_id)
    return shortened(found or "", kind) or NOTHING[kind]


def _last_line(session_id: str) -> str:
    """The first sentence of what it last said, which is usually the question it is asking."""
    turns = transcripts.read_turns(session_id, 3)
    return next((t.text for t in reversed(turns) if t.role == "assistant" and t.text), "")
