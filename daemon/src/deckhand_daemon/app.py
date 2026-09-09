"""HTTP surface. LAN-only, one shared token, no state of its own beyond stored audio."""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager

from fastapi import Body, Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import FileResponse

from . import (
    __version__,
    artifacts,
    briefings,
    config,
    deliver,
    files,
    nudge,
    plugin,
    push,
    saying,
    sessions,
    summarize,
)
from .filters import routes as filter_routes
from .log import log
from .reading import asked, readable, transcripts


def require_token(x_deckhand_token: str = Header(default="")) -> None:
    if x_deckhand_token != config.token():
        raise HTTPException(status_code=401, detail="bad token")


@asynccontextmanager
async def lifespan(_: FastAPI):
    """Deckhand's page inside utt, put there fresh on every start: it is what survives utt
    being reinstalled or the folder being cleared, and it costs one file write."""
    plugin.install()
    watchers = [asyncio.create_task(plugin.watch()), asyncio.create_task(push.watch()),
                asyncio.create_task(nudge.watch()), asyncio.create_task(briefings.watch())]
    yield
    for watcher in watchers:
        watcher.cancel()


app = FastAPI(title="Deckhand", version=__version__, lifespan=lifespan)
app.include_router(artifacts.router, dependencies=[Depends(require_token)])
app.include_router(filter_routes.router, dependencies=[Depends(require_token)])
app.include_router(saying.router, dependencies=[Depends(require_token)])


@app.get("/health")
def health() -> dict:
    """Open on purpose: the app pings it to tell 'wrong host' from 'wrong token'."""
    return {
        "name": "deckhand",
        "version": __version__,
        "host": config.base_url(),
        # So the phone can turn a session's `localhost:5173` into something it can actually open.
        "lan": config.lan_address(),
        "iterm": sessions.iterm_status(),
    }


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
    # How full each one's context is. Read here rather than on the session record because it
    # comes out of the transcript, not the registry — and a phone deciding which session needs
    # attention wants to know which one is about to compact.
    window = sessions.context_window()
    listed = [
        s.to_json() | {"context": {"used": sessions.context_used(s.session_id), "limit": window}}
        for s in live
    ]
    return {"sessions": listed, "iterm": status}


@app.get("/sessions/{session_id}/summary", dependencies=[Depends(require_token)])
async def session_summary(session_id: str) -> dict:
    """The last briefing written for this session, and this session to the front of the queue.

    Never waits for a model. Opening a session is exactly when its briefing matters most and
    exactly when there is least patience for a blank page, so the answer is the last true thing
    said about it and the reading is what promotes it to be written about next.
    """
    await saying.live_session(session_id)
    briefings.bump(session_id)
    return briefings.of(session_id)


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
    found = files.allowed(session_id, session.cwd, path)
    if found is None:
        raise HTTPException(status_code=404, detail="that file is not in this session's transcript")
    size = found.stat().st_size
    if size > config.MAX_FILE_BYTES:
        raise HTTPException(status_code=413, detail=f"{size // 1024 // 1024} MB is too big to send")
    return FileResponse(found, filename=found.name)


@app.get("/sessions/{session_id}/turns", dependencies=[Depends(require_token)])
def session_turns(session_id: str, limit: int = Query(default=8, ge=1, le=50)) -> dict:
    saying.session_or_404(session_id)
    return {
        "turns": [t.to_json() for t in transcripts.read_turns(session_id, limit)],
        # Said, delivered, and not picked up yet. Nothing in the transcript shows this: a
        # message sent mid-turn is not a turn until the session absorbs it.
        "queued": asked.queued(session_id),
    }


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


@app.post("/sessions/{session_id}/control", dependencies=[Depends(require_token)])
async def control_session(
    session_id: str,
    action: str = Query(description="cancel, compact or clear"),
) -> dict:
    """The three things you do to a session rather than say to it.

    `clear` throws away the conversation and cannot be undone, which is the phone's problem to
    ask about — here it is one more thing typed into the pane, exactly as it would be by hand.
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
    return {"renamed": deliver.clean_name(name), "was": session.name}

@app.post("/live/token", dependencies=[Depends(require_token)])
def live_token(token: str = Body(embed=True), kind: str = Body(embed=True)) -> dict:
    """The phone hands over what the Mac needs to reach its Lock Screen.

    Sent on every launch, because these change without warning and a stale one is a card that
    silently stops updating.
    """
    if kind not in ("activity", "start"):
        raise HTTPException(status_code=400, detail=f"no such token kind {kind!r}")
    push.remember(token, kind)
    return {"registered": kind}


def main() -> None:
    import uvicorn

    log.info("deckhand %s  token: %s", config.base_url(), config.token())
    uvicorn.run(app, host="0.0.0.0", port=config.PORT, log_level="info")
