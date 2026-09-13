import json
import re
import shutil
import socket
import subprocess
import tempfile
from pathlib import Path

import pytest

from deckhand_daemon import deliver
from deckhand_daemon.sessions import Pane, Session


@pytest.fixture
def inbox():
    """A listening socket standing in for a session. Short path: AF_UNIX caps it at 104 bytes."""
    directory = Path(tempfile.mkdtemp(dir="/tmp"))
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(directory / "s.sock"))
    server.listen(1)
    yield server
    server.close()
    shutil.rmtree(directory, ignore_errors=True)


def read_frames(server: socket.socket) -> list[dict]:
    """Whatever the delivery wrote, one dict per newline-delimited JSON line."""
    connection, _ = server.accept()
    with connection:
        received = b""
        while chunk := connection.recv(65536):
            received += chunk
    return [json.loads(line) for line in received.decode().splitlines() if line]


def session_for(socket_path: str, pid: int = 4242) -> Session:
    return Session(
        session_id="s-1",
        pid=pid,
        name="warm-okapi",
        cwd="/Users/jurrejan/dev",
        status="idle",
        updated_at=0.0,
        tty="ttys001",
        pane=None,
        socket_path=socket_path,
    )


def a_pane() -> Pane:
    return Pane(iterm_session_id="PANE-1", window_id="w", tab_id="t", title="deckhand")


def test_a_session_with_a_pane_is_typed_into(inbox, claude_home, monkeypatch):
    """The keyboard carries the person's authority; the socket says it is only a peer."""
    typed: list[list[str]] = []

    def run(argv, **_kwargs):
        typed.append(argv)
        return subprocess.CompletedProcess(argv, 0, "", "")

    monkeypatch.setattr(deliver.subprocess, "run", run)
    session = session_for(inbox.getsockname())
    session.pane = a_pane()
    assert deliver.deliver(session, "  run  the tests  ") == ("keyboard", None)
    assert typed == [
        ["it2", "session", "send", "-s", "PANE-1", deliver.CLEAR_LINE],
        ["it2", "session", "send", "-s", "PANE-1", "run the tests"],
        ["it2", "session", "send", "-s", "PANE-1", deliver.RETURN],
    ]


def test_a_pane_that_will_not_take_it_falls_back_to_the_socket(inbox, claude_home, monkeypatch):
    """iTerm is not always answering — under launchd it never is."""
    monkeypatch.setattr(
        deliver.subprocess,
        "run",
        lambda argv, **_k: subprocess.CompletedProcess(argv, 1, "", "no such session"),
    )
    session = session_for(inbox.getsockname())
    session.pane = a_pane()
    assert deliver.deliver(session, "hello") == ("socket", None)
    assert [f["type"] for f in read_frames(inbox)] == ["user"]


def test_the_keyboard_route_does_not_quietly_use_the_socket(inbox, claude_home, monkeypatch):
    """Choosing the keyboard is choosing whose authority the words carry. Never substitute."""
    monkeypatch.setattr(
        deliver.subprocess,
        "run",
        lambda argv, **_k: subprocess.CompletedProcess(argv, 1, "", "no such session"),
    )
    session = session_for(inbox.getsockname())
    session.pane = a_pane()
    taken, error = deliver.deliver(session, "hello", route="keyboard")
    assert taken is None
    assert "would not type" in error


def test_the_keyboard_route_says_so_when_there_is_no_pane(inbox, claude_home):
    taken, error = deliver.deliver(session_for(inbox.getsockname()), "hello", route="keyboard")
    assert taken is None
    assert "no iTerm pane" in error


def test_the_socket_route_ignores_a_perfectly_good_pane(inbox, claude_home, monkeypatch):
    monkeypatch.setattr(
        deliver.subprocess,
        "run",
        lambda *_a, **_k: pytest.fail("the socket route must not touch iTerm"),
    )
    session = session_for(inbox.getsockname())
    session.pane = a_pane()
    assert deliver.deliver(session, "hello", route="socket") == ("socket", None)
    assert [f["type"] for f in read_frames(inbox)] == ["user"]


def test_an_unknown_route_is_refused(inbox, claude_home):
    taken, error = deliver.deliver(session_for(inbox.getsockname()), "hello", route="carrier pigeon")
    assert taken is None
    assert "no such route" in error


def test_a_message_arrives_as_a_user_frame(inbox, claude_home):
    (claude_home / "sessions" / "4242.abc123.key").write_text(json.dumps({"peerToken": "beef" * 8}))
    assert deliver.deliver(session_for(inbox.getsockname()), "  run the tests  ") == ("socket", None)
    frames = read_frames(inbox)
    assert [f["type"] for f in frames] == ["auth", "user"]
    assert frames[1]["message"] == {
        "role": "user",
        "content": f"{deliver.PREAMBLE} run the tests",
    }
    assert frames[1]["priority"] == "next"
    assert frames[1]["msgV"] == deliver.MSG_VERSION


