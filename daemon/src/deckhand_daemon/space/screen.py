"""A session's pane as it stands, for the plane that shows it as a terminal.

The transcript is what was said; the pane is what is on the screen — the prompt box, the status
line, and the permission question a session is stopped at, none of which a transcript holds. The
headset's terminal plane (deckhand-web's `/p/terminal`) polls this once a second.

`it2 session read` is plain text and costs ~0.13 s, so one read per pane is shared across every
poll inside `FRESH`. A session with no pane — a Codex thread, or iTerm not answering — is a 409,
the same answer `/focus` gives, and the plane falls back to the transcript.
"""

from __future__ import annotations

import asyncio
import subprocess
import time

from fastapi import APIRouter, HTTPException

from .. import saying

FRESH = 0.5
TIMEOUT = 3.0

router = APIRouter(tags=["space"])
_read: dict[str, tuple[float, list[str]]] = {}


def visible(text: str) -> list[str]:
    """The screen's rows with the blank tail of an unfilled pane dropped."""
    rows = [row.rstrip() for row in text.splitlines()]
    while rows and not rows[-1]:
        rows.pop()
    return rows


def _read_pane(pane_id: str) -> tuple[float, list[str]]:
    kept = _read.get(pane_id)
    if kept and time.time() - kept[0] < FRESH:
        return kept
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
    _read[pane_id] = (time.time(), visible(out.stdout))
    return _read[pane_id]


@router.get("/sessions/{session_id}/screen")
async def session_screen(session_id: str) -> dict:
    """`{lines, at}`: the pane's rows, top to bottom, and when they were read."""
    session = await saying.live_session(session_id)
    if not session.pane:
        raise HTTPException(status_code=409, detail="session has no iTerm pane")
    at, lines = await asyncio.to_thread(_read_pane, session.pane.iterm_session_id)
    return {"lines": lines, "at": at}
