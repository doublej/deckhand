"""The one route: who has been messaging whom, and how recently.

Separate from `edges.py` for the reason `settings/` and `projects/` split theirs: this pulls in
FastAPI, and `app.py` is the only thing that should be deciding when that happens.
"""

from __future__ import annotations

import asyncio

from fastapi import APIRouter, Query

from ..sessions import live_sessions
from .edges import MAX_WINDOW, MIN_WINDOW, read_links

router = APIRouter(tags=["links"])


@router.get("/sessions/links")
async def session_links(
    within: float = Query(
        default=300.0,
        ge=MIN_WINDOW,
        le=MAX_WINDOW,
        description="how many seconds back to look for messages between sessions",
    ),
) -> dict:
    """Which sessions have messaged which, lately. Both ends are always on the listing.

    The window is the phone's, not the Mac's: the same number decides how far back the scan
    reads and how far back the screen draws, so the two cannot drift apart.

    `/sessions/links` would only be ambiguous if some route were `/sessions/{id}` on its own.
    None is, so this cannot be swallowed as a session id.
    """
    live = await asyncio.to_thread(live_sessions)
    found = await asyncio.to_thread(read_links, live, within)
    return {"links": [link.to_json() for link in found], "within": within}
