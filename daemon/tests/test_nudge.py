"""The idle check: a session that stops with asks still open gets asked about them."""

import time

import pytest

from deckhand_daemon import nudge, sessions, tasks


@pytest.fixture
def deckhand_data(tmp_path, monkeypatch):
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))
    # The sweep reads the session's subagent folder, and a suite that answered that off the real
    # ~/.claude would pass or fail by what this Mac happens to be running.
    monkeypatch.setenv("DECKHAND_CLAUDE_HOME", str(tmp_path / "claude"))


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
    """What a restart forgets. What was asked lives in the test's own data dir."""
    nudge._quiet_since.clear()


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


def test_a_session_whose_subagents_are_working_is_left_alone(deckhand_data, monkeypatch):
    """The report this exists for: a turn stopped with a background agent still running, and the
    session was asked to account for the asks that agent was working through.

    Treated as `busy` is — the quiet clock restarts — rather than as a veto at the end. A veto
    would let the clock run out underneath the agents and fire the question the instant the last
    one stopped, which is the same interruption a minute later.
    """
    clear()
    session, sent = make_session(), []
    stub(monkeypatch, session, sent)
    tasks.add("s1", "wire the settings screen")
    working = {"any": True}
    monkeypatch.setattr(nudge.agents, "alive", lambda session_id, now=None: working["any"])

    now = time.time()
    quiet_since(now)
    assert nudge.sweep(now + nudge.SETTLE + 1) == []
    assert sent == []
    working["any"] = False
    # The clock restarted with the last sweep, so it waits out another SETTLE before asking.
    assert nudge.sweep(now + nudge.SETTLE + 2) == []
    assert nudge.sweep(now + 2 * nudge.SETTLE + 3) == ["s1"]


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


def test_asks_moving_along_are_not_a_new_question(deckhand_data, monkeypatch):
    """Seen 2026-09-14: a session answered "waiting on JJ", the summariser moved the ask to doing
    on reading that, and the same ask was asked about again. Nor may one ask finishing reopen the
    rest."""
    clear()
    session, sent = make_session(), []
    stub(monkeypatch, session, sent)
    blocked = tasks.add("s1", "decide what to leave out of the backup")
    finished = tasks.add("s1", "start the first upload")

    quiet_since(time.time())
    now = time.time() + nudge.SETTLE + 1
    assert nudge.sweep(now) == ["s1"]
    tasks.set_state("s1", blocked["id"], "doing")
    tasks.set_state("s1", finished["id"], "done")
    assert nudge.sweep(now + nudge.AGAIN + 1) == []
    assert len(sent) == 1


def test_a_restart_does_not_ask_the_same_question_again(deckhand_data, monkeypatch):
    """The daemon restarted 11 times on 2026-09-14, and while this was kept in memory every one of
    those restarts asked every owing session again."""
    clear()
    session, sent = make_session(), []
    stub(monkeypatch, session, sent)
    tasks.add("s1", "wire the settings screen")

    quiet_since(time.time())
    now = time.time() + nudge.SETTLE + 1
    assert nudge.sweep(now) == ["s1"]
    clear()                                # everything a restart forgets
    quiet_since(now + nudge.AGAIN)
    assert nudge.sweep(now + nudge.AGAIN + nudge.SETTLE + 1) == []
    assert len(sent) == 1


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


def test_a_sweep_that_raises_anything_does_not_end_the_watcher(monkeypatch):
    """Only `OSError` was caught, so any other exception ended the task for good, and silently."""
    import asyncio

    swept = []

    def sweep():
        swept.append(1)
        if len(swept) == 1:
            raise KeyError("a row nobody expected")

    monkeypatch.setattr(nudge, "POLL", 0)
    monkeypatch.setattr(nudge, "sweep", sweep)

    async def run():
        task = asyncio.create_task(nudge.watch())
        while len(swept) < 2 and not task.done():
            await asyncio.sleep(0.01)
        task.cancel()
        return task.done() and not task.cancelled()

    assert asyncio.run(asyncio.wait_for(run(), 5)) is False
    assert len(swept) >= 2
