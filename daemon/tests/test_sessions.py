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
