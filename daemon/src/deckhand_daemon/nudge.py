"""Ask a session that has gone quiet about the asks still open on its list.

A session stops when it thinks it is finished. The list says otherwise often enough to be worth
a question: something was three asks deep and only two came back, or an ask was read as optional.
Nobody is watching every pane, so the Mac watches instead and puts the question to the session
itself — which is the only party that knows whether the remaining asks are unfinished, already
done under another name, or ones it decided against.

The message itself is `prompts/idle-check.md`. Deliberately not a task runner. It asks once about
each ask and takes any answer, because the wrong failure here is a daemon that will not let a
session stop working.
"""

from __future__ import annotations

import asyncio
import json
import os
import time
from pathlib import Path

from . import deliver, prompts, sessions, tasks
from .config import data_dir
from .log import log
from .reading import agents
from .settings import wants

# Between sweeps. Nothing here is urgent — a session that has stopped stays stopped.
POLL = 30
# How long a session must have been quiet before it is asked. Long enough that a pause between
# runs is not mistaken for the end of one.
SETTLE = 120
# The floor between two questions to the same session, whatever its list does in between. A
# session that cannot finish an ask must still be able to sit still.
AGAIN = 30 * 60
# How long what a session was asked about is remembered. Session ids are never reused, so this
# only keeps the file from growing without bound: a session still alive a week on, holding the
# same blocked ask, is asked about it once more.
KEEP = 7 * 24 * 3600

# When each session went quiet. This process's, not the file's: a restarted daemon only waits out
# SETTLE again. What each session was asked about is on disk — see `_asked`.
_quiet_since: dict[str, float] = {}

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
        except Exception:  # noqa: BLE001 -- anything else would end this task for good, silently
            log.exception("idle check failed")


def sweep(now: float | None = None) -> list[str]:
    """One pass. Returns the sessions asked, which is what the test reads."""
    now = time.time() if now is None else now
    live = sessions.live_sessions()
    asked = [session.session_id for session in live if _consider(session, now)]
    for gone in {*_quiet_since} - {s.session_id for s in live}:
        del _quiet_since[gone]
    return asked


def _consider(session: sessions.Session, now: float) -> bool:
    """Whether this session is quiet, owing, and has not already been asked about these asks."""
    # A Codex thread's only lane is the person's own, and the idle check is not the person.
    if session.provider == "codex":
        return False
    if session.status == "busy":
        _quiet_since.pop(session.session_id, None)
        return False
    # Before anything is read off disk: a folder set not to be chased is not chased, and the
    # environment switch stays what it is — the whole Mac, off.
    if not wants.resolved(session.cwd).chase:
        return False
    # A session whose subagents are still working is **not quiet**, whatever its own status says:
    # stopping a turn with a background agent running is the ordinary way to leave one going, and
    # asking then interrupts the work to ask whether the work is done. Treated exactly as `busy`
    # above — the clock restarts, so the question waits out another `SETTLE` after they finish —
    # rather than as a veto further down, which would let the quiet clock run out underneath it
    # and fire the moment the last agent stopped. It sits below the switch only because it is the
    # first thing here that costs a disk read, and a folder nobody chases should not pay it.
    if agents.alive(session.session_id, now):
        _quiet_since.pop(session.session_id, None)
        return False
    since = _quiet_since.setdefault(session.session_id, now)
    if now - since < SETTLE:
        return False
    open_asks = tasks.outstanding(session.session_id)
    if not open_asks:
        return False
    when, asked_ids = _asked().get(session.session_id, (0.0, []))
    open_ids = [task["id"] for task in open_asks]
    # Both guards, because they catch different runaways: nothing open that was not already asked
    # about is a session that has answered and moved on, and a changing list is one churning
    # through a job it cannot end.
    #
    # Ids, never states. The summariser moves an ask to doing on reading the session's answer to
    # this very question — "waiting on JJ" is blocked work, and blocked work is doing — so counting
    # states made every answer arm the next question. And a subset rather than the same list, so
    # one ask finishing does not reopen the ones already answered.
    if set(open_ids) <= set(asked_ids) or now - when < AGAIN:
        return False
    route, error = deliver.deliver(
        session, _question(open_asks, session.name), route=IDLE_CHECK.settings["route"])
    if error:
        log.warning("idle check could not reach %s: %s", session.name, error)
        return False
    _remember(session.session_id, now, open_ids)
    log.info("idle check asked %s about %d open asks by %s", session.name, len(open_asks), route)
    return True


def _asked() -> dict[str, list]:
    """What each session was last asked about, and when: `{session_id: [when, [ids]]}`.

    On disk, not in this process. The daemon is restarted many times a day — 11 on 2026-09-14 —
    and while this was a dict, every restart asked every owing session the same question again.
    An unreadable file reads as empty, which costs one repeated question and nothing else.
    """
    try:
        asked = json.loads(_asked_path().read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return asked if isinstance(asked, dict) else {}


def _remember(session_id: str, now: float, ids: list[str]) -> None:
    asked = {sid: entry for sid, entry in _asked().items() if now - entry[0] < KEEP}
    asked[session_id] = [now, ids]
    _asked_path().write_text(json.dumps(asked))


def _asked_path() -> Path:
    return data_dir() / "nudged.json"


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
