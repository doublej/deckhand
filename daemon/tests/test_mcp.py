"""The agent's own tools: which session they belong to, and the two that write a file."""

import asyncio
import json

import pytest

from deckhand_daemon.mcp import here, server

run = asyncio.run


@pytest.fixture
def in_session(tmp_path, monkeypatch):
    """This process pretending to be a session working in `tmp_path`."""
    record = {"sessionId": "sess-1", "name": "deckhand", "cwd": str(tmp_path), "status": "idle"}
    monkeypatch.setattr(here, "mine", lambda: record)
    monkeypatch.setattr(server.here, "mine", lambda: record)
    return tmp_path


def test_the_session_is_found_by_walking_up_the_tree(tmp_path, monkeypatch):
    """The record belongs to an ancestor, never to this process — uv sits in between."""
    home = tmp_path / "claude"
    (home / "sessions").mkdir(parents=True)
    (home / "sessions" / "900.json").write_text(json.dumps({"sessionId": "sess-1", "cwd": "/x"}))
    monkeypatch.setenv("DECKHAND_CLAUDE_HOME", str(home))
    monkeypatch.delenv("CLAUDE_CODE_SESSION_ID", raising=False)
    chain = {here.os.getpid(): 800, 800: 900, 900: None}
    monkeypatch.setattr(here, "_parent", lambda pid: chain.get(pid))
    assert here.mine()["sessionId"] == "sess-1"


def test_no_session_above_is_said_rather_than_guessed_at(monkeypatch):
    monkeypatch.setattr(here, "_parent", lambda pid: None)
    monkeypatch.delenv("CLAUDE_CODE_SESSION_ID", raising=False)
    assert here.mine() is None


def test_a_slip_lands_in_the_session_folder_and_reads_back(in_session):
    """Written where the record says, not where this process happens to be running."""
    made = run(server.ask_on_phone("Ship it?", kind="confirm", options=["Ship", "Wait"],
                                    action="ship"))
    page = in_session / ".deckhand" / "artifacts" / "sess-1" / "ship-it.html"
    assert page.exists() and made["id"] == "ship-it" and made["waiting"] is True
    assert run(server.read_answer("ship-it"))["answered"] is False
    (page.parent / "ship-it.answer.json").write_text(json.dumps({"value": True}))
    assert run(server.read_answer("ship-it")) == {
        "answered": True, "value": True, "verified": False, "device": None, "fingerprint": None}


def test_an_id_no_slip_has_is_told_apart_from_one_not_answered_yet(in_session):
    """Or an agent waits on a slip that was never written."""
    missed = run(server.read_answer("nope-123"))
    assert missed["answered"] is False and missed["code"] == "NO_SUCH_SLIP"


def test_an_answer_goes_out_as_compact_json(in_session):
    """The SDK indents by two; the whitespace is tokens the model rereads every turn."""
    answered = run(server.server.call_tool("whoami", {}))
    assert answered.content[0].text == (
        f'{{"session":"sess-1","name":"deckhand","folder":"{in_session}","status":"idle"}}')


def test_an_unknown_kind_is_refused_before_anything_is_written(in_session):
    made = run(server.ask_on_phone("Ship it?", kind="wizard"))
    assert "wizard" in made["error"]
    assert not (in_session / ".deckhand").exists()


def test_speaking_to_a_session_matches_by_name_and_never_picks_a_route(monkeypatch):
    sent = {}

    async def reach(method, path, **kw):
        if path == "/sessions":
            return {"sessions": [{"session_id": "s2", "name": "utt"}]}
        sent.update({"path": path} | kw)
        return {"delivered": True, "delivered_by": "socket"}

    monkeypatch.setattr(server.here, "reach", reach)
    assert run(server.say_to_session("utt", "hello")) == {
        "went": True, "by": "socket", "why": None}
    assert sent["path"] == "/sessions/s2/say" and sent["params"] == {"route": "socket"}
    missed = run(server.say_to_session("nobody", "hello"))
    assert missed["went"] is False and "nobody" in missed["why"]


def test_a_filter_stopping_a_prompt_is_not_a_delivery(monkeypatch):
    async def reach(method, path, **kw):
        if path == "/sessions":
            return {"sessions": [{"session_id": "s2", "name": "utt"}]}
        return {"delivered": False, "delivered_by": None, "stopped_by": "quiet-hours"}

    monkeypatch.setattr(server.here, "reach", reach)
    said = run(server.say_to_session("s2", "hello"))
    assert said["went"] is False and "quiet-hours" in said["why"]


def test_the_manager_is_said_to_down_its_inbox_though_it_is_not_listed(monkeypatch):
    sent = []

    async def reach(method, path, **kw):
        if path == "/sessions":
            return {"sessions": [{"session_id": "s2", "name": "utt"}]}
        if path == "/manager/session":
            return {"session_id": "m1", "name": "deckhand-manager", "provider": "claude"}
        sent.append((path, kw["params"]))
        return {"delivered": True, "delivered_by": "socket"}

    monkeypatch.setattr(server.here, "reach", reach)
    assert run(server.say_to_session("manager", "could not close three"))["went"] is True
    assert sent == [("/sessions/m1/say", {"route": "socket"})]


def test_the_managers_session_is_found_by_its_name(claude_home, token, monkeypatch):
    from fastapi.testclient import TestClient

    from deckhand_daemon.app import app
    from deckhand_daemon.manager import agent

    client = TestClient(app)
    headers = {"x-deckhand-token": token}
    assert client.get("/manager/session", headers=headers).status_code == 404
    monkeypatch.setattr(agent, "NAME", "cold-otter")
    assert client.get("/manager/session", headers=headers).json()["session_id"] == (
        "bbbb1111-2222-3333-4444-555566667777")
