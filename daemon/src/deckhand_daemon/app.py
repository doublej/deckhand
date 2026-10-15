"""HTTP surface. LAN-only, one shared token, no state of its own beyond stored audio."""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Body, Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import FileResponse

from . import (
    __version__,
    artifacts,
    beacon,
    briefings,
    config,
    deliver,
    files,
    filters,
    fleet,
    nudge,
    pairing,
    plugin,
    presence,
    push,
    saying,
    sessions,
    summarize,
)
from .bindings import routes as binding_routes
from .browser import routes as browser_routes
from .filters import routes as filter_routes
from .fleet import routing as fleet_routing
from .links import routes as link_routes
from .log import log
from .manager import agent as manager_agent
from .manager import routes as manager_routes
from .orders import routes as order_routes
from .pairing import routes as pairing_routes
from .projects import routes as project_routes
from .reading import asked, commands, context, readable, transcripts
from .reading import routes as reading_routes
from .settings import routes as settings_routes
from .space import routes as space_routes
from .space import tabs as tab_groups


def require_token(request: Request, x_deckhand_token: str = Header(default="")) -> None:
    # This Mac's own token or a paired device's: `pairing.allows` is the one place that knows.
    if not pairing.allows(x_deckhand_token):
        raise HTTPException(status_code=401, detail="bad token")
    # The one place every authenticated request passes, so the phone's last-heard-from stamp
    # costs an assignment and needs no route of its own. Only a request that got *past* the
    # token counts: a wrong token is not this phone, and nor is the loopback — see `seen`.
    presence.seen(request)


@asynccontextmanager
async def lifespan(_: FastAPI):
    """Deckhand's page inside utt, put there fresh on every start: it is what survives utt
    being reinstalled or the folder being cleared, and it costs one file write."""
    plugin.install()
    # And say on the LAN where this Mac answers, so the phone can find it rather than be
    # told. A child process rather than a task: `beacon.py` says why that is the whole of it.
    beacon.start()
    watchers = [asyncio.create_task(plugin.watch()), asyncio.create_task(push.watch()),
                asyncio.create_task(nudge.watch()), asyncio.create_task(briefings.watch()),
                asyncio.create_task(manager_agent.watch()),
                asyncio.create_task(tab_groups.watch()),
                # Open every machine's link now rather than on the first listing that wants one
                # — otherwise the whole ssh handshake lands on the one request a person is
                # watching — and go on asking, so a link that drops is remade in the background
                # and the hand behind it never falls silent long enough to time itself out.
                asyncio.create_task(fleet.keep_warm())]
    yield
    beacon.stop()
    for watcher in watchers:
        watcher.cancel()
    # Every hand dies with its link, which is why nothing had to be installed as a service.
    fleet.stop_all()


app = FastAPI(title="Deckhand", version=__version__, lifespan=lifespan)
# A read for a session on another machine goes to the machine that has the files. One place
# rather than a branch in nine handlers, and an allow-list rather than a skip-list, so a route
# added later is local until somebody says otherwise: see `fleet/routing.py`.
app.middleware("http")(fleet_routing.forward_remote_reads)
app.middleware("http")(sessions.answer_for_codex)
# Last, so it runs first: a browser's preflight is answered before anything asks for a token.
app.middleware("http")(browser_routes.cors)
app.include_router(artifacts.router, dependencies=[Depends(require_token)])
app.include_router(binding_routes.router, dependencies=[Depends(require_token)])
app.include_router(filter_routes.router, dependencies=[Depends(require_token)])
app.include_router(link_routes.router, dependencies=[Depends(require_token)])
app.include_router(manager_routes.router, dependencies=[Depends(require_token)])
app.include_router(order_routes.router, dependencies=[Depends(require_token)])
app.include_router(reading_routes.router, dependencies=[Depends(require_token)])
app.include_router(presence.router, dependencies=[Depends(require_token)])
app.include_router(push.router, dependencies=[Depends(require_token)])
app.include_router(project_routes.router, dependencies=[Depends(require_token)])
app.include_router(settings_routes.router, dependencies=[Depends(require_token)])
app.include_router(space_routes.router, dependencies=[Depends(require_token)])
app.include_router(saying.router, dependencies=[Depends(require_token)])
app.include_router(pairing_routes.router)  # its own checks: `POST /pair` has no token yet
app.include_router(browser_routes.router)  # `/health` is open; `/transcribe` has a scope of its own


