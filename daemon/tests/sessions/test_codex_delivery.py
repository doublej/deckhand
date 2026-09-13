"""Words into a Codex thread: which lane, and what is refused before anything is sent."""

import asyncio
import time

import pytest

from deckhand_daemon import deliver, nudge, tasks
from deckhand_daemon.manager import doing
from deckhand_daemon.mcp import server
from deckhand_daemon.sessions import Session, codex

WORDS = [{"type": "text", "text": "run the tests"}]


def plan(status="idle"):
    return Session(session_id="t-1", pid=0, name="plan", cwd="/tmp", status=status,
                   updated_at=0.0, tty="", pane=None, provider="codex")


def app_server(monkeypatch, running=None):
    """Codex behind the seam, with `running` as the turn in progress or none. Returns the calls."""
    calls = []

    def request(method, params=None, timeout=None):
        calls.append((method, params))
        if method == "thread/turns/list":
            status = "inProgress" if running else "completed"
            return {"data": [{"id": running or "turn-old", "status": status, "items": []}]}
        return {"turnId": running} if method == "turn/steer" else {}

    monkeypatch.setattr(codex, "request", request)
    return calls


def test_an_idle_thread_gets_a_new_turn_in_the_persons_own_words(monkeypatch):
    calls = app_server(monkeypatch)
    assert deliver.deliver(plan(), "  run  the tests ") == ("codex-direct", None)
    assert calls == [("turn/start", {"threadId": "t-1", "input": WORDS})]


def test_a_busy_thread_is_steered_into_the_turn_it_is_running(monkeypatch):
    calls = app_server(monkeypatch, running="turn-9")
    assert deliver.deliver(plan("busy"), "run the tests", "keyboard") == ("codex-steered", None)
    assert calls[-1] == ("turn/steer",
                         {"threadId": "t-1", "input": WORDS, "expectedTurnId": "turn-9"})


def test_a_busy_row_whose_turn_has_just_ended_gets_a_new_turn(monkeypatch):
    calls = app_server(monkeypatch)
    assert deliver.deliver(plan("busy"), "run the tests") == ("codex-direct", None)
    assert [method for method, _ in calls] == ["thread/turns/list", "turn/start"]


def test_the_socket_route_is_refused_rather_than_given_the_persons_authority(monkeypatch):
    calls = app_server(monkeypatch)
    taken, error = deliver.deliver(plan(), "run the tests", "socket")
    assert taken is None and "no peer inbox" in error and calls == []


def test_a_slash_command_is_refused_before_anything_is_sent(monkeypatch):
    calls = app_server(monkeypatch)
    taken, error = deliver.deliver(plan(), "/compact now")
    assert taken is None and "/compact" in error and calls == []


def test_codex_saying_no_comes_back_as_the_reason(monkeypatch):
    def refuse(method, params=None, timeout=None):
        raise codex.CodexError("thread not loaded")

    monkeypatch.setattr(codex, "request", refuse)
    taken, error = deliver.deliver(plan(), "run the tests")
    assert taken is None and "thread not loaded" in error


def test_a_stop_interrupts_the_running_turn_and_says_so_when_there_is_none(monkeypatch):
    calls = app_server(monkeypatch, running="turn-9")
    assert codex.interrupt(plan("busy")) is None
    assert calls[-1] == ("turn/interrupt", {"threadId": "t-1", "turnId": "turn-9"})
    app_server(monkeypatch)
    assert "no turn running" in codex.interrupt(plan())


def test_the_manager_does_not_speak_into_a_codex_thread(monkeypatch):
    monkeypatch.setattr(doing, "find", lambda wanted: plan())
    monkeypatch.setattr(doing.deliver, "deliver", lambda *a, **k: pytest.fail("nothing is sent"))
    answer = doing.speak("plan", "carry on")["content"][0]["text"]
    assert "Codex thread" in answer and "nothing was sent" in answer


def test_the_idle_check_leaves_a_codex_thread_alone(tmp_path, monkeypatch):
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setattr(nudge, "_quiet_since", {})
    monkeypatch.setattr(nudge.deliver, "deliver", lambda *a, **k: pytest.fail("not the person"))
    tasks.add("t-1", "finish the plan")
    now = time.time()
    assert nudge._consider(plan(), now) is False
    assert nudge._consider(plan(), now + nudge.SETTLE + 1) is False


def test_the_agents_tool_refuses_a_codex_thread_before_saying_anything(monkeypatch):
    sent = []

    async def reach(method, path, **kwargs):
        if path == "/sessions":
            return {"sessions": [{"session_id": "t-1", "name": "plan", "provider": "codex"}]}
        sent.append(path)
        return {"delivered": True}

    monkeypatch.setattr(server.here, "reach", reach)
    said = asyncio.run(server.say_to_session("plan", "carry on"))
    assert said["went"] is False and "Codex thread" in said["why"] and sent == []
