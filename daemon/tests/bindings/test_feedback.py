"""What was said about a spot on a page: kept under its folder, and a use of its binding."""

from __future__ import annotations

import base64
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
    entry |= {"id": answered.json()["id"], "created_at": "2026-09-15T12:00:00.000Z",
              "screenshot": None, "crop": None}
    assert answered.json() == entry
    assert len(entry["id"]) == 32

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


JPEG = b"\xff\xd8\xff\xe0 not really a jpeg \xff\xd9"
CROP = b"\xff\xd8 the cropped part \xff\xd9"


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def _shot(client, head) -> dict:
    return client.post("/feedback", json=SENT | {"screenshot": _b64(JPEG)}, headers=head).json()


def test_a_screenshot_is_a_file_and_the_entry_keeps_its_path(client, head):
    entry = _shot(client, head)
    shots = config.data_dir() / "feedback-shots"
    assert entry["screenshot"] == str((shots / f"{entry['id']}.jpg").resolve())
    assert entry["crop"] is None
    assert (shots / f"{entry['id']}.jpg").read_bytes() == JPEG
    kept = (config.data_dir() / "feedback.json").read_text()
    assert _b64(JPEG) not in kept
    assert json.loads(kept)[SHOP] == [entry]


def test_a_screenshot_that_is_not_base64_is_a_400_and_keeps_nothing(client, head):
    for bad in ("not base64!", "", 12):
        refused = client.post("/feedback", json=SENT | {"screenshot": bad}, headers=head)
        assert refused.status_code == 400
    assert client.get("/feedback", params={"path": SHOP}, headers=head).json() == {"entries": []}


def test_both_kinds_of_image_are_served_as_jpeg(client, head):
    entry = _shot(client, head)
    got = client.get("/feedback/image", params={"id": entry["id"], "kind": "screenshot"},
                     headers=head)
    assert (got.status_code, got.headers["content-type"], got.content) == (200, "image/jpeg", JPEG)
    client.put("/feedback/crop", json={"id": entry["id"], "image": _b64(CROP)}, headers=head)
    got = client.get("/feedback/image", params={"id": entry["id"], "kind": "crop"}, headers=head)
    assert (got.status_code, got.headers["content-type"], got.content) == (200, "image/jpeg", CROP)


def test_an_image_nobody_kept_is_a_404_and_another_kind_a_400(client, head):
    bare = client.post("/feedback", json=SENT, headers=head).json()
    shot = _shot(client, head)
    for id_, kind in ((bare["id"], "screenshot"), (shot["id"], "crop"),
                      ("0" * 32, "screenshot"), ("../feedback.json", "screenshot")):
        got = client.get("/feedback/image", params={"id": id_, "kind": kind}, headers=head)
        assert got.status_code == 404
    got = client.get("/feedback/image", params={"id": shot["id"], "kind": "json"}, headers=head)
    assert got.status_code == 400


def test_a_crop_is_kept_beside_its_screenshot(client, head):
    entry = _shot(client, head)
    answered = client.put("/feedback/crop", json={"id": entry["id"], "image": _b64(CROP)},
                          headers=head)
    assert answered.status_code == 200
    crop = config.data_dir() / "feedback-shots" / f"{entry['id']}-crop.jpg"
    assert answered.json() == entry | {"crop": str(crop.resolve())}
    assert crop.read_bytes() == CROP
    entries = client.get("/feedback", params={"path": SHOP}, headers=head).json()["entries"]
    assert entries == [answered.json()]


def test_a_crop_for_no_entry_is_a_404_and_one_not_base64_a_400(client, head):
    entry = _shot(client, head)
    missing = client.put("/feedback/crop", json={"id": "0" * 32, "image": _b64(CROP)}, headers=head)
    assert missing.status_code == 404
    bad = client.put("/feedback/crop", json={"id": entry["id"], "image": "@@"}, headers=head)
    assert bad.status_code == 400


def test_an_entry_kept_before_ids_reads_back_unchanged(client, head):
    old = {k: v for k, v in SENT.items() if k != "stray"}
    old["created_at"] = "2026-09-01T00:00:00.000Z"
    (config.data_dir() / "feedback.json").write_text(json.dumps({SHOP: [old]}))
    _shot(client, head)
    entries = client.get("/feedback", params={"path": SHOP}, headers=head).json()["entries"]
    assert entries[0] == old
