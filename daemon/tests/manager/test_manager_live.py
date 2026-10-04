"""The manager while a run is in flight: what the panel sees of it, and what reaches a pocket."""

from fastapi.testclient import TestClient

from deckhand_daemon import push
from deckhand_daemon.app import app
from deckhand_daemon.manager import agent, talk


def test_the_panel_sees_the_sentence_being_written_and_the_tool_in_flight(monkeypatch):
    monkeypatch.setattr(agent, "_partial", "")
    monkeypatch.setattr(agent, "_doing", "")
    agent._follow({"type": "content_block_start",
                   "content_block": {"type": "tool_use", "name": "mcp__deckhand__list_sessions"}})
    assert agent.progress() == {"partial": "", "doing": "list_sessions"}
    agent._follow({"type": "content_block_start", "content_block": {"type": "text"}})
    agent._follow({"type": "content_block_delta", "delta": {"type": "text_delta", "text": "Three "}})
    agent._follow({"type": "content_block_delta", "delta": {"type": "text_delta", "text": "busy"}})
    assert agent.progress() == {"partial": "Three busy", "doing": ""}


def test_reading_the_panel_carries_progress_and_marks_it_watched(claude_home, token, monkeypatch):
    monkeypatch.setattr(agent, "_seen", 0.0)
    monkeypatch.setattr(agent, "_partial", "half a")
    assert not agent.watched()
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    body = c.get("/manager").json()
    assert body["partial"] == "half a"
    assert agent.watched()


def test_a_message_is_pushed_only_when_nobody_has_the_panel_open(claude_home, monkeypatch):
    talk.clear()
    pushed = []
    monkeypatch.setattr(push, "told", pushed.append)
    agent.seen()
    agent.speak("manager", "deckhand: tests pass")
    assert pushed == []
    monkeypatch.setattr(agent, "_seen", 0.0)
    agent.speak("manager", "deckhand: tests pass")
    assert pushed == ["deckhand: tests pass"]
    assert [e["text"] for e in talk.entries()] == ["deckhand: tests pass"] * 2


def test_leaving_the_panel_counts_at_once_not_ten_seconds_later(claude_home, token):
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    c.get("/manager")
    assert agent.watched()
    assert c.post("/manager/away").status_code == 204
    assert not agent.watched()


def test_a_notification_needs_the_phones_own_token(claude_home):
    assert push.told("hello") == "the phone has not allowed notifications yet"


def test_the_away_prompt_exists_and_forbids_markdown():
    assert "markdown" in agent.AWAY.body
