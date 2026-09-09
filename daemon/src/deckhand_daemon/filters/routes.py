"""The two things the phone asks about filters: what there is, and which ones run.

No token check of its own — `app.py` mounts this with the same dependency every other route
carries. A router that knew about the token would have to import the app that includes it.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Body, HTTPException

from . import config, registry

router = APIRouter(tags=["filters"])


@router.get("/filters")
def list_filters() -> dict:
    """Everything this daemon can do to a prompt, and everything it is currently doing."""
    return {"known": registry.known(), "steps": config.load()}


@router.put("/filters")
def set_filters(steps: Annotated[list[dict], Body(embed=True)]) -> dict:
    """Replace the chain. List order is run order, and a filter may appear in it twice.

    A name this Mac does not have is refused rather than saved: the runner would step over it,
    and a step that silently does nothing looks exactly like one that silently fails.
    """
    named = {str(s.get("filter", "")) for s in steps if isinstance(s, dict)}
    missing = sorted(name for name in named if registry.get(name) is None)
    if missing:
        raise HTTPException(status_code=400, detail=f"no such filter: {', '.join(missing)}")
    return {"steps": config.save(steps)}
