"""One HTML page a session wrote, read on the phone, and the answer on its way back.

The store is the project's own folder — `<cwd>/.deckhand/artifacts` — and that is the design
rather than a detail of it. Kept per session under Deckhand's own state, the way everything else
here is kept, one project's pages would scatter across every session that ever worked on it and
the second session would never find the first one's work. In the project, an agent writes a page
with `Write`, lists them with `ls`, reads an old one with `Read` and duplicates one with `cp` —
no new tool, no token, no discovery step, because an agent already knows its own cwd.
`docs/artifacts.md` is the contract this builds.

Two things keep a folder inside someone's project from becoming a file server on their Mac. An
id is one strict slug and never a path, so `../../../etc/passwd` is not an id at all. And every
file is resolved and its parent compared against this session's own artifacts folder, which is
what catches a page that is really a symlink pointing elsewhere — the same check
`saying._kept_images` makes before a message may name a picture. A read also requires the folder
to be there already and nothing ever looks upward for one, so a session started in `/` or in
`$HOME` lists nothing and serves nothing.

Nothing here raises over a bad file. A page half-written by an agent that was interrupted, or one
that is not text at all, must not be able to empty the phone's listing: it lists under its id and
the rest of the folder is unaffected, the way every other store in this daemon degrades to empty.
"""

from __future__ import annotations

import asyncio
import html
import json
import re
import time
from pathlib import Path
from typing import Annotated, Any

from fastapi import APIRouter, Body, HTTPException, Query
from fastapi.responses import HTMLResponse

from . import deliver, plugin, sessions
from .log import log
from .saying import live_session

router = APIRouter(tags=["artifacts"])

