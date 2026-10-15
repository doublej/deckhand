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


def test_mcp_over_http_takes_a_manager_token_that_opens_nothing_else(token):
    from starlette.applications import Starlette
    from starlette.routing import Route

    from deckhand_daemon import pairing
    from deckhand_daemon.mcp import remote
    from deckhand_daemon.pairing import devices

    scoped, _ = devices.mint("tool", pairing.MANAGER, scope=pairing.MANAGER)
    served = Starlette(routes=[Route("/mcp", remote.endpoint)], lifespan=lambda _: remote.serving())
    listed = {"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}
    accept = {"accept": "application/json, text/event-stream"}
    with TestClient(served) as c:
        assert c.post("/mcp", json=listed, headers=accept).status_code == 401
        answered = c.post("/mcp", json=listed, headers={**accept, "authorization": f"Bearer {scoped}"})
    assert answered.status_code == 200
    names = {tool["name"] for tool in answered.json()["result"]["tools"]}
    assert len(names) == 14 and {"tmux_tree", "tmux_arrange"} <= names
    # The scope is the point: the same token is refused by every other route.
    assert not pairing.allows(scoped)
    other = TestClient(app)
    other.headers["x-deckhand-token"] = scoped
    assert other.get("/sessions").status_code == 401
