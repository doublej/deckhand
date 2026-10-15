"""`deckhand-manager-mcp`: the manager's own tools, forwarded to the daemon that runs them."""

import asyncio

from fastapi.testclient import TestClient

from deckhand_daemon.app import app
from deckhand_daemon.mcp import manager


def test_the_route_runs_the_managers_own_tool(token):
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    answered = c.post("/manager/tools/read_settings", json={})
    assert answered.status_code == 200
    assert answered.json()["text"].startswith("globally:")
    # Absence is the refusal: a verb the manager has no tool for has no route either.
    assert c.post("/manager/tools/stop_session", json={}).status_code == 404


def test_every_tool_is_forwarded_and_a_daemon_that_is_down_is_said(monkeypatch):
    sent = []

    async def reach(method, path, **kwargs):
        sent.append((method, path, kwargs["json"]))
        return {"error": "the Deckhand daemon is not answering", "code": "DAEMON_DOWN"}

    monkeypatch.setattr(manager.here, "reach", reach)
    assert manager.build().instructions == manager.__doc__
    forwarded = manager._forwarded("focus_session")
    answer = asyncio.run(forwarded({"session": "deckhand"}))
    assert sent == [("POST", "/manager/tools/focus_session", {"session": "deckhand"})]
    assert answer["is_error"] and "not answering" in answer["content"][0]["text"]
