"""What the phone asks about projects: what there is, and one that should have a session in it.

The listing is the whole permission, exactly as it is for `/sessions/{id}/file`. A folder this
Mac's project list does not name is refused, so this stays a way into the work that is already
catalogued and never becomes a way to run Claude Code anywhere on the disk. Refused with a 400
rather than a 404: the app reads a 404 as "that session is gone", a sentence about the wrong
thing entirely.

No token check of its own — `app.py` mounts this with the same dependency every other route
carries, and for the same reason `projects/__init__.py` must not import this module.
"""

from __future__ import annotations

import asyncio
from pathlib import Path

from fastapi import APIRouter, Body, HTTPException

from ..sessions import live_sessions
from . import sources, starting

router = APIRouter(tags=["projects"])


@router.get("/projects")
def list_projects() -> dict:
    """Every project on this Mac, most recently touched first, and where the list came from.

    The live count travels with each row because it is the one thing the phone cannot work out
    for itself without holding both lists at once — and "this folder already has two sessions in
    it" is the answer to the only question worth asking before starting a third. Whether the
    folder is trusted rides along for the same reason: it decides whether the row can be started
    at all, and finding that out by tapping it is finding out too late.
    """
    found, source = sources.catalog()
    running: dict[str, int] = {}
    for session in live_sessions():
        running[_resolved(session.cwd)] = running.get(_resolved(session.cwd), 0) + 1
    allowed = starting.trusted()
    for project in found:
        project.live = running.get(_resolved(project.path), 0)
        project.trusted = project.path in allowed
    return {"projects": [p.to_json() for p in found], "source": source}


@router.post("/projects/session")
async def start_project_session(path: str = Body(embed=True)) -> dict:
    """Open a terminal in that folder and start Claude Code in it.

    Answers with the session itself rather than an acknowledgement, because the phone's next move
    is to open it: waiting for the record here is what turns "a tab is opening somewhere" into a
    conversation you are already in.
    """
    known = {p.path for p in sources.catalog()[0]}
    if path not in known:
        raise HTTPException(status_code=400, detail="that folder is not in this Mac's project list")
    session, error = await asyncio.to_thread(starting.start, path)
    if session is None:
        raise HTTPException(status_code=409, detail=error or "could not start a session there")
    sources.forget()
    return {"session": session.to_json()}


def _resolved(path: str) -> str:
    """The same folder spelled the same way from both sides. The dev tree carries a symlink, and
    a session's own `cwd` is whatever the shell was given rather than what the catalogue holds."""
    try:
        return str(Path(path).resolve())
    except OSError:
        return path
