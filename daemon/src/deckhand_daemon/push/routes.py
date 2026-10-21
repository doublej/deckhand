"""The routes that feed the Lock Screen: the phone's tokens, an agent calling for you, and a
caller on this Mac asking you something with no session behind it (`callbacks.py`), and an agent
asking you to end sessions (`end_requests.py`).

Out of `app.py` when that file reached its line budget; they belong with the push they feed. A
module of their own rather than `push/__init__.py`, because `/notify` looks a session up through
`saying`, and `saying` imports `push`.
"""

from __future__ import annotations

import asyncio
from typing import Annotated

from fastapi import APIRouter, Body, Header, HTTPException, Request

from .. import fleet, push, saying, sessions
from . import callbacks, end_requests

router = APIRouter(tags=["push"])


@router.post("/live/token")
def live_token(token: str = Body(embed=True), kind: str = Body(embed=True),
               session: str = Body(embed=True, default="")) -> dict:
    """The phone hands over what the Mac needs to reach its Lock Screen.

    Sent on every launch, because these change without warning and a stale one is a card that
    silently stops updating.

    One card is one session, so an *activity* token says which one it addresses. A phone that
    sends none is a build from before that — taken rather than refused, and dropped, because a
    token that cannot say which card it is could only ever end the wrong one.

    A *device* token is the app's own, for plain notifications — the manager's messages, pushed
    while its panel is not on screen, and a decision's one alert. One per phone, like *start*.
    """
    if kind not in ("activity", "start", "device"):
        raise HTTPException(status_code=400, detail=f"no such token kind {kind!r}")
    push.remember(token, kind, session)
    return {"registered": kind}


@router.post("/sessions/{session_id}/notify")
def ask_for_attention(session_id: str, line: Annotated[str, Body(embed=True)]) -> dict:
    """An agent asking for the person outright, in its own words.

    The only thing on the Lock Screen a session raises for itself — everything else there is the
    Mac noticing something. So it is the one that a folder can refuse outright rather than merely
    keep quiet about, and the refusal comes back rather than being swallowed: an agent that
    thinks it has your attention and has not is worse than one that knows it has not.

    Empty words are refused here rather than pushed as a blank card. There is no useful default:
    the whole point of this route over the ones that fire on their own is that somebody had
    something specific to say. A session with a decision already waiting gets its card moved on
    quietly instead: that decision has had its one alert.
    """
    session = saying.session_or_404(session_id)
    said = " ".join(line.split())
    if not said:
        raise HTTPException(status_code=400, detail="nothing to say")
    if error := push.called(session, said):
        return {"pushed": False, "why": error}
    return {"pushed": True}


@router.post("/notify", status_code=202)
async def notify(request: Request) -> dict:
    """A Lock Screen card with two buttons and no session, whose tap this Mac answers to a loopback
    caller. One alert instead, on a phone that cannot take a card yet.

    `{title, line, actions: [{id, label}], callback: {url, body}}`, 4 KB at most. The action ids
    name a category the app already has (`approve`, `deny`); `callback.url` is http on
    127.0.0.1 or localhost only; every `"$action"` value in `callback.body` becomes the tapped
    id; the two labels are the card's buttons. 202 `{id}` once APNs took it, 502 when APNs
    refused, 503 when this Mac cannot send.
    """
    return {"id": await asyncio.to_thread(callbacks.notify, await request.body())}


@router.post("/notify/{notify_id}/answer")
def answer_notify(notify_id: str, proof: Annotated[dict | None, Body(embed=True)] = None,
                  x_deckhand_token: str = Header(default="")) -> dict:
    """The phone's tap, signed like a decision's answer with the session `notify` and the notify
    id as its slip, and the action id as its value. Calls back once: a second tap is answered
    from the first. 410 once the notify is a day old, 502 when the caller did not take it.
    """
    return callbacks.answered(notify_id, proof, x_deckhand_token)


@router.post("/end-requests", status_code=202)
async def ask_to_end(wanted: Annotated[list[str], Body(alias="sessions", embed=True)],
                     why: Annotated[str, Body(embed=True)],
                     asker: Annotated[str, Body(embed=True)] = "") -> dict:
    """An agent asking the person to end sessions, on any machine, by name or id. Ends nothing:
    the person's signed Allow on the alert does (`end_requests.py`), through `/notify/{id}/answer`.

    Resolved against a fresh listing of every machine, paneless sessions included, and refused
    with 400 unless each names exactly one Claude session with a process. `asker` is who the
    alert says is asking. 202 `{id, sessions}`; 502 when APNs refused, 503 when this Mac cannot send.
    """
    local = [s.to_json() for s in await asyncio.to_thread(sessions.live_sessions, False)]
    rows = await fleet.listings(local)
    return await asyncio.to_thread(end_requests.asked, wanted, why, asker, rows)
