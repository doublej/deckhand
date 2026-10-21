"""`deckhand-control-mcp`: the manager's own tools, forwarded to the daemon that runs them."""

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
    sent, kwargs_seen = [], []

    async def reach(method, path, **kwargs):
        sent.append((method, path, kwargs["json"]))
        kwargs_seen.append(kwargs)
        return {"error": "the Deckhand daemon is not answering", "code": "DAEMON_DOWN"}

    monkeypatch.setattr(manager.here, "reach", reach)
    monkeypatch.setattr(manager.here, "mine", lambda: None)
    assert manager.build().instructions == manager.INSTRUCTIONS
    forwarded = manager._forwarded("focus_session")
    answer = asyncio.run(forwarded({"session": "deckhand"}))
    assert sent == [("POST", "/manager/tools/focus_session", {"session": "deckhand"})]
    assert kwargs_seen[0]["headers"] == {"x-deckhand-for": "an agent"}
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
    assert len(names) == 17 and {"tmux_tree", "tmux_arrange", "tell_manager", "ask_to_end"} <= names
    shapes = {tool["name"]: tool["inputSchema"] for tool in answered.json()["result"]["tools"]}
    # What a handler defaults is not required: a voice agent leaving out `turns` was refused.
    assert shapes["read_session"]["required"] == ["session"]
    assert shapes["list_projects"]["required"] == []
    assert "match" in shapes["tmux_tree"]["properties"]
    # The scope is the point: the same token is refused by every other route.
    assert not pairing.allows(scoped)
    other = TestClient(app)
    other.headers["x-deckhand-token"] = scoped
    assert other.get("/sessions").status_code == 401


def test_the_manager_is_briefed_down_its_inbox_under_the_callers_name(monkeypatch):
    """`tell_manager` is the one way to the manager itself; it arrives as an agent, never as the
    person, with who sent it on the front."""
    sent = []

    async def reach(method, path, **kwargs):
        sent.append((method, path, kwargs))
        if path == "/manager/session":
            return {"session_id": "m1", "name": "deckhand-manager"}
        return {"delivered": True, "delivered_by": "socket"}

    monkeypatch.setattr(manager.here, "reach", reach)
    held = manager.talk.caller.set("voice-agent")
    try:
        answer = asyncio.run(manager._tell({"text": "the cleanup failed, follow up"}))
    finally:
        manager.talk.caller.reset(held)
    assert not answer["is_error"] and '"went": true' in answer["content"][0]["text"]
    method, path, kwargs = sent[1]
    assert (method, path, kwargs["params"]) == ("POST", "/sessions/m1/say", {"route": "socket"})
    assert kwargs["json"]["text"] == (
        "From voice-agent, over Deckhand's MCP: the cleanup failed, follow up")


def test_ending_is_asked_of_the_person_by_name(monkeypatch):
    sent = []

    async def reach(method, path, **kwargs):
        sent.append((method, path, kwargs["json"]))
        return {"id": "e1"}

    monkeypatch.setattr(manager.here, "reach", reach)
    monkeypatch.setattr(manager.here, "mine", lambda: {"name": "deckhand-2"})
    asyncio.run(manager._end({"names": ["velvet-pika"], "why": "idle 69h"}))
    assert sent == [("POST", "/end-requests",
                     {"sessions": ["velvet-pika"], "why": "idle 69h", "asker": "deckhand-2"})]


def test_what_a_borrowed_tool_did_is_written_under_its_callers_name(token, monkeypatch):
    """Or the panel shows a voice agent's work as the manager's own, and nobody can tell."""
    from deckhand_daemon.manager import routes, talk

    async def acting(args):
        talk.say("act", "started deckhand in multi-stack/deckhand")
        return {"content": [{"type": "text", "text": "started"}]}

    class Tool:
        handler = staticmethod(acting)

    monkeypatch.setattr(routes, "_tools", lambda: {"start_session": Tool})
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    c.post("/manager/tools/start_session", json={}, headers={"x-deckhand-for": "voice-agent"})
    talk.say("act", "the manager's own")
    assert [e["text"] for e in talk.entries()][-2:] == [
        "voice-agent: started deckhand in multi-stack/deckhand", "the manager's own"]
