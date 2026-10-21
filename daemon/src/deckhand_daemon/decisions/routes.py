"""The answer route, for every slip: a decision's signed answer, and every other page's as before.

One route rather than two because the phone already posts every answer here, and the page — not
the caller — decides which rules apply. A page that declares itself a decision takes only a
proof; any other page takes a `value` exactly as it always has, written `verified: false`.
"""

from __future__ import annotations

import asyncio
from typing import Annotated, Any

from fastapi import APIRouter, Body, Header, HTTPException, Query

from .. import artifacts, deliver, plugin
from ..log import log
from ..saying import live_session
from . import answering, delivery, pages

router = APIRouter(tags=["artifacts"])


@router.post("/sessions/{session_id}/artifacts/{artifact_id}/answer")
async def answer_artifact(
    session_id: str,
    artifact_id: str,
    value: Annotated[Any, Body(embed=True)] = None,
    proof: Annotated[dict | None, Body(embed=True)] = None,
    route: str | None = Query(default=None, description="auto, keyboard or socket; not a decision"),
    x_deckhand_token: str = Header(default=""),
) -> dict:
    """Take the answer, write it down, then tell the session — in that order, and it matters.

    A delivery that fails must not lose an answer. The file is the record and the message is only
    the wake-up, so a session whose pane has gone still finds the answer on disk, and the phone
    is told that the delivery failed rather than that the answer did.

    **A decision** takes `proof` — `{payload, signature}`, signed by this phone's filed key — and
    nothing else: `value` is the payload's, the route is the keyboard, and every refusal is
    `{"detail": {"code", "error"}}` (`answering.taken` lists them in order).

    **Any other page** takes `value`, by the route the person chose for speaking. `value` is any
    JSON value but a required one, and `null` is therefore not sendable: an empty body is not an
    answer. `false`, `0`, `""` and `[]` all arrive intact.
    """
    session = await live_session(session_id)
    found = answering.located(session, session_id, artifact_id)
    if (found and pages.declared(found[0])) or (found is None and proof is not None):
        return await _decided(session, session_id, artifact_id, proof, x_deckhand_token)
    if value is None:
        raise HTTPException(status_code=422, detail="an answer needs a value")
    written = artifacts.answer(session, artifact_id, value)
    if written is None:
        raise HTTPException(status_code=404, detail="no artifact with that id in this project")
    chosen = route or plugin.route()
    taken, error = await asyncio.to_thread(deliver.deliver, session, artifacts.message(written),
                                           chosen)
    log.info("the answer to %s in %s: %s", artifact_id, session.name, error or f"{taken} took it")
    return {"answer": written, "delivered": taken is not None, "delivered_by": taken,
            "delivery_error": error}


async def _decided(session, session_id: str, artifact_id: str, proof: object, token: str) -> dict:
    """A decision: checked and written by `answering`, then typed by `delivery`."""
    record, page, answer, metas = await asyncio.to_thread(
        answering.taken, proof, token, session, session_id, artifact_id)
    question = artifacts.titled(page, artifact_id)
    taken, error = await asyncio.to_thread(
        delivery.handed, session_id, artifact_id, question, metas, record, answer)
    log.info("decision %s in %s: %s", artifact_id, session.name, error or f"{taken} took it")
    shown = {key: kept for key, kept in record.items() if key != "proof"}
    return {"answer": shown | {"delivered": taken is not None, "file": str(answer)},
            "delivered": taken is not None, "delivered_by": taken, "delivery_error": error}
