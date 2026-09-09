"""HTTP surface. LAN-only, one shared token, no state of its own beyond stored audio."""

from __future__ import annotations

import asyncio
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated

from fastapi import Body, Depends, FastAPI, Header, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse

from . import (
    __version__,
    briefings,
    config,
    deliver,
    files,
    filters,
    nudge,
    plugin,
    push,
    sessions,
    summarize,
    transcribe,
)
from .filters import routes as filter_routes
from .log import log
from .reading import asked, readable, transcripts

AUDIO_SUFFIXES = {".m4a", ".caf", ".wav", ".mp3", ".aac", ".mp4", ".ogg", ".flac", ".webm"}


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
app.include_router(filter_routes.router, dependencies=[Depends(require_token)])


async def _filtered(
    session: sessions.Session, text: str, route: str, source: str, images: list[str] | None = None
) -> filters.Outcome:
    """What the chain makes of the words, before the session is ever told about them."""
    return await filters.run(filters.Prompt(
        text=text, session_id=session.session_id, session_name=session.name, cwd=session.cwd,
        route=route, source=source, images=images or []))


async def _live_session(session_id: str) -> sessions.Session:
    """Same lookup, off the event loop: listing shells out and would block every other request."""
    return await asyncio.to_thread(_session_or_404, session_id)


def _session_or_404(session_id: str) -> sessions.Session:
    # ponytail: every lookup re-lists sessions (one `it2` call, ~0.5 s). Cache it if the
    # phone ever polls harder than every few seconds.
    for s in sessions.live_sessions():
        if s.session_id == session_id:
            return s
    raise HTTPException(status_code=404, detail="no live session with that id")


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
    await _live_session(session_id)
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
    session = _session_or_404(session_id)
    return {"files": [f.to_json() for f in files.readable_files(session_id, session.cwd)]}


@app.get("/sessions/{session_id}/file", dependencies=[Depends(require_token)])
def session_file(session_id: str, path: str = Query(description="one of /files")) -> FileResponse:
    """One of those files, by the path the listing gave.

    The listing is the whole permission: a path this session's transcript never named is a
    404, so this stays a way to see what a session made and never becomes a file browser.
    """
    session = _session_or_404(session_id)
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
    _session_or_404(session_id)
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
    _session_or_404(session_id)
    return {"lines": readable.plain_tail(session_id, limit)}


@app.post("/sessions/{session_id}/queue/clear", dependencies=[Depends(require_token)])
def clear_queue(session_id: str) -> dict:
    """Draw a line under this session's inbox: whatever the lane still shows was never read."""
    _session_or_404(session_id)
    return {"cleared": asked.clear(session_id)}


@app.post("/sessions/{session_id}/focus", dependencies=[Depends(require_token)])
def focus_session(session_id: str) -> dict:
    session = _session_or_404(session_id)
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
    session = await _live_session(session_id)
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
    session = await _live_session(session_id)
    error = await asyncio.to_thread(deliver.rename, session, name)
    if error:
        raise HTTPException(status_code=409, detail=error)
    return {"renamed": deliver.clean_name(name), "was": session.name}


