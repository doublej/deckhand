"""What the phone asks about projects: what there is, and one that should have a session in it.

The listing is the whole permission, exactly as it is for `/sessions/{id}/file`. A folder this
Mac's project list does not name is refused, so this stays a way into the work that is already
catalogued and never becomes a way to run Claude Code anywhere on the disk. Refused with a 400
rather than a 404: the app reads a 404 as "that session is gone", a sentence about the wrong
thing entirely.

No token check of its own — `app.py` mounts this with the same dependency every other route
carries, and for the same reason `projects/__init__.py` must not import this module.
"""

from __future__ import annotations

import asyncio
from functools import lru_cache
from pathlib import Path

from fastapi import APIRouter, Body, HTTPException

from ..fleet import merge, proxy, registry
from ..sessions import live_sessions
from ..settings import wants
from . import sources, starting

router = APIRouter(tags=["projects"])


@router.get("/projects")
async def list_projects() -> dict:
    """Every project on every machine, most recently touched first, and where the list came from.

    atlas already catalogued all three roots, so the machines cost this route nothing to *list* —
    the `host` on each row is the same id `/machines` and `Session.machine` use. What they cost is
    two facts atlas does not hold, and they are answered in two different ways on purpose.

    **Live counts come off the last session listing**, which the phone refreshes every few
    seconds anyway, rather than from a second fan-out for a number this Mac already has.

    **Trusted is asked of each machine**, because it is the one thing only that machine knows: a
    trust dialog answered at its own keyboard. A machine that is asleep contributes no trusted
    rows, so its folders read as "cannot start here yet" — the right answer, arrived at honestly.
    """
    # In a thread, because both read: the catalogue asks atlas over HTTP with a three-second
    # timeout that this Mac's atlas has been measured hitting, and the counts walk the sessions.
    # On the event loop that is the whole daemon stopped for as long as the picker takes.
    found, source = await asyncio.to_thread(sources.catalog)
    here = registry.here()
    counts = await asyncio.to_thread(_live_counts, here)
    allowed = await _trusted(here)
    for project in found:
        machine = project.machine or here
        # Resolved on this Mac only: the dev tree here carries a symlink, and resolving a path
        # that names another machine's disk against this one's would answer about the wrong file.
        folder = _resolved(project.path) if machine == here else project.path
        project.live = counts.get((machine, folder), 0)
        project.trusted = project.path in allowed.get(machine, frozenset())
    return {"projects": [p.to_json() for p in found], "source": source}


def _live_counts(here: str) -> dict[tuple[str, str], int]:
    """How many live sessions each folder has, per machine. Keyed by both because two machines
    genuinely can hold the same path — `/home/jurrejan/development/x` exists on Ubuntu and could
    exist here tomorrow, and a count that merged them would be a count about neither."""
    counts: dict[tuple[str, str], int] = {}
    for session in live_sessions():
        key = (here, _resolved(session.cwd))
        counts[key] = counts.get(key, 0) + 1
    for row in merge.remote_rows():
        key = (str(row.get("machine") or ""), str(row.get("cwd") or ""))
        counts[key] = counts.get(key, 0) + 1
    return counts


async def _trusted(here: str) -> dict[str, frozenset[str]]:
    """Every machine's trusted folders, this one's read off disk and the rest asked for at once."""
    answers = await proxy.every("GET", "/projects/trusted")
    found = {here: frozenset(starting.trusted())}
    for machine_id, body in answers.items():
        found[machine_id] = frozenset(body.get("trusted", []))
    return found


@router.post("/projects/session")
async def start_project_session(path: str = Body(embed=True)) -> dict:
    """Open a terminal in that folder and start Claude Code in it, wherever that folder is.

    Answers with the session itself rather than an acknowledgement, because the phone's next move
    is to open it: waiting for the record here is what turns "a tab is opening somewhere" into a
    conversation you are already in.

    **Which machine is derived, never sent.** The catalogue already says where every folder is, so
    taking a machine off the request would be letting the caller name a target this Mac never
    offered — and the listing being the whole permission is the rule this route was built on.
    """
    project = next((p for p in sources.catalog()[0] if p.path == path), None)
    if project is None:
        raise HTTPException(status_code=400, detail="that folder is not in the project list")
    here = registry.here()
    machine = project.machine or here
    if machine != here:
        return await _start_over_there(machine, path)
    session, error = await asyncio.to_thread(starting.start, path)
    if session is None:
        raise HTTPException(status_code=409, detail=error or "could not start a session there")
    sources.forget()
    return {"session": session.to_json()}


async def _start_over_there(machine: str, path: str) -> dict:
    """Ask that machine's hand to start it, and hand back the session it made.

    The model goes across rather than being looked up over there: what the person set for this
    folder is on this Mac, and a hand keeps no settings of its own that could disagree.

    A hand answers 200 with an `error` for a refusal — "not trusted there" is a sentence, not a
    status code — so None from `proxy.call` means only one thing, and it is the one thing a
    status code would have been ambiguous about: that machine is not reachable at all.
    """
    answer = await proxy.call(
        machine, "POST", "/projects/session",
        json={"path": path, "model": wants.resolved(path).session_model},
    )
    if answer is None:
        raise HTTPException(status_code=409, detail=f"{machine} is not reachable right now")
    if error := answer.get("error"):
        raise HTTPException(status_code=409, detail=error)
    sources.forget()
    return {"session": answer.get("session")}


# ponytail: cached for the life of the daemon, so a folder that gains or loses a symlink after
# this answered for it keeps the old spelling until a restart. Give it a TTL if that ever matters.
@lru_cache(maxsize=2048)
def _resolved(path: str) -> str:
    """The same folder spelled the same way from both sides. The dev tree carries a symlink, and
    a session's own `cwd` is whatever the shell was given rather than what the catalogue holds.

    Remembered, because `/projects` resolves every row: `resolve` walks each path component
    looking for a link, and over the 504 folders atlas catalogues here that measured 1.7 s —
    paid on the event loop, so it was every other request in the daemon waiting on the picker.
    A folder does not move while the daemon runs.
    """
    try:
        return str(Path(path).resolve())
    except OSError:
        return path
