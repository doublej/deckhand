import json
import time
from datetime import UTC, datetime

import pytest

from deckhand_daemon import sessions


def test_only_running_sessions_are_listed(claude_home):
    names = [s.name for s in sessions.live_sessions()]
    assert names == ["warm-okapi", "cold-otter"]  # busiest first, dead-mole's pid is gone


def test_session_carries_its_iterm_pane(claude_home):
    first = sessions.live_sessions()[0]
    assert first.pane.iterm_session_id == "ITERM-A"
    assert first.pane.window_id == "win-1"
    assert first.to_json()["folder"] == "shop"


def test_sessions_without_a_pane_are_dropped_while_iterm_answers(claude_home, monkeypatch):
    monkeypatch.setattr(
        sessions.panes,
        "lookup",
        lambda: {"ttys014": sessions.Pane("ITERM-A", "win-1", "180", "◐ warm-okapi")},
    )
    assert [s.name for s in sessions.live_sessions()] == ["warm-okapi"]


def test_ps_is_asked_only_about_the_pids_that_have_a_record(claude_home, monkeypatch):
    """Narrowing what `ps` is asked must not narrow the join it answers.

    `ps -eo pid=,tty=,command=` pulls every process's whole argv out of the kernel — 1.8-3.5 s
    over the 1254 processes on this Mac, paid on every listing. Only the pids with a session
    record were ever read out of it, so those are what it is asked about now; the dead one is
    still among them, because being asked and being alive are what this call tells apart.
    """
    asked: list[set[int]] = []

    def watched(pids):
        asked.append(pids)
        return {4242: "ttys014", 4243: "ttys015"}

    monkeypatch.setattr(sessions.live, "_processes", watched)
    listed = sessions.live_sessions()

    assert asked == [{4242, 4243, 9999}]
    assert [s.name for s in listed] == ["warm-okapi", "cold-otter"]


def test_one_listing_is_shared_rather_than_rebuilt_for_every_route(claude_home, monkeypatch):
    """Nearly every route in the daemon asks for this, and building it costs two subprocesses.

    The phone polls several of them at once — turns every 1.1 s, the rail every 4 s, the deck
    every 6 s — and each arrived as its own threadpool thread sitting on its own `ps`. Forty of
    those is the whole pool, and then every route queues, `/health` with them.
    """
    monkeypatch.setattr(sessions.live, "LISTING_TTL", 30.0)
    asked: list[set[int]] = []

    def watched(pids):
        asked.append(pids)
        return {4242: "ttys014", 4243: "ttys015"}

    monkeypatch.setattr(sessions.live, "_processes", watched)

    first = sessions.live_sessions()
    again = sessions.live_sessions()
    both = sessions.live_sessions(iterm_only=False)

    assert len(asked) == 1  # three routes' worth of listing, one `ps`
    assert [s.name for s in again] == [s.name for s in first]
    assert [s.name for s in both] == [s.name for s in first]


def test_the_shared_listing_expires_on_its_own(claude_home, monkeypatch):
    """A cache over the pid join has to be a window and not a memory.

    Nothing calls `forget_listing` on the polling path, so expiry is the only thing that lets a
    session that has stopped running disappear from the phone — and that join is what the whole
    repo hangs off. The window is shorter than every poll the app makes.
    """
    monkeypatch.setattr(sessions.live, "LISTING_TTL", 0.05)
    assert [s.name for s in sessions.live_sessions()] == ["warm-okapi", "cold-otter"]

    monkeypatch.setattr(sessions.live, "_processes", lambda pids: {4243: "ttys015"})
    time.sleep(0.06)

    assert [s.name for s in sessions.live_sessions()] == ["cold-otter"]


def test_a_caller_waiting_on_a_new_session_can_make_it_ask_again(claude_home, monkeypatch):
    """`projects.starting` polls for a session that did not exist when the listing was built."""
    monkeypatch.setattr(sessions.live, "LISTING_TTL", 30.0)
    sessions.live_sessions()
    _clear(claude_home, 4242, "dddd1111-2222-3333-4444-555566667777")

    sessions.forget_listing()

    assert sessions.live_sessions()[0].session_id == "dddd1111-2222-3333-4444-555566667777"


def test_every_session_survives_when_iterm_is_unavailable(claude_home, monkeypatch):
    monkeypatch.setattr(sessions.panes, "lookup", dict)
    listed = sessions.live_sessions()
    assert [s.name for s in listed] == ["warm-okapi", "cold-otter"]
    assert listed[0].pane is None


