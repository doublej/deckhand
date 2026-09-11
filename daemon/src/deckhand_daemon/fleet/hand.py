"""What runs on a machine that is not this Mac: reads its own disk, writes one socket, decides
nothing.

**This is a separate app rather than a flag on `app.py`, and that is the design.** The refusals
are enforced by absence — there is no `/settings`, no `/filters`, no `/orders`, no `/say`, no
`/notify`, no `/manager`, no pane route — because this file does not define them, not because a
conditional declined to. Nothing here can be switched back on by a config mistake.

The split is not arbitrary either. **A hand holds what only exists on its own disk; the daemon
holds everything that decides.** A hand has no filter chain, no standing orders, no utt, no APNs
key and no manager, so it cannot be asked for a judgement — it has nothing to judge with. In
particular `POST /sessions/{id}/deliver` is a primitive: exact bytes into one socket, no filter
chain, no orders, no delivery record. The daemon runs all of that and calls this last.

It binds loopback only. The daemon reaches it through an ssh forward, so nothing about a session's
inbox is ever on the LAN — see `link.py`.

Two more absences worth naming, because both look like oversights and are not:

- **No `/projects`.** Atlas already catalogues every machine's folders and the daemon reads that
  directly. A route here would be a second, staler answer to a question already answered.
- **No `POST /projects/session`.** Starting a session is `it2` from end to end (`projects/
  starting.py`), so it is pane work, and pane work is what a hand does not do. The phone lists a
  remote machine's folders and opens them only on this Mac.
"""

from __future__ import annotations

from fastapi import Body, Depends, FastAPI, Header, HTTPException, Query

from .. import __version__, artifacts, config, deliver, sessions
from ..links import routes as link_routes
from ..log import log
from ..reading import asked, commands, context, readable, transcripts
from . import registry


def require_token(x_deckhand_token: str = Header(default="")) -> None:
    """The same shared secret the daemon uses, fetched over ssh rather than typed. Belt and
    braces behind a loopback bind: the only way to this port is an authenticated ssh session."""
    if x_deckhand_token != config.token():
        raise HTTPException(status_code=401, detail="bad token")


app = FastAPI(title="deckhand-hand", docs_url=None, redoc_url=None, openapi_url=None)

# Two routers come across whole rather than being written again here. Both are already exactly
# what a hand should serve — files on this machine's own disk — and a second copy of either would
# be a second answer that could drift from the first.
#
# `artifacts` is a slip: a file a session wrote in its own `<cwd>/.deckhand/artifacts`, so it can
# only be read where that disk is. `links` is who has messaged whom, which is within one machine
# by construction — `AF_UNIX` does not cross one, so a cross-machine edge cannot exist to miss.
app.include_router(artifacts.router, dependencies=[Depends(require_token)])
app.include_router(link_routes.router, dependencies=[Depends(require_token)])


def session_or_404(session_id: str) -> sessions.Session:
    """The same lookup `saying.session_or_404` does, including the one case where it answers with
    a session other than the one asked for: `/clear` retires a conversation and keeps the pid, the
    socket and the name, so a phone holding the old id still means the session on its screen."""
    live = sessions.live_sessions()
    for s in live:
        if s.session_id == session_id:
            return s
    if (now := sessions.succeeded_by(session_id)) and (
        found := next((s for s in live if s.session_id == now), None)
    ):
        log.info("%s was cleared — %s answers for it now", session_id[:8], found.name)
        return found
    raise HTTPException(status_code=404, detail="no live session with that id")


@app.get("/health")
def health() -> dict:
    """Open, like the daemon's. The daemon polls it to know the hand has finished binding — the
    ssh forward is up before the process behind it is listening."""
    return {"name": "deckhand-hand", "version": __version__, "machine": registry.here()}


@app.get("/sessions", dependencies=[Depends(require_token)])
def list_sessions() -> dict:
    """Every live session on this machine, already stamped with it.

    `iterm_only=False` because there is no iTerm here at all. On the Mac that flag hides a
    session whose pane could not be found among panes that *were* found — evidence something is
    wrong. Here nothing is wrong: there are no panes anywhere, and every session is addressable
    down its socket.
    """
    live = sessions.live_sessions(iterm_only=False)
    window = sessions.context_window()
    return {
        "sessions": [
            s.to_json() | sessions.last_request(s.session_id).to_json(window) | artifacts.counted(s)
            for s in live
        ]
    }


@app.get("/sessions/{session_id}/turns", dependencies=[Depends(require_token)])
def session_turns(
    session_id: str,
    limit: int = Query(default=8, ge=1, le=200),
    before: int = Query(default=0, ge=0),
) -> dict:
    session_or_404(session_id)
    turns, more = transcripts.page_turns(session_id, limit, before)
    return {
        "turns": [t.to_json() for t in turns],
        "queued": asked.queued(session_id) if before == 0 else [],
        "more": more,
    }


@app.get("/sessions/{session_id}/raw", dependencies=[Depends(require_token)])
def session_raw(session_id: str, limit: int = Query(default=1500, ge=1, le=4000)) -> dict:
    session_or_404(session_id)
    return {"lines": readable.plain_tail(session_id, limit)}


@app.get("/sessions/{session_id}/context", dependencies=[Depends(require_token)])
def session_context(session_id: str) -> dict:
    session = session_or_404(session_id)
    found = context.documents(session.cwd)
    return {"documents": [d.to_json() for d in found], "tokens": sum(d.tokens for d in found)}


@app.get("/sessions/{session_id}/commands", dependencies=[Depends(require_token)])
def session_commands(session_id: str) -> dict:
    session = session_or_404(session_id)
    return {"commands": [c.to_json() for c in commands.commands(session.cwd)]}


@app.post("/sessions/{session_id}/queue/clear", dependencies=[Depends(require_token)])
def clear_queue(session_id: str) -> dict:
    session_or_404(session_id)
    return {"cleared": asked.clear(session_id)}


@app.post("/sessions/{session_id}/deliver", dependencies=[Depends(require_token)])
def deliver_text(session_id: str, text: str = Body(embed=True)) -> dict:
    """The primitive, and the only thing a hand writes.

    Exact bytes into that session's own inbox socket. **No filter chain, no standing orders, no
    delivery record** — the daemon ran all of that before calling this, and running any of it
    twice would be the shape of bug that looks like it works.

    Socket only, never a route argument. There is no pane on this machine to type into, so the
    keyboard route is not a thing this can be asked for and then refuse: it is absent.
    """
    session = session_or_404(session_id)
    delivered_by, error = deliver.deliver(session, text, route="socket")
    return {"delivered": delivered_by is not None, "delivered_by": delivered_by, "error": error}


def main() -> None:
    """`deckhand-daemon --hand`. Loopback only: the daemon gets here through an ssh forward."""
    import uvicorn

    log.info("hand on %s, port %d, loopback only", registry.here(), config.PORT + 1)
    uvicorn.run(app, host="127.0.0.1", port=config.PORT + 1, log_level="warning")
