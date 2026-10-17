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
- **No `POST /projects/session`.** The hub's route is where the gates and the settings are; a
  hand only takes `start_here`, below, which is tmux and the trust check and nothing else.
"""

from __future__ import annotations

import secrets
import time

from fastapi import Body, Depends, FastAPI, Header, HTTPException, Query

from .. import __version__, artifacts, config, deliver, sessions
from ..links import routes as link_routes
from ..log import log
from ..projects import starting, tmux
from ..reading import asked, commands, context, readable, transcripts
from ..reading import routes as agent_routes
from ..tray import routes as tray_routes
from . import registry


def require_token(x_deckhand_token: str = Header(default="")) -> None:
    """The same shared secret the daemon uses, fetched over ssh rather than typed. Belt and
    braces behind a loopback bind: the only way to this port is an authenticated ssh session."""
    if not secrets.compare_digest(x_deckhand_token, config.token()):
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
# The third, and it arrives for the same reason: a subagent's conversation is a file under
# `<sessionId>/subagents/` on the machine that ran it, so this is the machine that can read it.
app.include_router(agent_routes.router, dependencies=[Depends(require_token)])
# The fourth: what is open here, for the Mac's tray. Only the open half — the feed is written by
# the Lock Screen's sweep, which is the daemon's and not a hand's.
app.include_router(tray_routes.here_router, dependencies=[Depends(require_token)])


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

    `paned_only=False` because a pane means nothing here. On the Mac that flag hides a session
    tmux has no pane for among panes that *were* found. Here every session is addressable down
    its socket and nothing else, so whether tmux holds it changes nothing.
    """
    live = sessions.live_sessions(paned_only=False)
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


@app.get("/projects/trusted", dependencies=[Depends(require_token)])
def trusted_folders() -> dict:
    """Which folders Claude Code has been trusted in on this machine.

    The one fact about a remote project atlas cannot answer: it catalogues folders, not whether
    somebody once pressed a key in a trust dialog. The daemon asks every machine this when the
    picker opens, so a row says whether it can be started *before* it is tapped rather than
    after — and a hand that is asleep simply contributes no trusted rows, which reads as
    "cannot start here yet", the same answer and for an honest reason.
    """
    return {"trusted": sorted(starting.trusted())}


@app.post("/projects/session", dependencies=[Depends(require_token)])
def start_here(path: str = Body(embed=True), model: str = Body(embed=True, default="")) -> dict:
    """Start a session in that folder on this machine, with tmux.

    **This route is the one thing `docs/network.md` said a hand refuses by absence**, and it is
    here now for the reason that note gave for adding it: reading a remote session stopped being
    enough. What has *not* changed is the authority it carries — `tmux.start` fills in no pane,
    so the session it makes is socket-only exactly like every other session on this machine, and
    the keyboard route goes on refusing it.

    `path` is not checked against a catalogue here. It is checked against one on the daemon, which
    is the machine that has atlas; checking it twice against two different lists would mean two
    answers that can disagree. What this checks is the thing only this machine knows: whether
    Claude Code has been trusted in that folder.

    200 with an `error` rather than a 4xx, matching `deliver` above: the daemon reads None from
    `proxy.call` as "that machine is not reachable", so a refusal spelled as a status code would
    arrive as the wrong sentence entirely.
    """
    session, error = tmux.start(path, model)
    return {"session": session.to_json() if session else None, "error": error}


#: When the daemon was last heard from, however it asked. Stamped by the middleware below.
_heard = time.monotonic()
#: How long a hand goes unspoken-to before deciding it has been orphaned. Comfortably longer
#: than `merge.KEEP_WARM`, so a hand only ever reaches this when the daemon has actually gone.
FORGOTTEN_AFTER = 300.0


@app.middleware("http")
async def _remember_the_daemon(request, call_next):
    """Anything at all from the daemon counts as the link being alive, `/health` included."""
    global _heard
    _heard = time.monotonic()
    return await call_next(request)


def _die_with_the_link() -> None:
    """Exit when the ssh connection that started this one goes away.

    **Measured, not assumed: a hand does not die on its own when its link is terminated.** One
    outlived its ssh by over a minute, kept port 4181, and then answered the *next* link's calls
    with the code it had been started with — so a machine went on reporting its own hostname as
    its id long after that was fixed and shipped. A stale hand is invisible from the Mac: the
    link comes up, `/health` answers, and everything it says is a version behind.

    stdin closing is the one signal that survives everything. No tty is involved, so `-tt` and
    SIGHUP are not reliable, and this works the same on Windows, where neither is.
    """
    import os
    import sys
    import threading

    def watch() -> None:
        try:
            while sys.stdin.readline():
                pass
        except (OSError, ValueError):
            pass
        log.info("link closed; hand exiting")
        os._exit(0)  # not sys.exit: this is a daemon thread under a running event loop

    threading.Thread(target=watch, daemon=True).start()


def _die_when_forgotten() -> None:
    """Exit when the daemon has not asked this hand anything for `FORGOTTEN_AFTER`.

    **The backstop `_die_with_the_link` cannot be**, and it is not belt-and-braces: it answers a
    failure that one structurally cannot. Measured on 2026-09-12 — a hand started at 18:44 the
    day before was still holding port 4181 seventeen hours later, its stdin a pipe from an
    `sshd: jurrejan@notty` with no client left at the other end. The Mac's ssh had gone without
    closing the connection (a sleeping laptop sends no FIN), and sshd, which has no
    `ClientAliveInterval` here, held that session open forever. stdin never saw EOF because the
    write end was never closed.

    What that costs is worth spelling out, because it is invisible from the Mac: the squatting
    hand keeps the port, so every new hand fails to bind and exits at once — while `/health`
    through the new forward still answers, *from the old hand*. The link reads up, the listing
    is a day stale, and nothing anywhere says so.

    A hand exists to serve one daemon. Silence for five minutes means that daemon is gone,
    whatever the reason, and the right thing is to let go of the port.
    """
    import os
    import threading

    def watch() -> None:
        while True:
            time.sleep(FORGOTTEN_AFTER / 5)
            if time.monotonic() - _heard > FORGOTTEN_AFTER:
                log.info("nothing from the daemon in %.0fs; hand exiting", FORGOTTEN_AFTER)
                os._exit(0)

    threading.Thread(target=watch, daemon=True).start()


def main() -> None:
    """`deckhand-daemon --hand`. Loopback only: the daemon gets here through an ssh forward."""
    import uvicorn

    _die_with_the_link()
    _die_when_forgotten()
    log.info("hand on %s, port %d, loopback only", registry.here(), config.PORT + 1)
    uvicorn.run(app, host="127.0.0.1", port=config.PORT + 1, log_level="warning")
