"""Putting something into a session: a spoken clip, a picture, or words already read.

Everything here writes; `reading/` is the other half. Split out of `app.py` when that file went
past its line budget, and this is the seam that makes sense — these three endpoints are the only
ones that hand a prompt to `filters` before `deliver` ever sees it, and `_filtered` has no other
caller.

A router rather than more `@app.post`, the way `filters/routes.py` does it: no token check of its
own, because `app.py` mounts this with the same dependency every other route carries.

The two session lookups live here because the speaking path is the only one that needs the
off-the-loop variant, and a second module holding fifteen lines of `raise 404` would be worse
than one import in `app.py`.
"""

from __future__ import annotations

import asyncio
import time
import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Body, HTTPException, Query, UploadFile

from . import config, deliver, filters, plugin, push, sessions, transcribe
from .log import log

router = APIRouter(tags=["saying"])

AUDIO_SUFFIXES = {".m4a", ".caf", ".wav", ".mp3", ".aac", ".mp4", ".ogg", ".flac", ".webm"}
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".heic", ".gif", ".webp"}


def session_or_404(session_id: str) -> sessions.Session:
    # ponytail: every lookup re-lists sessions (one `it2` call, ~0.5 s). Cache it if the
    # phone ever polls harder than every few seconds.
    for s in sessions.live_sessions():
        if s.session_id == session_id:
            return s
    raise HTTPException(status_code=404, detail="no live session with that id")


async def live_session(session_id: str) -> sessions.Session:
    """Same lookup, off the event loop: listing shells out and would block every other request."""
    return await asyncio.to_thread(session_or_404, session_id)


async def _filtered(
    session: sessions.Session, text: str, route: str, source: str, images: list[str] | None = None
) -> filters.Outcome:
    """What the chain makes of the words, before the session is ever told about them."""
    return await filters.run(filters.Prompt(
        text=text, session_id=session.session_id, session_name=session.name, cwd=session.cwd,
        route=route, source=source, images=images or []))


@router.post("/sessions/{session_id}/audio", status_code=201)
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
    session = await live_session(session_id)
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
    elif text:
        # The card now shows the whole text with an Edit button, so what it shows is what the
        # person believes they are sending: the chain runs here too and the words come back as
        # `prepared`. Without this you dictate "deck hand", read "deck hand", press Send and the
        # session receives "deckhand" — the swap was right and the card was lying.
        #
        # ponytail: the chain therefore runs twice for a clip that is read first — here, and
        # again in `/say` when Send puts the words in. Free for word replacement, which is
        # idempotent, and wrong for a translate or enhance filter, which would run on its own
        # output. The fix when one of those lands is a flag on `/say` saying these words have
        # already been through the chain. Nothing needs it yet, so nothing has it.
        checked = await _filtered(session, text, route or plugin.route(), "spoken")
    return {
        "path": str(path),
        "bytes": len(body),
        "received_at": time.time(),
        # What utt heard, not what the chain made of it. The notes say what was changed.
        "transcript": text,
        "transcript_error": error,
        # What the chain made of it, and null when it left the words alone — so the card shows
        # the transcript itself rather than a second copy of it under another name.
        "prepared": checked.text if text and checked.text != text else None,
        "delivered": taken is not None,
        "delivered_by": taken,
        "delivery_error": delivery_error,
        "notes": checked.notes,
        "stopped_by": checked.stopped_by,
    }


@router.post("/sessions/{session_id}/image")
async def add_image(session_id: str, file: UploadFile) -> dict:
    """Take a picture from the phone and keep it, so a message can name where it is.

    Answers with the path, which is the only thing the phone does with it: saying something with
    an image attached is saying the words and naming the file, and the session reads it itself.
    """
    session_or_404(session_id)
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


@router.post("/sessions/{session_id}/say")
async def say(
    session_id: str,
    text: str = Body(embed=True),
    images: Annotated[list[str] | None, Body(embed=True)] = None,
    route: str | None = Query(default=None, description="auto, keyboard or socket"),
    prepared: bool = Query(
        default=False,
        description="true when these words were already shown on the card, chain included",
    ),
) -> dict:
    """Put words into a session. The other half of an upload the person asked to read first."""
    session = await live_session(session_id)
    chosen = route or plugin.route()
    kept = _kept_images(session_id, images or [])
    # Words the person has already read on the card are the words, and the chain does not get a
    # second go at them. Not an optimisation: the first filter that rewrites rather than swaps —
    # prompt crafting — is not idempotent, and running it on its own output rewrites a prompt
    # twice. It also contradicts the card to change anything after somebody has approved it.
    # The words are filtered before the attachments are named: a replacement list is aimed at
    # what a person said, and a path is not something they said.
    checked = (filters.Outcome(text=text) if prepared
               else await _filtered(session, text, chosen, "typed", kept))
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
