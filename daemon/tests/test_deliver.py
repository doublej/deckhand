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
    assert deliver.deliver(session, "  run  the tests  ") == (True, None)
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
    assert deliver.deliver(session, "hello") == (True, None)
    assert [f["type"] for f in read_frames(inbox)] == ["user"]


def test_a_message_arrives_as_a_user_frame(inbox, claude_home):
    (claude_home / "sessions" / "4242.abc123.key").write_text(json.dumps({"peerToken": "beef" * 8}))
    assert deliver.deliver(session_for(inbox.getsockname()), "  run the tests  ") == (True, None)
    frames = read_frames(inbox)
    assert [f["type"] for f in frames] == ["auth", "user"]
    assert frames[1]["message"] == {
        "role": "user",
        "content": f"{deliver.PREAMBLE}\n\nrun the tests",
    }
    assert frames[1]["priority"] == "next"
    assert frames[1]["msgV"] == deliver.MSG_VERSION


def test_the_auth_line_carries_the_sessions_peer_token(inbox, claude_home):
    (claude_home / "sessions" / "4242.abc123.key").write_text(json.dumps({"peerToken": "cafe" * 8}))
    deliver.deliver(session_for(inbox.getsockname()), "hello")
    assert read_frames(inbox)[0] == {"type": "auth", "token": "cafe" * 8}


def test_a_session_without_a_key_file_is_still_written_to(inbox, claude_home):
    assert deliver.deliver(session_for(inbox.getsockname(), pid=7777), "hello") == (True, None)
    assert [f["type"] for f in read_frames(inbox)] == ["user"]


def test_an_empty_message_is_refused_before_connecting(inbox, claude_home):
    delivered, error = deliver.deliver(session_for(inbox.getsockname()), "   \n ")
    assert (delivered, error) == (False, "nothing to deliver")


def test_a_session_record_without_a_socket_is_refused(claude_home):
    delivered, error = deliver.deliver(session_for(""), "hello")
    assert not delivered
    assert "no inbox socket" in error


def test_a_stale_socket_reports_the_session_as_gone(inbox, claude_home):
    path = inbox.getsockname()
    inbox.close()  # the file stays behind, the way it does when a session is killed
    delivered, error = deliver.deliver(session_for(path), "hello")
    assert not delivered
    assert "stale" in error


def test_a_dead_session_leaves_nothing_to_connect_to(claude_home):
    # Never a real inbox path: a live session with this pid would be messaged for real.
    delivered, error = deliver.deliver(session_for("/tmp/deckhand-gone.sock"), "hello")
    assert not delivered
    assert "not listening" in error


def test_an_unreadable_key_file_does_not_stop_delivery(inbox, claude_home):
    (claude_home / "sessions" / "4242.abc123.key").write_text("{ not json")
    assert deliver.deliver(session_for(inbox.getsockname()), "hello") == (True, None)
    assert [f["type"] for f in read_frames(inbox)] == ["user"]