@app.post("/sessions/{session_id}/audio", dependencies=[Depends(require_token)], status_code=201)
async def upload_audio(
    session_id: str,
    file: UploadFile,
    route: str | None = Query(default=None, description="auto, keyboard or socket"),
    deliver_now: bool = Query(
        default=True,
        alias="deliver",
        description="false to transcribe only, when the person wants to read it first",
    ),
) -> dict:
    """Speaking to a session: the clip lands on the Mac and utt turns it into text."""
    session = await _live_session(session_id)
    suffix = Path(file.filename or "clip.m4a").suffix.lower()
    if suffix not in AUDIO_SUFFIXES:
        raise HTTPException(status_code=415, detail=f"unsupported audio type {suffix!r}")
    body = await file.read(config.MAX_UPLOAD_BYTES + 1)
    if len(body) > config.MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="clip larger than 32 MB")
    if not body:
        raise HTTPException(status_code=400, detail="empty clip")
    stamp = time.strftime("%Y%m%dT%H%M%S", time.gmtime())
    path = config.audio_dir(session_id) / f"{stamp}-{uuid.uuid4().hex[:8]}{suffix}"
    path.write_bytes(body)
    log.info("clip for %s: %d bytes", session.name, len(body))
    hints = transcribe.hints_for(session.name, session.cwd)
    text, error = await asyncio.to_thread(transcribe.transcribe, path, hints)
    log.info("transcript for %s: %s", session.name, error or repr(text))
    plugin.status(lastClip=f"{session.name}, {error or 'heard'}")
    taken, delivery_error, checked = None, None, filters.Outcome(text=text or "")
    if text and deliver_now and plugin.delivers():
        chosen = route or plugin.route()
        checked = await _filtered(session, text, chosen, "spoken")
        if checked.delivered:
            taken, delivery_error = await asyncio.to_thread(
                deliver.deliver, session, checked.text, chosen)
            log.info("delivery to %s: %s", session.name, delivery_error or f"{taken} took it")
            push.spoke_to(session_id)
        else:
            delivery_error = checked.reason
            log.info("%s refused a clip for %s: %s", checked.stopped_by, session.name, checked.reason)
    return {
        "path": str(path),
        "bytes": len(body),
        "received_at": time.time(),
        # What utt heard, not what the chain made of it. The notes say what was changed.
        "transcript": text,
        "transcript_error": error,
        "delivered": taken is not None,
        "delivered_by": taken,
        "delivery_error": delivery_error,
        "notes": checked.notes,
        "stopped_by": checked.stopped_by,
    }


IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".heic", ".gif", ".webp"}


@app.post("/sessions/{session_id}/image", dependencies=[Depends(require_token)])
async def add_image(session_id: str, file: UploadFile) -> dict:
    """Take a picture from the phone and keep it, so a message can name where it is.

    Answers with the path, which is the only thing the phone does with it: saying something with
    an image attached is saying the words and naming the file, and the session reads it itself.
    """
    _session_or_404(session_id)
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in IMAGE_SUFFIXES:
        raise HTTPException(status_code=415, detail=f"{suffix or 'that'} is not an image")
    body = await file.read()
    if len(body) > config.MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="that picture is too big to send")
    if not body:
        raise HTTPException(status_code=400, detail="that picture is empty")
    path = config.image_dir(session_id) / f"{int(time.time())}-{uuid.uuid4().hex[:8]}{suffix}"
    path.write_bytes(body)
    log.info("kept a %d KB image for %s at %s", len(body) // 1024, session_id, path.name)
    return {"path": str(path)}


@app.post("/sessions/{session_id}/say", dependencies=[Depends(require_token)])
async def say(
    session_id: str,
    text: str = Body(embed=True),
    images: Annotated[list[str] | None, Body(embed=True)] = None,
    route: str | None = Query(default=None, description="auto, keyboard or socket"),
) -> dict:
    """Put words into a session. The other half of an upload the person asked to read first."""
    session = await _live_session(session_id)
    chosen = route or plugin.route()
    kept = _kept_images(session_id, images or [])
    # The words are filtered before the attachments are named: a replacement list is aimed at
    # what a person said, and a path is not something they said.
    checked = await _filtered(session, text, chosen, "typed", kept)
    taken, error = None, checked.reason or None
    if checked.delivered:
        said = deliver.with_images(checked.text, kept)
        taken, error = await asyncio.to_thread(deliver.deliver, session, said, chosen)
        log.info("delivery to %s: %s", session.name, error or f"{taken} took it")
        push.spoke_to(session_id)
    else:
        log.info("%s refused a prompt for %s: %s", checked.stopped_by, session.name, checked.reason)
    return {"delivered": taken is not None, "delivered_by": taken, "delivery_error": error,
            "notes": checked.notes, "stopped_by": checked.stopped_by}


def _kept_images(session_id: str, wanted: list[str]) -> list[str]:
    """Only files this session's own image folder holds.

    The phone names a path it was given rather than one it chose, and this is what keeps that
    true: without it, "say this and read that file" would point a session at anything on the Mac.
    """
    folder = config.image_dir(session_id).resolve()
    kept = []
    for path in wanted:
        found = Path(path).resolve()
        if found.parent == folder and found.is_file():
            kept.append(str(found))
        else:
            log.warning("refused an image outside %s's own folder: %s", session_id, path)
    return kept


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
