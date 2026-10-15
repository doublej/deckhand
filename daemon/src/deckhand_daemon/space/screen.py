"""A session's pane as it stands, for the plane that shows it as a terminal.

The transcript is what was said; the pane is what is on the screen — the prompt box, the status
line, and the permission question a session is stopped at, none of which a transcript holds. The
headset's terminal plane (deckhand-web's `/p/terminal`) polls this once a second.

`tmux capture-pane -e` reads the visible rows with their SGR escapes, ~10 ms, so every read
carries each row's colours and attributes as `runs` beside `lines` (`styled.py`), and `styled` is
always true. A read is shared across every poll inside `FRESH`. A session with no pane — a Codex
thread, or one not running inside tmux — is a 409, the same answer `/focus` gives, and the plane
falls back to the transcript.
"""

from __future__ import annotations

import asyncio
import subprocess
import time

from fastapi import APIRouter, HTTPException

from .. import saying
from . import styled, theme

FRESH = 0.5
TIMEOUT = 3.0

router = APIRouter(tags=["space"])
_read: dict[str, dict] = {}


def trimmed(rows: list[str]) -> list[str]:
    rows = [row.rstrip() for row in rows]
    while rows and not rows[-1]:
        rows.pop()
    return rows


def _read_pane(pane_id: str) -> dict:
    kept = _read.get(pane_id)
    if kept and time.time() - kept["at"] < FRESH:
        return kept
    out = subprocess.run(
        ["tmux", "capture-pane", "-p", "-e", "-t", pane_id],
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
        check=False,
    )
    if out.returncode != 0:
        raise HTTPException(
            status_code=409, detail=f"tmux would not read that pane: {out.stderr.strip()[:200]}"
        )
    # Row by row, not `splitlines`, which would also cut a row at a stray form feed.
    rows = out.stdout.removesuffix("\n").split("\n")
    lines = trimmed([styled.plain(row) for row in rows])
    look = theme.theme()
    _read[pane_id] = {
        "lines": lines,
        "at": time.time(),
        "styled": True,
        "runs": [styled.runs(row, look["ansi"], look["brightBold"]) for row in rows[: len(lines)]],
    }
    return _read[pane_id]


@router.get("/sessions/{session_id}/screen")
async def session_screen(session_id: str) -> dict:
    """`{lines, at, styled, runs?}`: the pane's rows, top to bottom, and when they were read."""
    session = await saying.live_session(session_id)
    if not session.pane:
        raise HTTPException(status_code=409, detail="session is not in a tmux pane")
    return await asyncio.to_thread(_read_pane, session.pane.iterm_session_id)
