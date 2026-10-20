"""The words utt is told to listen for: the phone reads them, prunes them, and gets back what is kept."""

from __future__ import annotations

from deckhand_daemon.settings import hints


def test_no_file_is_the_seeded_list_without_socket(claude_home):
    assert hints.load() == list(hints.SEEDED)
    assert "socket" not in hints.load()


def test_the_list_goes_out_and_comes_back_as_stored(client, token):
    head = {"x-deckhand-token": token}
    written = client.put("/hints", json={"hints": ["Claude", " claude ", "", "Swift\n  UI"]},
                         headers=head).json()
    assert written == {"hints": ["Claude", "Swift UI"]}
    assert client.get("/hints", headers=head).json() == written


def test_an_emptied_list_stays_empty(claude_home):
    hints.save([])
    assert hints.load() == []


def test_the_hints_need_the_token(client):
    assert client.get("/hints").status_code == 401


SHOP = "/Users/jj/dev/web/shop"


def test_a_deeper_folder_appends_to_every_list_above_it(claude_home):
    """CLAUDE.md's rule: the global words, then each folder's own from home down to the session."""
    hints.save(["Claude"])
    hints.save_folder("/Users/jj/dev", ["pytest"])
    hints.save_folder(SHOP, ["Shopify", "claude"])
    assert [layer["path"] for layer in hints.layers(SHOP)] == [
        "", "/Users/jj", "/Users/jj/dev", "/Users/jj/dev/web", SHOP]
    assert hints.for_folder(SHOP) == ["Claude", "pytest", "Shopify"]
    assert hints.for_folder("/Users/jj/dev/other") == ["Claude", "pytest"]


def test_an_emptied_folder_is_forgotten_and_the_global_list_kept(claude_home):
    hints.save(["Claude"])
    hints.save_folder(SHOP, ["Shopify"])
    hints.save_folder(SHOP, [])
    assert hints.for_folder(SHOP) == ["Claude"]
    assert "folders" in hints.path().read_text()


def test_one_layer_is_read_and_written_from_the_phone(client, token):
    head = {"x-deckhand-token": token}
    written = client.put("/hints/folder", json={"path": SHOP, "hints": ["Shopify", " "]},
                         headers=head).json()
    assert written == {"path": SHOP, "hints": ["Shopify"]}
    layers = client.get("/hints/folder", params={"path": SHOP}, headers=head).json()["layers"]
    assert layers[0]["path"] == ""
    assert layers[-1] == {"path": SHOP, "hints": ["Shopify"]}
