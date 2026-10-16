"""What the phone does to an OpenCode session: read it, speak into it, stop it, rename it, start one."""

import anyio
import pytest
from fastapi.testclient import TestClient
from opencode_fake import NOW, SHOP, info

from deckhand_daemon import config, filters
from deckhand_daemon.app import app
from deckhand_daemon.orders import kept
from deckhand_daemon.projects import routes, sources, starting
from deckhand_daemon.sessions import opencode_input

SID = "ses_eba59923effeIFj6MQZ28SzabW"
KID = "ses_kid0000000000000000000001"


def said(text, kind="user", **more):
    return {"id": f"m{len(text)}{kind}", "type": kind, "time": {"created": NOW}, "text": text} | more


def step(*content, **more):
    return {"id": "a" + str(len(content)), "type": "assistant", "time": {"created": NOW + 1},
            "agent": "build", "model": {"id": "claude-opus-5-5", "providerID": "anthropic"},
            "content": list(content)} | more


def tool(name, status="completed", text="ok", **given):
    state = {"status": status, "input": given, "content": [{"type": "text", "text": text}]}
    return {"type": "tool", "id": f"call-{name}", "name": name, "time": {"created": NOW},
            "state": state}


HISTORY = [
    said("Plan it."),
    step({"type": "reasoning", "text": "Reading the schema first"},
         tool("read", path=f"{SHOP}/schema.sql"), tool("shell", "error", "1 failed", command="just check")),
    step({"type": "text", "text": "One test fails."}),
    said("<peer-message>…</peer-message>", "synthetic", description="Deckhand, not your user",
         metadata={"deckhand": "Idle check: anything open?"}),
    step({"type": "tool", "id": "call-sub", "name": "subagent", "time": {"created": NOW},
          "state": {"status": "completed", "input": {"description": "find callers"},
                    "content": [{"type": "text", "text": "done"}],
                    "metadata": {"sessionID": KID}}}),
]


@pytest.fixture
def phone(opencode_service):
    """A paired phone, and an OpenCode service with one busy session in the shop."""
    fake = opencode_service
    fake.add(info(SID, "Integration review"), busy=True, messages=HISTORY)
    fake.add(info(KID, "find callers", parent=SID), messages=[said("find callers")])
    client = TestClient(app)
    client.headers["x-deckhand-token"] = config.token()
    return client, fake


def test_the_history_reads_as_turns_with_what_came_before_each_reply(phone):
    client, _ = phone
    body = client.get(f"/sessions/{SID}/turns", params={"limit": 20}).json()
    you, reply, peer, working = body["turns"]
    assert (you["role"], you["text"], you["written_by"]) == ("user", "Plan it.", "")
    assert you["timestamp"].endswith("Z") and "." in you["timestamp"]
    assert (reply["text"], reply["thoughts"]) == ("One test fails.", ["Reading the schema first"])
    assert [(t["name"], t["detail"], t["succeeded"]) for t in reply["tools"]] == [
        ("read", f"{SHOP}/schema.sql", True), ("shell", "just check", False)]
    # Input on the agent lane reads as what was said, by whom — never as YOU.
    assert (peer["text"], peer["written_by"]) == ("Idle check: anything open?",
                                                  "Deckhand, not your user")
    # A subagent's dot carries its child session's id, which is its agent row's id.
    assert working["text"] == "" and working["tools"][0]["tool_id"] == KID
    older = client.get(f"/sessions/{SID}/turns", params={"limit": 1, "before": 3}).json()
    assert [t["text"] for t in older["turns"]] == ["Plan it."] and older["more"] is False


def test_what_is_still_in_the_inbox_is_queued_and_clearing_cancels_it(phone):
    client, fake = phone
    fake.inbox[SID] = [{"id": "in1", "type": "user", "payload": {"text": "and the docs"}},
                       {"id": "in2", "type": "compaction", "payload": {}}]
    assert client.get(f"/sessions/{SID}/turns").json()["queued"] == [{"text": "and the docs"}]
    cleared = client.post(f"/sessions/{SID}/queue/clear").json()
    assert cleared["cancelled"] == 1
    assert ("DELETE", f"/api/session/{SID}/inbox/in1", None, None) in fake.calls
    assert client.get(f"/sessions/{SID}/turns").json()["queued"] == []


def test_a_permission_it_is_waiting_on_closes_the_conversation(phone):
    client, fake = phone
    fake.permissions[SID] = [{"id": "per1", "sessionID": SID, "action": "edit",
                              "resources": ["/Users/jj/dev/web/shop/src/app.py"]}]
    fake.forms[SID] = [{"id": "f1", "sessionID": SID, "title": "Which database?", "fields": []}]
    last = client.get(f"/sessions/{SID}/turns", params={"limit": 20}).json()["turns"][-1]
    assert last["text"] == ("Waiting on you in OpenCode: wants permission to edit src/app.py; "
                            "asks: Which database?.")


def test_the_raw_page_is_the_same_history_as_lines(phone):
    client, _ = phone
    lines = client.get(f"/sessions/{SID}/raw").json()["lines"]
    assert any(line.endswith("YOU Plan it.") for line in lines)
    assert any("← shell just check" in line for line in lines)
    assert any(line.endswith("OPENCODE One test fails.") for line in lines)
    assert any("DECKHAND, NOT YOUR USER Idle check" in line for line in lines)


