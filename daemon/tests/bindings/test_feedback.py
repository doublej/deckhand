"""What was said about a spot on a page: kept under its folder, and a use of its binding."""

from __future__ import annotations

import json

import pytest

from deckhand_daemon import config
from deckhand_daemon.bindings import stored

SHOP = "/Users/jj/dev/web/shop"
SENT = {
    "path": SHOP, "url": "https://a.com/docs/intro?x=1", "title": "Intro", "selector": "main > h1",
    "page_x": 120.5, "page_y": 40, "viewport_width": 1280, "viewport_height": 800,
    "transcript": "make this bigger", "stray": "dropped",
}


def test_an_entry_is_kept_whole_stamped_and_uses_the_best_binding(client, head, monkeypatch):
    monkeypatch.setattr(stored, "now", lambda: "2026-09-15T10:00:00.000Z")
    for pattern in ("https://a.com", "https://a.com/docs"):
        client.post("/bindings", json={"pattern": pattern, "path": SHOP}, headers=head)
    monkeypatch.setattr(stored, "now", lambda: "2026-09-15T12:00:00.000Z")

    answered = client.post("/feedback", json=SENT, headers=head)
    assert answered.status_code == 200
    entry = {key: value for key, value in SENT.items() if key != "stray"}
    entry["created_at"] = "2026-09-15T12:00:00.000Z"
    assert answered.json() == entry

    used = {b["pattern"]: b["last_used"] for b in
            client.get("/bindings", headers=head).json()["bindings"]}
    assert used == {"https://a.com": "2026-09-15T10:00:00.000Z",
                    "https://a.com/docs": "2026-09-15T12:00:00.000Z"}
    assert json.loads((config.data_dir() / "feedback.json").read_text()) == {SHOP: [entry]}


def test_entries_come_back_oldest_first(client, head):
    assert client.get("/feedback", params={"path": SHOP}, headers=head).json() == {"entries": []}
    for said in ("first", "second"):
        client.post("/feedback", json=SENT | {"transcript": said}, headers=head)
    entries = client.get("/feedback", params={"path": SHOP}, headers=head).json()["entries"]
    assert [e["transcript"] for e in entries] == ["first", "second"]


def test_no_binding_to_use_is_not_a_refusal(client, head):
    assert client.post("/feedback", json=SENT, headers=head).status_code == 200
    assert client.get("/bindings", headers=head).json() == {"bindings": []}


def test_title_and_selector_may_be_left_out(client, head):
    sent = {k: v for k, v in SENT.items() if k not in ("title", "selector")}
    answered = client.post("/feedback", json=sent, headers=head).json()
    assert (answered["title"], answered["selector"]) == ("", "")


@pytest.mark.parametrize("change", [
    {"path": "/Users/jj/elsewhere"}, {"path": None}, {"url": "ftp://a.com"}, {"url": None},
    {"transcript": "   "}, {"transcript": None}, {"page_x": "12"}, {"page_y": None},
    {"viewport_width": True}, {"viewport_height": [800]}, {"title": 3}, {"selector": {}},
])
def test_an_entry_missing_what_makes_it_one_is_a_400(client, head, change):
    refused = client.post("/feedback", json=SENT | change, headers=head)
    assert refused.status_code == 400
    assert "detail" in refused.json()
    assert client.get("/feedback", params={"path": SHOP}, headers=head).json() == {"entries": []}


def test_a_number_json_can_spell_and_no_answer_can_carry_is_a_400(client, head):
    body = json.dumps(SENT).replace("120.5", "NaN")
    refused = client.post("/feedback", content=body, headers=head | {"content-type": "application/json"})
    assert refused.status_code == 400


def test_an_unlisted_folder_has_no_entries_to_read(client, head):
    assert client.get("/feedback", params={"path": "/Users/jj/elsewhere"},
                      headers=head).status_code == 400
