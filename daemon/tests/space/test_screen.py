"""`/sessions/{id}/screen`: the pane's rows as iTerm reads them, shared between polls."""

from __future__ import annotations

import subprocess
from types import SimpleNamespace

import pytest

from deckhand_daemon import saying
from deckhand_daemon.space import screen

READ = "⏺ done\n\n> next\x00step\n   \n\n"


@pytest.fixture
def pane(monkeypatch):
    calls = []

    async def live(session_id):
        return SimpleNamespace(pane=SimpleNamespace(iterm_session_id="P1"), name="s")

    def run(argv, **kw):
        calls.append(argv)
        return subprocess.CompletedProcess(argv, 0, stdout=READ, stderr="")

    monkeypatch.setattr(saying, "live_session", live)
    monkeypatch.setattr(screen.subprocess, "run", run)
    monkeypatch.setattr(screen, "_read", {})
    return calls


def test_the_rows_come_back_without_the_blank_tail(client, head, pane):
    answered = client.get("/sessions/any/screen", headers=head).json()
    assert answered["lines"] == ["⏺ done", "", "> next step"]
    assert pane == [["it2", "session", "read", "-s", "P1"]]


def test_polls_inside_fresh_share_one_read(client, head, pane):
    for _ in range(3):
        client.get("/sessions/any/screen", headers=head)
    assert len(pane) == 1


def test_no_pane_is_a_409(client, head, monkeypatch):
    async def live(session_id):
        return SimpleNamespace(pane=None, name="s")

    monkeypatch.setattr(saying, "live_session", live)
    answered = client.get("/sessions/any/screen", headers=head)
    assert answered.status_code == 409
