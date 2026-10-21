"""`POST /notify`: an alert with no session, its signed tap, and the one loopback callback."""

import time

import httpx
import pytest
from decision_kit import signed
from fastapi.testclient import TestClient

from deckhand_daemon import config
from deckhand_daemon.app import app
from deckhand_daemon.push import callbacks, sending

ASKED = {"title": "Access request: shop", "line": "Ann from 10.0.0.7",
         "actions": [{"id": "approve", "label": "Allow"}, {"id": "deny", "label": "Deny"}],
         "callback": {"url": "http://127.0.0.1:47891/api/hostnames/access",
                      "body": {"slug": "shop", "id": "r1", "action": "$action",
                               "note": "$action!", "$action": ["$action"]}}}


@pytest.fixture
def pushed(monkeypatch):
    """Every card raised and every card ended, with APNs taking each; no alert unless asked."""
    seen = []
    monkeypatch.setattr(sending, "show", lambda card, mac, loud=True: seen.append(card))
    monkeypatch.setattr(sending, "end", lambda session: seen.append(("end", session)))
    monkeypatch.setattr(sending, "alert", lambda *a: pytest.fail("the card went up"))
    return seen


@pytest.fixture
def called(monkeypatch):
    """Every callback POST; answers with `called.status` (a list, popped from the front)."""
    seen = []

    def post(url, json, **kwargs):
        seen.append((url, json, kwargs))
        status = seen_status.pop(0) if seen_status else 200
        if status == 0:
            raise httpx.ConnectError("refused")
        return httpx.Response(status)

    seen_status: list[int] = []
    monkeypatch.setattr(callbacks.httpx, "post", post)
    monkeypatch.setattr(callbacks, "RETRY_AFTER", 0.0)
    return seen, seen_status


def sent(token, body=ASKED):
    return TestClient(app).post("/notify", json=body, headers={config.TOKEN_HEADER: token})


def tapped(phone, key, nid, action="approve", **fields):
    proof = signed(key, **({"v": 1, "session": "notify", "artifact": nid, "hash": "",
                            "value": action, "at": int(time.time())} | fields))
    return TestClient(app).post(f"/notify/{nid}/answer", json={"proof": proof},
                                headers={config.TOKEN_HEADER: phone[0]})


def test_the_card_carries_the_callers_labels_and_no_callback(token, pushed):
    answered = sent(token)
    assert answered.status_code == 202, answered.text
    nid = answered.json()["id"]
    card = pushed[0]
    assert card.session == f"notify:{nid}" and card.name == "Access request: shop"
    assert card.state() | {"when": 0} == {"kind": "asking", "line": "Ann from 10.0.0.7", "when": 0,
                                          "notify": nid, "accept": "Allow", "decline": "Deny"}
    assert "47891" not in str(sending._start(card, "m2"))


def test_no_card_falls_back_to_the_alert(token, monkeypatch):
    alerts = []
    monkeypatch.setattr(sending, "show", lambda *a, **k: "no start token")
    monkeypatch.setattr(sending, "alert", lambda payload, collapse="": alerts.append(
        (payload, collapse)))
    nid = sent(token).json()["id"]
    payload, collapse = alerts[0]
    assert collapse == f"notify:{nid}"
    assert payload["aps"]["category"] == "CALLBACK_ALLOW_DENY"
    assert payload["aps"]["alert"] == {"title": "Access request: shop", "body": "Ann from 10.0.0.7"}
    assert payload["notify"] == {"id": nid, "question": "Access request: shop"}
    assert "47891" not in str(payload)


@pytest.mark.parametrize("change", [
    {"title": " "},
    {"actions": [{"id": "approve", "label": "Allow"}]},
    {"actions": [{"id": "approve", "label": "Allow"}, {"id": "deny", "label": " "}]},
    {"callback": {"url": "https://127.0.0.1:1/x", "body": {}}},
    {"callback": {"url": "http://example.com:80/x", "body": {}}},
    {"callback": {"url": "http://evil@127.0.0.1:1/x", "body": {}}},
    {"callback": {"url": "http://127.0.0.1/x", "body": {}}},
    {"callback": {"url": "http://127.0.0.1:1@evil.com/x", "body": {}}},
    {"callback": {"url": "http://127.0.0.1:1/x", "body": ["not", "an", "object"]}},
    {"line": "x" * 5000},
])
def test_what_is_refused(token, pushed, change):
    answered = sent(token, ASKED | change)
    assert answered.status_code == 400, answered.text
    assert pushed == []


def test_no_device_token_is_503_and_apns_refusing_is_502(token, monkeypatch):
    monkeypatch.setattr(sending, "show", lambda *a, **k: "no start token")
    monkeypatch.setattr(sending, "alert", lambda *a: "the phone has not allowed notifications yet")
    assert sent(token).status_code == 503
    monkeypatch.setattr(sending, "alert", lambda *a: "APNs refused the notification (400): Bad")
    assert sent(token).status_code == 502


def test_a_tap_calls_back_once_with_the_action_filled_in(token, pushed, called, phone, key):
    nid = sent(token).json()["id"]
    answered = tapped(phone, key, nid)
    assert answered.status_code == 200, answered.text
    assert answered.json() == {"action": "approve", "status": 200}
    url, body, kwargs = called[0][0]
    assert url == "http://127.0.0.1:47891/api/hostnames/access"
    assert body == {"slug": "shop", "id": "r1", "action": "approve", "note": "$action!",
                    "$action": ["approve"]}
    assert kwargs["follow_redirects"] is False and kwargs["trust_env"] is False
    assert tapped(phone, key, nid, "deny").json() == {"action": "approve", "status": 200}
    assert len(called[0]) == 1
    assert pushed[1:] == [("end", f"notify:{nid}")]


def test_a_404_is_decided_elsewhere_and_not_retried(token, pushed, called, phone, key):
    called[1].append(404)
    nid = sent(token).json()["id"]
    assert tapped(phone, key, nid).status_code == 200
    assert len(called[0]) == 1


def test_a_failing_caller_is_retried_once_then_told(token, pushed, called, phone, key):
    called[1].extend([500, 0])
    nid = sent(token).json()["id"]
    answered = tapped(phone, key, nid)
    assert answered.status_code == 502
    assert "could not be reached" in answered.json()["detail"]
    assert len(called[0]) == 2
    assert tapped(phone, key, nid).status_code == 502
    assert len(called[0]) == 2


def test_the_signature_is_held_to_this_notify(token, pushed, called, phone, key, claude_home):
    nid = sent(token).json()["id"]
    assert tapped(phone, key, nid, artifact="other").status_code == 400
    assert tapped(phone, key, nid, session="aaaa1111-2222-3333-4444-555566667777").status_code \
        == 400
    assert tapped(phone, key, nid, "maybe").status_code == 400
    mac = TestClient(app).post(f"/notify/{nid}/answer", json={"proof": {}},
                               headers={config.TOKEN_HEADER: token})
    assert mac.json()["detail"]["code"] == "NO_KEY"
    assert called[0] == []


def test_an_unknown_or_day_old_notify_has_expired(token, pushed, called, phone, key,
                                                   monkeypatch):
    assert tapped(phone, key, "nope").json()["detail"]["code"] == "EXPIRED"
    nid = sent(token).json()["id"]
    monkeypatch.setattr(callbacks, "KEEP", 0)
    assert tapped(phone, key, nid).status_code == 410
    assert called[0] == []
