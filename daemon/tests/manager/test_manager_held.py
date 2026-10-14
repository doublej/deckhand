"""The manager held open: a turn another session starts reaches the panel and never a pocket."""

import asyncio

from claude_agent_sdk import AssistantMessage, ResultMessage, TextBlock, ToolUseBlock

from deckhand_daemon import push
from deckhand_daemon.manager import agent, talk


class _Session:
    def __init__(self, messages):
        self.messages = messages

    async def receive_messages(self):
        for message in self.messages:
            yield message


def _turn(*blocks):
    return [
        AssistantMessage(content=list(blocks), model="opus"),
        ResultMessage(subtype="success", duration_ms=1, duration_api_ms=1, is_error=False,
                      num_turns=1, session_id="s-1"),
    ]


def test_an_inbox_turn_is_shown_but_only_the_panels_own_is_pushed(claude_home, monkeypatch):
    talk.clear()
    pushed = []
    monkeypatch.setattr(push, "told", pushed.append)
    monkeypatch.setattr(agent, "_seen", 0.0)
    reply = ToolUseBlock(id="t", name="SendMessage", input={"to": "yarrow", "message": "pong"})

    monkeypatch.setattr(agent, "_asked", False)
    asyncio.run(agent._read(_Session(_turn(reply, TextBlock(text="answered yarrow"))), asyncio.Event()))
    assert pushed == []
    assert [(e["role"], e["text"]) for e in talk.entries()] == [
        ("act", "told yarrow: pong"), ("manager", "answered yarrow")]
    assert talk.resumes() == "s-1"

    monkeypatch.setattr(agent, "_asked", True)
    asyncio.run(agent._read(_Session(_turn(TextBlock(text="done"))), asyncio.Event()))
    assert pushed == ["done"]
