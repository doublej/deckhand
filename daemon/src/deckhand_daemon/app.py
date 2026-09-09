"""HTTP surface. LAN-only, one shared token, no state of its own beyond stored audio."""

from __future__ import annotations

import time
import uuid
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException, Query, UploadFile

from . import __version__, config, sessions, transcripts

AUDIO_SUFFIXES = {".m4a", ".caf", ".wav", ".mp3", ".aac", ".mp4", ".ogg", ".flac", ".webm"}


def require_token(x_deckhand_token: str = Header(default="")) -> None:
    if x_deckhand_token != config.token():
        raise HTTPException(status_code=401, detail="bad token")


app = FastAPI(title="Deckhand", version=__version__)


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
    return {"name": "deckhand", "version": __version__, "host": config.base_url()}


@app.get("/sessions", dependencies=[Depends(require_token)])
def list_sessions() -> dict:
    return {"sessions": [s.to_json() for s in sessions.live_sessions()]}


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
async def upload_audio(session_id: str, file: UploadFile) -> dict:
    """Phase 1 of speaking to a session: the clip lands on the Mac, transcript stays empty."""
    _session_or_404(session_id)
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
    return {
        "path": str(path),
        "bytes": len(body),
        "received_at": time.time(),
        "transcript": None,  # filled in phase 2, on the Mac
    }


def main() -> None:
    import uvicorn

    print(f"deckhand {config.base_url()}  token: {config.token()}", flush=True)
    uvicorn.run(app, host="0.0.0.0", port=config.PORT, log_level="info")
