"""Reading and writing what this Mac has been set to do.

One document, fetched whole and written whole — the same shape `/filters` takes, and for the
same reason: it is small, a person edits several things at once on one screen, and a partial
write would need a merge rule that nothing else here has.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Body

from .. import files, saying
from . import aliases, folders, hints, wants

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


@router.get("/hints/folder")
def read_folder_hints(path: str) -> dict:
    """Every list a session in `path` hears, outermost first — "" is the global one."""
    return {"path": path, "layers": hints.layers(path)}


@router.put("/hints/folder")
def write_folder_hints(path: Annotated[str, Body()],
                       words: Annotated[list, Body(alias="hints")]) -> dict:
    """Replace one layer's own words, and answer with what was stored."""
    return {"path": path, "hints": hints.save_folder(path, words)}


@router.get("/settings/project")
def for_project(path: str) -> dict:
    """What actually applies in one folder, already resolved.

    Here rather than worked out on the phone because it is the same question the daemon itself
    asks before every card and every idle check, and two answers to one question is how they
    come apart.
    """
    return {"path": path, "wants": wants.resolved(path).to_json()}


@router.get("/sessions/{session_id}/folders")
def read_folders(session_id: str) -> dict:
    """The folders connected to this session's project, and the ones worth suggesting."""
    return _folders(saying.session_or_404(session_id))


@router.put("/sessions/{session_id}/folders")
def write_folders(session_id: str,
                  folders_sent: Annotated[list, Body(embed=True, alias="folders")]) -> dict:
    """Replace the project's folders whole — see `settings/folders.py`. Answers with what was
    kept: a relative path, the disk's root and the home folder itself are dropped."""
    session = saying.session_or_404(session_id)
    folders.save(session.cwd, folders_sent)
    return _folders(session)


def _folders(session) -> dict:
    return {
        "path": session.cwd,
        "folders": folders.load(session.cwd),
        "suggested": files.suggested(session.session_id, session.cwd, session.provider),
    }
