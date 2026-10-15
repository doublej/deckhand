"""`/health`, `/transcribe`, and the CORS on exactly those two. See `__init__.py`."""

from __future__ import annotations

import asyncio
import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response, UploadFile

from .. import __version__, config, pairing, presence, saying, sessions, transcribe
from ..log import log
from ..settings import aliases

router = APIRouter()

#: The pages that may call `OPEN`: the Jaimes chat, live and on the dev server.
ORIGINS = {"https://wallgen.birdsonpaper.com", "http://127.0.0.1:4131"}
OPEN = {"/health", "/transcribe"}


async def cors(request: Request, call_next) -> Response:
    """CORS for `ORIGINS` on `OPEN`, answered here so a preflight never meets a token check."""
    origin = request.headers.get("origin", "")
    if request.url.path not in OPEN or origin not in ORIGINS:
        return await call_next(request)
    allowed = {"Access-Control-Allow-Origin": origin, "Vary": "Origin"}
    if request.method == "OPTIONS" and "access-control-request-method" in request.headers:
        allowed |= {"Access-Control-Allow-Methods": "GET, POST",
                    "Access-Control-Allow-Headers": config.TOKEN_HEADER,
                    "Access-Control-Max-Age": "600"}
        if request.headers.get("access-control-request-private-network") == "true":
            allowed["Access-Control-Allow-Private-Network"] = "true"
        return Response(status_code=204, headers=allowed)
    answer = await call_next(request)
    answer.headers.update(allowed)
    return answer


def require_transcribe(x_deckhand_token: str = Header(default="")) -> None:
    if not pairing.allows_transcribe(x_deckhand_token):
        raise HTTPException(status_code=401, detail="bad token")


@router.get("/health")
def health() -> dict:
    """Open on purpose: the app pings it to tell 'wrong host' from 'wrong token'."""
    return {
        "name": "deckhand",
        "version": __version__,
        "host": config.base_url(),
        # So the phone can turn a session's `localhost:5173` into something it can actually open.
        "lan": config.lan_address(),
        "id": config.machine_id(), "web": config.web_url(), "remote": config.remote_url(),
        "iterm": sessions.pane_status(), "codex": sessions.codex.answered(),
        # Who has this Mac. Unauthenticated like the rest of /health, and deliberately so: it
        # says whether a person is at the keyboard, never what they are doing.
        "presence": (person := presence.state()),
        # utt's cover reads this, the one route with no token; null keeps it down.
        "cover": presence.cover(person),
        # Whether `POST /transcribe` could hear a browser's clip right now.
        "transcribe": transcribe.ready(),
    }


@router.post("/transcribe", dependencies=[Depends(require_transcribe)])
async def transcribe_clip(file: UploadFile) -> dict:
    """A clip in, its words out. No session, no delivery, and the clip is not kept."""
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in saying.AUDIO_SUFFIXES:
        raise HTTPException(status_code=415, detail=f"unsupported audio type {suffix!r}")
    body = await file.read(config.MAX_UPLOAD_BYTES + 1)
    if len(body) > config.MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="clip larger than 32 MB")
    if not body:
        raise HTTPException(status_code=400, detail="empty clip")
    with tempfile.TemporaryDirectory(prefix="deckhand-transcribe-") as folder:
        clip = Path(folder) / f"clip{suffix}"
        clip.write_bytes(body)
        heard = await asyncio.to_thread(transcribe.transcribe, clip, aliases.spoken())
    log.info("browser clip, %d bytes: %s", len(body), heard.error or "heard")
    if heard.error or not heard.text:
        raise HTTPException(status_code=422, detail=heard.error or "nothing heard")
    return {"text": aliases.applied(heard.text)[0]}
