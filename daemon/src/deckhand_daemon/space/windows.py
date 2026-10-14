"""This Mac's windows, passed through from `deckhand-windows` on `127.0.0.1:4181`.

The helper is a Swift process from `deckhand-xr/windows/` — ScreenCaptureKit is not something to
reach from Python — and binds loopback only, so this is the one door to it, behind the token.
Each route answers what the helper answered; when nothing is listening the answer is a 503 saying
so, which the headset shows rather than an empty list that looks like a Mac with no windows.

The stream is relayed chunk by chunk, never read whole: it is `multipart/x-mixed-replace` and has
no end. When the headset goes away the relay closes its side to the helper, which is how the
helper knows to stop capturing.
"""

from __future__ import annotations

import json
from typing import Annotated, Literal

import httpx
from fastapi import APIRouter, Body, HTTPException, Request, Response
from fastapi.responses import StreamingResponse
from starlette.background import BackgroundTask

from .. import presence

HELPER = "http://127.0.0.1:4181"
TIMEOUT = 5.0

router = APIRouter(tags=["windows"])


def _down(error: Exception) -> HTTPException:
    return HTTPException(
        status_code=503,
        detail=f"deckhand-windows is not answering on {HELPER} ({error.__class__.__name__}) — "
        "start it from ~/dev/multi-stack/deckhand-xr/windows",
    )


def _refused(answered: httpx.Response, body: bytes) -> HTTPException:
    # The helper's errors are `{"detail": …}` already; passing the body on whole wraps it twice.
    if answered.headers.get("content-type", "").startswith("application/json"):
        said = str(json.loads(body).get("detail", ""))[:200]
    else:
        said = body.decode(errors="replace").strip()[:200]
    return HTTPException(
        status_code=answered.status_code,
        detail=said or f"deckhand-windows answered {answered.status_code}",
    )


async def _get(path: str, params=None) -> httpx.Response:
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            answered = await client.get(f"{HELPER}{path}", params=params)
    except httpx.HTTPError as error:
        raise _down(error) from error
    if answered.status_code >= 400:
        raise _refused(answered, answered.content)
    return answered


async def listed() -> list[dict]:
    """`[{id, app, title, w, h}]`, or a 503 when the helper is not running."""
    return (await _get("/windows")).json()


@router.get("/windows")
async def list_windows() -> list[dict]:
    return await listed()


@router.get("/windows/{window_id}/frame")
async def window_frame(window_id: int, request: Request) -> Response:
    """One JPEG. The query (`whole=1`, …) is the helper's, as on the streams."""
    answered = await _get(f"/windows/{window_id}/frame", request.query_params)
    return Response(answered.content, media_type="image/jpeg")


@router.post("/windows/{window_id}/input", status_code=204)
async def window_input(window_id: int, sent: Annotated[dict, Body()]) -> None:
    """A click, drag, scroll or keystroke for that window, as the real cursor and keyboard.

    Headset only, and on purpose not an agent tool: this is the person's own hand on the Mac,
    the keyboard route's authority, and an agent driving it would be speaking as them.
    """
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            answered = await client.post(f"{HELPER}/windows/{window_id}/input", json=sent)
    except httpx.HTTPError as error:
        raise _down(error) from error
    if answered.status_code >= 400:
        raise _refused(answered, answered.content)
    # The event the helper just posted reads as a key pressed at the Mac; a beat keeps `where`
    # on the headset even if this click is the first sign of it.
    presence.headset_on()


@router.get("/windows/{window_id}/{kind}")
async def window_stream(window_id: int, kind: Literal["stream", "hevc"], request: Request):
    """`stream` is MJPEG, `hevc` the same window as HEVC access units off the Mac's hardware
    encoder. The query (`fps`, `max`, `q`, …) is the helper's to read and goes through whole —
    picking out `fps` alone is how the headset's `max` was once dropped on the floor here."""
    client = httpx.AsyncClient(timeout=httpx.Timeout(TIMEOUT, read=None))
    asked = client.build_request(
        "GET", f"{HELPER}/windows/{window_id}/{kind}", params=request.query_params
    )
    try:
        upstream = await client.send(asked, stream=True)
    except httpx.HTTPError as error:
        await client.aclose()
        raise _down(error) from error
    if upstream.status_code >= 400:
        body = await upstream.aread()
        await client.aclose()
        raise _refused(upstream, body)

    async def close() -> None:
        await upstream.aclose()
        await client.aclose()

    # The close is a background task rather than a `finally` in the generator: on a disconnect
    # Starlette cancels the stream, and an await inside a cancelled scope is cancelled with it.
    # The background task runs after that scope has ended, on a finished stream or a gone client.
    return StreamingResponse(
        upstream.aiter_raw(),
        media_type=upstream.headers.get("content-type", "application/octet-stream"),
        background=BackgroundTask(close),
    )
