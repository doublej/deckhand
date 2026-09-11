"""The idle check: a session that stops with asks still open gets asked about them."""

import time

import pytest

from deckhand_daemon import nudge, sessions, tasks


@pytest.fixture
def deckhand_data(tmp_path, monkeypatch):
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))


def make_session(session_id="s1", status="idle"):
    return sessions.Session(
        session_id=session_id, pid=1, name="deckhand", cwd="/tmp",
        status=status, updated_at=0.0, tty="ttys000", pane=None,
    )


def stub(monkeypatch, session, sent):
    monkeypatch.setattr(sessions, "live_sessions", lambda: [session])
    monkeypatch.setattr(nudge.sessions, "live_sessions", lambda: [session])
    monkeypatch.setattr(nudge.deliver, "deliver",
                        lambda s, text, route="auto": (sent.append(text), ("socket", None))[1])


def clear():
    nudge._quiet_since.clear()
    nudge._asked_about.clear()


def quiet_since(now):
    """One sweep to note that the session is quiet. Nothing is asked on the sweep that finds it."""
    assert nudge.sweep(now) == []


def test_a_quiet_session_with_open_asks_is_asked_about_them(deckhand_data, monkeypatch):
    clear()
    session, sent = make_session(), []
    stub(monkeypatch, session, sent)
    tasks.add("s1", "wire the settings screen")

    now = time.time()
    quiet_since(now)                       # quiet, but only just
    assert nudge.sweep(now + nudge.SETTLE + 1) == ["s1"]
    assert "wire the settings screen" in sent[0]
    # It says what it is. A session must be able to tell this from the person typing.
    assert "not JJ" in sent[0]


def test_a_busy_session_is_left_alone(deckhand_data, monkeypatch):
    clear()
    session, sent = make_session(status="busy"), []
    stub(monkeypatch, session, sent)
    tasks.add("s1", "wire the settings screen")

    quiet_since(time.time())
    assert nudge.sweep(time.time() + nudge.SETTLE + 1) == []
    assert sent == []


def test_a_finished_list_is_nothing_to_ask_about(deckhand_data, monkeypatch):
    clear()
    session, sent = make_session(), []
    stub(monkeypatch, session, sent)
    task = tasks.add("s1", "wire the settings screen")
    tasks.set_state("s1", task["id"], "done")

    quiet_since(time.time())
    assert nudge.sweep(time.time() + nudge.SETTLE + 1) == []


def test_the_same_list_is_not_asked_about_twice(deckhand_data, monkeypatch):
    """The runaway this exists to prevent: a session that cannot finish an ask must still stop."""
    clear()
    session, sent = make_session(), []
    stub(monkeypatch, session, sent)
    tasks.add("s1", "wire the settings screen")

    quiet_since(time.time())
    now = time.time() + nudge.SETTLE + 1
    assert nudge.sweep(now) == ["s1"]
    assert nudge.sweep(now + nudge.AGAIN + 1) == []
    assert len(sent) == 1


def test_a_changed_list_waits_for_the_cooldown(deckhand_data, monkeypatch):
    """The other runaway: a list churning through a job nobody can end."""
    clear()
    session, sent = make_session(), []
    stub(monkeypatch, session, sent)
    tasks.add("s1", "wire the settings screen")

    quiet_since(time.time())
    now = time.time() + nudge.SETTLE + 1
    assert nudge.sweep(now) == ["s1"]
    tasks.add("s1", "and the crash on rotate")
    assert nudge.sweep(now + 60) == []
    assert nudge.sweep(now + nudge.AGAIN + 1) == ["s1"]
    assert "crash on rotate" in sent[1]


def test_the_question_is_addressed_to_the_session_by_name(deckhand_data, monkeypatch):
    """A misrouted nudge must be answerable. Unnamed, another session's asks read as your own."""
    asked = nudge._question([{"id": "t1", "state": "todo", "text": "ship it"}], "quiet-gannet")
    assert "quiet-gannet" in asked
    assert "misrouted" in asked
    # A session that checks the wrong name declares a false misroute and answers nothing, so
    # the message says where the name comes from and which way to fall when unsure.
    assert "~/.claude/sessions/" in asked
    assert "unsure" in asked
    # Answered by messaging a peer instead, the reply never reaches the summariser, which
    # reads the transcript. Observed live: framelink answered t35 to a peer, not in its turn.
    assert "your own reply in this session" in asked
    assert "{" not in asked, "a placeholder left unfilled goes to a live session as the word"