def test_the_auth_line_carries_the_sessions_peer_token(inbox, claude_home):
    (claude_home / "sessions" / "4242.abc123.key").write_text(json.dumps({"peerToken": "cafe" * 8}))
    deliver.deliver(session_for(inbox.getsockname()), "hello")
    assert read_frames(inbox)[0] == {"type": "auth", "token": "cafe" * 8}


def test_a_session_without_a_key_file_is_still_written_to(inbox, claude_home):
    assert deliver.deliver(session_for(inbox.getsockname(), pid=7777), "hello") == ("socket", None)
    assert [f["type"] for f in read_frames(inbox)] == ["user"]


def test_an_empty_message_is_refused_before_connecting(inbox, claude_home):
    taken, error = deliver.deliver(session_for(inbox.getsockname()), "   \n ")
    assert (taken, error) == (None, "nothing to deliver")


def test_a_session_record_without_a_socket_is_refused(claude_home):
    taken, error = deliver.deliver(session_for(""), "hello")
    assert taken is None
    assert "no inbox socket" in error


def test_a_stale_socket_reports_the_session_as_gone(inbox, claude_home):
    path = inbox.getsockname()
    inbox.close()  # the file stays behind, the way it does when a session is killed
    taken, error = deliver.deliver(session_for(path), "hello")
    assert taken is None
    assert "stale" in error


def test_a_dead_session_leaves_nothing_to_connect_to(claude_home):
    # Never a real inbox path: a live session with this pid would be messaged for real.
    taken, error = deliver.deliver(session_for("/tmp/deckhand-gone.sock"), "hello")
    assert taken is None
    assert "not listening" in error


def test_an_unreadable_key_file_does_not_stop_delivery(inbox, claude_home):
    (claude_home / "sessions" / "4242.abc123.key").write_text("{ not json")
    assert deliver.deliver(session_for(inbox.getsockname()), "hello") == ("socket", None)
    assert [f["type"] for f in read_frames(inbox)] == ["user"]


def test_the_controls_are_keystrokes_in_the_pane(inbox, claude_home, monkeypatch):
    """Escape stops a run; the rest are slash commands typed like any other line."""
    typed: list[list[str]] = []
    monkeypatch.setattr(
        deliver.subprocess,
        "run",
        lambda argv, **_k: (typed.append(argv), subprocess.CompletedProcess(argv, 0, "", ""))[1],
    )
    session = session_for(inbox.getsockname())
    session.pane = a_pane()

    assert deliver.control(session, "cancel") is None
    assert deliver.control(session, "compact") is None

    assert typed == [
        ["it2", "session", "send", "-s", "PANE-1", deliver.ESCAPE],
        ["it2", "session", "send", "-s", "PANE-1", deliver.CLEAR_LINE],
        ["it2", "session", "send", "-s", "PANE-1", "/compact"],
        ["it2", "session", "send", "-s", "PANE-1", deliver.RETURN],
    ]


def test_every_control_the_phone_offers_is_one_the_daemon_knows(inbox, claude_home):
    """The phone's menu and this table are two lists of the same four things.

    They are in two languages and nothing joins them, so a control added to `Control` in Swift and
    not here is a menu item that reaches the daemon and comes back "no such control" — which looks
    like a broken session rather than a missing line. This is the join, written down.
    """
    assert set(deliver.CONTROLS) == {"cancel", "compact", "clear", "exit"}


def test_exit_is_typed_and_returned_like_any_other_slash_command(inbox, claude_home, monkeypatch):
    """It quits Claude Code, and it is still only two bursts into the pane."""
    typed: list[list[str]] = []
    monkeypatch.setattr(
        deliver.subprocess,
        "run",
        lambda argv, **_k: (typed.append(argv), subprocess.CompletedProcess(argv, 0, "", ""))[1],
    )
    session = session_for(inbox.getsockname())
    session.pane = a_pane()

    assert deliver.control(session, "exit") is None
    assert typed == [
        ["it2", "session", "send", "-s", "PANE-1", deliver.CLEAR_LINE],
        ["it2", "session", "send", "-s", "PANE-1", "/exit"],
        ["it2", "session", "send", "-s", "PANE-1", deliver.RETURN],
    ]


def test_a_slash_command_is_refused_where_it_would_arrive_as_words(inbox, claude_home):
    """The socket delivers a message, and a message beginning with a slash is not a command.

    The receiving session reads it, runs nothing, and reports no failure — because from where it
    sits nothing failed. Saying no is the only way anybody finds out, so this is a refusal rather
    than a delivery.
    """
    session = session_for(inbox.getsockname())

    # No pane, so `auto` would fall through to the socket.
    route, error = deliver.deliver(session, "/feature a new branch")
    assert route is None
    assert "/feature is a slash command" in (error or "")

    # And explicitly, with a pane there to type into: choosing the socket is still choosing words.
    session.pane = a_pane()
    route, error = deliver.deliver(session, "/feature a new branch", route="socket")
    assert route is None
    assert "would receive it as words" in (error or "")


def test_ordinary_words_are_untouched_by_that_guard(inbox, claude_home):
    """Only a leading slash. A sentence with a path in the middle of it is a sentence."""
    session = session_for(inbox.getsockname())

    route, error = deliver.deliver(session, "look in /Users/jj/dev for it")

    assert error is None
    assert route == "socket"


