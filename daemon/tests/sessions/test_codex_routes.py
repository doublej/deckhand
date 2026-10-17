"""The routes a Codex thread answers differently, and starting one from the project picker."""

import anyio
import pytest
from fastapi.testclient import TestClient

from deckhand_daemon import briefings, config
from deckhand_daemon.app import app
from deckhand_daemon.orders import kept
from deckhand_daemon.projects import routes, sources, starting
from deckhand_daemon.sessions import codex

TID = "01a09b82-64b0-7f82-8e43-838622fbc02e"
SHOP = "/Users/jj/dev/web/shop"
ROUND = {"id": "turn-1", "status": "completed", "startedAt": 1789316110, "completedAt": 1789316200,
         "items": [
             {"type": "userMessage", "id": "u", "content": [{"type": "text", "text": "Plan it."}]},
             {"type": "reasoning", "id": "r", "summary": ["Reading the schema first"]},
             {"type": "commandExecution", "id": "c", "command": "just check", "status": "failed",
              "aggregatedOutput": "1 failed", "commandActions": [], "cwd": SHOP},
             {"type": "agentMessage", "id": "a", "text": "One test fails."},
             {"type": "fileChange", "id": "f", "status": "inProgress",
              "changes": [{"path": f"{SHOP}/x.py", "kind": {"type": "add"}, "diff": "+x"}]},
         ]}
RUNNING = {"id": "turn-2", "status": "inProgress", "startedAt": 1789316300, "items": []}


@pytest.fixture
def phone(claude_home, monkeypatch):
    """A paired phone, and a Mac whose app server has one busy Codex thread. Returns the calls."""
    calls = []

    def request(method, params=None, timeout=None):
        calls.append((method, params))
        if method == "thread/loaded/list":
            return {"data": [TID]}
        if method == "thread/read":
            return {"thread": {"id": TID, "name": "Plan", "cwd": SHOP, "updatedAt": 1789316385,
                               "status": {"type": "active", "activeFlags": []}}}
        if method == "thread/turns/list":
            return {"data": [RUNNING, ROUND] if params["itemsView"] == "full" else [RUNNING]}
        if method == "thread/start":
            return {"thread": {"id": "t-new", "cwd": params["cwd"], "status": {"type": "idle"},
                               "updatedAt": 1789316400}}
        return {}

    monkeypatch.setattr(codex, "request", request)
    client = TestClient(app)
    client.headers["x-deckhand-token"] = config.token()
    return client, calls


def test_the_listing_says_which_provider_each_row_is(phone):
    client, _ = phone
    rows = {row["session_id"]: row for row in client.get("/sessions").json()["sessions"]}
    assert rows[TID]["provider"] == "codex" and rows[TID]["pane"] is None
    assert {row["provider"] for sid, row in rows.items() if sid != TID} == {"claude"}


def test_a_round_reads_as_the_persons_turn_and_a_reply_carrying_what_came_before_it(phone):
    client, _ = phone
    body = client.get(f"/sessions/{TID}/turns").json()
    assert body["queued"] == [] and body["more"] is False
    you, reply, working = body["turns"]
    assert (you["role"], you["text"], you["written_by"]) == ("user", "Plan it.", "")
    assert you["timestamp"].endswith(".000Z") and reply["timestamp"] > you["timestamp"]
    assert (reply["role"], reply["text"]) == ("assistant", "One test fails.")
    assert reply["thoughts"] == ["Reading the schema first"]
    assert [(t["name"], t["detail"], t["succeeded"], t["result"]) for t in reply["tools"]] == [
        ("commandExecution", "just check", False, "1 failed")]
    # Work with no reply after it yet is a turn with no words, as a run in flight reads for Claude.
    assert working["text"] == "" and working["tools"][0]["detail"] == f"{SHOP}/x.py"
    older = client.get(f"/sessions/{TID}/turns", params={"limit": 1, "before": 1}).json()
    assert [t["text"] for t in older["turns"]] == ["One test fails."] and older["more"] is True


def test_the_raw_page_is_the_same_history_as_lines(phone):
    client, _ = phone
    lines = client.get(f"/sessions/{TID}/raw").json()["lines"]
    assert any(line.endswith("YOU Plan it.") for line in lines)
    assert any("← commandExecution just check" in line for line in lines)
    assert any(line.endswith("CODEX One test fails.") for line in lines)


def test_a_stop_interrupts_the_turn_and_claude_codes_own_controls_are_refused(phone):
    client, calls = phone
    stopped = client.post(f"/sessions/{TID}/control", params={"action": "cancel"})
    assert stopped.json() == {"sent": "cancel"}
    assert calls[-1] == ("turn/interrupt", {"threadId": TID, "turnId": "turn-2"})
    for action in ("compact", "clear", "exit"):
        refused = client.post(f"/sessions/{TID}/control", params={"action": action})
        assert refused.status_code == 409 and action in refused.json()["detail"]