def test_subagents_are_child_sessions_and_each_reads_as_a_conversation(phone):
    client, _ = phone
    (agent,) = client.get(f"/sessions/{SID}/agents").json()["agents"]
    assert (agent["id"], agent["tool_use_id"], agent["description"]) == (KID, KID, "find callers")
    turns = client.get(f"/sessions/{SID}/agents/{KID}/turns").json()["turns"]
    assert [t["text"] for t in turns] == ["find callers"]
    assert client.get(f"/sessions/{SID}/agents/ses_other/turns").status_code == 404


def test_the_commands_are_opencodes_own_and_its_skills(phone):
    client, _ = phone
    listed = client.get(f"/sessions/{SID}/commands").json()["commands"]
    assert [(c["name"], c["kind"], c["scope"]) for c in listed] == [
        ("review", "command", "project"), ("plain-writing", "skill", "user")]


def test_the_person_speaks_as_a_prompt_with_the_orders_in_front(phone):
    client, fake = phone
    kept.save(SID, "keep it short")
    body = client.post(f"/sessions/{SID}/say", params={"route": "auto"},
                       json={"text": "and the docs"}).json()
    assert (body["delivered"], body["delivered_by"]) == (True, "opencode-steered")
    method, path, sent, _ = fake.calls[-1]
    assert (method, path) == ("POST", f"/api/session/{SID}/prompt")
    assert "keep it short" in sent["text"] and "and the docs" in sent["text"]


def test_the_agent_lane_is_synthetic_input_that_says_it_is_not_the_person(phone):
    client, fake = phone
    taken, error = opencode_input.deliver(_row(client), "finish the docs", "socket")
    assert (taken, error) == ("opencode-peer", None)
    _, path, sent, _ = fake.calls[-1]
    assert path == f"/api/session/{SID}/synthetic" and sent["resume"] is True
    assert "not typed by your user" in sent["text"] and "finish the docs" in sent["text"]
    assert sent["metadata"] == {"deckhand": "finish the docs"}
    refused, why = opencode_input.deliver(_row(client), "/review", "socket")
    assert refused is None and "slash command" in why


def test_a_slash_runs_a_command_and_else_hands_over_a_skill(phone):
    client, fake = phone
    row = _row(client)
    assert opencode_input.deliver(row, "/review --staged", "auto") == ("opencode-command", None)
    assert fake.calls[-1][2] == {"name": "review", "text": "--staged"}
    assert opencode_input.deliver(row, "/plain-writing tidy this", "auto") == (
        "opencode-skill", None)
    assert fake.calls[-1][2] == {"text": "tidy this", "skills": [{"id": "plain-writing"}]}
    taken, why = opencode_input.deliver(row, "/nothing", "auto")
    assert taken is None and "no command or skill called /nothing" in why


def test_stop_and_compact_are_opencodes_and_claude_codes_controls_are_refused(phone):
    client, fake = phone
    assert client.post(f"/sessions/{SID}/control", params={"action": "cancel"}).json() == {
        "sent": "cancel"}
    assert fake.calls[-1][1] == f"/api/session/{SID}/interrupt"
    assert client.post(f"/sessions/{SID}/control", params={"action": "compact"}).status_code == 200
    assert fake.calls[-1][1] == f"/api/session/{SID}/compact"
    for action in ("clear", "exit"):
        refused = client.post(f"/sessions/{SID}/control", params={"action": action})
        assert refused.status_code == 409 and action in refused.json()["detail"]
    for method, suffix in (("GET", "context"), ("POST", "focus")):
        assert client.request(method, f"/sessions/{SID}/{suffix}").status_code == 409


def test_a_rename_sets_the_title_and_carries_the_filter_chain(phone):
    client, fake = phone
    assert filters.save(filters.key("", "Integration review"), [{"filter": "words"}])
    body = client.post(f"/sessions/{SID}/name", json={"name": "Docs pass"}).json()
    assert (body["renamed"], body["was"]) == ("Docs pass", "Integration review")
    assert fake.sessions[SID]["title"] == "Docs pass"
    assert body["carried_filters"] is True and filters.load(filters.key("", "Docs pass"))


def test_the_files_it_touched_come_out_of_its_history(phone, tmp_path):
    client, fake = phone
    shot = tmp_path / "shot.png"
    shot.write_bytes(b"png")
    fake.messages[SID].append(step(tool("write", path=str(shot))))
    listed = client.get(f"/sessions/{SID}/files").json()["files"]
    assert [f["name"] for f in listed] == ["shot.png"]
    assert client.get(f"/sessions/{SID}/file", params={"path": str(shot)}).content == b"png"


def test_no_token_reads_no_opencode_history(phone):
    _, fake = phone
    assert TestClient(app).get(f"/sessions/{SID}/turns").status_code == 401
    assert not [c for c in fake.calls if c[1].endswith("/message")]


def test_an_opencode_session_starts_on_opencodes_configuration_without_the_trust_gate(
        phone, monkeypatch):
    _, fake = phone
    cold = "/Users/jj/dev/web/cold"
    monkeypatch.setattr(sources, "catalog", lambda: ([sources.Project("cold", cold)], "atlas"))
    monkeypatch.setattr(starting, "start", lambda cwd: pytest.fail("Claude Code was not asked for"))
    monkeypatch.setattr(starting, "trusted", lambda: pytest.fail("trust is Claude Code's record"))
    row = anyio.run(routes.start_project_session, cold, "opencode")["session"]
    assert fake.calls[-1][:3] == ("POST", "/api/session", {"location": {"directory": cold}})
    assert (row["provider"], row["name"], row["pid"]) == ("opencode", "cold-opencode-resh", 0)


def _row(client):
    from deckhand_daemon import sessions

    client.get("/sessions")
    return next(s for s in sessions.live_sessions() if s.session_id == SID)
