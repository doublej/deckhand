"""Reading and writing what this Mac has been set to do.

One document, fetched whole and written whole — the same shape `/filters` takes, and for the
same reason: it is small, a person edits several things at once on one screen, and a partial
write would need a merge rule that nothing else here has.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Body

from . import wants

router = APIRouter(tags=["settings"])


@router.get("/settings")
def read() -> dict:
    return wants.document()


@router.put("/settings")
def write(sent: Annotated[dict, Body()]) -> dict:
    """What was stored, which is not always what was sent — see `wants.save`."""
    return wants.save(sent)


@router.get("/settings/project")
def for_project(path: str) -> dict:
    """What actually applies in one folder, already resolved.

    Here rather than worked out on the phone because it is the same question the daemon itself
    asks before every card and every idle check, and two answers to one question is how they
    come apart.
    """
    return {"path": path, "wants": wants.resolved(path).to_json()}
