"""Reading and writing what this Mac has been set to do.

One document, fetched whole and written whole — the same shape `/filters` takes, and for the
same reason: it is small, a person edits several things at once on one screen, and a partial
write would need a merge rule that nothing else here has.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Body

from . import aliases, hints, wants

router = APIRouter(tags=["settings"])


@router.get("/settings")
def read() -> dict:
    """What this Mac has been set to do, globally and per folder."""
    return wants.document()


@router.put("/settings")
def write(sent: Annotated[dict, Body()]) -> dict:
    """What was stored, which is not always what was sent — see `wants.save`."""
    return wants.save(sent)


@router.get("/aliases")
def read_aliases() -> dict:
    """Every word this Mac swaps on the way out of utt, as rows of two: heard, then meant."""
    return {"aliases": aliases.load()}


@router.put("/aliases")
def write_aliases(aliases_sent: Annotated[list, Body(embed=True, alias="aliases")]) -> dict:
    """Replace the list whole, the way `/settings` and `/filters` are written.

    Answers with what was stored rather than what was sent: a row with nothing on its left is
    dropped, a word aliased twice keeps only the later answer, and a row that is not two elements
    goes with them — a hand-rolled `{"heard":…,"meant":…}` is discarded here with a 200 back. A
    screen that followed its own copy would then be showing a list this Mac is not running.
    """
    return {"aliases": aliases.save(aliases_sent)}


@router.get("/hints")
def read_hints() -> dict:
    """Every word utt is told to listen for in every clip — see `settings/hints.py`."""
    return {"hints": hints.load()}


@router.put("/hints")
def write_hints(hints_sent: Annotated[list, Body(embed=True, alias="hints")]) -> dict:
    """Replace the list whole, and answer with what was stored: blanks and repeats are dropped."""
    return {"hints": hints.save(hints_sent)}


@router.get("/settings/project")
def for_project(path: str) -> dict:
    """What actually applies in one folder, already resolved.

    Here rather than worked out on the phone because it is the same question the daemon itself
    asks before every card and every idle check, and two answers to one question is how they
    come apart.
    """
    return {"path": path, "wants": wants.resolved(path).to_json()}
