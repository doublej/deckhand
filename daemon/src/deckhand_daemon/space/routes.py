"""The space over the wire: what is open in the headset, opening and closing it, and where it is.

A plane is furniture, not a session. Opening one starts nothing and closing one stops nothing,
which is why an agent may do both (`docs/space.md`). Starting a session beside another is the one
door here that makes a session, and it is `POST /projects/session` with both its gates plus a place
to stand: JJ asked for agents to bring sessions into the space (2026-10-14). A session's own plane is never kept here — it
comes from the listing — so `DELETE /space/planes/{id}` structurally cannot close a session.

Bodies are taken as plain objects and checked by hand, as `bindings/routes.py` does, so anything
wrong with one is a 400 with a `detail` and a key nobody asked for is dropped.

No token check of its own: `app.py` mounts this with the dependency every other route carries,
and `/windows` rides along on the same router so it is mounted, and guarded, in the same breath.
"""

from __future__ import annotations

import asyncio
import math
import re
import uuid
from typing import Annotated
from urllib.parse import urlsplit, urlunsplit

from fastapi import APIRouter, Body, HTTPException, Response

from .. import config, saying
from ..bindings.stored import now
from ..projects import catalog
from ..projects import routes as projects
from ..sessions import live_sessions, project
from . import around, screen, stored, theme, windows

router = APIRouter(tags=["space"])
router.include_router(windows.router)
router.include_router(screen.router)
router.include_router(theme.router)

#: A host that means "this machine" to whoever wrote it — and the headset is another machine.
LOOPBACK = {"localhost", "127.0.0.1", "0.0.0.0", "::1"}
#: The fixed planes, which are neither a session nor a kept plane.
FIXED = {"manager", "projects", "launcher"}
GROUP = re.compile(r"[A-Za-z0-9_-]{1,64}")
MIN_SCALE, MAX_SCALE = 0.25, 4.0
#: Further from the floor origin than this is a pose gone wrong, not a room.
REACH = 20.0


@router.get("/space")
async def get_space() -> dict:
    return await asyncio.to_thread(stored.space)


@router.post("/space/planes", status_code=201)
async def open_plane(sent: Annotated[dict, Body()], response: Response) -> dict:
    kind = sent.get("kind")
    title = _text(sent, "title")
    if kind == "web":
        url = _url(sent.get("url"))
        window = None
        title = title or urlsplit(url).hostname or url
    elif kind == "window":
        url = None
        window = sent.get("window")
        if isinstance(window, bool) or not isinstance(window, int):
            raise HTTPException(status_code=400, detail="window must be an integer window id")
        title = title or await _window_title(window)
    else:
        raise HTTPException(status_code=400, detail="kind must be web or window")
    near = _text(sent, "near") or None
    # The same lookup every session route makes: a 404 for a session not listed, and a cleared
    # conversation answered by the one that replaced it in the same pane.
    session = await saying.live_session(near) if near else None
    plane = {
        "id": uuid.uuid4().hex,
        "kind": kind,
        "url": url,
        "window": window,
        "title": title,
        "near": session.session_id if session else None,
        "by": _text(sent, "by") or None,
        "at": now(),
    }
    plane, reused = await asyncio.to_thread(stored.add, plane)
    if reused:
        response.status_code = 200
        return plane | {"reused": True}
    # No `by` is the person, in the headset: an agent's plane names the agent and is its own news.
    if session and plane["by"] is None:
        await asyncio.to_thread(around.tell, session, plane)
    return plane


@router.put("/space/planes/{plane_id}/near", status_code=204)
async def give_plane(plane_id: str, sent: Annotated[dict, Body()]) -> Response:
    """The person moved a page or window to another session's side, or to nobody's (`near`
    null). The headset's to call; the session it now belongs to is told."""
    near = _text(sent, "near") or None
    session = await saying.live_session(near) if near else None
    was = await asyncio.to_thread(stored.given, plane_id, session.session_id if session else None)
    if was is None:
        raise HTTPException(status_code=404, detail="no plane with that id")
    if session and was["near"] != session.session_id:
        await asyncio.to_thread(around.tell, session, was | {"near": session.session_id})
    return Response(status_code=204)


@router.get("/sessions/{session_id}/space")
async def session_space(session_id: str) -> dict:
    """Where this session stands in the headset and what stands with it (`space/around.py`)."""
    session = await saying.live_session(session_id)
    rows = [s.to_json() for s in await asyncio.to_thread(live_sessions)]
    return around.around(await asyncio.to_thread(stored.space), rows, session.session_id)


@router.post("/space/sessions", status_code=201)
async def start_beside(sent: Annotated[dict, Body()]) -> dict:
    """Start a session in `path` that stands beside the session `near` in the headset, in its
    group, until it is moved. The listing and the trust record gate it exactly as they gate
    `POST /projects/session`, which does the starting; a folder inside a listed repo is taken as
    that repo, since a session's own folder is the one an agent knows."""
    near, path = _text(sent, "near"), _text(sent, "path")
    if not near or not path:
        raise HTTPException(status_code=400, detail="near and path are both needed")
    by = (await saying.live_session(near)).session_id
    listed = {p.path for p in (await asyncio.to_thread(catalog))[0]}
    if path not in listed:
        path = await asyncio.to_thread(project.root, path)
    started = await projects.start_project_session(
        path=path, provider=_text(sent, "provider") or "claude"
    )
    await asyncio.to_thread(stored.started, started["session"]["session_id"], by)
    return started["session"]


