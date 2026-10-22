"""What the manager's reads cost, and that each lets an agent ask for less.

Measured from a voice agent's seat (`deckhand-control`): a whole listing to find two sessions on
one machine, every section of a session to read its asks, and a thousand-token tree to learn how
loaded it is. Each read now narrows, and a narrowed answer says what was left out.
"""

from __future__ import annotations

import asyncio
import json

import pytest

from deckhand_daemon.fleet import merge
from deckhand_daemon.manager import tools
from deckhand_daemon.reading import transcripts

FAR = {"session_id": "dddd1111-2222-3333-4444-555566667777", "pid": 3131, "name": "far-otter",
       "cwd": "/home/jj/dev", "status": "idle", "updated_at": 0.0, "tty": "", "machine": "ubuntu"}


@pytest.fixture
def network(monkeypatch):
    monkeypatch.setattr(tools.registry, "here", lambda: "m2")
    monkeypatch.setattr(merge, "_owner", {}, raising=False)
    monkeypatch.setattr(merge, "_rows", {}, raising=False)

    async def machines():
        return [{"id": "m2", "label": "M2 Pro", "os": "darwin", "reachable": True, "primary": True}]

    async def listings(local):
        merge.remembered("ubuntu", [FAR])
        return list(local) + [FAR]

    monkeypatch.setattr(merge, "machines", machines)
    monkeypatch.setattr(merge, "listings", listings)


def text(answer: dict) -> str:
    return answer["content"][0]["text"]


def test_the_listing_narrows_to_a_machine_or_a_state(claude_home, network):
    whole = text(asyncio.run(tools.listing()))
    assert "machines on this network" in whole and "far-otter" in whole and "warm-okapi" in whole
    far = text(asyncio.run(tools.listing(machine="ubuntu")))
    assert "far-otter" in far and "warm-okapi" not in far and "machines" not in far
    busy = text(asyncio.run(tools.listing(state="busy")))
    assert "warm-okapi" in busy and "cold-otter" not in busy and "far-otter" not in busy
    assert text(asyncio.run(tools.listing(machine="fractal"))) == "no live session on fractal right now."


def test_a_session_is_read_by_the_parts_asked_for(claude_home, network):
    asyncio.run(tools.listing())
    okapi = tools.find("warm-okapi")
    whole = text(asyncio.run(tools.one(okapi, 0)))
    assert "briefing:" in whole and "orders:" in whole and "filters:" in whole
    asks = text(asyncio.run(tools.one(okapi, 0, parts="asks")))
    assert "asks:" in asks and "briefing:" not in asks and "orders:" not in asks
    assert asks.startswith("warm-okapi [busy]")  # the head always comes


def test_turns_say_when_they_were_cut_and_where_the_older_page_is(claude_home, network,
                                                                  monkeypatch):
    said = [transcripts.Turn("user", "x" * 500, "1"), transcripts.Turn("assistant", "short", "2")]
    asked = []

    def page_turns(session_id, limit, before):
        asked.append((limit, before))
        return said, True

    monkeypatch.setattr(transcripts, "page_turns", page_turns)
    asyncio.run(tools.listing())
    drawn = asyncio.run(tools._turns(tools.find("warm-okapi"), 2, False, before=4))
    assert asked == [(2, 4)]
    assert "x" * tools.CUT + "…" in drawn and "x" * (tools.CUT + 1) not in drawn
    assert "cut at 400 characters" in drawn and "before=6" in drawn


def test_a_name_that_matches_nothing_is_an_error(claude_home, network):
    missed = tools.missing("nope")
    assert missed["is_error"] is True and "warm-okapi" in text(missed)


def test_context_is_a_total_unless_the_tree_is_asked_for(claude_home, network, monkeypatch):
    from types import SimpleNamespace as Doc

    docs = [Doc(prefix="", label=f"doc{i}", tokens=100 * i) for i in range(1, 8)]
    monkeypatch.setattr(tools.context, "documents", lambda cwd: docs)
    asyncio.run(tools.listing())
    okapi = tools.find("warm-okapi")
    short = text(asyncio.run(tools.loaded(okapi)))
    assert "~2800 tokens" in short and "7 CLAUDE.md" in short
    assert "doc7 ~700" in short and "doc2" not in short and "`whole`" in short
    assert "doc1" in text(asyncio.run(tools.loaded(okapi, whole=True)))


def test_the_tool_list_says_what_may_be_left_out():
    from deckhand_daemon.manager import doing
    from deckhand_daemon.prompts import load

    made = {one.name: one for one in doing.build(load("manager").settings["tools"])}
    assert made["list_sessions"].input_schema["required"] == []
    assert made["read_session"].input_schema["required"] == ["session"]
    assert made["read_context"].input_schema["properties"]["whole"] == {"type": "boolean"}
    json.dumps(made["read_session"].input_schema)  # plain JSON, nothing a client cannot read
