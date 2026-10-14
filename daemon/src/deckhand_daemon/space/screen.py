"""A session's pane as it stands, for the plane that shows it as a terminal.

The transcript is what was said; the pane is what is on the screen — the prompt box, the status
line, and the permission question a session is stopped at, none of which a transcript holds. The
headset's terminal plane (deckhand-web's `/p/terminal`) polls this once a second.

Once iTerm's API is approved (`iterm.py`) the read carries every cell's colours and attributes
too, as `runs` beside `lines`, and `styled` says which it was. Until then, and for a minute after
the API fails, it is `it2 session read`: plain text, ~0.13 s. Either read is shared across every
poll inside `FRESH`. A session with no pane — a Codex thread, or iTerm not answering — is a 409,
the same answer `/focus` gives, and the plane falls back to the transcript.
"""

from __future__ import annotations

import asyncio
import subprocess
import time

from fastapi import APIRouter, HTTPException

from .. import saying
from . import iterm, styled, theme

FRESH = 0.5
TIMEOUT = 3.0

router = APIRouter(tags=["space"])
_read: dict[str, dict] = {}


def visible(text: str) -> list[str]:
    """The screen's rows with the blank tail of an unfilled pane dropped.

    iTerm reports a cell nothing was ever written to as NUL, not a space — "Two caveats" came
    back as "Two\x00caveats" and read as one word — so a NUL is a space here.
    """
    return trimmed(text.splitlines())


def trimmed(rows: list[str]) -> list[str]:
    rows = [row.replace("\x00", " ").rstrip() for row in rows]
    while rows and not rows[-1]:
        rows.pop()
    return rows


def _read_pane(pane_id: str) -> dict:
    kept = _read.get(pane_id)
    if kept and time.time() - kept["at"] < FRESH:
        return kept
    _read[pane_id] = _styled(pane_id) or _plain(pane_id)
    return _read[pane_id]


def _styled(pane_id: str) -> dict | None:
    """The same rows with their runs, or None when the API is not to be asked right now."""
    rows = iterm.screen(pane_id)
    if rows is None:
        return None
    # Row by row, not `splitlines`, which would also cut a row at a stray form feed.
    lines = trimmed([row.text for row in rows])
    look = theme.theme(pane_id)
    return {
        "lines": lines,
        "at": time.time(),
        "styled": True,
        "runs": [styled.runs(row, look["ansi"], look["brightBold"]) for row in rows[: len(lines)]],
    }


def _plain(pane_id: str) -> dict:
    out = subprocess.run(
        ["it2", "session", "read", "-s", pane_id],
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
        check=False,
    )
    if out.returncode != 0:
        raise HTTPException(
            status_code=409, detail=f"iTerm would not read that pane: {out.stderr.strip()[:200]}"
        )
    return {"lines": visible(out.stdout), "at": time.time(), "styled": False}


@router.get("/sessions/{session_id}/screen")
async def session_screen(session_id: str) -> dict:
    """`{lines, at, styled, runs?}`: the pane's rows, top to bottom, and when they were read."""
    session = await saying.live_session(session_id)
    if not session.pane:
        raise HTTPException(status_code=409, detail="session has no iTerm pane")
    return await asyncio.to_thread(_read_pane, session.pane.iterm_session_id)