# Two clients polling every few seconds would bury everything else in the log, so a listing
# only gets a line when the answer actually changed.
_last_listing: tuple[int, str] | None = None


@app.get("/sessions", dependencies=[Depends(require_token)])
def list_sessions() -> dict:
    global _last_listing
    live = sessions.live_sessions()
    status = sessions.iterm_status()
    if _last_listing != (len(live), status):
        _last_listing = (len(live), status)
        log.info("listing changed: %d sessions, iterm %s", len(live), status)
        # The phone asks for this every few seconds anyway, so the plugin page gets a live
        # count for free rather than the daemon paying for one of its own.
        plugin.status(sessions=f"{len(live)} live")
    # How full each one's context is, and what answered its last request. Read here rather than
    # off the session record because all three come out of the transcript, not the registry — and
    # a phone deciding which session needs attention wants to know which one is about to compact.
    window = sessions.context_window()
    listed = [
        s.to_json()
        | sessions.last_request(s.session_id).to_json(window)
        # And how far the person has got with what it asked them: a page with no answer file
        # beside it is the session stopped and waiting, which is the one thing on a row that is
        # genuinely blocked on you. It travels with the listing rather than costing the phone a
        # request per session to find out.
        | artifacts.counted(s)
        for s in live
    ]
    # What the week has cost so far, which belongs to the Mac rather than to any session. One
    # small file read per listing, not per session — the statusline's agent does the counting.
    return {"sessions": listed, "iterm": status, "week": sessions.week_usage()}


@app.get("/machines", dependencies=[Depends(require_token)])
async def list_machines() -> dict:
    """Every machine on the network and whether it is reachable right now.

    Separate from `/sessions` on purpose: the listing answers "what can I talk to", and a machine
    that is asleep simply contributes nothing to it rather than failing it. This is where a
    person finds out that a machine is missing, and why.
    """
    return {"machines": await fleet.machines()}


@app.get("/sessions/all", dependencies=[Depends(require_token)])
async def list_every_session() -> dict:
    """The whole network's sessions in one answer, newest first.

    A route of its own rather than a flag on `/sessions`, because `/sessions` is what every older
    build of the app already polls and it must go on meaning exactly this Mac. The phone moves
    over when it is ready to draw a machine, and nothing breaks in between.

    Everything `/sessions` says, plus the machines — `iterm` and `week` included, so the phone
    polls one route for a whole screen rather than two that can disagree about the same moment.
    """
    local = await asyncio.to_thread(list_sessions)
    return {
        **local,
        "sessions": await fleet.listings(local["sessions"]),
        "machines": await fleet.machines(),
    }


@app.get("/sessions/{session_id}/summary", dependencies=[Depends(require_token)])
async def session_summary(session_id: str) -> dict:
    """The last briefing written for this session, and this session to the front of the queue.

    Never waits for a model. Opening a session is exactly when its briefing matters most and
    exactly when there is least patience for a blank page, so the answer is the last true thing
    said about it and the reading is what promotes it to be written about next.
    """
    await saying.live_session(session_id)
    briefings.bump(session_id)
    return await asyncio.to_thread(briefings.of, session_id)


@app.get("/briefings", dependencies=[Depends(require_token)])
def all_briefings() -> dict:
    """Every live session's last briefing, off disk, in one call.

    This is what makes a cold start whole: a reinstalled app knows everything the Mac knew a
    moment before, without buying a single briefing to find it out.
    """
    kept = {s.session_id: briefings.of(s.session_id) for s in sessions.live_sessions()}
    whole = summarize.spent()
    if whole["runs"]:
        plugin.status(briefings=f"{whole['runs']} written, {whole['tokens']:,} tokens")
    return {"briefings": kept}


@app.get("/sessions/{session_id}/files", dependencies=[Depends(require_token)])
def session_files(session_id: str) -> dict:
    """Everything this session touched that a person could open and look at."""
    session = saying.session_or_404(session_id)
    return {"files": [f.to_json() for f in files.readable_files(session_id, session.cwd)]}


