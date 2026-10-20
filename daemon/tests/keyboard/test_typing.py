"""What it takes for typed words to actually become a prompt, and how that is known.

Apart from `test_deliver.py` because these are not about which route was chosen: they are about
the one route that goes through a tty, where a write is not a read and an accepted keystroke is
not a submitted prompt. Both failures they pin were live for days while every receipt said the
delivery had gone.
"""

import json
import socket
import subprocess
import tempfile
from pathlib import Path

import pytest

from deckhand_daemon import deliver
from deckhand_daemon.sessions import Pane, Session, panes

SID = "dddd1111-2222-3333-4444-555566667777"


@pytest.fixture
def inbox():
    """A listening socket standing in for a session, so a fallback to it would be visible."""
    directory = Path(tempfile.mkdtemp(dir="/tmp"))
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(directory / "s.sock"))
    server.listen(1)
    yield server
    server.close()


def watched(home: Path, socket_path: str, session_id: str = SID) -> tuple[Session, Path]:
    """A session with a pane to type into and a transcript to read back from — the only thing
    that can say what arrived."""
    transcript = home / "projects" / "-Users-jj-dev" / f"{session_id}.jsonl"
    transcript.write_text("")
    session = Session(
        session_id=session_id, pid=4242, name="warm-okapi", cwd="/Users/jj/dev/web/shop",
        status="idle", updated_at=0.0, tty="ttys014",
        pane=Pane(iterm_session_id="PANE-1", window_id="w", tab_id="t", title="warm-okapi"),
        socket_path=socket_path,
    )
    return session, transcript


def recording_tmux(monkeypatch) -> list[str]:
    """Every burst tmux was handed, in order."""
    bursts: list[str] = []

    def run(argv, **_kwargs):
        bursts.append(argv[-1])
        return subprocess.CompletedProcess(argv, 0, "", "")

    monkeypatch.setattr(panes.subprocess, "run", run)
    return bursts


def taking(transcript: Path, monkeypatch, keep=slice(None)):
    """A tmux whose session writes what it was typed into its transcript, as one would."""
    def run(argv, **_kwargs):
        if argv[-1] not in (deliver.CLEAR_BOX, deliver.RETURN):
            transcript.write_text(json.dumps({"message": {"content": argv[-1][keep]}}) + "\n")
        return subprocess.CompletedProcess(argv, 0, "", "")

    monkeypatch.setattr(panes.subprocess, "run", run)


def test_a_message_longer_than_one_read_is_typed_in_pieces(inbox, claude_home, monkeypatch):
    """The shape that mangled prompts: a pane's tty hands Claude Code at most 1022 bytes per
    read, and a single longer write arrives as two reads it keeps only one of. Measured against
    a live session, a 1212-character prompt sent whole came back with its first 1014 characters
    gone — delivered, reported delivered, and not what was said."""
    monkeypatch.setattr(deliver, "SUBMITTED", 0.05)  # nothing writes the transcript here
    typed = recording_tmux(monkeypatch)
    session, _ = watched(claude_home, inbox.getsockname())
    said = "another sentence about the rail. " * 200

    deliver.deliver(session, said, route="keyboard")

    assert "".join(typed).startswith(deliver.CLEAR_BOX + said.strip() + deliver.RETURN)
    assert max(len(burst.encode()) for burst in typed) <= deliver.BURST


def test_words_are_never_cut_through_the_middle_of_a_character():
    """The cut is by bytes, because the buffer is; a character split across two writes would
    arrive as two broken halves."""
    for message in ("a" * 4000, "é" * 900, "🙂" * 400):
        pieces = deliver._pieces(message)
        assert "".join(pieces) == message
        assert max(len(piece.encode()) for piece in pieces) <= deliver.BURST


def test_a_prompt_the_session_never_took_is_not_called_delivered(inbox, claude_home, monkeypatch):
    """`send-keys` exiting 0 says the keys were accepted, never that the prompt was submitted — and a
    prompt left sitting in the box was reported to the phone as sent for as long as that was the
    only thing asked. The route is `auto` on purpose: words already in a session's box are not
    words to say again down the socket, which would leave it holding both."""
    monkeypatch.setattr(deliver, "SUBMITTED", 0.1)
    typed = recording_tmux(monkeypatch)
    session, _ = watched(claude_home, inbox.getsockname())

    taken, error = deliver.deliver(session, "run the tests")

    assert taken is None
    assert "unsent in its box" in error
    assert typed.count(deliver.RETURN) == 2, "the return is pressed once more before giving up"


def test_a_prompt_the_transcript_records_is_the_one_called_delivered(inbox, claude_home,
                                                                     monkeypatch):
    """An idle session writes the prompt as a turn and a busy one writes a `queue-operation` for
    its inbox. Either way it is in the file within a second, which is what is waited for."""
    session, transcript = watched(claude_home, inbox.getsockname())
    taking(transcript, monkeypatch)

    assert deliver.deliver(session, "run the tests") == ("keyboard", None)


def test_a_prompt_that_arrived_with_its_front_missing_is_not_called_delivered(inbox, claude_home,
                                                                             monkeypatch):
    """The whole message is looked for and not its opening: the half that survives the failure
    is the tail, so an opening that matched would be the half that was lost."""
    monkeypatch.setattr(deliver, "SUBMITTED", 0.1)
    session, transcript = watched(claude_home, inbox.getsockname())
    taking(transcript, monkeypatch, keep=slice(-20, None))

    assert deliver.deliver(session, "run the tests and then say what broke")[0] is None


def test_a_long_prompt_a_busy_session_took_as_separate_pastes_is_called_delivered(
        inbox, claude_home, monkeypatch):
    """Each piece of a long message is a paste of its own to a session mid-run: wrapped, and an
    entry apiece. The words are all there and never in one place — and calling that unsent put the
    card back on the phone, so the person sent a prompt that had already arrived."""
    session, transcript = watched(claude_home, inbox.getsockname())

    def run(argv, **_kwargs):
        if argv[-1] not in (deliver.CLEAR_BOX, deliver.RETURN):
            entry = {"operation": "enqueue", "content": f'<pasted_content id="1"> {argv[-1]}'}
            with transcript.open("a") as file:
                file.write(json.dumps(entry) + "\n")
        return subprocess.CompletedProcess(argv, 0, "", "")

    monkeypatch.setattr(panes.subprocess, "run", run)

    assert deliver.deliver(session, "another sentence about the rail. " * 100,
                           route="keyboard") == ("keyboard", None)
