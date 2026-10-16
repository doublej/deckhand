"""OpenCode's sessions in the listing: which count as live, their rows, and a service that is not
there."""

import httpx
import pytest
from fastapi.testclient import TestClient
from opencode_fake import NOW, SHOP, info

from deckhand_daemon import config, sessions
from deckhand_daemon.app import app
from deckhand_daemon.sessions import opencode

HOUR = 3_600_000


def rows(client):
    return {r["session_id"]: r for r in client.get("/sessions").json()["sessions"]}


@pytest.fixture
def client(opencode_service):
    found = TestClient(app)
    found.headers["x-deckhand-token"] = config.token()
    return found


def test_a_running_or_recent_root_session_is_a_row(opencode_service, client):
    fake = opencode_service
    fake.add(info("ses_busy0001", "Busy one", updated=NOW - 5 * HOUR), busy=True)
    fake.add(info("ses_idle0002", "Idle one", updated=NOW - HOUR))
    fake.add(info("ses_cold0003", "Cold one", updated=NOW - 3 * HOUR))
    fake.add(info("ses_kid00004", "A subagent", parent="ses_idle0002"), busy=True)
    fake.add(info("ses_gone0005", "Archived", archived=NOW))
    fake.add(info("ses_none0006"))
    listed = rows(client)
    ours = {sid: r for sid, r in listed.items() if r["provider"] == "opencode"}
    assert set(ours) == {"ses_busy0001", "ses_idle0002", "ses_none0006"}
    busy = ours["ses_busy0001"]
    assert (busy["status"], busy["name"], busy["cwd"], busy["pane"], busy["pid"]) == (
        "busy", "Busy one", SHOP, None, 0)
    assert ours["ses_idle0002"]["status"] == "idle"
    # Untitled until its first prompt, and never the folder's bare name, which is the Claude row's.
    assert ours["ses_none0006"]["name"] == "shop-opencode-0006"
    # Claude's rows are still there: a third provider is beside them, not instead of them.
    assert {r["provider"] for r in listed.values()} == {"claude", "opencode"}
    assert client.get("/health").json()["opencode"] is True


def test_the_context_figure_is_the_last_finished_request_against_its_models_window(
        opencode_service, client):
    stepped = {"id": "m1", "type": "assistant", "time": {"created": NOW},
               "model": {"id": "claude-opus-5-5", "providerID": "anthropic", "variant": "xhigh"},
               "content": [], "tokens": {"input": 10, "output": 50, "reasoning": 0,
                                         "cache": {"read": 30_000, "write": 2_000}}}
    streaming = {"id": "m2", "type": "assistant", "time": {"created": NOW}, "content": [],
                 "model": {"id": "claude-opus-5-5", "providerID": "anthropic"}}
    opencode_service.add(info("ses_ctx00001", "Measured"), messages=[stepped, streaming])
    row = rows(client)["ses_ctx00001"]
    assert row["context"] == {"used": 32_010, "limit": 1_000_000}
    assert (row["model"], row["effort"]) == ("claude-opus-5-5", "xhigh")


def test_no_registration_is_no_rows_and_the_service_is_not_asked_again_at_once(claude_home):
    client = TestClient(app)
    client.headers["x-deckhand-token"] = config.token()
    assert all(r["provider"] == "claude" for r in rows(client).values())
    assert opencode.answered() is False
    asked = opencode._asked[0]
    sessions.forget_listing()
    rows(client)
    assert opencode._asked[0] == asked  # backed off, not asked again


def test_the_registration_is_basic_auth_and_a_stale_password_is_unreachable(
        claude_home, tmp_path, monkeypatch):
    registration = tmp_path / "opencode" / "service.json"
    registration.parent.mkdir(parents=True)
    registration.write_text('{"url": "http://127.0.0.1:5555/", "password": "pw"}')
    seen = {}

    def answered(method, url, **sent):
        seen.update(method=method, url=url, auth=sent["auth"], params=sent["params"])
        return httpx.Response(200, json={"data": {}})

    monkeypatch.setattr(opencode.httpx, "request", answered)
    assert opencode.request("GET", "/api/session/active", query={"a": "b"}) == {"data": {}}
    assert seen == {"method": "GET", "url": "http://127.0.0.1:5555/api/session/active",
                    "auth": ("opencode", "pw"), "params": {"a": "b"}}
    monkeypatch.setattr(opencode.httpx, "request", lambda *a, **k: httpx.Response(401))
    with pytest.raises(opencode.Unreachable):
        opencode.request("GET", "/api/session/active")
    monkeypatch.setattr(opencode.httpx, "request", lambda *a, **k: httpx.Response(
        404, json={"_tag": "SessionNotFoundError", "message": "Session not found: x"}))
    with pytest.raises(opencode.OpenCodeError, match="Session not found: x"):
        opencode.request("GET", "/api/session/x")


def test_a_location_scoped_route_takes_the_folder_as_a_deep_object():
    assert opencode.located(SHOP) == {"location[directory]": SHOP}
