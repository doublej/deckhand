"""Pinning a web page to a project, and keeping what was said about a spot on it.

The listing is the whole permission here as it is for `/projects`: a folder this Mac's project
list does not name is a 400, never a 404, which the app reads as "that session is gone". Unlike
`/projects/commands`, a folder on another machine is taken: nothing runs in it, and the words are
only kept on this Mac.

Bodies are taken as plain objects and checked by hand, so that everything wrong with one is a 400
with a `detail` rather than FastAPI's 422, and a key nobody asked for is dropped.

No token check of its own: `app.py` mounts this with the same dependency every other route
carries, and `bindings/__init__.py` must not import this module.
"""

from __future__ import annotations

import asyncio
import base64
import binascii
import math
import uuid
from typing import Annotated

from fastapi import APIRouter, Body, HTTPException
from fastapi.responses import FileResponse

from ..projects import sources
from . import patterns, stored

router = APIRouter(tags=["bindings"])


@router.get("/bindings/match")
async def match_bindings(url: str) -> dict:
    """The bindings a page belongs to, best first: longest prefix, then most recently used."""
    _normalised(url, "url")
    kept = await asyncio.to_thread(stored.bindings)
    return {"matches": patterns.matching(kept, url)}


@router.get("/bindings")
async def list_bindings() -> dict:
    return {"bindings": await asyncio.to_thread(stored.bindings)}


@router.post("/bindings")
async def add_binding(sent: Annotated[dict, Body()]) -> dict:
    """Idempotent on (normalised pattern, path), and creating one counts as using it."""
    pattern = _normalised(sent.get("pattern"), "pattern")
    path = await _listed(sent.get("path"))
    return await asyncio.to_thread(stored.bind, pattern, path)


@router.delete("/bindings")
async def remove_binding(pattern: str, path: str) -> dict:
    pattern = _normalised(pattern, "pattern")
    return {"removed": await asyncio.to_thread(stored.unbind, pattern, path)}


@router.post("/feedback")
async def add_feedback(sent: Annotated[dict, Body()]) -> dict:
    """Keep one thing said about one spot on a page, stamped here, under its folder.

    A `screenshot` sent with it is written beside `feedback.json`; the entry keeps its path only.
    """
    path = await _listed(sent.get("path"))
    url = sent.get("url")
    _normalised(url, "url")
    transcript = sent.get("transcript")
    if not isinstance(transcript, str) or not transcript.strip():
        raise HTTPException(status_code=400, detail="transcript must be a non-empty string")
    jpeg = None if sent.get("screenshot") is None else _jpeg(sent, "screenshot")
    entry = {
        "id": uuid.uuid4().hex,
        "path": path,
        "url": url,
        "title": _text(sent, "title"),
        "selector": _text(sent, "selector"),
        "page_x": _number(sent, "page_x"),
        "page_y": _number(sent, "page_y"),
        "viewport_width": _number(sent, "viewport_width"),
        "viewport_height": _number(sent, "viewport_height"),
        "transcript": transcript,
        "created_at": stored.now(),
        "screenshot": None,
        "crop": None,
    }
    if jpeg is not None:
        entry["screenshot"] = await asyncio.to_thread(
            stored.save_shot, entry["id"], "screenshot", jpeg)
    return await asyncio.to_thread(stored.add_feedback, entry)


@router.get("/feedback")
async def list_feedback(path: str) -> dict:
    folder = await _listed(path)
    return {"entries": await asyncio.to_thread(stored.feedback, folder)}


@router.get("/feedback/image")
async def feedback_image(id: str, kind: str) -> FileResponse:
    """An entry's screenshot or crop. Found by the kept entry's id, never by a path sent here."""
    if kind not in ("screenshot", "crop"):
        raise HTTPException(status_code=400, detail="kind must be screenshot or crop")
    entry = await asyncio.to_thread(stored.entry, id)
    if entry is None or not entry.get(kind):
        raise HTTPException(status_code=404, detail=f"no {kind} for that id")
    found = stored.shot(entry["id"], kind)
    if not found.is_file():
        raise HTTPException(status_code=404, detail=f"no {kind} for that id")
    return FileResponse(found, media_type="image/jpeg")


@router.put("/feedback/crop")
async def crop_feedback(sent: Annotated[dict, Body()]) -> dict:
    """Keep the crop of an entry's screenshot the person drew, replacing any before it."""
    entry_id = sent.get("id")
    jpeg = _jpeg(sent, "image")
    found = None
    if isinstance(entry_id, str):
        found = await asyncio.to_thread(stored.set_crop, entry_id, jpeg)
    if found is None:
        raise HTTPException(status_code=404, detail="no feedback entry has that id")
    return found


async def _listed(path: object) -> str:
    """A folder the project list names, or a 400. In a thread: the list may ask atlas over HTTP."""
    if isinstance(path, str) and path:
        found, _ = await asyncio.to_thread(sources.catalog)
        if any(project.path == path for project in found):
            return path
    raise HTTPException(status_code=400, detail="that folder is not in the project list")


def _normalised(value: object, name: str) -> str:
    if not isinstance(value, str):
        raise HTTPException(status_code=400, detail=f"{name} must be a string")
    try:
        return patterns.normalised(value)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=f"{name}: {error}") from error


def _jpeg(sent: dict, name: str) -> bytes:
    """Base64 without a `data:` prefix, decoded. Not checked for being a JPEG: it is only kept."""
    value = sent.get(name)
    if isinstance(value, str) and value:
        try:
            return base64.b64decode(value, validate=True)
        except binascii.Error as error:
            raise HTTPException(status_code=400, detail=f"{name} must be base64") from error
    raise HTTPException(status_code=400, detail=f"{name} must be base64")


def _number(sent: dict, name: str) -> int | float:
    """A JSON number. Not a bool, which Python counts as one, and not NaN or infinity, which
    Python's JSON reads and no response could carry back out."""
    value = sent.get(name)
    if (isinstance(value, bool) or not isinstance(value, int | float)
            or (isinstance(value, float) and not math.isfinite(value))):
        raise HTTPException(status_code=400, detail=f"{name} must be a number")
    return value


def _text(sent: dict, name: str) -> str:
    value = sent.get(name)
    if value is None:
        return ""
    if not isinstance(value, str):
        raise HTTPException(status_code=400, detail=f"{name} must be a string")
    return value
