"""`GET /sessions/{id}/addresses` — every address the session named, checked, ranked, with atlas's word.

Answers inside about four seconds whatever is in the list: checks still going when the budget
runs out come back as `checking` and finish in the background, as does atlas's registry the
first time it is read. `complete` is false while either is still out, and the phone polls until
it is true. What matters most comes first, and `ranking.py` says what that means.
"""

from __future__ import annotations

import asyncio

from fastapi import APIRouter

from .. import saying
from . import atlas, checking, finding, ranking

router = APIRouter(tags=["addresses"])


@router.get("/sessions/{session_id}/addresses")
async def session_addresses(session_id: str) -> dict:
    """Every URL, IP and domain the session and its subagents wrote: checked, ranked, matched to atlas."""
    session = await asyncio.to_thread(saying.session_or_404, session_id)
    found = await asyncio.to_thread(finding.mentioned, session_id)
    checked = await checking.check_all({row.origin: next(iter(row.paths), "") for row in found})
    known = atlas.registry()
    registered = known or []
    rows = ranking.rank(found, checked, registered, ranking.project_of(session.cwd, registered),
                        await asyncio.to_thread(finding.active, session_id))
    complete = known is not None and all(row["state"] != "checking" for row in rows)
    return {"addresses": rows, "complete": complete}
