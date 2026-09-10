"""The store, and the one function that puts standing orders in front of a message.

Nothing here goes through the app — `test_routes.py` is that half. What is proved here is the
promise the rest of the daemon leans on: a session with no orders gets its prompt back untouched.
"""

import pytest

from deckhand_daemon import orders


@pytest.fixture(autouse=True)
def store(tmp_path, monkeypatch):
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))


def test_a_session_with_no_orders_gets_the_prompt_back_byte_for_byte():
    """The whole guarantee, and `is` rather than `==` is the point of it: not an equal string, the
    same one. Nothing is added — no wrapper, no header, not a leading space — to a prompt for a
    session nobody has given orders to."""
    prompt = "run the tests"
    assert orders.carry("never-told", prompt) is prompt


def test_orders_that_are_only_whitespace_are_no_orders_at_all():
    orders.save("s1", "   \n\n  \t ")
    prompt = "run the tests"
    assert orders.load("s1") == ""
    assert orders.carry("s1", prompt) is prompt


def test_clearing_the_field_stops_them_being_carried():
    orders.save("s1", "always run just check")
    assert orders.carry("s1", "ship it") != "ship it"
    orders.save("s1", "")
    prompt = "ship it"
    assert orders.carry("s1", prompt) is prompt


def test_the_orders_go_in_front_and_the_message_has_the_last_word():
    orders.save("s1", "always run just check")
    carried = orders.carry("s1", "ship it")
    assert carried.index("always run just check") < carried.index("ship it")
    assert carried.endswith("ship it")


def test_orders_survive_between_reads():
    orders.save("s1", "always run just check")
    assert orders.load("s1") == "always run just check"


def test_orders_are_one_sessions_own():
    """Filed by session id, so the terminal next door is not quietly running under them."""
    orders.save("s1", "always run just check")
    prompt = "ship it"
    assert orders.carry("s2", prompt) is prompt


def test_a_pasted_escape_sequence_is_not_keystrokes():
    """These end up typed into a live iTerm pane. Newlines stay — the phone shows them back."""
    assert orders.save("s1", "keep it\n\x1b[31mshort\x07") == "keep it\n[31mshort"


def test_too_much_is_clamped_rather_than_refused():
    assert len(orders.save("s1", "x" * (orders.LIMIT + 500))) == orders.LIMIT


def test_unreadable_orders_are_no_orders_rather_than_an_exception():
    """A half-written file must not take out every prompt into that session."""
    orders.save("s1", "always run just check")
    orders.path("s1").write_text("{ not json")
    prompt = "ship it"
    assert orders.carry("s1", prompt) is prompt
