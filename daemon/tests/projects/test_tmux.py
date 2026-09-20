"""Which session a hand is hung off. The rest of `tmux.py` is one `subprocess.run`."""

from deckhand_daemon.projects.tmux import _pick


def test_prefers_an_attached_session_over_a_newer_idle_one() -> None:
    assert _pick("0 200 work\n1 100 byobu\n") == "byobu"


def test_falls_back_to_the_most_recently_used() -> None:
    assert _pick("0 100 old\n0 200 new\n") == "new"


def test_ignores_other_hands() -> None:
    assert _pick("0 300 deckhand-alpha\n0 100 mine\n") == "mine"
    assert _pick("0 300 deckhand-alpha\n") is None


def test_no_server_reads_as_no_session() -> None:
    assert _pick("") is None