def test_a_control_needs_a_pane_and_says_so(inbox, claude_home):
    """The peer socket delivers messages, and none of these is a message."""
    session = session_for(inbox.getsockname())
    session.pane = None

    assert "no iTerm pane" in (deliver.control(session, "cancel") or "")


def test_an_unknown_control_is_refused_rather_than_typed(inbox, claude_home, monkeypatch):
    monkeypatch.setattr(deliver.subprocess, "run", lambda *_a, **_k: pytest.fail("typed anyway"))
    session = session_for(inbox.getsockname())
    session.pane = a_pane()

    assert deliver.control(session, "rm -rf") == "no such control 'rm -rf'"


def test_a_rename_runs_claude_code_s_own_command(inbox, claude_home, monkeypatch):
    """`/rename` takes the name as an argument, so it is typed like any other line."""
    typed: list[list[str]] = []
    monkeypatch.setattr(
        deliver.subprocess,
        "run",
        lambda argv, **_k: (typed.append(argv), subprocess.CompletedProcess(argv, 0, "", ""))[1],
    )
    session = session_for(inbox.getsockname())
    session.pane = a_pane()

    assert deliver.rename(session, "  the   promo  edit \n") is None
    assert typed == [
        ["it2", "session", "send", "-s", "PANE-1", deliver.CLEAR_LINE],
        ["it2", "session", "send", "-s", "PANE-1", "/rename the promo edit"],
        ["it2", "session", "send", "-s", "PANE-1", deliver.RETURN],
    ]


def test_a_name_is_flattened_before_it_is_typed():
    """A newline in it would submit half a command and leave the rest in the box."""
    assert deliver.clean_name("two\nlines") == "two lines"
    assert deliver.clean_name("  padded  ") == "padded"
    assert deliver.clean_name("x" * 200) == "x" * deliver.MAX_NAME
    assert deliver.clean_name("   ") == ""


def test_an_empty_name_is_refused_rather_than_typed(inbox, claude_home, monkeypatch):
    monkeypatch.setattr(deliver.subprocess, "run", lambda *_a, **_k: pytest.fail("typed anyway"))
    session = session_for(inbox.getsockname())
    session.pane = a_pane()

    assert deliver.rename(session, "  ") == "a name cannot be empty"


# Claude Code's input tokenizer splits a bare control byte out as its own keypress only when
# the whole read is under 64 bytes; in a longer one it is folded into the surrounding text run
# and arrives as characters. An escape sequence is split out of a read of any size. That rule
# is the bug, so this is the rule.
KEYSTROKE = re.compile(r"\x1b\[[\d;]*u|[\x00-\x1f]")


def recording_it2(monkeypatch) -> list[str]:
    """Every burst `it2` was handed, in order, without a pane to type it into."""
    bursts: list[str] = []

    def run(argv, **_kwargs):
        bursts.append(argv[-1])
        return subprocess.CompletedProcess(argv, 0, "", "")

    monkeypatch.setattr(deliver.subprocess, "run", run)
    return bursts


def keys_pressed(chunk: str) -> list[str]:
    """What a session reading `chunk` in one go would take as keypresses rather than as text."""
    return [k.group() for k in KEYSTROKE.finditer(chunk)
            if k.group().startswith("\x1b") or len(chunk) < 64]


def test_a_long_prompt_with_pictures_submits_even_read_as_one_chunk(inbox, claude_home,
                                                                    monkeypatch):
    """The shape that broke: a long spoken prompt and two pictures, typed and never sent.

    The daemon always writes the return after the words, and against a reader that drains its
    tty at once the two arrive as two reads. A session that is slow to drain takes both in one
    — measured against an inert pane, a reader stalled for six seconds got the words and the
    return in a single 122-byte read — and at that size a bare return is text, not a keypress.
    So the test is not whether the return was written; it is whether it still reads as a
    keypress when everything written lands together.
    """
    typed = recording_it2(monkeypatch)
    session = session_for(inbox.getsockname())
    session.pane = a_pane()
    folder = "/Users/jurrejan/Library/Application Support/Deckhand/images/s-1"
    said = deliver.with_images(
        "tell me which of these two crops reads better on the rail. " * 12,
        [f"{folder}/1789054000-aaaa1111.png", f"{folder}/1789054001-bbbb2222.png"],
    )

    assert deliver.deliver(session, said, route="keyboard") == ("keyboard", None)

    one_chunk = "".join(typed)
    assert len(one_chunk) > 64, "the shape under test is the long one"
    assert keys_pressed(one_chunk) == [deliver.CLEAR_LINE, deliver.RETURN]


def test_a_control_byte_in_the_words_is_never_typed(inbox, claude_home, monkeypatch):
    """An escape in a prompt would cancel the turn it was meant to start."""
    typed = recording_it2(monkeypatch)
    session = session_for(inbox.getsockname())
    session.pane = a_pane()

    assert deliver.deliver(session, "run \x1b\x07the \x15tests", route="keyboard")[0] == "keyboard"

    assert typed[:2] == [deliver.CLEAR_LINE, "run the tests"]
