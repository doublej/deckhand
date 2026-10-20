"""`GET /sessions/{id}/addresses` — every address the session named, checked, with atlas's word.

Answers inside about four seconds whatever is in the list: checks still going when the budget
runs out come back as `checking` and finish in the background, as does atlas's registry the
first time it is read. `complete` is false while either is still out, and the phone polls until
it is true.

A bare name that does not resolve is dropped here rather than shown as dead: written without a
scheme, `self.local` or `k.local` is code that happened to end in a domain's ending, and only
the lookup can tell the two apart.
"""

from __future__ import annotations

import asyncio

from fastapi import APIRouter

from .. import saying
from . import atlas, checking, finding

router = APIRouter(tags=["addresses"])


@router.get("/sessions/{session_id}/addresses")
async def session_addresses(session_id: str) -> dict:
    """Every URL, IP and domain the session and its subagents wrote, checked, with atlas's match."""
    await asyncio.to_thread(saying.session_or_404, session_id)
    found = await asyncio.to_thread(finding.mentioned, session_id)
    checked = await checking.check_all({row.origin: next(iter(row.paths), "") for row in found})
    known = atlas.registry()
    rows = []
    for row in found:
        check = checked.get(row.origin)
        if check and row.kind == "domain" and check.reach == "none":
            continue
        registered = atlas.match(known or [], row.origin)
        rows.append(row.to_json()
                    | (check.to_json() if check else {"state": "checking"})
                    | {"atlas": registered.to_json() if registered else None})
    complete = known is not None and all(row["state"] != "checking" for row in rows)
    return {"addresses": rows, "complete": complete}