def test_what_only_a_claude_session_has_is_refused_or_empty(phone):
    client, _ = phone
    for method, suffix in (("GET", "context"), ("GET", "commands"), ("POST", "queue/clear"),
                           ("POST", "focus")):
        assert client.request(method, f"/sessions/{TID}/{suffix}").status_code == 409
    assert client.post(f"/sessions/{TID}/name", json={"name": "x"}).status_code == 409
    assert client.get(f"/sessions/{TID}/files").json() == {"files": []}
    assert client.get(f"/sessions/{TID}/agents").json() == {"agents": []}


def test_no_token_reads_no_codex_history(phone):
    _, calls = phone
    assert TestClient(app).get(f"/sessions/{TID}/turns").status_code == 401
    assert "thread/turns/list" not in [method for method, _ in calls]


def test_saying_something_runs_the_orders_and_steers_the_busy_thread(phone):
    client, calls = phone
    kept.save(TID, "keep it short")
    body = client.post(f"/sessions/{TID}/say", params={"route": "auto"},
                       json={"text": "and the docs"}).json()
    assert (body["delivered"], body["delivered_by"]) == (True, "codex-steered")
    method, params = calls[-1]
    assert method == "turn/steer" and params["expectedTurnId"] == "turn-2"
    assert "keep it short" in params["input"][0]["text"]
    assert "and the docs" in params["input"][0]["text"]


def test_the_briefings_worker_never_picks_a_codex_thread(phone, monkeypatch):
    phone[0].get("/sessions")
    monkeypatch.setattr(briefings, "_bumped", [TID])
    assert briefings._next() != TID


def test_a_codex_session_starts_on_codex_configuration_without_the_trust_gate(phone, monkeypatch):
    _, calls = phone
    cold = "/Users/jj/dev/web/cold"
    monkeypatch.setattr(sources, "catalog", lambda: ([sources.Project("cold", cold)], "atlas"))
    monkeypatch.setattr(starting, "start", lambda cwd: pytest.fail("Claude Code was not asked for"))
    monkeypatch.setattr(starting, "trusted", lambda: pytest.fail("trust is Claude Code's record"))
    answer = anyio.run(routes.start_project_session, cold, "codex")
    assert calls[-1] == ("thread/start", {"cwd": cold, "ephemeral": False})
    row = answer["session"]
    assert (row["session_id"], row["provider"], row["name"], row["pid"]) == (
        "t-new", "codex", "cold-codex--new", 0)


def test_a_provider_nobody_offers_is_refused(phone, monkeypatch):
    monkeypatch.setattr(sources, "catalog", lambda: ([sources.Project("shop", SHOP)], "atlas"))
    with pytest.raises(Exception) as raised:
        anyio.run(routes.start_project_session, SHOP, "gemini")
    assert "no such provider" in str(raised.value)


def test_a_subagent_codex_started_is_an_agent_row_that_opens(phone, monkeypatch):
    client, _ = phone
    child = "01a146df-e7f5-76f1-b0e2-22bb464eaacd"
    spawned = {"id": "turn-3", "status": "completed", "startedAt": 1789316400, "items": [
        {"type": "subAgentActivity", "id": "s1", "kind": "started", "agentThreadId": child,
         "agentPath": "/root/rewrite_clients", "model": "gpt-5.6"},
        {"type": "subAgentActivity", "id": "s2", "kind": "completed", "agentThreadId": child,
         "agentPath": "/root/rewrite_clients"}]}
    worked = {"id": "turn-c", "status": "completed", "startedAt": 1789316401, "items": [
        {"type": "agentMessage", "id": "m", "text": "Rewrote the clients."}]}
    real = codex.request

    def request(method, params=None, timeout=None):
        if method == "thread/turns/list":
            return {"data": [worked] if params["threadId"] == child else [spawned]}
        return real(method, params, timeout)

    monkeypatch.setattr(codex, "request", request)
    rows = client.get(f"/sessions/{TID}/agents").json()["agents"]
    assert [(r["id"], r["kind"], r["running"]) for r in rows] == [(child, "rewrite_clients", False)]
    dot = client.get(f"/sessions/{TID}/turns").json()["turns"][-1]["tools"][0]
    assert (dot["name"], dot["tool_id"]) == ("subagent", child)
    opened = client.get(f"/sessions/{TID}/agents/{child}/turns").json()["turns"]
    assert [t["text"] for t in opened] == ["Rewrote the clients."]
    assert client.get(f"/sessions/{TID}/agents/nope/turns").status_code == 404