# An id is a slug the agent picked and a person can read: `release-check`, `palette-pick`. One
# segment and nothing else — no dot, so `..` cannot be spelled, and no separator, so no path can.
ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}")
# The title comes out of the head of the page rather than all of it: a `<title>` further in than
# this is not in the head, and one page carrying a `data:` picture runs to megabytes.
PEEK = 8192
TITLE = re.compile(rb"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)
# A phone-shaped page of hand-written HTML. Past this it is not an artifact, and reading it into
# memory to hand to the phone is how a daemon dies.
MAX_PAGE_BYTES = 4 * 1024 * 1024
# How much of the answer travels in the message. The file beside the page holds all of it.
BRIEF = 240


def folder(session: sessions.Session) -> Path:
    """This project's artifacts folder, made if it is not there yet.

    `.deckhand/.gitignore` holding `*` goes in beside it, so the folder ignores itself and no
    repository gains an entry because someone answered a question on their phone. It is topped
    up rather than written once: an agent creating the folder with `Write` leaves no `.gitignore`
    behind, and the daemon is the only thing that can put one there. A folder that will not take
    the write is only a folder git can see — it is not a reason for the phone to see nothing.
    """
    spot = _where(session)
    spot.mkdir(parents=True, exist_ok=True)
    ignore = spot.parent / ".gitignore"
    if not ignore.exists():
        try:
            ignore.write_text("*\n")
        except OSError as error:
            log.warning("could not make %s ignore itself: %s", spot.parent, error)
    return spot


def kept(session: sessions.Session) -> Path | None:
    """The same folder, but only when it is already there. None is what a read gets otherwise.

    This is the difference between a feature and a file server: a session working in `/` or in
    `$HOME` has no artifacts folder, so it has no artifacts, and nothing walks upward to find a
    folder belonging to some enclosing directory.
    """
    return folder(session) if _where(session).is_dir() else None


def listing(session: sessions.Session) -> list[dict]:
    """Every page in this project's folder, newest first, with what the phone needs to show it."""
    spot = kept(session)
    if spot is None:
        return []
    rows = (_row(session, found.stem) for found in spot.glob("*.html"))
    return sorted((row for row in rows if row), key=lambda row: row["modified"], reverse=True)


def counted(session: sessions.Session) -> dict:
    """The two numbers the session listing carries: pages still waiting, and pages answered.

    Both, because the phone's overview says them the way it says how much of what you asked for
    is done — one number alone turns "two of five answered" into "three", which is a worse thing
    to read at a glance than either half. Spelled with the keys the row uses, so the listing can
    merge this fragment the way it merges `context`.

    On the listing rather than behind a request of its own, because the overview draws every
    session at once: one call per row to find out whether a row has something to say is the shape
    that makes a feature feel slow.

    Counted off `listing` rather than off the folder, so the numbers a row promises are exactly
    what the page tab will show. A file whose name is not a slug is not an artifact of this
    session's, and counting one here would promise a page that does not list.
    """
    rows = listing(session)
    answered = sum(1 for row in rows if row["answered"])
    return {"artifacts_waiting": len(rows) - answered, "artifacts_answered": answered}


def page(session: sessions.Session, artifact_id: str) -> str | None:
    """The page itself, as the phone will render it. None when there is no such artifact."""
    found = _file(session, artifact_id, ".html")
    if found is None:
        return None
    try:
        size = found.stat().st_size
        if size > MAX_PAGE_BYTES:
            log.warning("the artifact %s is too big to serve (%d bytes)", artifact_id, size)
            return None
        return found.read_text(errors="replace")
    except OSError as error:
        log.warning("could not read the artifact %s: %s", artifact_id, error)
        return None


def answer(session: sessions.Session, artifact_id: str, value: Any) -> dict | None:
    """Write `<id>.answer.json` beside the page and hand back what was written.

    The page has to exist: an answer to a question nobody asked is not an answer, and writing one
    would let the phone create files in a project by naming ids. What comes back carries `file`
    as well, because the message that wakes the session has to say where the answer is; the file
    itself holds the three keys `docs/artifacts.md` promises and does not need to say where it is.
    """
    found = _file(session, artifact_id, ".html")
    answer_file = _file(session, artifact_id, ".answer.json")
    if found is None or answer_file is None or not found.is_file():
        return None
    written = {"id": artifact_id, "answeredAt": time.time(), "value": value}
    answer_file.write_text(json.dumps(written, indent=2))
    log.info("%s answered the artifact %s", session.name, artifact_id)
    return written | {"file": str(answer_file)}


def _where(session: sessions.Session) -> Path:
    """Where this session's artifacts would be. A path, not a promise: nothing is created here."""
    return Path(session.cwd) / ".deckhand" / "artifacts"


def _file(session: sessions.Session, artifact_id: str, suffix: str) -> Path | None:
    """One file of this artifact's, inside this session's own folder, or None.

    The only place an id from the phone turns into a path, so it is the only place the check has
    to be made. `fullmatch` refuses anything that is not one plain slug, and resolving before
    comparing parents is what catches the rest: a page that is a symlink out of the folder
    resolves somewhere whose parent is not this folder. What the project itself links its own
    artifacts folder to is the project's business — the id cannot reach outside either way.
    """
    spot = kept(session)
    if spot is None or not ID.fullmatch(artifact_id):
        return None
    settled = (spot / f"{artifact_id}{suffix}").resolve()
    if settled.parent != spot.resolve():
        log.warning("refused an artifact outside %s's own folder: %r", session.name, artifact_id)
        return None
    return settled


def _row(session: sessions.Session, artifact_id: str) -> dict | None:
    """One page as the phone lists it. None for a file that is not an artifact of this session's.

    `answered` is the whole state there is: a page with no answer beside it is open, and one with
    an answer has been answered and can be asked again by deleting the file.
    """
    found = _file(session, artifact_id, ".html")
    if found is None:
        return None
    try:
        modified = found.stat().st_mtime
    except OSError:
        return None
    beside = _file(session, artifact_id, ".answer.json")
    return {
        "id": artifact_id,
        "title": _title(found, artifact_id),
        "modified": modified,
        "answered": beside is not None and beside.is_file(),
    }


def _title(path: Path, artifact_id: str) -> str:
    """The page's own `<title>`, which is the artifact's name. Its id when it has none.

    A page being written as this is read, or one that is not text, falls back to the id rather
    than taking the listing down with it.
    """
    try:
        with path.open("rb") as page_file:
            head = page_file.read(PEEK)
    except OSError:
        return artifact_id
    found = TITLE.search(head)
    if found is None:
        return artifact_id
    said = html.unescape(found.group(1).decode("utf-8", "replace"))
    return " ".join(said.split()) or artifact_id


def _brief(value: Any) -> str:
    """The answer in a line, for the message. Cut rather than summarised — the file holds it all."""
    said = json.dumps(value, ensure_ascii=False)
    return said if len(said) <= BRIEF else said[:BRIEF] + "…"


def _message(written: dict) -> str:
    """What the session is told. The person's own answer, so it reads as the person saying it.

    It names the page, carries the answer when it is short, and says where the whole of it is: a
    session that was waiting reads the file, and one that had stopped is woken by the message.
    """
    return (
        f"Answered the artifact {written['id']} on my phone: {_brief(written['value'])}. "
        f"The whole answer is in {written['file']}."
    )


@router.get("/sessions/{session_id}/artifacts")
async def list_artifacts(session_id: str) -> dict:
    """What this project is currently asking, and which of it has been answered."""
    session = await live_session(session_id)
    return {"artifacts": listing(session)}


@router.get("/sessions/{session_id}/artifacts/{artifact_id}", response_class=HTMLResponse)
async def artifact_page(session_id: str, artifact_id: str) -> HTMLResponse:
    """The page, as HTML. The app injects the tokens and the policy around it; this only serves."""
    session = await live_session(session_id)
    found = page(session, artifact_id)
    if found is None:
        raise HTTPException(status_code=404, detail="no artifact with that id in this project")
    return HTMLResponse(found)


@router.post("/sessions/{session_id}/artifacts/{artifact_id}/answer")
async def answer_artifact(
    session_id: str,
    artifact_id: str,
    value: Annotated[Any, Body(embed=True)],
    route: str | None = Query(default=None, description="auto, keyboard or socket"),
) -> dict:
    """Take the answer, write it down, then tell the session — in that order, and it matters.

    A delivery that fails must not lose an answer. The file is the record and the message is only
    the wake-up, so a session whose pane has gone still finds the answer on disk, and the phone
    is told that the delivery failed rather than that the answer did.

    It travels by the route the person chose for speaking, because it is the person speaking.
    `nudge.py` pins the socket for the opposite reason: what it sends is the daemon's own question
    and has to arrive labelled as another agent's.

    `value` is any JSON value but a required one, and `null` is therefore not sendable: FastAPI
    cannot tell a field that is missing from one that is explicitly null, so accepting null would
    make an empty body an answer. `false`, `0`, `""` and `[]` all arrive intact, and an answer
    carrying nothing at all is what the absence of the file already says.
    """
    session = await live_session(session_id)
    written = answer(session, artifact_id, value)
    if written is None:
        raise HTTPException(status_code=404, detail="no artifact with that id in this project")
    chosen = route or plugin.route()
    taken, error = await asyncio.to_thread(deliver.deliver, session, _message(written), chosen)
    log.info("the answer to %s in %s: %s", artifact_id, session.name,
             error or f"{taken} took it")
    return {
        "answer": written,
        "delivered": taken is not None,
        "delivered_by": taken,
        "delivery_error": error,
    }
