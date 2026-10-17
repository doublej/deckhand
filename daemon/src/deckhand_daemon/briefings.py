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
from .reading.activity import activity_since_last_user
from .sessions import live, opencode, opencode_turns

# The providers a briefing can be written for: those with a history to read.
BRIEFED = ("claude", opencode.PROVIDER)

# Between two briefings. One model at a time, always: six sessions summarised at once is six
# models thinking, and nothing on the phone is waiting for any of them.
GAP = 4
# Between two briefings **of the same session**, which is a different floor and the one that was
# missing. `GAP` bounds how fast the worker writes; nothing bounded how often it wrote about the
# same session, so one fast-moving session took every slot for as long as it kept moving —
# measured, 20 in a row for `3f91172f` between 16:31 and 16:39 while the other five sat idle.
#
# `_due` answers "has anything happened", which is the right question for *whether* to buy a
# briefing and no answer at all to *how often*. Over the 5849 briefings in this Mac's log the
# median gap between two of one session was **26 seconds** and 59% were under 30 — a re-summary
# rate for something a person reads every few minutes. Simulated against that same log, this
# floor would have cut the model calls by 60% (5849 → 2362); 30 s cuts 39%, 120 s cuts 75%.
#
# It costs the phone nothing it was not already built for: a read is always handed the last
# briefing off disk, and `stale` goes on saying a newer one is on its way — it is, within a
# minute rather than within four seconds.
SAME_SESSION = 60.0
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
        # One session's own answer, never the whole queue's, and the cheap gate rather than
        # `_due`. Asking whether this id was in the queue meant walking every live session to
        # answer a boolean about one of them; asking `_due` then read a 4 MB tail per session
        # and parsed every line of it — 26 MB per `/briefings`, on a route the phone polls
        # every 12 s, to decide whether to draw a spinner.
        "stale": _moved(session_id),
    }


