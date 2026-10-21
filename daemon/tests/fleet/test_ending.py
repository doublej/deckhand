"""Ending a session by its process: on the machine it runs on, after a fresh look there."""

from __future__ import annotations

import signal

import httpx
import pytest
from fastapi.testclient import TestClient

from deckhand_daemon import config, deliver
from deckhand_daemon.fleet import hand, remote
from deckhand_daemon.sessions import Session, ending

WARM = "aaaa1111-2222-3333-4444-555566667777"


@pytest.fixture
def killed(monkeypatch):
    """Every signal sent, and none of them sent for real."""
    seen = []
    monkeypatch.setattr(ending.os, "kill", lambda pid, sig: seen.append((pid, sig)))
    return seen


def paneless(**changed) -> Session:
    return Session(**({"session_id": WARM, "pid": 4242, "name": "warm-okapi", "cwd": "/x",
                       "status": "idle", "updated_at": 0.0, "tty": "", "pane": None} | changed))


def test_the_pid_signalled_is_the_one_listed_now(claude_home, killed):
    assert ending.end_here(WARM) is None
    assert killed == [(4242, signal.SIGTERM)]


def test_a_session_that_went_is_not_signalled(claude_home, killed):
    assert ending.end_here("cccc1111-2222-3333-4444-555566667777") == ending.GONE
    assert killed == []


def test_a_process_gone_under_the_signal_says_so(claude_home, monkeypatch):
    def gone(pid, sig):
        raise ProcessLookupError

    monkeypatch.setattr(ending.os, "kill", gone)
    assert "already gone" in ending.end_here(WARM)


def test_exit_on_a_session_with_no_pane_ends_its_process(claude_home, killed):
    assert deliver.control(paneless(), "exit") is None
    assert killed == [(4242, signal.SIGTERM)]
    assert "not in a tmux pane" in deliver.control(paneless(), "compact")
    assert len(killed) == 1


def test_a_session_on_another_machine_is_ended_by_its_hand(claude_home, killed, monkeypatch):
    asked = []
    monkeypatch.setattr(remote, "end_on", lambda machine, sid: asked.append((machine, sid)))
    assert deliver.control(paneless(machine="ubuntu"), "exit") is None
    assert asked == [("ubuntu", WARM)] and killed == []


def test_a_session_with_no_process_of_its_own_is_refused(claude_home, killed):
    assert "no process" in ending.end(paneless(pid=0, provider="opencode"))
    assert killed == []


def test_the_hand_ends_what_it_lists(claude_home, killed, token):
    answered = TestClient(hand.app).post(f"/sessions/{WARM}/end",
                                         headers={config.TOKEN_HEADER: token})
    assert answered.json() == {"error": None}
    assert killed == [(4242, signal.SIGTERM)]


@pytest.mark.parametrize(("status", "body", "said"), [
    (200, {"error": None}, None),
    (200, {"error": ending.GONE}, ending.GONE),
    (404, {}, "too old"),
])
def test_the_hands_answer_is_read_back(monkeypatch, status, body, said):
    monkeypatch.setattr(remote, "_base", lambda machine: "http://127.0.0.1:1")
    monkeypatch.setattr(remote.httpx, "post",
                        lambda url, **kw: httpx.Response(status, json=body))
    answer = remote.end_on("ubuntu", WARM)
    assert answer == said if said in (None, ending.GONE) else said in answer
