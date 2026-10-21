"""Who is speaking: "JJ, spoken:", standing orders and the card's end belong to the person only."""

import asyncio

import httpx
from decision_kit import SID
from fastapi.testclient import TestClient

from deckhand_daemon import config, deliver, push, saying, sessions
from deckhand_daemon.app import app
from deckhand_daemon.mcp import here

AGENT = {config.CALLER_HEADER: "agent"}


def socket_message(monkeypatch, person):
    """What a local pane-less session's inbox would be handed."""
    sent = []
    monkeypatch.setattr(deliver, "_through_socket", lambda s, m: sent.append(m) or (True, None))
    lone = sessions.Session(session_id="s", pid=0, name="s", cwd="/tmp", status="idle",
                            updated_at=0.0, tty="", pane=None)
    assert deliver.deliver(lone, "run the tests", "socket", person=person) == ("socket", None)
    return sent[0]


def test_the_preamble_is_only_on_the_persons_words(monkeypatch):
    assert socket_message(monkeypatch, person=True) == f"{deliver.PREAMBLE} run the tests"
    assert socket_message(monkeypatch, person=False) == "run the tests"


def say(monkeypatch, headers):
    """POST /say, with the delivery, the orders and the card's end all caught."""
    seen = {"ended": []}
    monkeypatch.setattr(deliver, "deliver", lambda s, text, route, person=False: (
        seen.update(text=text, person=person), ("socket", None))[1])
    monkeypatch.setattr(saying, "_with_orders", lambda s, text: f"ORDERS {text}")
    monkeypatch.setattr(push, "spoke_to", lambda sid: seen["ended"].append(sid))
    answered = TestClient(app).post(f"/sessions/{SID}/say?route=socket", json={"text": "hi"},
                                    headers={config.TOKEN_HEADER: config.token(), **headers})
    assert answered.status_code == 200
    return seen


def test_the_persons_say_carries_orders_and_ends_the_card(claude_home, monkeypatch):
    seen = say(monkeypatch, {})
    assert seen == {"text": "ORDERS hi", "person": True, "ended": [SID]}


def test_an_agents_say_carries_no_orders_and_leaves_the_card(claude_home, monkeypatch):
    seen = say(monkeypatch, AGENT)
    assert seen == {"text": "hi", "person": False, "ended": []}


def test_words_that_did_not_arrive_do_not_end_the_card(claude_home, monkeypatch):
    ended = []
    monkeypatch.setattr(deliver, "deliver", lambda *a, **k: (None, "no inbox"))
    monkeypatch.setattr(push, "spoke_to", ended.append)
    TestClient(app).post(f"/sessions/{SID}/say", json={"text": "hi"},
                         headers={config.TOKEN_HEADER: config.token()})
    assert ended == []


def test_an_agent_cannot_say_the_person_is_on_the_phone(claude_home):
    c = TestClient(app)
    c.headers[config.TOKEN_HEADER] = config.token()
    assert c.post("/presence/phone", headers=AGENT).status_code == 403
    assert c.post("/presence/phone").status_code == 204


def test_every_call_an_agents_tools_make_says_it_is_an_agent(monkeypatch):
    sent = {}

    async def request(self, method, url, headers=None, **kw):
        sent.update(headers or {})
        return httpx.Response(200, json={}, request=httpx.Request(method, url))

    monkeypatch.setattr(httpx.AsyncClient, "request", request)
    asyncio.run(here.reach("GET", "/presence"))
    assert sent[config.CALLER_HEADER] == "agent"
