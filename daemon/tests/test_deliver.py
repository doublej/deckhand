import json
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
        ["it2", "session", "send", "-s", "PANE-1", deliver.CLEAR_LINE + "run the tests"],
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


def test_the_three_controls_are_keystrokes_in_the_pane(inbox, claude_home, monkeypatch):
    """Escape stops a run; the other two are slash commands typed like any other line."""
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
        ["it2", "session", "send", "-s", "PANE-1", deliver.CLEAR_LINE + "/compact"],
        ["it2", "session", "send", "-s", "PANE-1", deliver.RETURN],
    ]


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