@app.get("/sessions/{session_id}/file", dependencies=[Depends(require_token)])
def session_file(session_id: str, path: str = Query(description="one of /files")) -> FileResponse:
    """One of those files, by the path the listing gave.

    The listing is the whole permission: a path this session's transcript never named is a
    404, so this stays a way to see what a session made and never becomes a file browser.
    """
    session = saying.session_or_404(session_id)
    # ponytail: re-reads the transcript tail per request (~10 ms). Cache it if a files tab
    # ever polls rather than being opened.
    #
    # Two doors, and the second is the folder's own context tree: those documents are the
    # standing instructions a session here already runs under, so they are readable whether this
    # run happened to open them or not. Both sets are computed rather than supplied, which is
    # what keeps this a window onto one session's work and not a file browser.
    found = files.allowed(session_id, session.cwd, path) or context.allowed(session.cwd, path)
    if found is None:
        raise HTTPException(status_code=404, detail="that file is not in this session's transcript")
    size = found.stat().st_size
    if size > config.MAX_FILE_BYTES:
        raise HTTPException(status_code=413, detail=f"{size // 1024 // 1024} MB is too big to send")
    return FileResponse(found, filename=found.name)


@app.get("/sessions/{session_id}/turns", dependencies=[Depends(require_token)])
def session_turns(
    session_id: str,
    limit: int = Query(default=8, ge=1, le=200),
    before: int = Query(default=0, ge=0, description="how many turns from the end to skip"),
) -> dict:
    """A page of the conversation, newest page first.

    `before` walks backwards: 0 is the tail, `before=25` is the twenty-five turns before that.
    The phone holds nothing between launches, so this is the only way it ever sees history —
    which is the right way round, since the Mac is where the transcript lives and where it is
    parsed. `more` says whether there is an older page, so a screen knows when to stop asking.
    """
    saying.session_or_404(session_id)
    turns, more = transcripts.page_turns(session_id, limit, before)
    return {
        "turns": [t.to_json() for t in turns],
        # Said, delivered, and not picked up yet. Nothing in the transcript shows this: a
        # message sent mid-turn is not a turn until the session absorbs it. Only ever true of
        # the newest page — an older page is history, and nothing is queued behind history.
        "queued": asked.queued(session_id) if before == 0 else [],
        "more": more,
    }


@app.get("/sessions/{session_id}/context", dependencies=[Depends(require_token)])
def session_context(session_id: str) -> dict:
    """Every CLAUDE.md a session in this folder is loaded with, as a tree.

    Not what it touched — that is `/files`, and the transcript bounds it. This is what it started
    with, which is the other half of "why did it do that": a rule three folders up is invisible
    in a transcript and is running all the same.
    """
    session = saying.session_or_404(session_id)
    found = context.documents(session.cwd)
    return {"documents": [d.to_json() for d in found], "tokens": sum(d.tokens for d in found)}


@app.get("/sessions/{session_id}/raw", dependencies=[Depends(require_token)])
def session_raw(session_id: str, limit: int = Query(default=1500, ge=1, le=4000)) -> dict:
    """Everything in the transcript, in order, without the syntax it is stored in.

    Handing over the JSONL itself was the first answer and a bad one: one entry runs to tens of
    kilobytes, so a window that holds a day of work held ten lines of mostly punctuation.
    """
    saying.session_or_404(session_id)
    return {"lines": readable.plain_tail(session_id, limit)}


@app.post("/sessions/{session_id}/queue/clear", dependencies=[Depends(require_token)])
def clear_queue(session_id: str) -> dict:
    """Draw a line under this session's inbox: whatever the lane still shows was never read."""
    saying.session_or_404(session_id)
    return {"cleared": asked.clear(session_id)}


@app.post("/sessions/{session_id}/focus", dependencies=[Depends(require_token)])
def focus_session(session_id: str) -> dict:
    session = saying.session_or_404(session_id)
    if not sessions.focus(session):
        raise HTTPException(status_code=409, detail="session has no iTerm pane")
    return {"focused": True}


