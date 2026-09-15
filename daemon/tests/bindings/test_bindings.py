"""Pinning a page to a project over the wire, and who may."""

from __future__ import annotations

import json

from deckhand_daemon import config

SHOP = "/Users/jj/dev/web/shop"
DOCS = "/home/jj/dev/web/docs"


def test_every_route_needs_the_token(client):
    assert client.get("/bindings").status_code == 401
    assert client.get("/bindings/match", params={"url": "https://a.com"}).status_code == 401
    assert client.post("/bindings", json={"pattern": "https://a.com", "path": SHOP}).status_code == 401
    assert client.delete("/bindings",
                         params={"pattern": "https://a.com", "path": SHOP}).status_code == 401
    assert client.post("/feedback", json={"path": SHOP}).status_code == 401
    assert client.get("/feedback", params={"path": SHOP}).status_code == 401


def test_a_binding_goes_in_is_matched_and_goes_away(client, head):
    sent = {"pattern": "https://Example.com/docs/", "path": SHOP, "stray": 1}
    kept = client.post("/bindings", json=sent, headers=head)
    assert kept.status_code == 200
    binding = kept.json()
    assert (binding["pattern"], binding["path"]) == ("https://example.com/docs", SHOP)
    assert binding["last_used"].endswith("Z")
    assert set(binding) == {"pattern", "path", "last_used"}

    # The same pair again is the same binding, used again.
    again = client.post("/bindings", json=sent, headers=head).json()
    assert again["last_used"] >= binding["last_used"]
    assert client.get("/bindings", headers=head).json() == {"bindings": [again]}
    on_disk = json.loads((config.data_dir() / "bindings.json").read_text())
    assert on_disk == {"bindings": [again]}

    page = {"url": "https://example.com/docs/intro"}
    assert client.get("/bindings/match", params=page, headers=head).json() == {"matches": [again]}

    gone = {"pattern": "https://EXAMPLE.com/docs", "path": SHOP}
    assert client.delete("/bindings", params=gone, headers=head).json() == {"removed": True}
    assert client.delete("/bindings", params=gone, headers=head).json() == {"removed": False}
    assert client.get("/bindings", headers=head).json() == {"bindings": []}
    assert client.get("/bindings/match", params=page, headers=head).json() == {"matches": []}


def test_a_folder_on_another_machine_may_be_bound(client, head):
    sent = {"pattern": "https://a.com", "path": DOCS}
    assert client.post("/bindings", json=sent, headers=head).status_code == 200


def test_an_unlisted_folder_or_a_bad_pattern_is_a_400(client, head):
    for sent in ({"pattern": "https://a.com", "path": "/Users/jj/elsewhere"},
                 {"pattern": "https://a.com"},
                 {"pattern": "a.com", "path": SHOP},
                 {"pattern": 3, "path": SHOP}):
        refused = client.post("/bindings", json=sent, headers=head)
        assert refused.status_code == 400
        assert "detail" in refused.json()
    assert client.delete("/bindings", params={"pattern": "ftp://a.com", "path": SHOP},
                         headers=head).status_code == 400
    assert client.get("/bindings/match", params={"url": "file:///etc/hosts"},
                      headers=head).status_code == 400
    assert client.get("/bindings", headers=head).json() == {"bindings": []}
