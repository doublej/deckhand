"""The session routes an OpenCode session answers differently, in one place.

Codex's pattern (`codex_routes.py`), for the same reasons: an allow-list, so a route added
tomorrow stays Claude's until somebody names it here, and middleware so the token is checked
before a session's history is read.

Less is refused than for Codex, because OpenCode's API has more of what the phone asks for. The
conversation, the subagents, the commands and the inbox are all OpenCode's own, read over its
API here. What a route does to a session that runs anywhere — `say`, `audio`, `control`, `name` —
is not here at all: those routes branch inside `deliver`, so the chain, the orders, the record
and a renamed session's filter chain run exactly as they do for Claude. `files` and `file` branch
in `files.py`, which reads OpenCode's history for the paths the same way it reads a transcript.
"""

from __future__ import annotations

import asyncio

from fastapi import Request
from fastapi.responses import JSONResponse, Response
from starlette.datastructures import QueryParams

from .. import config, pairing, presence
from ..reading.transcripts import Turn
from . import opencode_input, opencode_turns
from .live import Session, live_sessions
from .opencode import PROVIDER, OpenCodeError, fetch, owns

#: What an OpenCode session cannot be asked for that a Claude session can, and why.
REFUSED = {
    ("GET", "context"): "OpenCode loads its own instructions; the CLAUDE.md tree is Claude Code's",
    ("POST", "focus"): "an OpenCode session runs in OpenCode's service, not in a tmux pane",
}
#: Answered here out of OpenCode's own API.
ANSWERED = {("GET", "turns"), ("GET", "raw"), ("GET", "agents"), ("GET", "commands"),
            ("POST", "queue/clear")}


async def answer_for_opencode(request: Request, call_next) -> Response:
    """Answer for an OpenCode session here, and hand everything else to the route it was meant for."""
    path = request.url.path
    session_id, _, suffix = path.removeprefix("/sessions/").partition("/")
    kind = "agents" if suffix.startswith("agents/") else suffix
    wanted = (request.method, kind)
    if not path.startswith("/sessions/") or (wanted not in REFUSED and wanted not in ANSWERED):
        return await call_next(request)
    # A wrong token falls through, and the route's own dependency refuses it as it always has.
    if not pairing.allows(request.headers.get(config.TOKEN_HEADER, "")):
        return await call_next(request)
    session = await asyncio.to_thread(opencode_session, session_id)
    if session is None:
        return await call_next(request)
    presence.seen(request)
    return await asyncio.to_thread(_answer, wanted, suffix, session, request.query_params)


def opencode_session(session_id: str) -> Session | None:
    """The OpenCode session with that id: off the shared listing, else asked of the service.

    The listing is JJ's two-hour rule, so a session that went quiet, or one a listing timeout
    left out for the 30 s backoff, fell through to Claude's routes and every read and every
    prompt answered 404 — 138 in a row for one session. OpenCode keeps every session, so an id
    it still knows can still be read and spoken to. None for anything that is not OpenCode's.
    """
    listed = next((s for s in live_sessions()
                   if s.session_id == session_id and s.provider == PROVIDER), None)
    if listed or not owns(session_id):
        return listed
    return Session(**found) if (found := fetch(session_id)) else None


def _answer(wanted: tuple[str, str], suffix: str, session: Session, query: QueryParams) -> Response:
    if why := REFUSED.get(wanted):
        return _refused(409, f"{session.name}: {why}")
    kind = wanted[1]
    try:
        if kind == "agents":
            return _agents(suffix, session, query)
        if kind == "commands":
            return JSONResponse({"commands": [c.to_json() for c in opencode_input.commands(session)]})
        if kind == "queue/clear":
            return JSONResponse(opencode_input.clear_queue(session.session_id))
        if kind == "raw":
            limit = _number(query, "limit", 1500, 1, 4000)
            return JSONResponse({"lines": opencode_turns.raw_lines(session.session_id, limit)})
        before = _number(query, "before", 0, 0, 1000)
        turns, more = opencode_turns.page_turns(session.session_id,
                                                _number(query, "limit", 8, 1, 200), before)
        # What it is waiting on the person for, read where the conversation is: OpenCode holds
        # the turn open until somebody answers it there, and the phone cannot answer it yet.
        if before == 0 and (waiting := opencode_input.asks(session)):
            turns.append(Turn(
                role="assistant", text="Waiting on you in OpenCode: " + "; ".join(waiting) + ".",
                timestamp=turns[-1].timestamp if turns else "", written_by="OpenCode"))
        queued = opencode_input.queued(session.session_id) if before == 0 else []
    except OpenCodeError as error:
        return _refused(409, f"OpenCode would not answer for {session.name}: {error}")
    return JSONResponse({"turns": [t.to_json() for t in turns], "queued": queued, "more": more})


def _agents(suffix: str, session: Session, query: QueryParams) -> Response:
    """The child sessions, or one child's own conversation paged as a session's is."""
    if suffix == "agents":
        return JSONResponse({"agents": [a.to_json() for a in opencode_turns.children(
            session.session_id)]})
    child, _, rest = suffix.removeprefix("agents/").partition("/")
    if rest != "turns" or child not in {a.id for a in opencode_turns.children(session.session_id)}:
        return _refused(404, f"{session.name} started no subagent {child!r}")
    turns, more = opencode_turns.page_turns(child, _number(query, "limit", 8, 1, 200),
                                            _number(query, "before", 0, 0, 1000))
    return JSONResponse({"turns": [t.to_json() for t in turns], "more": more})


def _refused(status: int, why: str) -> JSONResponse:
    """The shape `HTTPException` answers with, so the phone reads it as it reads any refusal."""
    return JSONResponse({"detail": why}, status_code=status)


def _number(query: QueryParams, name: str, default: int, low: int, high: int) -> int:
    """A query number held to the bounds the Claude route declares. Anything else is the default."""
    raw = query.get(name, "")
    return max(low, min(int(raw), high)) if raw.isdigit() else default
