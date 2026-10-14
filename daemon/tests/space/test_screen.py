"""`/sessions/{id}/screen`: the pane's rows as iTerm reads them, shared between polls — plain
through `it2` until iTerm's API is approved, and with every cell's style once it is."""

from __future__ import annotations

import os
import subprocess
import time
from types import SimpleNamespace

import iterm2
import pytest
from iterm2 import api_pb2

from deckhand_daemon import saying
from deckhand_daemon.space import iterm, screen

READ = "⏺ done\n\n> next\x00step\n   \n\n"


@pytest.fixture
def pane(monkeypatch):
    calls = []

    async def live(session_id):
        return SimpleNamespace(pane=SimpleNamespace(iterm_session_id="P1"), name="s")

    def run(argv, **kw):
        calls.append(argv)
        return subprocess.CompletedProcess(argv, 0, stdout=READ, stderr="")

    monkeypatch.setattr(saying, "live_session", live)
    monkeypatch.setattr(screen.subprocess, "run", run)
    monkeypatch.setattr(screen, "_read", {})
    return calls


def test_the_rows_come_back_without_the_blank_tail(client, head, pane):
    answered = client.get("/sessions/any/screen", headers=head).json()
    assert answered["lines"] == ["⏺ done", "", "> next step"]
    assert pane == [["it2", "session", "read", "-s", "P1"]]


def test_polls_inside_fresh_share_one_read(client, head, pane):
    for _ in range(3):
        client.get("/sessions/any/screen", headers=head)
    assert len(pane) == 1


def test_no_pane_is_a_409(client, head, monkeypatch):
    async def live(session_id):
        return SimpleNamespace(pane=None, name="s")

    monkeypatch.setattr(saying, "live_session", live)
    answered = client.get("/sessions/any/screen", headers=head)
    assert answered.status_code == 409


def row(text: str, *styles: api_pb2.CellStyle) -> api_pb2.LineContents:
    one_each = api_pb2.CodePointsPerCell(num_code_points=1, repeats=len(text))
    return api_pb2.LineContents(text=text, code_points_per_cell=[one_each], style=styles)


def test_unapproved_iterms_api_is_never_asked(client, head, pane, iterm_api):
    answered = client.get("/sessions/any/screen", headers=head).json()
    assert answered["styled"] is False
    assert "runs" not in answered
    assert answered["lines"] == ["⏺ done", "", "> next step"]
    assert iterm_api.connects == 0
    assert iterm_api.reads == 0


def test_approved_the_screen_carries_every_cells_style(client, head, pane, iterm_api, approved):
    iterm_api.rows = [row("ab", api_pb2.CellStyle(fgStandard=1, repeats=2)), row("  ")]
    iterm_api.profile = {"Ansi 1 Color": {"Red Component": 1.0}}
    answered = client.get("/sessions/any/screen", headers=head).json()
    assert answered["styled"] is True
    assert answered["lines"] == ["ab"]
    assert answered["runs"] == [[{"t": "ab", "fg": "#ff0000"}]]
    assert pane == []
    assert iterm_api.connects == 1
    assert iterm2.connection.get_script_name() == "deckhand"
    assert "ITERM2_COOKIE" not in os.environ


def test_a_failing_api_reads_plain_text_for_a_minute(
    client, head, pane, iterm_api, approved, monkeypatch
):
    iterm_api.broken = True
    assert client.get("/sessions/any/screen", headers=head).json()["styled"] is False
    monkeypatch.setattr(screen, "_read", {})
    assert client.get("/sessions/any/screen", headers=head).json()["styled"] is False
    assert iterm_api.reads == 1
    assert len(pane) == 2

    # A minute on, a fresh connection: the failed one was dropped.
    iterm_api.broken = False
    monkeypatch.setattr(screen, "_read", {})
    monkeypatch.setattr(iterm, "_failed_at", time.monotonic() - iterm.RETRY_AFTER)
    assert client.get("/sessions/any/screen", headers=head).json()["styled"] is True
    assert iterm_api.connects == 2
