"""Pairing by code, and the token per device it hands out.

The negative assertions are the point: what a stranger on the LAN can do with `POST /pair`, what
a paired device may not do, and what keeps working for everything paired before this existed.
"""

from __future__ import annotations

from collections import deque

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon import config, plugin
from deckhand_daemon.app import app
from deckhand_daemon.fleet import routing
from deckhand_daemon.pairing import devices, window


@pytest.fixture(autouse=True)
def a_closed_window(monkeypatch):
    """The window and the attempt count are process state; every test starts with neither."""
    monkeypatch.setattr(window, "_open", None)
    monkeypatch.setattr(window, "_attempts", deque())
    monkeypatch.setattr(plugin, "status", lambda **fields: None)


def as_mac(token: str) -> TestClient:
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    return c


def opened(token: str) -> str:
    answer = as_mac(token).post("/pair/open")
    assert answer.status_code == 200
    return answer.json()["code"]


def paired(code: str, name: str = "Quest 3", kind: str = "headset") -> dict:
    answer = TestClient(app).post("/pair", json={"code": code, "name": name, "kind": kind})
    assert answer.status_code == 200, answer.text
    return answer.json()


def test_nothing_pairs_until_the_mac_opens_a_window(token):
    answer = TestClient(app).post("/pair", json={"code": "123456", "name": "x", "kind": "phone"})
    assert answer.status_code == 410


def test_only_this_macs_own_token_opens_a_window(token):
    assert TestClient(app).post("/pair/open").status_code == 401
    assert as_mac("wrong").post("/pair/open").status_code == 401
    device = paired(opened(token))["token"]
    assert as_mac(device).post("/pair/open").status_code == 403
    assert as_mac(device).get("/devices").status_code == 403


def test_the_code_buys_a_token_that_works_and_is_spent(token):
    code = opened(token)
    answer = paired(f"{code[:3]} {code[3:]}")  # typed as it is shown, with the space
    assert answer["mac"]["id"] == config.machine_id()
    assert answer["device"]["name"] == "Quest 3" and "hash" not in answer["device"]
    assert as_mac(answer["token"]).get("/sessions").status_code == 200
    again = TestClient(app).post("/pair", json={"code": code, "name": "y", "kind": "phone"})
    assert again.status_code == 410


def test_wrong_codes_close_the_window(token):
    code = opened(token)
    wrong = "000000" if code != "000000" else "111111"
    for _ in range(window.TRIES - 1):
        assert TestClient(app).post("/pair", json={"code": wrong}).status_code == 403
    assert TestClient(app).post("/pair", json={"code": wrong}).status_code == 410
    assert TestClient(app).post("/pair", json={"code": code}).status_code == 410


def test_a_flood_is_refused_before_it_is_read(token):
    opened(token)
    for _ in range(window.BURST):
        TestClient(app).post("/pair", json={"code": "x"})
    assert TestClient(app).post("/pair", json={"code": "x"}).status_code == 429


def test_an_expired_code_is_no_code(token, monkeypatch):
    code = opened(token)
    monkeypatch.setattr(window._open, "closes", 0)
    assert TestClient(app).post("/pair", json={"code": code}).status_code == 410


def test_forgetting_a_device_stops_it_at_once_and_only_it(token):
    first = paired(opened(token), name="phone", kind="phone")
    second = paired(opened(token))
    assert as_mac(token).delete(f"/devices/{first['device']['id']}").status_code == 204
    assert as_mac(first["token"]).get("/sessions").status_code == 401
    assert as_mac(second["token"]).get("/sessions").status_code == 200
    assert as_mac(token).get("/sessions").status_code == 200
    listed = as_mac(token).get("/devices").json()["devices"]
    assert [d["id"] for d in listed] == [second["device"]["id"]]
    assert as_mac(token).delete("/devices/nope").status_code == 404


def test_the_kept_file_holds_no_token(token):
    given = paired(opened(token))["token"]
    kept = (config.data_dir() / "devices.json").read_text()
    assert given not in kept and devices._digest(given) in kept


def test_the_edge_can_ask_whether_a_token_is_good(token):
    device = paired(opened(token))["token"]
    assert as_mac(token).get("/pair/check").status_code == 200
    assert as_mac(device).get("/pair/check").status_code == 200
    assert TestClient(app).get("/pair/check").status_code == 401
    assert as_mac("wrong").get("/pair/check").status_code == 401


def test_a_remote_sessions_files_are_not_fetched_without_a_token(token, monkeypatch, no_hands):
    """The middleware asks the hand with this Mac's token, so it must not do that for a request
    that carried none — it falls through to the route's own 401 instead."""
    sid = "f1ddae0a-7aaf-4bb0-9f42-9a26753f3b03"
    monkeypatch.setattr(routing.merge, "owner", lambda s: "ubuntu" if s == sid else "")
    monkeypatch.setattr(routing.registry, "here", lambda: "m2")
    carried = []
    monkeypatch.setattr(routing.remote, "forward", lambda *a: carried.append(a))
    assert TestClient(app).get(f"/sessions/{sid}/turns").status_code == 401
    assert carried == []
    as_mac(token).get(f"/sessions/{sid}/turns")
    assert carried
