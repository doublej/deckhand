"""The two routes that feed the Lock Screen: the phone's tokens, and an agent calling for you.

Out of `app.py` when that file reached its line budget; they belong with the push they feed. A
module of their own rather than `push/__init__.py`, because `/notify` looks a session up through
`saying`, and `saying` imports `push`.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Body, HTTPException

from .. import push, saying

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
