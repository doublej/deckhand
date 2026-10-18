"""The manager sees what the phone sees: any of this daemon's GET routes, read as the phone reads it.

JJ's rule (2026-10-18): the manager should be able to see everything the person can, if it chooses
to. So this is not a second reading of sessions but the phone's own: one request to this daemon's
app, in-process, so every limit the phone has holds here too — `/file` serves only what the
session's transcript named, a session on another machine answers what its hand answers, and a
route added tomorrow is visible the day it lands. It reads and nothing else: a GET is the whole of
it, so nothing here can type, press, answer a slip or change a switch.

In-process means loopback, and `presence.seen` never counts loopback as the person, so the
manager looking does not put utt's cover up. A picture comes back as a picture, which is what lets
it see a screenshot a session took or a window in the headset; text comes back whole, up to
`MAX_CHARS`.
"""

from __future__ import annotations

import base64

import httpx

from .. import config
from .tools import find, missing, said

#: Endpoints that never end. A read waits for its answer, and these have no last byte.
ENDLESS = ("stream", "hevc")
#: Reads that are not only reads. `/manager` polled counts as the panel on screen, which stops every
#: push to the phone, and it is the manager's own conversation besides.
NOT_HERE = ("/manager",)
#: Enough for a long spec or a whole transcript page, and still a fraction of the context.
MAX_CHARS = 200_000
#: The API's own ceiling on one image, with room for base64 to grow it by a third.
MAX_IMAGE_BYTES = 3_750_000
WAIT = 20.0


async def look(path: str, session: str = "") -> dict:
    """GET `path` from this daemon, under `/sessions/<that session's id>` when `session` names one."""
    path = path.strip()
    if session:
        found = find(session)
        if found is None:
            return missing(session)
        path = f"/sessions/{found.session_id}/{path.lstrip('/')}".rstrip("/")
    if not path.startswith("/") or ".." in path:
        return said(f"{path!r} is not a path on this daemon: it starts with / and goes nowhere up")
    if path.split("?")[0].rstrip("/") in NOT_HERE:
        return said(f"{path} is the manager's own panel; reading it would silence the phone's pushes")
    if any(part in ENDLESS for part in path.split("?")[0].split("/")):
        return said(f"{path} is a stream with no end; read one frame instead (/windows/<id>/frame)")
    from ..app import app  # here, because the app mounts the manager's routes

    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://deckhand",
                                 headers={config.TOKEN_HEADER: config.token()}, timeout=WAIT) as client:
        answer = await client.get(path)
    kind = answer.headers.get("content-type", "").split(";")[0]
    if answer.status_code >= 400:
        return said(f"{answer.status_code} for {path}: {answer.text[:500]}")
    if kind.startswith("image/"):
        if len(answer.content) > MAX_IMAGE_BYTES:
            return said(f"{path} is a {kind} of {len(answer.content):,} bytes, too large to look at")
        data = base64.b64encode(answer.content).decode()
        return {"content": [{"type": "image", "data": data, "mimeType": kind}]}
    if not (kind.startswith("text/") or kind.endswith("json") or _is_text(answer.content)):
        return said(f"{path} is {kind or 'binary'}, {len(answer.content):,} bytes: nothing to read as text")
    text = answer.text
    if len(text) > MAX_CHARS:
        return said(text[:MAX_CHARS] + f"\n\n[cut at {MAX_CHARS:,} of {len(text):,} characters]")
    return said(text)


def _is_text(body: bytes) -> bool:
    """A file served as octet-stream that is really text: a spec in /tmp, a log with no suffix."""
    try:
        body[:4096].decode()
    except UnicodeDecodeError:
        return False
    return b"\x00" not in body[:4096]
