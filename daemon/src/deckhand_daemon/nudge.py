"""Ask a session that has gone quiet about the asks still open on its list.

A session stops when it thinks it is finished. The list says otherwise often enough to be worth
a question: something was three asks deep and only two came back, or an ask was read as optional.
Nobody is watching every pane, so the Mac watches instead and puts the question to the session
itself — which is the only party that knows whether the remaining asks are unfinished, already
done under another name, or ones it decided against.

The message itself is `prompts/idle-check.md`. Deliberately not a task runner. It asks once per state of the list and takes any answer, because
the wrong failure here is a daemon that will not let a session stop working.
"""

from __future__ import annotations

import asyncio
import os
import time

from . import deliver, prompts, sessions, tasks
from .log import log

# Between sweeps. Nothing here is urgent — a session that has stopped stays stopped.
POLL = 30
# How long a session must have been quiet before it is asked. Long enough that a pause between
# runs is not mistaken for the end of one.
SETTLE = 120
# The floor between two questions to the same session, whatever its list does in between. A
# session that cannot finish an ask must still be able to sit still.
AGAIN = 30 * 60

# What each session was last seen doing, when it went quiet, and what its list said last time
# it was asked. All three are this process's, not the file's: a restarted daemon asks again.
_quiet_since: dict[str, float] = {}
_asked_about: dict[str, tuple[float, str]] = {}

IDLE_CHECK = prompts.load("idle-check")


def enabled() -> bool:
    """On unless the Mac says otherwise. It sends messages to live sessions, so it has a switch."""
    return os.environ.get("DECKHAND_NUDGE", "1") not in ("0", "false", "no")


async def watch() -> None:
    """Poll for sessions that have gone quiet owing something. Runs beside the other watchers."""
    if not enabled():
        log.info("idle check is off (DECKHAND_NUDGE)")
        return
    while True:
        await asyncio.sleep(POLL)
        try:
            await asyncio.to_thread(sweep)
        except OSError as error:
            log.warning("idle check failed: %s", error)


def sweep(now: float | None = None) -> list[str]:
    """One pass. Returns the sessions asked, which is what the test reads."""
    now = time.time() if now is None else now
    live = sessions.live_sessions()
    asked = [session.session_id for session in live if _consider(session, now)]
    for gone in {*_quiet_since} - {s.session_id for s in live}:
        del _quiet_since[gone]
    return asked


def _consider(session: sessions.Session, now: float) -> bool:
    """Whether this session is quiet, owing, and has not just been asked the same thing."""
    if session.status == "busy":
        _quiet_since.pop(session.session_id, None)
        return False
    since = _quiet_since.setdefault(session.session_id, now)
    if now - since < SETTLE:
        return False
    open_asks = tasks.outstanding(session.session_id)
    if not open_asks:
        return False
    when, about = _asked_about.get(session.session_id, (0.0, ""))
    standing = _fingerprint(open_asks)
    # Both guards, because they catch different runaways: the same list twice is a session that
    # has answered and moved on, and a changing list is one churning through a job it cannot end.
    if standing == about or now - when < AGAIN:
        return False
    route, error = deliver.deliver(
        session, _question(open_asks, session.name), route=IDLE_CHECK.settings["route"])
    if error:
        log.warning("idle check could not reach %s: %s", session.name, error)
        return False
    _asked_about[session.session_id] = (now, standing)
    log.info("idle check asked %s about %d open asks by %s", session.name, len(open_asks), route)
    return True


def _fingerprint(open_asks: list[dict]) -> str:
    """What was asked about last time. Its state counts: todo becoming doing is an answer."""
    return "|".join(f"{task['id']}:{task['state']}" for task in open_asks)


def _question(open_asks: list[dict], name: str) -> str:
    """The whole message. Says what it is, so nobody reads it as the person typing.

    It is addressed by name on purpose. The asks and the session they are sent to come from the
    same `Session` in `_consider`, so this cannot pick up another session's list — but the socket
    underneath can go to the wrong process if a record is stale or a pid was reused, and a message
    saying only "this session" would arrive looking exactly right. Named, a misroute announces
    itself, because the session reading it knows what it is called and this says what it expected.
    """
    listed = "; ".join(f"{task['id']} [{task['state']}] {task['text']}" for task in open_asks)
    return IDLE_CHECK.filled(name=name, listed=listed)
