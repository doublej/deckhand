"""`GET /tray` on the Mac, and `GET /tray/open` on every machine that holds sessions.

What is open is asked of each machine at once and never cached: a slip is a file on the disk of
the machine its session runs on, and that machine is the only one that can say it is still there.
A machine that is asleep contributes nothing, as it does to the listing.
"""

from __future__ import annotations

import asyncio

from fastapi import APIRouter, Query

from .. import artifacts, push, sessions
from ..fleet import proxy, registry
from . import feed, shapes

router = APIRouter(tags=["tray"])
#: The hand's half: only what is open here, because only the Mac keeps a feed.
here_router = APIRouter(tags=["tray"])


def open_here(lines: dict[str, str], paned_only: bool = True) -> list[dict]:
    """Every session on this machine with a slip nobody answered or a line asking for you.

    Each slip carries its shape, so the phone draws the question itself. Reading every waiting
    page is the cost, and it is the same read the Lock Screen's sweep does every five seconds.
    """
    found = []
    for session in sessions.live_sessions(paned_only=paned_only):
        slips = [row | {"ask": shapes.ask(artifacts.page(session, row["id"]))}
                 for row in artifacts.listing(session) if not row["answered"]]
        if slips or lines.get(session.session_id):
            found.append({"session": session.session_id, "name": session.name,
                          "machine": session.machine or registry.here(),
                          "status": session.status, "provider": session.provider,
                          "waiting": lines.get(session.session_id, ""), "slips": slips})
    return found


@router.get("/tray")
async def tray(
    since: int = Query(default=0, ge=0, description="the last update id this phone has seen"),
) -> dict:
    """Everything open on every machine, newest first, and every update after the cursor."""
    found = await asyncio.to_thread(open_here, push.waiting_lines())
    for body in (await proxy.every("GET", "/tray/open")).values():
        rows = body.get("open") if isinstance(body, dict) else None
        found.extend(kept for row in rows or [] if (kept := _sound(row)) is not None)
    found.sort(key=lambda row: max((s.get("modified") or 0.0 for s in row["slips"]), default=0.0),
               reverse=True)
    return {"open": found, "updates": feed.after(since), "newest": feed.newest()}


def _sound(row: object) -> dict | None:
    """A hand's row in the shape the sort and the phone read, or None to leave it out. A hand is
    upgraded on its own schedule, and one odd row must not take the whole tray down with a 500."""
    if not isinstance(row, dict) or not all(isinstance(row.get(k), str) for k in ("session", "name")):
        return None
    slips = row.get("slips") or []
    if not isinstance(slips, list) or not all(
            isinstance(s, dict) and isinstance(s.get("modified") or 0.0, int | float) for s in slips):
        return None
    return row | {"slips": slips}


@here_router.get("/tray/open")
def tray_open() -> dict:
    """A hand's open sessions. No lines: calling for you is a daemon route a hand does not have."""
    return {"open": open_here({}, paned_only=False)}
