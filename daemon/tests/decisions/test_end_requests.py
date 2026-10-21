"""`POST /end-requests`: an agent asks, and only the person's signed Allow ends anything."""

from __future__ import annotations

import signal

import pytest
from fastapi.testclient import TestClient
from test_notify_callbacks import pushed, tapped  # noqa: F401 — `pushed` is a fixture

from deckhand_daemon import config
from deckhand_daemon.app import app
from deckhand_daemon.push import routes
from deckhand_daemon.sessions import ending

AWAY = {"session_id": "dddd1111-2222-3333-4444-555566667777", "name": "velvet-pika",
        "machine": "ubuntu", "pid": 77, "provider": "claude"}


@pytest.fixture
def listed(monkeypatch):
    """Every machine's listing: this Mac's, plus `listed` rows from elsewhere."""
    rows = [AWAY]

    async def listings(local):
        return local + rows

    monkeypatch.setattr(routes.fleet, "listings", listings)
    return rows


@pytest.fixture
def ended(monkeypatch):
    seen = []
    monkeypatch.setattr(ending.os, "kill", lambda pid, sig: seen.append((pid, sig)))
    monkeypatch.setattr(ending.remote, "end_on", lambda m, sid: seen.append((m, sid)))
    return seen


def asked(token, names, why="idle for two days"):
    return TestClient(app).post("/end-requests", json={
        "sessions": names, "why": why, "asker": "deckhand"},
        headers={config.TOKEN_HEADER: token})


def test_the_card_names_each_session_and_ends_nothing(token, pushed, listed, ended):  # noqa: F811
    answered = asked(token, ["velvet-pika", "cold-otter"])
    assert answered.status_code == 202, answered.text
    assert answered.json()["sessions"] == ["velvet-pika", "cold-otter"]
    card = pushed[0]
    assert card.name == "deckhand asks to end 2 sessions"
    assert card.line.startswith("velvet-pika (ubuntu), cold-otter")
    assert (card.accept, card.decline) == ("End", "Keep")
    assert ended == []


def test_allow_ends_each_where_it_runs(token, pushed, listed, ended, phone, key):  # noqa: F811
    nid = asked(token, ["velvet-pika", "cold-otter"]).json()["id"]
    answered = tapped(phone, key, nid)
    assert answered.status_code == 200, answered.text
    assert ended == [("ubuntu", AWAY["session_id"]), (4243, signal.SIGTERM)]
    assert tapped(phone, key, nid).status_code == 200
    assert len(ended) == 2


def test_deny_ends_none(token, pushed, listed, ended, phone, key):  # noqa: F811
    nid = asked(token, ["velvet-pika"]).json()["id"]
    assert tapped(phone, key, nid, "deny").json() == {"action": "deny", "status": 200}
    assert ended == []


@pytest.mark.parametrize(("names", "rows", "why"), [
    (["nobody"], [], "idle"),
    (["velvet-pika"], [AWAY | {"session_id": "eeee", "machine": "fractal"}], "idle"),
    (["plan"], [{"session_id": "t-1", "name": "plan", "provider": "codex", "pid": 0}], "idle"),
    (["velvet-pika"], [], " "),
    ([], [], "idle"),
])
def test_what_is_refused(token, pushed, listed, ended, names, rows, why):  # noqa: F811
    listed.extend(rows)
    assert asked(token, names, why).status_code == 400
    assert pushed == [] and ended == []