def _clear(home, pid, new_id):
    """What `/clear` does to a record: same pid, same pane, same socket, same name, new id."""
    record = home / "sessions" / f"{pid}.json"
    rec = json.loads(record.read_text())
    rec["sessionId"] = new_id
    record.write_text(json.dumps(rec))


def test_a_cleared_session_is_still_reachable_by_the_id_the_phone_holds(claude_home):
    """The phone opened the page before the clear and has no way to know the conversation was
    retired: the name, the pane and the socket it can see are all still there."""
    was = sessions.live_sessions()[0].session_id
    _clear(claude_home, 4242, "dddd1111-2222-3333-4444-555566667777")
    now = next(s for s in sessions.live_sessions() if s.pid == 4242).session_id
    assert now != was
    assert sessions.succeeded_by(was) == now


def test_an_id_from_a_pid_that_has_gone_resolves_to_nothing(claude_home, monkeypatch):
    """Pids are recycled. An id left pointing at a dead one would answer with whatever
    unrelated session the OS handed that number to next."""
    was = sessions.live_sessions()[0].session_id
    _clear(claude_home, 4242, "dddd1111-2222-3333-4444-555566667777")
    sessions.live_sessions()
    monkeypatch.setattr(sessions.live, "_processes", lambda pids: {4243: "ttys015"})
    sessions.live_sessions()
    assert sessions.succeeded_by(was) == ""


def test_an_id_never_seen_here_is_not_guessed_at(claude_home):
    sessions.live_sessions()
    assert sessions.succeeded_by("eeee1111-2222-3333-4444-555566667777") == ""


def _transcript(home, session_id, *entries):
    """A transcript for one session, of whatever entries the test cares about."""
    path = home / "projects" / "-Users-jj-dev" / f"{session_id}.jsonl"
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n")
    return path


def _said(stop_reason, when="2026-09-11T12:32:51.000Z"):
    return {"type": "assistant", "timestamp": when, "message": {"stop_reason": stop_reason}}


def _busy_one(claude_home):
    """warm-okapi: the fixture's busy session, and its id."""
    return next(s for s in sessions.live_sessions() if s.name == "warm-okapi").session_id


def test_a_busy_record_its_own_transcript_contradicts_is_listed_idle(claude_home):
    """Claude Code stops rewriting the record for some sessions: measured here, four turns
    began and ended after the stamp froze at `busy` and the phone read WORKING for half an
    hour at a session sitting at its prompt."""
    sid = _busy_one(claude_home)
    _transcript(claude_home, sid, _said("tool_use", "2026-09-11T12:30:00.000Z"), _said("end_turn"))
    listed = next(s for s in sessions.live_sessions() if s.session_id == sid)
    assert listed.status == "idle"
    # And since the turn ended, not since the record froze — the rail fades a row by this.
    assert listed.updated_at == pytest.approx(
        datetime(2026, 9, 11, 12, 32, 51, tzinfo=UTC).timestamp()
    )


def test_a_busy_record_is_kept_while_the_session_is_still_mid_turn(claude_home):
    """The long turn is why the age of the claim cannot be the test: measured on this Mac, a
    session stale by 1546 s was working and one stale by 2036 s was finished."""
    sid = _busy_one(claude_home)
    _transcript(claude_home, sid, _said("end_turn", "2026-09-11T12:30:00.000Z"), _said("tool_use"))
    assert next(s for s in sessions.live_sessions() if s.session_id == sid).status == "busy"


def test_a_prompt_with_nothing_said_after_it_is_not_a_finished_turn(claude_home):
    """The window between a message arriving and the model's first word. Without this the
    session flickers idle on every phone poll that lands in it."""
    sid = _busy_one(claude_home)
    _transcript(claude_home, sid, _said("end_turn"), {"type": "user", "message": {"content": "go"}})
    assert next(s for s in sessions.live_sessions() if s.session_id == sid).status == "busy"


def test_a_subagents_own_rounds_do_not_end_the_session_they_run_in(claude_home):
    sid = _busy_one(claude_home)
    _transcript(claude_home, sid, _said("tool_use"), _said("end_turn") | {"isSidechain": True})
    assert next(s for s in sessions.live_sessions() if s.session_id == sid).status == "busy"


def test_an_idle_record_is_never_raised_to_busy(claude_home):
    """The transcript is read to catch a record over-claiming and for nothing else."""
    sid = next(s for s in sessions.live_sessions() if s.name == "cold-otter").session_id
    _transcript(claude_home, sid, _said("tool_use"))
    listed = next(s for s in sessions.live_sessions() if s.session_id == sid)
    assert listed.status == "idle"
