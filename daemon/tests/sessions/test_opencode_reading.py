"""An OpenCode session read the way a Claude one is: by the manager, and by the briefing worker."""

import pytest
from opencode_fake import NOW, info

from deckhand_daemon import briefings, sessions
from deckhand_daemon.manager import tools
from deckhand_daemon.sessions import opencode

SID = "ses_eb6a4c866ffeEVdB0YA7ltlPo2"


def said(text):
    return {"id": f"u{len(text)}", "type": "user", "time": {"created": NOW}, "text": text}


def step(*content, **more):
    return {"id": f"a{len(content)}", "type": "assistant", "time": {"created": NOW + 1},
            "model": {"id": "claude-opus-5-5", "providerID": "anthropic"},
            "content": list(content)} | more


HISTORY = [
    said("Old ask."),
    step({"type": "text", "text": "Old answer."}),
    said("Wire utt in."),
    step({"type": "tool", "id": "call-read", "name": "read", "time": {"created": NOW},
          "state": {"status": "completed", "input": {"path": "src/voice.ts"}, "content": []}}),
    step({"type": "text", "text": "Voice notes go through utt now."},
         tokens={"input": 100_000, "output": 10, "cache": {"read": 0, "write": 0}}),
]


@pytest.fixture
def session(opencode_service):
    opencode_service.add(info(SID, "Voice message transcription integration with utt"),
                         messages=HISTORY)
    briefings._bumped.clear()
    briefings._cursor = 0
    return next(s for s in sessions.live_sessions() if s.session_id == SID)


def test_the_manager_reads_the_conversation_out_of_the_service(session):
    text = tools.one(session, 4)["content"][0]["text"]
    assert "Voice notes go through utt now." in text
    assert "nothing readable" not in text


def test_the_manager_listing_has_its_context_and_says_why_there_is_no_pane(session):
    line = next(row for row in tools.listing()["content"][0]["text"].splitlines()
                if row.startswith(f"- {session.name}"))
    assert "context 10%" in line  # 100k of the model's 1M window, not Claude's
    assert "over opencode's API" in line


def test_a_briefing_is_owed_and_reads_only_what_followed_the_last_ask(session):
    assert briefings._next() == SID
    asks, activity = briefings._read(SID)
    assert asks == ""
    assert activity == "ran read: src/voice.ts\nsaid: Voice notes go through utt now."

    briefings.save(SID, {"hash": briefings._hash(SID), "mtime": briefings._mark(SID),
                         "written_at": 0.0})
    assert briefings._due(SID) is False
    assert briefings.of(SID)["stale"] is False


def test_a_service_that_stops_answering_does_not_take_the_worker_down(session, monkeypatch):
    def refuse(*_, **__):
        raise opencode.OpenCodeError("connection refused")

    monkeypatch.setattr(opencode, "request", refuse)
    assert briefings._read(SID) == ("", "")
