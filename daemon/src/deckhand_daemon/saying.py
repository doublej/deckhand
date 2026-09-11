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
import json
import time
import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Body, HTTPException, Query, UploadFile

from . import config, deliver, filters, orders, plugin, push, sessions, transcribe
from .log import log, took
from .settings import aliases

router = APIRouter(tags=["saying"])

AUDIO_SUFFIXES = {".m4a", ".caf", ".wav", ".mp3", ".aac", ".mp4", ".ogg", ".flac", ".webm"}
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".heic", ".gif", ".webp"}


def session_or_404(session_id: str) -> sessions.Session:
    # ponytail: every lookup re-lists sessions (one `it2` call, ~0.5 s). Cache it if the
    # phone ever polls harder than every few seconds.
    live = sessions.live_sessions()
    for s in live:
        if s.session_id == session_id:
            return s
    # The one lookup that is allowed to answer with a session other than the one asked for. A
    # `/clear` retires the conversation and keeps everything the phone can see — the pane, the
    # name, the socket, the process — so a page opened before it is addressing an id that is
    # gone while showing a session that is plainly still there. The person means the session on
    # their screen, and this is the same pid in the same pane: it is theirs.
    if (now := sessions.succeeded_by(session_id)) and (
        found := next((s for s in live if s.session_id == now), None)
    ):
        log.info("%s was cleared — %s answers for it now", session_id[:8], found.name)
        return found
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


def _with_orders(session: sessions.Session, text: str) -> str:
    """The words, with this session's standing orders in front. Unchanged when it has none.

    After the chain and never before it. A filter judges what the *person* said — a word swap is
    aimed at what they dictated, a word count is a count of their words, and prompt crafting would
    happily rewrite the orders into a version of themselves. Putting them in afterwards keeps every
    filter looking at the same thing it was written to look at.

    Here rather than in `deliver`, which is the other place both doors meet, because `deliver` also
    carries the idle check and a slip's answer — neither of which is the person speaking, and the
    person's standing orders have no business riding on a message they did not send. These two call
    sites are the two doors a prompt from the phone comes through, and that is exactly the set.

    Not applied on the `?deliver=false` path, so the review card still shows what the person said
    rather than what the session will read. The card is editable, and orders that appeared in it
    would be orders somebody could edit by accident from the wrong screen — they have a pane. What
    the session was actually sent is in the transcript, which Deckhand never rewrites.
    """
    return orders.carry(session.session_id, text)


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
    seconds: float | None = Query(
        default=None,
        description="how long the clip runs, as the phone measured it — recorded, never used",
    ),
) -> dict:
    """Speaking to a session: the clip lands on the Mac and utt turns it into text."""
    ms: dict[str, float] = {}
    whole = time.perf_counter()
    with took(ms, "session"):
        session = await live_session(session_id)
    suffix = Path(file.filename or "clip.m4a").suffix.lower()
    if suffix not in AUDIO_SUFFIXES:
        raise HTTPException(status_code=415, detail=f"unsupported audio type {suffix!r}")
    with took(ms, "read"):
        body = await file.read(config.MAX_UPLOAD_BYTES + 1)
    if len(body) > config.MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="clip larger than 32 MB")
    if not body:
        raise HTTPException(status_code=400, detail="empty clip")
    stamp = time.strftime("%Y%m%dT%H%M%S", time.gmtime())
    path = config.audio_dir(session_id) / f"{stamp}-{uuid.uuid4().hex[:8]}{suffix}"
    with took(ms, "write"):
        path.write_bytes(body)
    log.info("clip for %s: %d bytes", session.name, len(body))
    with took(ms, "hints"):
        hints = transcribe.hints_for(session.name, session.cwd)
    heard = await asyncio.to_thread(transcribe.transcribe, path, hints)
    ms.update(heard.stages)
    log.info("transcript for %s: %s", session.name, heard.error or repr(heard.text))
    plugin.status(lastClip=f"{session.name}, {heard.error or 'heard'}")
    # Before the chain and before `heard.text` is handed anywhere, so the card, the session and
    # the manager all read the one sentence. `heard.text` itself is left as utt said it — it is
    # what `transcript` answers with, and `Rewrites` on the phone diffs utt's `raw` against it to
    # name which of utt's stages changed something. Swapping it here would put this Mac's own
    # word list on that line under utt's name, which is the one lie that view exists to avoid.
    spoken, swaps = aliases.applied(heard.text) if heard.text else (heard.text, [])
    taken, delivery_error, checked = await _handled(session, spoken, route, deliver_now, ms)
    # In front of whatever the chain said, because it happened in front of it. The card draws
    # these as the quiet line under the words: there is no size of card on which it is acceptable
    # to show somebody a word they did not say without saying so.
    checked.notes[:0] = swaps
    ms["total"] = round((time.perf_counter() - whole) * 1000, 1)
    _record(session, path, len(body), seconds, heard, taken is not None, ms)
    return _receipt(path, body, heard, taken, delivery_error, checked, ms)


