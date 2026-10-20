"""A project's header: one wide picture the phone draws faintly behind a session page's title.

It lives at `<cwd>/.deckhand/header.{jpg,png,webp}`, beside the slips and ignored by git the same
way. The agent working in the project makes it from a picture the project already has — a logo,
a hero, a screenshot, cover art — and never asks the person for one (the MCP instructions say so).
No file is the normal case and costs nothing: the page simply has no picture behind its title.
"""

from __future__ import annotations

import asyncio
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from ..sessions import Session, live_sessions

router = APIRouter()

NAMES = ("header.jpg", "header.jpeg", "header.png", "header.webp")
# A banner a few hundred points tall needs no more than this; a bigger file is a mistake.
MAX_BYTES = 2 * 1024 * 1024


def found(session: Session) -> Path | None:
    """The header file in this session's folder, or None where there is none worth serving."""
    folder = Path(session.cwd) / ".deckhand"
    for name in NAMES:
        path = folder / name
        if path.is_file() and path.stat().st_size <= MAX_BYTES:
            return path
    return None


@router.get("/sessions/{session_id}/header")
async def header(session_id: str) -> FileResponse:
    """The picture itself. 404 is "this project has none", which the phone draws as nothing."""
    # `live_sessions` rather than `saying.live_session`: this package is imported by `saying`'s
    # own imports, and the header of a session on another Mac is not on this one's disk anyway.
    live = await asyncio.to_thread(live_sessions)
    session = next((s for s in live if s.session_id == session_id), None)
    path = found(session) if session else None
    if path is None:
        raise HTTPException(status_code=404, detail="no header in this project")
    return FileResponse(path)
