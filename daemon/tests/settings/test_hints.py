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
