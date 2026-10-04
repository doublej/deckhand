"""The manager's own front door. Four routes, and only one of them changes anything.

The panel is a poll, not a stream: `GET /manager?since=` hands back every entry after the id the
phone last saw, and `working` is what makes it poll fast. There is no socket to hold open to a
phone in a pocket, and there is no push that could carry a sentence being written — so the file
is the channel and the cursor is the whole protocol.

Speaking to the manager answers the moment the words are written down, never when the model is
done. The panel draws what was said immediately and fills in the answer as the poll brings it,
which is also why a run taking a minute is not a failed request.
"""

from __future__ import annotations

import asyncio
import time
import uuid
from pathlib import Path

from fastapi import APIRouter, Body, HTTPException, Query, UploadFile

from .. import config, plugin, sessions, transcribe
from ..log import log
from ..settings import aliases
from . import agent, talk

router = APIRouter(tags=["manager"])

#: What the phone may hand over, matching the recorder it records with.
AUDIO_SUFFIXES = (".m4a", ".wav", ".caf", ".mp3", ".aac")


@router.get("/manager")
def read_manager(
    since: int = Query(default=0, ge=0, description="the last entry id this phone has seen"),
) -> dict:
    """What has been said, after the id the phone already has, and whether more is coming.

    `partial` and `doing` are the run in flight as far as it has got, so the panel can draw the
    sentence being written and the tool being called rather than a dot until a block is done.
    Asking is also what tells the daemon the panel is open — see `agent.watched`.
    """
    agent.seen()
    return {
        "entries": talk.entries(since),
        "newest": talk.newest(),
        "working": agent.working(),
        **agent.progress(),
    }


@router.post("/manager/away", status_code=204)
def leave_manager() -> None:
    """The panel went off screen. Everything the manager says from here is pushed."""
    agent.away()


@router.post("/manager/say", status_code=201)
def say_to_manager(text: str = Body(embed=True)) -> dict:
    """Say something to the manager. Answers with the entry, not with the reply."""
    entry = agent.ask(text)
    if not entry:
        raise HTTPException(status_code=400, detail="nothing to say")
    return {"entry": entry, "working": True}


@router.post("/manager/audio", status_code=201)
async def speak_to_manager(
    file: UploadFile,
    say: bool = Query(default=True, description="false to transcribe only, for the review card"),
) -> dict:
    """A clip for the manager: utt turns it into text and the manager is asked with it.

    The hints are every live session's name, because the sentence this is almost always going to
    be is "tell <a session> to …" — the one word in it that must not come back wrong is the name,
    and this Mac knows all of them before the clip is even recorded.
    """
    suffix = Path(file.filename or "clip.m4a").suffix.lower()
    if suffix not in AUDIO_SUFFIXES:
        raise HTTPException(status_code=415, detail=f"unsupported audio type {suffix!r}")
    body = await file.read(config.MAX_UPLOAD_BYTES + 1)
    if len(body) > config.MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="clip larger than 32 MB")
    if not body:
        raise HTTPException(status_code=400, detail="empty clip")
    stamp = time.strftime("%Y%m%dT%H%M%S", time.gmtime())
    path = config.audio_dir("manager") / f"{stamp}-{uuid.uuid4().hex[:8]}{suffix}"
    path.write_bytes(body)
    heard = await asyncio.to_thread(transcribe.transcribe, path, _hints())
    log.info("clip for the manager: %s", heard.error or repr(heard.text))
    plugin.status(lastClip=f"the manager, {heard.error or 'heard'}")
    if heard.error or not (heard.text or "").strip():
        return {"text": heard.text, "error": heard.error, "said": False}
    # The same Mac-wide aliases a session's clip gets, and this is the half of them a per-terminal
    # word list could never reach: the manager runs no filter chain. `notes` is what the card
    # draws under the words, so a swap is never silent here either.
    spoken, swaps = aliases.applied(heard.text)
    entry = agent.ask(spoken) if say else {}
    return {"text": spoken, "error": None, "said": bool(entry), "entry": entry or None,
            "notes": swaps}


@router.post("/manager/clear")
def clear_manager() -> dict:
    """Start over. The entries go and so does the thread behind them — see `talk.clear`."""
    agent.clear()
    return {"entries": [], "newest": 0, "working": False}


def _hints() -> list[str]:
    words = {"deckhand", "manager", "session", "slip", "pane", "orders", *aliases.spoken()}
    for session in sessions.live_sessions():
        words.update(session.name.replace("-", " ").split())
        words.update(part for part in Path(session.cwd).parts[-2:] if part not in ("/", "Users"))
    return sorted(word for word in words if len(word) > 2)
