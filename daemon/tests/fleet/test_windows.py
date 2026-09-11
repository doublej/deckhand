"""The two things a hand on Fractal does differently, tested from a Mac.

Neither can be run for real here, so what is checked is the seam: that the Windows branch is
taken on Windows and never anywhere else, and that the answer it gives has the same shape as the
POSIX one. The behaviour behind each branch belongs to the machine it runs on.
"""

from __future__ import annotations

import pytest

from deckhand_daemon import deliver
from deckhand_daemon.sessions import live

WINDOWS_PIPE = r"\\.\pipe\LOCAL\cc-msg-998b280e0e6d414253fbcd36837d176e"
# A real `procStart` off Fractal, which is a FILETIME — 100 ns ticks since 1601.
FILETIME = "134330490701669727"


class TestWhetherAPidIsStillThatSession:
    def test_posix_asks_ps_and_ignores_the_records_own_answer(self, monkeypatch):
        monkeypatch.setattr(live.sys, "platform", "darwin")
        assert live._still_running(42, {42: "ttys001"}, FILETIME)
        assert not live._still_running(42, {}, FILETIME)

    def test_windows_compares_the_records_start_time_with_the_pids(self, monkeypatch):
        """The better test of the two: a pid handed to something else since has a different
        creation time, which `ps | grep claude` cannot see."""
        monkeypatch.setattr(live.sys, "platform", "win32")
        monkeypatch.setattr(live, "_created_at", lambda pid: FILETIME)

        assert live._still_running(44736, {}, FILETIME)
        assert not live._still_running(44736, {}, "134330490701669999")

    def test_a_windows_record_with_no_start_time_is_not_live(self, monkeypatch):
        """Nothing to compare is not the same as a match. Without this a record from a Claude
        Code too old to write one would list a session whose process is long gone."""
        monkeypatch.setattr(live.sys, "platform", "win32")
        monkeypatch.setattr(live, "_created_at", lambda pid: "")

        assert not live._still_running(44736, {}, "")

    def test_there_is_no_ps_on_windows_to_ask(self, monkeypatch):
        """`ps` is not on that machine at all, so asking is an OSError rather than an empty
        answer — which is what used to take the whole listing down with it."""
        monkeypatch.setattr(live.sys, "platform", "win32")
        monkeypatch.setattr(live.subprocess, "run", lambda *a, **k: pytest.fail("ran ps"))

        assert live._processes() == {}


class TestWhichDoorTheFramesGoThrough:
    @pytest.fixture
    def session(self):
        from deckhand_daemon.sessions import Session

        return Session(
            session_id="d53bf267-c0b4-490e-8155-a5978ad37f9d",
            pid=44736, name="jurre-28", cwd="C:\\Users\\jurre", status="idle",
            updated_at=0.0, tty="", pane=None, socket_path=WINDOWS_PIPE, machine="fractal",
        )

    def test_windows_writes_the_pipe_and_never_opens_a_unix_socket(self, monkeypatch, session):
        wrote: list[bytes] = []
        monkeypatch.setattr(deliver.sys, "platform", "win32")
        monkeypatch.setattr(deliver, "_peer_token", lambda pid: None)
        monkeypatch.setattr(deliver, "_write_pipe", lambda p, b: (wrote.append((p, b)), (True, None))[1])
        monkeypatch.setattr(deliver, "_write_unix", lambda p, b: pytest.fail("opened AF_UNIX"))

        assert deliver._through_socket(session, "hello") == (True, None)
        assert wrote[0][0] == WINDOWS_PIPE
        # The frames are the wire, and the wire is the same on every machine.
        assert wrote[0][1].endswith(b"\n")
        assert b'"priority": "next"' in wrote[0][1]

    def test_posix_writes_the_socket_and_never_opens_a_pipe(self, monkeypatch, session):
        monkeypatch.setattr(deliver.sys, "platform", "darwin")
        monkeypatch.setattr(deliver, "_peer_token", lambda pid: None)
        monkeypatch.setattr(deliver, "_write_unix", lambda p, b: (True, None))
        monkeypatch.setattr(deliver, "_write_pipe", lambda p, b: pytest.fail("opened a pipe"))

        assert deliver._through_socket(session, "hello") == (True, None)

    def test_a_refusal_names_the_session_rather_than_the_path(self, monkeypatch, session):
        """The writers hand back a template because they have the path and not the name, and a
        person reading `\\\\.\\pipe\\LOCAL\\cc-msg-998b…` has been told nothing."""
        monkeypatch.setattr(deliver.sys, "platform", "win32")
        monkeypatch.setattr(deliver, "_peer_token", lambda pid: None)
        monkeypatch.setattr(
            deliver, "_write_pipe", lambda p, b: (False, "{name} is not listening — gone")
        )

        sent, error = deliver._through_socket(session, "hello")
        assert sent is False
        assert error == "jurre-28 is not listening — gone"

    def test_a_session_with_no_inbox_at_all_is_refused_before_either(self, monkeypatch, session):
        from dataclasses import replace

        monkeypatch.setattr(deliver, "_write_pipe", lambda p, b: pytest.fail("opened a pipe"))
        monkeypatch.setattr(deliver, "_write_unix", lambda p, b: pytest.fail("opened a socket"))

        sent, error = deliver._through_socket(replace(session, socket_path=""), "hello")
        assert sent is False
        assert error == "jurre-28 has no inbox socket"