async def _handled(
    session: sessions.Session,
    text: str | None,
    route: str | None,
    deliver_now: bool,
    ms: dict[str, float],
) -> tuple[str | None, str | None, filters.Outcome]:
    """The chain, and the delivery when there is one to make."""
    taken, delivery_error, checked = None, None, filters.Outcome(text=text or "")
    if not text:
        return taken, delivery_error, checked
    chosen = route or plugin.route()
    if deliver_now and plugin.delivers():
        with took(ms, "filters"):
            checked = await _filtered(session, text, chosen, "spoken")
        if checked.delivered:
            with took(ms, "deliver"):
                taken, delivery_error = await asyncio.to_thread(
                    deliver.deliver, session, _with_orders(session, checked.text), chosen)
            log.info("delivery to %s: %s", session.name, delivery_error or f"{taken} took it")
            # Ending a card is an APNs round trip with a ten-second timeout on it, so it goes
            # off the event loop the same way the delivery above it does.
            await asyncio.to_thread(push.spoke_to, session.session_id)
        else:
            delivery_error = checked.reason
            log.info("%s refused a clip for %s: %s",
                     checked.stopped_by, session.name, checked.reason)
        return taken, delivery_error, checked
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
    with took(ms, "filters"):
        checked = await _filtered(session, text, chosen, "spoken")
    return taken, delivery_error, checked


def _receipt(
    path: Path,
    body: bytes,
    heard: transcribe.Heard,
    taken: str | None,
    delivery_error: str | None,
    checked: filters.Outcome,
    ms: dict[str, float],
) -> dict:
    """What the phone is handed back. Every key that was here before still means what it did."""
    text = heard.text
    reply = {
        "path": str(path),
        "bytes": len(body),
        "received_at": time.time(),
        # What utt handed back, which is not quite what it heard: the jobs lane answers with
        # `text`, `error` and `finishedAt` and nothing else, so the raw transcript never crosses
        # it. utt's own cleanup stage has already run by then, and so has any other extension
        # declaring `filtersTranscripts`. This is the earliest form Deckhand can see; the notes
        # below say what *Deckhand's* own chain changed, which is a different question.
        "transcript": text,
        "transcript_error": heard.error,
        # What the chain made of it, and null when it left the words alone — so the card shows
        # the transcript itself rather than a second copy of it under another name.
        "prepared": checked.text if text and checked.text != text else None,
        "delivered": taken is not None,
        "delivered_by": taken,
        "delivery_error": delivery_error,
        "notes": checked.notes,
        "stopped_by": checked.stopped_by,
        # Milliseconds per stage, in the order they ran, `total` last. A list rather than an
        # object on purpose: the phone decodes with `convertFromSnakeCase`, which rewrites
        # dictionary *keys* as happily as struct ones, and a stage name is data.
        "timings": _staged(ms, heard),
    }
    # Whatever utt said that this daemon has no name for, verbatim. `raw`, `stages` and
    # `cleanupSkipped` arrive this way the day utt sends them, with no change here.
    #
    # `timings` is the one key both sides now use, and utt's is not a rival to ours — it is the
    # inside of our `utt` span, and `_staged` has already nested it there. Any *other* collision
    # is utt taking a name we answer with, and that is worth a line in the log: the old
    # `setdefault` dropped it in silence, which is the failure nobody would ever notice.
    for key, value in heard.extra.items():
        if key == "timings":
            continue
        if key in reply:
            log.warning("utt sent a %r of its own; kept this daemon's and dropped utt's", key)
            continue
        reply[key] = value
    return reply


def _staged(ms: dict[str, float], heard: transcribe.Heard) -> list[dict]:
    """This daemon's stages, with utt's own broken out inside the one that is utt's.

    Nested rather than flattened, because they answer different questions: the top level is
    where the time went across the whole path, and the inside of `utt` is where it went within
    utt. A utt that measures nothing leaves the single opaque number that was always there.
    """
    stages = []
    for name, spent in ms.items():
        stage = {"name": name, "ms": spent}
        if name == "utt":
            parts = transcribe.inside(spent, heard)
            if parts:
                stage["inside"] = parts
        stages.append(stage)
    return stages


def _record(
    session: sessions.Session,
    path: Path,
    size: int,
    seconds: float | None,
    heard: transcribe.Heard,
    went: bool,
    ms: dict[str, float],
) -> None:
    """One line per clip in `timings.jsonl`, so two runs can be compared afterwards.

    Beside the state the daemon already keeps, appended and never rewritten: a speed or
    compression experiment wants the same keys from a fortnight ago as from this morning.
    `seconds` is the phone's own measure of the clip — nothing on this side opens the audio.
    """
    line = {
        "at": round(time.time(), 3),
        "clip": path.name,
        "session_id": session.session_id,
        "session": session.name,
        "bytes": size,
        "seconds": seconds,
        "chars": len(heard.text or ""),
        "error": heard.error,
        "delivered": went,
        "ms": ms,
        # Everything utt said for itself, verbatim and in one place: `duration` (its own count of
        # the audio, against the phone's `seconds` above), `timings`, `stages`, `raw`. Empty on
        # every utt shipped today, and a line that reads the same either way.
        "utt": heard.extra,
    }
    try:
        with (config.data_dir() / "timings.jsonl").open("a") as jsonl:
            jsonl.write(json.dumps(line) + "\n")
    except OSError as error:
        log.warning("could not record the timings for %s: %s", path.name, error)


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
        said = deliver.with_images(_with_orders(session, checked.text), kept)
        taken, error = await asyncio.to_thread(deliver.deliver, session, said, chosen)
        log.info("delivery to %s: %s", session.name, error or f"{taken} took it")
        await asyncio.to_thread(push.spoke_to, session_id)
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
