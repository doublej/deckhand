"""What one answer says about an address, and the route that puts it all together."""

from __future__ import annotations

import json

import httpx
import pytest
from fastapi.testclient import TestClient

from deckhand_daemon.addresses import atlas, checking

SESSION = "aaaa1111-2222-3333-4444-555566667777"


def _answer(status, url="https://shop.nl/", headers=None, came_from=None):
    answer = httpx.Response(status, headers=headers, request=httpx.Request("GET", url))
    if came_from:
        answer.history = [httpx.Response(302, request=httpx.Request("GET", came_from))]
    return answer


@pytest.mark.parametrize(("answer", "body", "state", "note"), [
    (_answer(200), b"<title>Shop &amp; co</title>", "loads", ""),
    (_answer(401), b"", "locked", "asks for a password"),
    (_answer(200, "https://shop.nl/login", came_from="https://shop.nl/admin"), b"", "locked",
     "sends you to a login page"),
    (_answer(200, "https://team.cloudflareaccess.com/x"), b"", "locked", "behind Cloudflare Access"),
    (_answer(200), b'<input type="password">', "loads", "has a login form"),
    (_answer(403, headers={"cf-mitigated": "challenge"}), b"", "loads",
     "behind a bot check — a browser gets through"),
    (_answer(404, "http://localhost:4180/"), b"", "loads", "up, with nothing at /"),
    (_answer(502, "https://shop.nl/app"), b"", "fails", "answers 502"),
])
def test_one_answer_reads_as(answer, body, state, note):
    check = checking._verdict(answer, body)
    assert (check.state, check.note) == (state, note)


def test_a_path_carrying_a_key_is_never_requested():
    assert checking._url("https://shop.nl", "/magic?token=abc") == "https://shop.nl/"
    assert checking._url("https://shop.nl", "/admin?page=2") == "https://shop.nl/admin?page=2"


def test_a_port_on_this_mac_means_the_project_reserving_it():
    known = [atlas.Known("eink", port=4109, local="https://web-eink.atlas.local.jurrejan.com",
                         hosts={"web-eink.atlas.local.jurrejan.com"})]
    assert atlas.match(known, "http://localhost:4109").name == "eink"
    assert atlas.match(known, "https://web-eink.atlas.local.jurrejan.com").name == "eink"
    assert atlas.match(known, "http://192.168.99.99:4109") is None


def test_the_route_checks_names_and_drops_code_that_does_not_resolve(claude_home, token, monkeypatch):
    path = claude_home / "projects" / "-Users-jj-dev" / f"{SESSION}.jsonl"
    path.write_text(json.dumps({"type": "assistant", "timestamp": "2026-10-20T10:00:00Z", "message": {
        "content": [{"type": "text", "text": "up on localhost:4109, see self.local"}]}}) + "\n")

    async def probe(url):
        if "self.local" in url:
            return checking.Check("down", "none", note="the name does not resolve")
        return checking.Check("loads", "home", 200, lan_url="http://192.168.1.2:4109/")

    monkeypatch.setattr(checking, "_kept", {})
    monkeypatch.setattr(checking, "probe", probe)
    monkeypatch.setattr(atlas, "registry", lambda: [atlas.Known("eink", port=4109)])
    from deckhand_daemon.app import app

    rows = TestClient(app).get(f"/sessions/{SESSION}/addresses",
                               headers={"x-deckhand-token": token}).json()
    assert rows["complete"] is True
    assert [(r["origin"], r["state"], r["reach"], r["atlas"]["name"]) for r in rows["addresses"]] == [
        ("http://localhost:4109", "loads", "home", "eink")]
