"""Reading and writing one session's standing orders.

Two routes, and the session has to be live for either: the id is the only handle the phone has and
resolving it is what proves there is still something to give orders to. A dead session is a 404
here the way it is everywhere else.

`limit` rides on both answers rather than being a number the app also knows. The field is capped
and a cap the phone guessed at would be a cap that drifts — the counter under the box has to be
counting against the same number the Mac clamps with, or it says "1,340 of 2,000" while the Mac is
quietly cutting at 1,200.

No token check of its own: `app.py` mounts this with the same dependency every other route carries.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Body

from ..saying import session_or_404
from . import kept

router = APIRouter(tags=["orders"])


@router.get("/sessions/{session_id}/orders")
def read(session_id: str) -> dict:
    """What this session is being reminded of on every message. Empty when it has never been told."""
    session_or_404(session_id)
    return {"text": kept.load(session_id), "limit": kept.LIMIT}


@router.put("/sessions/{session_id}/orders")
def write(session_id: str, text: Annotated[str, Body(embed=True)]) -> dict:
    """Replace them, and answer with what was stored — which is what will actually be carried.

    Clamped rather than refused when it is too long. A person dictating into a box has no way to
    see the cap coming, and losing the paragraph on a 401-style refusal would be worse than
    keeping the first two thousand characters of it and showing them the counter.
    """
    session_or_404(session_id)
    return {"text": kept.save(session_id, text), "limit": kept.LIMIT}