@router.delete("/space/planes/{plane_id}", status_code=204)
async def close_plane(plane_id: str) -> Response:
    if not await asyncio.to_thread(stored.drop, plane_id):
        raise HTTPException(status_code=404, detail="no plane with that id")
    return Response(status_code=204)


@router.put("/space/poses/{key}", status_code=204)
async def place(key: str, sent: Annotated[dict, Body()]) -> Response:
    kind, _, rest = key.partition(":")
    if not (key in FIXED or (kind in ("session", "plane") and rest)):
        raise HTTPException(
            status_code=400,
            detail="key must be session:<id>, plane:<id>, manager, projects or launcher",
        )
    if kind == "plane" and not await asyncio.to_thread(stored.has_plane, rest):
        raise HTTPException(status_code=404, detail="no plane with that id")
    pose = {name: _number(sent, name) for name in ("x", "y", "z", "yaw")}
    if math.hypot(pose["x"], pose["y"], pose["z"]) > REACH:
        raise HTTPException(status_code=400, detail=f"a pose is within {REACH:g} m of the origin")
    # Held in the hand a plane tilts, rolls and grows too; all three are optional so a pose that
    # only ever turned about the vertical stays four numbers.
    for name, low, high in (
        ("pitch", -math.pi, math.pi),
        ("roll", -math.pi, math.pi),
        ("scale", MIN_SCALE, MAX_SCALE),
    ):
        if sent.get(name) is not None:
            value = _number(sent, name)
            if not low <= value <= high:
                raise HTTPException(status_code=400, detail=f"{name} is {low:g} to {high:g}")
            pose[name] = value
    # Planes sharing a `group` move as one and are one project, whatever mix of sessions, pages
    # and windows the person put together. The headset decides who is in one; this only keeps it.
    if (group := sent.get("group")) is not None:
        if not isinstance(group, str) or not GROUP.fullmatch(group):
            raise HTTPException(status_code=400, detail="group is 1-64 of A-Z, a-z, 0-9, _ or -")
        pose["group"] = group
    # A minimized plane is a chip where it stood: `true` on its own, `"group"` with its whole
    # group, so restoring the group lifts only what the group put down. Kept across a relaunch.
    if (minimized := sent.get("minimized")) is not None:
        if not (isinstance(minimized, bool) or minimized == "group"):  # 1 == True in Python
            raise HTTPException(status_code=400, detail='minimized is true, false or "group"')
        if minimized:
            pose["minimized"] = minimized
    await asyncio.to_thread(stored.place, key, pose)
    return Response(status_code=204)


def reachable(url: str, lan: str) -> str:
    """The same URL with a loopback host swapped for this Mac's LAN address, port kept.

    `http://localhost:5173` is true where the session runs and false in the headset. Swapping
    the host only helps if the server listens on every interface, which the tools say.
    """
    parts = urlsplit(url)
    if parts.hostname not in LOOPBACK or not lan:
        return url
    port = f":{parts.port}" if parts.port else ""
    return urlunsplit(parts._replace(netloc=f"{lan}{port}"))


def _url(value: object) -> str:
    if not isinstance(value, str):
        raise HTTPException(status_code=400, detail="a web plane needs a url")
    parts = urlsplit(value.strip())
    try:
        parts.port  # noqa: B018 — reading it raises for a port that is not a number
    except ValueError as error:
        raise HTTPException(status_code=400, detail=f"url: {error}") from error
    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise HTTPException(status_code=400, detail="url must be http(s) with a host")
    return reachable(parts.geturl(), config.lan_address())


async def _window_title(window: int) -> str:
    """The window's own title, or its app's name when it has none. A 404 for a window the
    helper does not list, and its 503 when it is not running: a plane nothing can draw is not
    worth keeping."""
    found = next((w for w in await windows.listed() if w.get("id") == window), None)
    if found is None:
        raise HTTPException(status_code=404, detail="no Mac window with that id")
    return found.get("title") or found.get("app") or f"window {window}"


def _number(sent: dict, name: str) -> float:
    """A finite JSON number. Not a bool, and not NaN or infinity, which Python's JSON reads."""
    value = sent.get(name)
    if isinstance(value, bool) or not isinstance(value, int | float) or not math.isfinite(value):
        raise HTTPException(status_code=400, detail=f"{name} must be a finite number")
    return float(value)


def _text(sent: dict, name: str) -> str:
    value = sent.get(name)
    if value is None:
        return ""
    if not isinstance(value, str):
        raise HTTPException(status_code=400, detail=f"{name} must be a string")
    return value.strip()