def _moved(session_id: str) -> bool:
    """Whether the transcript has moved since the worker last looked at this session.

    Exactly what `stale` means, and it costs a `stat`. It is not an approximation of `_due`:
    `_due` writes the new mtime down whenever it opens the expensive gate and finds nothing
    behind it, so a file that moved without saying anything is settled there rather than left
    reading stale here. Without that half this would be a spinner that never stopped.
    """
    moved = _mark(session_id)
    return moved is not None and load(session_id).get("mtime") != moved


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
    """The next session to write about: anything bumped, else the cycle, else nothing at all.

    **A bump is popped, so a refusal throws it away** — which was harmless while the only
    refusals were "gone" and "nothing has happened", and is not once `SAME_SESSION` refuses too.
    At the measured 26-second median between two briefings of one session, most bumps land
    inside that floor, and a bump destroyed for being early is somebody opening a session page
    and never being promoted for it. Only that one refusal puts the request back.
    """
    global _cursor
    # A Codex thread has no transcript to write a briefing from, so it is never in the cycle.
    # Nor is an Agent SDK run — this daemon's own briefings and manager among them, which were
    # being briefed in their turn whenever the daemon ran in a pane: a summary of a summary.
    runs = _model_runs()
    live = [s.session_id for s in sessions.live_sessions()
            if s.provider in BRIEFED and s.pid not in runs]
    while _bumped:
        wanted = _bumped.pop(0)
        if wanted not in live:
            continue
        if _due(wanted):
            return wanted
        if _too_soon(wanted):
            # The person is looking at this session now, so the request waits the floor out
            # rather than being dropped. `break` and not `continue`: reinserting at the front
            # of a loop that pops from the front is otherwise forever.
            _bumped.insert(0, wanted)
            break
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

    Three gates, cheapest first. How long ago the last one was written settles it without
    touching the disk at all — see `SAME_SESSION` for why that gate is here and what it was
    costing. Then the transcript's own mtime, for a session nobody has touched since the last
    sweep. Only if the file moved is it read, because plenty of what Claude Code appends (a mode
    change, an attachment) is not activity anybody wants a briefing about.

    A session that has never had a briefing passes the first gate outright: there is no
    `written_at` to be inside, and the one moment a briefing is worth buying immediately is the
    moment there is none.
    """
    if _too_soon(session_id):
        return False
    kept = load(session_id)
    moved = _mark(session_id)
    if moved is None or kept.get("mtime") == moved:
        return False
    if kept.get("hash") != _hash(session_id):
        return True
    # The file moved and nothing in it did. Write the new mtime down rather than buying the
    # expensive gate to reach this same answer on every sweep from now on — and so that
    # `_moved`, which is all a read is allowed to spend, stops saying a briefing is on its way
    # when the worker has already looked and decided none is.
    save(session_id, kept | {"mtime": moved})
    return False


def _too_soon(session_id: str) -> bool:
    """Whether this session was briefed so recently that another one is not worth buying.

    Its own function rather than a line inside `_due`, because `_next` has to tell this refusal
    from the others: every other reason to say no means there is nothing to write about, and
    this one means there is and it can wait.
    """
    return time.time() - load(session_id).get("written_at", 0.0) < SAME_SESSION


def _mark(session_id: str) -> float | None:
    """When the session last moved, or None when there is nothing to read: its transcript's
    mtime, or for an OpenCode session — which has no file — the `updated` time its service keeps."""
    if opencode.owns(session_id):
        found = (s.updated_at for s in sessions.live_sessions() if s.session_id == session_id)
        return next(found, None)
    file = transcripts.transcript_path(session_id)
    try:
        return file.stat().st_mtime if file else None
    except OSError:
        return None


def _read(session_id: str) -> tuple[str, str]:
    """The asks and the activity, the two things `summarize` is handed and `_hash` keys on.

    OpenCode has no `AskUserQuestion` to read asks out of, and a service that does not answer
    reads as nothing new rather than taking the worker down with it.
    """
    if not opencode.owns(session_id):
        return asked.asks_of(session_id), activity_since_last_user(session_id)
    try:
        return "", opencode_turns.activity(session_id)
    except opencode.OpenCodeError as error:
        log.warning("briefing for %s: OpenCode did not answer: %s", session_id, error)
        return "", ""


def _model_runs() -> set[int]:
    """The pids whose session record says the Agent SDK started them, not a person."""
    return {r["pid"] for r in live._records() if r.get("entrypoint") == "sdk-py"}


def _state(session_id: str) -> str:
    """Whether the session is working now or its turn has ended, and the time, for the model."""
    now = time.strftime("%H:%M")
    if opencode.owns(session_id):
        found = next((s for s in sessions.live_sessions() if s.session_id == session_id), None)
        ended = found.updated_at if found and found.status != "busy" else 0.0
    else:
        ended = transcripts.turn_ended(session_id)
    if not ended:
        return f"working now (it is {now})"
    return f"turn ended at {time.strftime('%H:%M', time.localtime(ended))}; it is {now} now"


def _hash(session_id: str) -> str:
    """What the session has done, as one string. The same reading `summarize` is handed."""
    asks, activity = _read(session_id)
    return hashlib.sha256(f"{asks}\n\n{activity}".encode()).hexdigest()


async def _write(session_id: str) -> None:
    """One briefing, stored whatever happens — an error is news too, and it is not free."""
    # Marked before the model runs, not after: a transcript that moves while the model is
    # thinking is a session that has done something new, and marking it current would swallow that.
    moved = await asyncio.to_thread(_mark, session_id) or 0.0
    asks, activity = await asyncio.to_thread(_read, session_id)
    state = await asyncio.to_thread(_state, session_id)
    fingerprint = hashlib.sha256(f"{asks}\n\n{activity}".encode()).hexdigest()
    summary, error = await summarize.summarize(session_id, activity, asks, state)
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
