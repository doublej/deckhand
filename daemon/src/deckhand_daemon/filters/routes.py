"""What the phone asks about filters: what this Mac has, and what one terminal does with it.

Two halves on purpose. The list of filters is global — it is what this Mac can do, and it changes
when the daemon is updated, not when a person decides something. The chain is per session, because
that is the thing being decided: the same words want crafting in one terminal and swapping in
another. So `/filters` answers what exists, and the session routes answer and set one chain.

The session routes are keyed by **name** underneath, not by the id in the URL — `config` says why.
That is also why a dead session is a 404 here like everywhere else: the id is the only handle the
phone has, and resolving it is what turns it into the name the chain is filed under.

No token check of its own — `app.py` mounts this with the same dependency every other route
carries. A router that knew about the token would have to import the app that includes it, and for
the same reason `filters/__init__.py` must never import this module: it reaches back out to
`saying` for the session lookup, and a package that imported its own routes would close that loop.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Body, HTTPException

from ..saying import session_or_404
from . import config, registry

router = APIRouter(tags=["filters"])


@router.get("/filters")
def list_filters() -> dict:
    """Everything this daemon can do to a prompt. No chain: a chain belongs to a terminal."""
    return {"known": registry.known()}


@router.get("/sessions/{session_id}/filters")
def session_filters(session_id: str) -> dict:
    """What this terminal runs, and what it could run, in the one call a settings screen needs."""
    session = session_or_404(session_id)
    chain = config.load(config.key(session.machine, session.name))
    return {"session": session.name, "known": registry.known(), "steps": chain}


@router.put("/sessions/{session_id}/filters")
def set_session_filters(session_id: str, steps: Annotated[list[dict], Body(embed=True)]) -> dict:
    """Replace this terminal's chain. List order is run order, and a filter may appear twice.

    A name this Mac does not have is refused rather than saved: the runner would step over it,
    and a step that silently does nothing looks exactly like one that silently fails.
    """
    session = session_or_404(session_id)
    named = {str(s.get("filter", "")) for s in steps if isinstance(s, dict)}
    missing = sorted(name for name in named if registry.get(name) is None)
    if missing:
        raise HTTPException(status_code=400, detail=f"no such filter: {', '.join(missing)}")
    saved = config.save(config.key(session.machine, session.name), steps)
    return {"session": session.name, "steps": saved}
