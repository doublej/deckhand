"""Where briefings are kept, and the one worker that keeps them current.

Split from `summarize`, which knows how a briefing is *written*. This knows when one is worth
writing and where the last one lives, and those turned out to be the whole cost of the feature.

What it replaces was a dictionary in memory with a two-minute TTL. Two consequences, both
expensive. A session that had done nothing since its last briefing still paid a model run every
two minutes for as long as anyone had the list on screen — the hash made a re-read free only
inside the TTL, and past it an identical transcript was a miss like any other. And nothing
survived a restart: a reinstalled app, or a restarted daemon, faced a rail of blank rows and
bought every one of them again.

So the briefing is a file, keyed by what the transcript actually said when it was written, and
one worker walks the sessions. A session whose transcript has not been touched costs a `stat`.
One whose transcript moved but whose activity reads the same costs a read. Only genuinely new
work costs a model, and the phone never waits for one: it is always handed the last briefing
there was, which is the answer to "what happened" every time except the few seconds after
something happens.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import time
from pathlib import Path

from . import sessions, summarize, tasks
from .config import data_dir
from .log import log
from .reading import asked, transcripts

# Between two briefings. One model at a time, always: six sessions summarised at once is six
# models thinking, and nothing on the phone is waiting for any of them.
GAP = 4
# When nothing is due. The worker is woken early by `bump`, so this is only the floor on
# noticing work that arrived while it was asleep.
IDLE = 15


def path(session_id: str) -> Path:
    folder = data_dir() / "briefings"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"{session_id}.json"


def load(session_id: str) -> dict:
    """The last briefing written for this session. Empty when there has never been one."""
    try:
        return json.loads(path(session_id).read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def save(session_id: str, briefing: dict) -> None:
    path(session_id).write_text(json.dumps(briefing, indent=2))


def of(session_id: str) -> dict:
    """One session's briefing as the phone reads it: the prose, the line, the list, the cost."""
    kept = load(session_id)
    return {
        "summary": kept.get("summary"),
        "headline": kept.get("headline"),
        "tasks": tasks.load(session_id),
        "spent": summarize.spent(session_id),
        "error": kept.get("error"),
        "writtenAt": kept.get("written_at"),
        # Whether a newer one is on its way. Not "wrong" — the briefing below it is still the
        # last true thing said about this session.
        #
        # One session's own answer, never the whole queue's. Asking whether this id was in the
        # queue meant walking every live session to answer a boolean about one of them, and
        # `/briefings` calls this once per session: N listings and N² transcript reads for a
        # route the phone opens cold. `_due` is the same fact — the queue is the live sessions
        # it is true of — and liveness is already settled by both callers.
        "stale": _due(session_id),
    }


def bump(session_id: str) -> None:
    """To the front of the queue, and wake the worker.

    Opening a session is the one moment its briefing is worth more than any other's, so reading
    one is what promotes it. No separate call to forget to make.
    """
    if session_id in _bumped:
        _bumped.remove(session_id)
    _bumped.insert(0, session_id)
    _wake.set()


async def watch() -> None:
    """Walk the sessions forever, writing a briefing only where one is actually owed."""
    while True:
        try:
            session_id = await asyncio.to_thread(_next)
        except OSError as error:
            log.warning("briefing sweep failed: %s", error)
            session_id = None
        if session_id is None:
            await _sleep(IDLE)
            continue
        await _write(session_id)
        await _sleep(GAP)


async def _sleep(seconds: float) -> None:
    """Sleep, unless somebody opens a session — then stop sleeping and go and write theirs."""
    _wake.clear()
    try:
        await asyncio.wait_for(_wake.wait(), timeout=seconds)
    except TimeoutError:
        pass


# Sessions somebody is looking at, newest first. The worker takes from here before the cycle.
_bumped: list[str] = []
_wake = asyncio.Event()
# Where the round-robin got to, so a session at the end of the list is not starved by one at
# the start that keeps changing.
_cursor = 0


def _next() -> str | None:
    """The next session to write about: anything bumped, else the cycle, else nothing at all."""
    global _cursor
    live = [s.session_id for s in sessions.live_sessions()]
    while _bumped:
        wanted = _bumped.pop(0)
        if wanted in live and _due(wanted):
            return wanted
    if not live:
        return None
    for step in range(len(live)):
        candidate = live[(_cursor + step) % len(live)]
        if _due(candidate):
            _cursor = (_cursor + step + 1) % len(live)
            return candidate
    return None


def _due(session_id: str) -> bool:
    """Whether anything has happened to this session since its briefing was written.

    Two gates, cheapest first. The transcript's own mtime settles the common case without
    opening the file — a session nobody has touched since the last sweep answers in a `stat`.
    Only if the file moved is it read, because plenty of what Claude Code appends (a mode
    change, an attachment) is not activity anybody wants a briefing about.
    """
    kept = load(session_id)
    file = transcripts.transcript_path(session_id)
    if file is None:
        return False
    try:
        moved = file.stat().st_mtime
    except OSError:
        return False
    if kept.get("mtime") == moved:
        return False
    return kept.get("hash") != _hash(session_id)


def _hash(session_id: str) -> str:
    """What the session has done, as one string. The same reading `summarize` is handed."""
    activity = transcripts.activity_since_last_user(session_id)
    asks = asked.asks_of(session_id)
    return hashlib.sha256(f"{asks}\n\n{activity}".encode()).hexdigest()


async def _write(session_id: str) -> None:
    """One briefing, stored whatever happens — an error is news too, and it is not free."""
    activity = await asyncio.to_thread(transcripts.activity_since_last_user, session_id)
    asks = await asyncio.to_thread(asked.asks_of, session_id)
    file = transcripts.transcript_path(session_id)
    # Read before the model runs, not after: a transcript that moves while the model is thinking
    # is a session that has done something new, and marking it current would swallow that.
    moved = file.stat().st_mtime if file else 0.0
    fingerprint = hashlib.sha256(f"{asks}\n\n{activity}".encode()).hexdigest()
    summary, error = await summarize.summarize(session_id, activity, asks)
    if summary is None and error is None:
        # Nothing said and nothing wrong: the session has done nothing since they last spoke.
        # Still worth recording, or it is asked again on every sweep for the rest of the day.
        summary = load(session_id).get("summary")
    save(session_id, {
        "summary": summary,
        "headline": summarize.headline(summary),
        "hash": fingerprint,
        "mtime": moved,
        "written_at": time.time(),
        "error": error,
    })
    log.info("briefing for %s: %s", session_id[:8], error or f"{len(summary or '')} chars")
