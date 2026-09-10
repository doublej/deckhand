import json

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
        sessions,
        "_panes",
        lambda: {"ttys014": sessions.Pane("ITERM-A", "win-1", "180", "◐ warm-okapi")},
    )
    assert [s.name for s in sessions.live_sessions()] == ["warm-okapi"]


def test_every_session_survives_when_iterm_is_unavailable(claude_home, monkeypatch):
    monkeypatch.setattr(sessions, "_panes", dict)
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
    monkeypatch.setattr(sessions, "_processes", lambda: {4243: "ttys015"})
    sessions.live_sessions()
    assert sessions.succeeded_by(was) == ""


def test_an_id_never_seen_here_is_not_guessed_at(claude_home):
    sessions.live_sessions()
    assert sessions.succeeded_by("eeee1111-2222-3333-4444-555566667777") == ""
