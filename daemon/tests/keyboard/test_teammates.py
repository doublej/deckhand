"""A prompt box talking to a teammate, and the keys that take it back to the lead.

The screens below are the ones a throwaway Claude Code 2.1.304 pane drew for each key. What these
pin is the order, and the one key that must never be pressed blind: Escape interrupts a running
turn everywhere except in the team list, so it goes only once the list has the cursor.
"""

import json
import socket
import tempfile
from pathlib import Path

import pytest

from deckhand_daemon import deliver
from deckhand_daemon.sessions import Pane, Session, teammates

RULE = "─" * 40
TEAMMATE_BOX = f"{RULE} @book-builder ─\n❯ Message @book-builder…\n{RULE}\n  ◯ main\n  ⏺ book-builder\n"
LIST_ON_MAIN = f"{RULE} @book-builder ─\n❯ Message @book-builder…\n{RULE}\n❯ ◯ main\n  ⏺ book-builder\n"
LEAD_LIST_HELD = f"{RULE} misty-weasel ─\n❯ \n{RULE}\n❯ ⏺ main\n  ◯ book-builder\n"
LEAD_BOX = f"{RULE} misty-weasel ─\n❯ \n{RULE}\n  ⏺ main\n  ◯ book-builder\n"
#: What each key turns the screen into, as measured.
MEASURED = {deliver.CLEAR_BOX: TEAMMATE_BOX, teammates.DOWN: LIST_ON_MAIN,
            teammates.ENTER: LEAD_LIST_HELD, teammates.ESCAPE: LEAD_BOX}


@pytest.fixture
def inbox():
    directory = Path(tempfile.mkdtemp(dir="/tmp"))
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(directory / "s.sock"))
    server.listen(1)
    yield server
    server.close()


@pytest.fixture
def pane(monkeypatch):
    """A pane that starts on a teammate's box and answers each key with `answers`."""
    state = {"screen": TEAMMATE_BOX, "pressed": [], "answers": dict(MEASURED)}

    def press(pane_id, key):
        state["pressed"].append(key)
        state["screen"] = state["answers"].get(key, state["screen"])
        return True

    monkeypatch.setattr(teammates, "press", press)
    monkeypatch.setattr(teammates, "_screen", lambda pane_id: state["screen"])
    monkeypatch.setattr(teammates, "SETTLE", 0.05)
    return state


def misty(status="idle", socket_path="") -> Session:
    return Session(
        session_id="s-1", pid=4242, name="misty-weasel", cwd="/Users/jj/dev/web/silentsongs",
        status=status, updated_at=0.0, tty="ttys014",
        pane=Pane(iterm_session_id="PANE-1", window_id="w", tab_id="t", title="misty-weasel"),
        socket_path=socket_path,
    )


def test_the_box_is_read_off_the_rule_over_it(pane):
    assert teammates.addressed_to("PANE-1") == "book-builder"
    pane["screen"] = LEAD_BOX
    assert teammates.addressed_to("PANE-1") is None


def test_an_idle_lead_is_brought_back_with_the_keys_as_measured(pane):
    assert teammates.bring_back(misty(), deliver.CLEAR_BOX) is None
    assert pane["pressed"] == [deliver.CLEAR_BOX, teammates.DOWN, teammates.ENTER,
                               teammates.ESCAPE]


def test_a_lead_mid_turn_gets_no_keys_at_all(pane):
    """Measured: with the lead busy, the keys that open the list landed elsewhere and the
    Escape after them stopped the lead's turn."""
    assert "mid-turn" in teammates.bring_back(misty(status="busy"), deliver.CLEAR_BOX)
    assert pane["pressed"] == []


def test_a_collapsed_list_stops_before_enter_or_escape(pane):
    """"← 1 agent" draws no rows, so Down reaches nothing — and an Escape after that would be
    a cancel in the chat box."""
    pane["answers"][teammates.DOWN] = TEAMMATE_BOX
    assert "did not go as measured" in teammates.bring_back(misty(), deliver.CLEAR_BOX)
    assert pane["pressed"] == [deliver.CLEAR_BOX, teammates.DOWN]


def test_a_box_that_stays_a_teammates_goes_down_the_inbox_on_auto(pane, inbox, claude_home):
    session = misty(status="busy", socket_path=inbox.getsockname())

    assert deliver.deliver(session, "continue") == ("socket", None)
    connection, _ = inbox.accept()
    with connection:
        frames = [json.loads(line) for line in connection.makefile().read().splitlines()]
    assert frames[-1]["type"] == "user"
    assert pane["pressed"] == []


def test_the_keyboard_route_refuses_rather_than_typing_to_the_teammate(pane, claude_home):
    taken, error = deliver.deliver(misty(status="busy"), "continue", route="keyboard")

    assert taken is None
    assert "@book-builder" in error
    assert pane["pressed"] == []
