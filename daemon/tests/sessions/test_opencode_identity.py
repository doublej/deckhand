"""Who an OpenCode session is to the MCP server, the Lock Screen and the manager."""

from types import SimpleNamespace

import anyio
import pytest
from opencode_fake import SHOP, info

from deckhand_daemon import push, sessions
from deckhand_daemon.manager import doing
from deckhand_daemon.mcp import here, server

SID = "ses_eba59923effeIFj6MQZ28SzabW"


@pytest.fixture
def busy(opencode_service):
    opencode_service.add(info(SID, "Integration review"), busy=True)
    return opencode_service


def test_a_call_that_names_its_opencode_session_is_that_session(busy, monkeypatch):
    monkeypatch.setattr(here, "_parent", lambda pid: pytest.fail("no process tree under OpenCode"))
    held = here.calling.set(SID)
    try:
        found = here.mine()
    finally:
        here.calling.reset(held)
    assert found == {"sessionId": SID, "name": "Integration review", "cwd": SHOP,
                     "status": "busy", "provider": "opencode"}


def test_a_shell_opencode_runs_is_found_by_its_environment(busy, monkeypatch):
    monkeypatch.setattr(here, "_parent", lambda pid: None)
    monkeypatch.delenv("CLAUDE_CODE_SESSION_ID", raising=False)
    monkeypatch.setenv("OPENCODE_SESSION_ID", SID)
    assert here.mine()["sessionId"] == SID
    monkeypatch.delenv("OPENCODE_SESSION_ID")
    assert here.mine() is None


def test_the_server_lifts_the_session_out_of_the_calls_meta(busy, monkeypatch):
    monkeypatch.setattr(here, "_parent", lambda pid: None)
    called = SimpleNamespace(meta={"ai.opencode/sessionID": SID})
    context = server.Context(request_context=called, mcp_server=server.server)
    answer = anyio.run(server.server.call_tool, "whoami", {}, context)
    assert SID in answer.content[0].text and SHOP in answer.content[0].text
    # And only for the length of that call: the next one with no meta is nobody's.
    bare = anyio.run(server.server.call_tool, "whoami", {},
                     server.Context(request_context=SimpleNamespace(meta=None),
                                    mcp_server=server.server))
    assert "NO_SESSION" in bare.content[0].text


def test_a_permission_it_stops_on_raises_one_asking_card_and_its_answer_ends_it(
        busy, monkeypatch):
    shown, ended = [], []
    monkeypatch.setattr(push, "_blocked", {})
    monkeypatch.setattr(push, "_said", {})
    monkeypatch.setattr(push, "announce", lambda session, kind: shown.append(
        (session.session_id, kind, push._said.get(session.session_id))))
    monkeypatch.setattr(push, "end", ended.append)
    sessions.forget_listing()
    (row,) = [s for s in sessions.live_sessions() if s.provider == "opencode"]
    push._stopped(row)  # nothing waiting yet, and the first look is never an event
    busy.permissions[SID] = [{"id": "p1", "sessionID": SID, "action": "shell",
                              "resources": ["rm -rf build"]}]
    push._stopped(row)
    push._stopped(row)  # still the same request: no second card
    assert shown == [(SID, push.ASKING, "wants permission to shell rm -rf build")]
    busy.permissions[SID] = []
    push._stopped(row)
    assert ended == [SID]


def test_the_manager_speaks_into_an_opencode_session_on_the_agent_lane(busy, monkeypatch):
    sessions.forget_listing()
    (row,) = [s for s in sessions.live_sessions() if s.provider == "opencode"]
    monkeypatch.setattr(doing, "find", lambda wanted: row)
    answer = doing.speak("Integration review", "carry on")["content"][0]["text"]
    assert "opencode-peer" in answer and "labelled as another agent" in answer
    assert busy.calls[-1][1] == f"/api/session/{SID}/synthetic"
