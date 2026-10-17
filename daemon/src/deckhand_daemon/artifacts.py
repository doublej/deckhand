"""One HTML page a session wrote, read on the phone, and the answer on its way back.

The store is inside the project — `<cwd>/.deckhand/artifacts` — and that is the design rather
than a detail of it. Kept under Deckhand's own state, the way everything else here is kept, an
agent could not reach its own pages at all. In the project it writes one with `Write`, lists
them with `ls`, reads an old one with `Read` and duplicates one with `cp` — no new tool, no
token, no discovery step, because an agent already knows its own cwd. `docs/artifacts.md` is the
contract this builds.

**Inside that folder there are two scopes, and the session's own is the default.** A slip a
session writes lives under `artifacts/<session id>/`; one written flat in `artifacts/` belongs to
the folder and every session working in it sees it. Flat was the only scope once, on the argument
that pages are about the project and outlive the session that wrote one — true of some of them,
and making the rest wrong. Three sessions open in one repo listed the same slips three times, and
answering one delivered into whichever session the phone had open rather than the one that asked,
because the route in is `/sessions/{id}/artifacts/{aid}/answer`. Scoping the default to the
session is what sends an answer back where the question came from. What the old scope was for
survives: the store is still in the project, so `ls ..` from a session's folder finds a sibling's
work and a page meant for the folder is still written flat. Only the phone's listing narrows —
to this session's own, plus the folder's.

Three things keep a folder inside someone's project from becoming a file server on their Mac. An
id is one strict slug and never a path, so `../../../etc/passwd` is not an id at all. A session
id is now a path component too, so it is held to exactly that same rule — it arrives over HTTP
and is no more trustworthy than an id is. And every file is resolved and its parent compared
against the folder it was looked up in, which is what catches a page that is really a symlink
pointing elsewhere — the same check `saying._kept_images` makes before a message may name a
picture. A read also requires the folder to be there already and nothing ever looks upward for
one, so a session started in `/` or in `$HOME` lists nothing and serves nothing.

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


def project(session: sessions.Session) -> Path:
    """Where a slip that belongs to the folder lives, and the root every scope hangs under."""
    return Path(session.cwd) / ".deckhand" / "artifacts"


def own(session: sessions.Session) -> Path | None:
    """Where this session's own slips live: a folder under that one, named by its session id.

    None when that id could not be a folder name. It reaches here off a record on disk by way of
    a path segment in a URL, so it is held to exactly the rule an artifact id is held to — one
    segment, no dot and no separator, so neither `..` nor a path can be spelled. A session whose
    id fails it has no folder of its own and sees only the folder's, which is what every session
    saw before this existed; it never falls back to writing somewhere it was not asked to.
    """
    return project(session) / session.session_id if ID.fullmatch(session.session_id) else None


def folder(session: sessions.Session) -> Path:
    """This session's own artifacts folder, made if it is not there yet.

    `.deckhand/.gitignore` holding `*` goes in, so the folder ignores itself and no repository
    gains an entry because someone answered a question on their phone. It is topped up rather
    than written once: an agent creating the folder with `Write` leaves no `.gitignore` behind,
    and the daemon is the only thing that can put one there. A folder that will not take the
    write is only a folder git can see — it is not a reason for the phone to see nothing.
    """
    spot = own(session) or project(session)
    spot.mkdir(parents=True, exist_ok=True)
    _ignore(session)
    return spot


def listing(session: sessions.Session) -> list[dict]:
    """Every page this session can see, newest first, with what the phone needs to show it.

    Its own and the folder's, in one list. The folder's are read first and the session's own
    written over them, so an id in both scopes is the session's own — it wrote that page for
    itself, and a page it did not write cannot displace it.
    """
    if not project(session).is_dir():
        return []
    _ignore(session)
    rows: dict[str, dict] = {}
    for spot in reversed(_spots(session)):
        if not spot.is_dir():
            continue
        shared = spot == project(session)
        for found in spot.glob("*.html"):
            row = _row(spot, found.stem, shared=shared)
            if row:
                rows[row["id"]] = row
    return sorted(rows.values(), key=lambda row: row["modified"], reverse=True)


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
    session's, and counting one here would promise a page that does not list. That is also why
    the folder's own slips count: they are on this session's tab, they are waiting on the person
    the same way, and a row saying one fewer than the tab it opens is the worse of the two.
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


def answered(session: sessions.Session, artifact_id: str) -> Any:
    """What was answered last time, or None if nobody has.

    A page that asked a question and got one is not finished with it: reopening it should show
    what you said, not an empty form pretending it has never been filled in. The page is the only
    thing that knows how to put its own answer back into its own controls, so this hands back the
    value exactly as it was responded with and says nothing about shape.

    None covers both "never answered" and "the file is unreadable", and deliberately: a page that
    cannot find a previous answer draws itself blank, which is what it did before any of this.
    """
    beside = _file(session, artifact_id, ".answer.json")
    if beside is None or not beside.is_file():
        return None
    try:
        found = json.loads(beside.read_text())
    except (OSError, json.JSONDecodeError) as error:
        log.warning("could not read the answer to %s: %s", artifact_id, error)
        return None
    # The file is written by this daemon, but it sits in the session's own folder.
    return found.get("value") if isinstance(found, dict) else None


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


def _spots(session: sessions.Session) -> list[Path]:
    """The folders a slip of this session's can be in, its own first — first is what wins a tie."""
    mine = own(session)
    return [mine, project(session)] if mine else [project(session)]


