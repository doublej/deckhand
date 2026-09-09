"""HTTP surface. LAN-only, one shared token, no state of its own beyond stored audio."""

from __future__ import annotations

import asyncio
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Body, Depends, FastAPI, Header, HTTPException, Query, UploadFile

from . import (
    __version__,
    config,
    deliver,
    plugin,
    push,
    sessions,
    summarize,
    transcribe,
    transcripts,
)
from .log import log

AUDIO_SUFFIXES = {".m4a", ".caf", ".wav", ".mp3", ".aac", ".mp4", ".ogg", ".flac", ".webm"}


def require_token(x_deckhand_token: str = Header(default="")) -> None:
    if x_deckhand_token != config.token():
        raise HTTPException(status_code=401, detail="bad token")


@asynccontextmanager
async def lifespan(_: FastAPI):
    """Deckhand's page inside utt, put there fresh on every start: it is what survives utt
    being reinstalled or the folder being cleared, and it costs one file write."""
    plugin.install()
    watchers = [asyncio.create_task(plugin.watch()), asyncio.create_task(push.watch())]
    yield
    for watcher in watchers:
        watcher.cancel()


app = FastAPI(title="Deckhand", version=__version__, lifespan=lifespan)


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
    return {"sessions": [s.to_json() for s in live], "iterm": status}


@app.get("/sessions/{session_id}/summary", dependencies=[Depends(require_token)])
async def session_summary(session_id: str) -> dict:
    """What this session has been doing since the person last spoke to it."""
    session = await _live_session(session_id)
    activity = await asyncio.to_thread(transcripts.activity_since_last_user, session_id)
    text, error = await summarize.summarize(session_id, activity)
    log.info("summary for %s: %s", session.name, error or f"{len(text or '')} chars")
    return {"summary": text, "error": error}


@app.get("/sessions/{session_id}/turns", dependencies=[Depends(require_token)])
def session_turns(session_id: str, limit: int = Query(default=8, ge=1, le=50)) -> dict:
    _session_or_404(session_id)
    return {"turns": [t.to_json() for t in transcripts.read_turns(session_id, limit)]}


@app.post("/sessions/{session_id}/focus", dependencies=[Depends(require_token)])
def focus_session(session_id: str) -> dict:
    session = _session_or_404(session_id)
    if not sessions.focus(session):
        raise HTTPException(status_code=409, detail="session has no iTerm pane")
    return {"focused": True}


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
    taken, delivery_error = None, None
    if text and deliver_now and plugin.delivers():
        taken, delivery_error = await asyncio.to_thread(
            deliver.deliver, session, text, route or plugin.route())
        log.info("delivery to %s: %s", session.name, delivery_error or f"{taken} took it")
        push.spoke_to(session_id)
    return {
        "path": str(path),
        "bytes": len(body),
        "received_at": time.time(),
        "transcript": text,
        "transcript_error": error,
        "delivered": taken is not None,
        "delivered_by": taken,
        "delivery_error": delivery_error,
    }


@app.post("/sessions/{session_id}/say", dependencies=[Depends(require_token)])
async def say(
    session_id: str,
    text: str = Body(embed=True),
    route: str | None = Query(default=None, description="auto, keyboard or socket"),
) -> dict:
    """Put words into a session. The other half of an upload the person asked to read first."""
    session = await _live_session(session_id)
    taken, error = await asyncio.to_thread(
        deliver.deliver, session, text, route or plugin.route())
    log.info("delivery to %s: %s", session.name, error or f"{taken} took it")
    push.spoke_to(session_id)
    return {"delivered": taken is not None, "delivered_by": taken, "delivery_error": error}


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
