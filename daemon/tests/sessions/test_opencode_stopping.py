"""Stopping an OpenCode session and going on after: what a stop reaches, what waits, what reads."""

import pytest
from fastapi.testclient import TestClient
from opencode_fake import NOW, info

from deckhand_daemon import config, saying, sessions
from deckhand_daemon.app import app
from deckhand_daemon.sessions import opencode

SID = "ses_eb6b63e5bffe9alZhEMw74IfDX"
KID = "ses_kid0000000000000000000002"


@pytest.fixture
def phone(opencode_service):
    fake = opencode_service
    fake.add(info(SID, "Session not using MCP"))
    fake.add(info(KID, "find callers", parent=SID))
    client = TestClient(app)
    client.headers["x-deckhand-token"] = config.token()
    return client, fake


def row():
    return next(s for s in sessions.live_sessions() if s.session_id == SID)


def test_a_session_whose_subagents_still_run_reads_busy(phone):
    _, fake = phone
    fake.active.add(KID)  # the turn ended, leaving its subagent going
    assert row().status == "busy"


def test_a_stop_resumes_the_words_said_into_the_turn_and_stops_its_subagents(phone):
    client, fake = phone
    fake.active |= {SID, KID}
    assert client.post(f"/sessions/{SID}/control", params={"action": "cancel"}).json() == {
        "sent": "cancel"}
    stops = [(path, query) for method, path, _, query in fake.calls if path.endswith("/interrupt")]
    # Without resume the person's steering words stay parked, and the next prompt released them
    # beside itself: the same line arrived twice.
    assert (f"/api/session/{SID}/interrupt", {"resume": "true"}) in stops
    assert (f"/api/session/{KID}/interrupt", None) in stops


def test_only_words_somebody_sent_are_queued_and_clearing_takes_opencodes_notes_too(phone):
    client, fake = phone
    fake.inbox[SID] = [
        {"id": "in1", "type": "user", "payload": {"text": "and the docs"}},
        {"id": "in2", "type": "synthetic", "payload": {
            "text": "<shell state=\"cancelled\">Command cancelled because the server restarted"}},
        {"id": "in3", "type": "synthetic", "payload": {"text": "<peer>…", "metadata": {
            "deckhand": "Idle check: anything open?"}}},
    ]
    queued = client.get(f"/sessions/{SID}/turns").json()["queued"]
    assert queued == [{"text": "and the docs"}, {"text": "Idle check: anything open?"}]
    assert client.post(f"/sessions/{SID}/queue/clear").json()["cancelled"] == 3


def test_opencodes_own_note_is_a_dot_in_the_run_and_not_a_thing_said(phone):
    client, fake = phone
    fake.messages[SID] = [
        {"id": "u1", "type": "user", "time": {"created": NOW}, "text": "Deploy it."},
        {"id": "s1", "type": "synthetic", "time": {"created": NOW + 1},
         "description": "Continuing after restart",
         "text": "The server restarted while you were working. Continue."},
        {"id": "a1", "type": "assistant", "time": {"created": NOW + 2},
         "content": [{"type": "text", "text": "Deployed."}]},
    ]
    turns = client.get(f"/sessions/{SID}/turns").json()["turns"]
    assert [(t["role"], t["text"]) for t in turns] == [("user", "Deploy it."),
                                                       ("assistant", "Deployed.")]
    assert turns[1]["tools"][0]["name"] == "Continuing after restart"


def test_a_session_the_listing_let_go_can_still_be_read_and_spoken_to(phone):
    client, fake = phone
    fake.sessions[SID]["time"]["updated"] = NOW - 3 * 60 * 60 * 1000  # past the two hours
    assert SID not in {s.session_id for s in sessions.live_sessions()}
    assert client.get(f"/sessions/{SID}/turns").status_code == 200
    assert saying.found_session(SID).session_id == SID


def test_a_deleted_session_a_tab_still_names_is_asked_about_once(phone, monkeypatch):
    _, fake = phone
    gone = "ses_deleted00000000000000000"
    monkeypatch.setattr(opencode.opencode_tabs, "open_sessions", lambda _: {gone})
    for _ in range(3):
        opencode._asked = (0.0, False)
        opencode.records()
    assert sum(path == f"/api/session/{gone}" for _, path, _, _ in fake.calls) == 1
