"""The session routes a Codex thread answers differently, in one place.

A Codex session is a row like any other, and most of what the phone does to one needs nothing
different: the listing, `summary`, `orders`, `filters`, slips, `say` and `audio` all run exactly
as they do for Claude — delivery branches once, inside `deliver.deliver`, after the chain, the
orders and the record have run. What cannot run the same is everything that reads a Claude
transcript, presses keys in a pane, or is Claude Code's own command: those are answered here,
before the route that would have read the wrong thing.

Middleware for the reason `fleet/routing.py` is middleware: one place rather than a branch in eight
handlers. **An allow-list** like that one, so a route added tomorrow stays Claude's until somebody
names it here. And like that one it runs before any route dependency, so the token is checked here
too — otherwise a Codex thread's history would be answered to anybody who asked for it.
"""

from __future__ import annotations

import asyncio

from fastapi import Request
from fastapi.responses import JSONResponse, Response
from starlette.datastructures import QueryParams

from .. import config, pairing, presence
from . import codex, codex_turns
from .live import Session, live_sessions

#: What a Codex thread cannot be asked for that a Claude session can, and why, as the phone reads it.
REFUSED = {
    ("GET", "context"): "Codex does not load a CLAUDE.md tree; that view is Claude Code's",
    ("GET", "commands"): "Codex takes no slash commands or skills over its app server",
    ("POST", "queue/clear"): "a Codex thread has no inbox to draw a line under",
    ("POST", "focus"): "a Codex thread has no iTerm pane to bring to the front",
    ("POST", "name"): "a Codex thread has no pane to type /rename into",
}
#: Answered here out of Codex's own reading, or with nothing where Codex has nothing to say.
ANSWERED = {("GET", "turns"), ("GET", "raw"), ("GET", "files"), ("GET", "file"),
            ("GET", "agents"), ("POST", "control")}


async def answer_for_codex(request: Request, call_next) -> Response:
    """Answer for a Codex session here, and hand everything else to the route it was meant for."""
    path = request.url.path
    session_id, _, suffix = path.removeprefix("/sessions/").partition("/")
    kind = "agents" if suffix.startswith("agents/") else suffix
    wanted = (request.method, kind)
    if not path.startswith("/sessions/") or (wanted not in REFUSED and wanted not in ANSWERED):
        return await call_next(request)
    # A wrong token falls through, and the route's own dependency refuses it as it always has.
    if not pairing.allows(request.headers.get(config.TOKEN_HEADER, "")):
        return await call_next(request)
    session = await asyncio.to_thread(_codex_session, session_id)
    if session is None:
        return await call_next(request)
    presence.seen(request)
    return await asyncio.to_thread(_answer, wanted, suffix, session, request.query_params)


def _codex_session(session_id: str) -> Session | None:
    """The live Codex row with that id, off the shared listing. None for anything else."""
    return next((s for s in live_sessions()
                 if s.session_id == session_id and s.provider == "codex"), None)


def _answer(wanted: tuple[str, str], suffix: str, session: Session, query: QueryParams) -> Response:
    if why := REFUSED.get(wanted):
        return _refused(409, f"{session.name}: {why}")
    kind = wanted[1]
    if kind in ("files", "agents"):
        # Nothing to list, and so nothing a row of that listing could open.
        if suffix == kind:
            return JSONResponse({kind: []})
        return _refused(404, f"a Codex thread lists no {kind}")
    if kind == "file":
        return _refused(404, "a Codex thread lists no files")
    if kind == "control":
        return _control(session, query.get("action", ""))
    try:
        if kind == "raw":
            limit = _number(query, "limit", 1500, 1, 4000)
            return JSONResponse({"lines": codex_turns.raw_lines(session.session_id, limit)})
        turns, more = codex_turns.page_turns(session.session_id,
                                             _number(query, "limit", 8, 1, 200),
                                             _number(query, "before", 0, 0, 1000))
    except codex.CodexError as error:
        return _refused(409, f"Codex would not read {session.name}: {error}")
    # No `queued`: Codex takes the words into a turn at once, so nothing waits in an inbox.
    return JSONResponse({"turns": [t.to_json() for t in turns], "queued": [], "more": more})


def _control(session: Session, action: str) -> Response:
    """`cancel` is a stop, and Codex has one. `compact`, `clear` and `exit` are Claude Code's."""
    if action != "cancel":
        return _refused(409, f"{session.name} is a Codex thread: only a stop reaches it, "
                             f"and {action or 'that'} is Claude Code's own command")
    if why := codex.interrupt(session):
        return _refused(409, why)
    return JSONResponse({"sent": action})


def _refused(status: int, why: str) -> JSONResponse:
    """The shape `HTTPException` answers with, so the phone reads it as it reads any refusal."""
    return JSONResponse({"detail": why}, status_code=status)


def _number(query: QueryParams, name: str, default: int, low: int, high: int) -> int:
    """A query number held to the bounds the Claude route declares. Anything else is the default."""
    raw = query.get(name, "")
    return max(low, min(int(raw), high)) if raw.isdigit() else default