@app.get("/sessions/{session_id}/commands", dependencies=[Depends(require_token)])
async def list_commands(session_id: str) -> dict:
    """The slash commands and skills this session could be handed by name.

    Read per request rather than kept: they are files on the Mac that a person edits, and a
    listing this phone opens once in a while is not worth a cache that can go stale. Scoped to the
    session's own folder as well as the Mac's, because a project's `.claude/commands` are only
    that project's — which is why this is a session route and not a `/commands`.
    """
    session = await saying.live_session(session_id)
    found = await asyncio.to_thread(commands.commands, session.cwd)
    return {"commands": [command.to_json() for command in found]}


@app.post("/sessions/{session_id}/control", dependencies=[Depends(require_token)])
async def control_session(
    session_id: str,
    action: str = Query(description="cancel, compact, clear or exit"),
) -> dict:
    """The four things you do to a session rather than say to it.

    `clear` throws away the conversation and `exit` throws away the session; neither can be
    undone, which is the phone's problem to ask about — here they are one more thing typed into
    the pane, exactly as they would be by hand.
    """
    session = await saying.live_session(session_id)
    if action not in deliver.CONTROLS:
        raise HTTPException(status_code=400, detail=f"no such control {action!r}")
    error = await asyncio.to_thread(deliver.control, session, action)
    if error:
        raise HTTPException(status_code=409, detail=error)
    plugin.status(lastAction=f"{action} on {session.name}")
    return {"sent": action}


@app.post("/sessions/{session_id}/name", dependencies=[Depends(require_token)])
async def rename_session(session_id: str, name: str = Body(embed=True)) -> dict:
    """Give a session a new display name, by running Claude Code's own `/rename` in its pane."""
    session = await saying.live_session(session_id)
    error = await asyncio.to_thread(deliver.rename, session, name)
    if error:
        raise HTTPException(status_code=409, detail=error)
    # A filter chain is filed under the session's name, so it has to be carried across exactly as
    # the phone carries a star. Done now rather than when the rename lands: a busy session runs
    # the command when its turn ends, and the phone moves its own favourites on the same optimism.
    carried = filters.renamed(
        filters.key(session.machine, session.name),
        filters.key(session.machine, deliver.clean_name(name)),
    )
    return {"renamed": deliver.clean_name(name), "was": session.name, "carried_filters": carried}

@app.post("/live/token", dependencies=[Depends(require_token)])
def live_token(token: str = Body(embed=True), kind: str = Body(embed=True),
               session: str = Body(embed=True, default="")) -> dict:
    """The phone hands over what the Mac needs to reach its Lock Screen.

    Sent on every launch, because these change without warning and a stale one is a card that
    silently stops updating.

    One card is one session, so an *activity* token says which one it addresses. A phone that
    sends none is a build from before that — taken rather than refused, and dropped, because a
    token that cannot say which card it is could only ever end the wrong one.

    A *device* token is the app's own, for plain notifications — the manager's messages, pushed
    while its panel is not on screen. One per phone, like *start*.
    """
    if kind not in ("activity", "start", "device"):
        raise HTTPException(status_code=400, detail=f"no such token kind {kind!r}")
    push.remember(token, kind, session)
    return {"registered": kind}


@app.post("/sessions/{session_id}/notify", dependencies=[Depends(require_token)])
def ask_for_attention(session_id: str, line: Annotated[str, Body(embed=True)]) -> dict:
    """An agent asking for the person outright, in its own words.

    The only thing on the Lock Screen a session raises for itself — everything else there is the
    Mac noticing something. So it is the one that a folder can refuse outright rather than merely
    keep quiet about, and the refusal comes back rather than being swallowed: an agent that
    thinks it has your attention and has not is worse than one that knows it has not.

    Empty words are refused here rather than pushed as a blank card. There is no useful default:
    the whole point of this route over the ones that fire on their own is that somebody had
    something specific to say.
    """
    session = saying.session_or_404(session_id)
    said = " ".join(line.split())
    if not said:
        raise HTTPException(status_code=400, detail="nothing to say")
    if error := push.called(session, said):
        return {"pushed": False, "why": error}
    return {"pushed": True}