def _ignore(session: sessions.Session) -> None:
    """Top up `.deckhand/.gitignore`, so the store ignores itself whoever made the folder."""
    ignore = project(session).parent / ".gitignore"
    if not ignore.exists():
        try:
            ignore.write_text("*\n")
        except OSError as error:
            log.warning("could not make %s ignore itself: %s", ignore.parent, error)


def _inside(spot: Path, artifact_id: str, suffix: str) -> Path | None:
    """One file of this artifact's, inside that one folder, or None.

    The only place an id from the phone turns into a path, so it is the only place the check has
    to be made. `fullmatch` refuses anything that is not one plain slug, and resolving before
    comparing parents is what catches the rest: a page that is a symlink out of the folder
    resolves somewhere whose parent is not this folder. What the project itself links its own
    artifacts folder to is the project's business — the id cannot reach outside either way.
    """
    if not ID.fullmatch(artifact_id):
        return None
    settled = (spot / f"{artifact_id}{suffix}").resolve()
    if settled.parent != spot.resolve():
        log.warning("refused an artifact outside %s: %r", spot, artifact_id)
        return None
    return settled


def _file(session: sessions.Session, artifact_id: str, suffix: str) -> Path | None:
    """The same file, in whichever of this session's scopes actually holds that page.

    The page decides the scope and the suffix follows it, so an answer is always written beside
    the question it answers rather than in the folder a caller happened to think of. A folder
    that is not there holds no page, which is how "a read requires the folder to exist" survives
    two of them.
    """
    for spot in _spots(session):
        page_at = _inside(spot, artifact_id, ".html")
        if page_at is not None and page_at.is_file():
            return _inside(spot, artifact_id, suffix)
    return None


def _row(spot: Path, artifact_id: str, shared: bool) -> dict | None:
    """One page as the phone lists it. None for a file in there that is not an artifact.

    `answered` is the whole state there is: a page with no answer beside it is open, and one with
    an answer has been answered and can be asked again by deleting the file. `shared` is the
    other half of what a row means — it says this page belongs to the folder and every session
    working in it is looking at the same one, so answering it is not answering *this* session.
    """
    found = _inside(spot, artifact_id, ".html")
    if found is None:
        return None
    try:
        modified = found.stat().st_mtime
    except OSError:
        return None
    beside = _inside(spot, artifact_id, ".answer.json")
    return {
        "id": artifact_id,
        "title": _title(found, artifact_id),
        "modified": modified,
        "answered": beside is not None and beside.is_file(),
        "shared": shared,
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

    It names the slip, carries the answer when it is short, and says where the whole of it is: a
    session that was waiting reads the file, and one that had stopped is woken by the message.

    "Slip" rather than "artifact" because that is what the thing is called on the phone, and the
    two have to be the same word: a session told about an artifact and a person looking at a tab
    labelled Slips are talking about the same file, and neither should have to work that out.
    """
    return (
        f"Answered the slip {written['id']} on my phone: {_brief(written['value'])}. "
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


@router.get("/sessions/{session_id}/artifacts/{artifact_id}/answer")
async def read_answer(session_id: str, artifact_id: str) -> dict:
    """What was answered last time. `{"value": null}` when nobody has, which is not an error.

    Its own request rather than a field on the listing: the listing draws a whole tab and would
    then be reading every answer file on the Mac to fill in a value only the one page you open
    can use. `answered` in the listing is the flag; this is the thing itself.
    """
    session = await live_session(session_id)
    if page(session, artifact_id) is None:
        raise HTTPException(status_code=404, detail="no artifact with that id in this project")
    return {"value": answered(session, artifact_id)}


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
