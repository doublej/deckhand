"""`space.json`, in the data dir: `{"rev", "planes": [Plane], "poses": {key: Pose}, "beside"?}`.

`rev` rises on every change, so the headset can poll `GET /space` and redraw only when it moved.
Read whole and written whole through `os.replace`, like `bindings/stored.py`, so a crash mid-write
leaves the last good file. Every change is read, modify, write under one lock, or two planes
opened in the same instant would each be written over the other.

A plane's pose goes with it: closing a plane drops `plane:<id>` from `poses`.

`beside` is `{session id: session id}`, written only once an agent has started a session: the one
it started, and the one that started it. The headset stands a session with no pose of its own
beside that one, in its group.
"""

from __future__ import annotations

import json
import os
import threading

from ..config import data_dir

SPACE = "space.json"

_lock = threading.Lock()


def space() -> dict:
    try:
        return json.loads((data_dir() / SPACE).read_text())
    except FileNotFoundError:
        return {"rev": 0, "planes": [], "poses": {}}


def add(plane: dict) -> tuple[dict, bool]:
    """Keep `plane`, or hand back the one already open beside the same session showing the same
    page or window — and whether it was that one. A retried open is then the same plane."""
    with _lock:
        kept = space()
        for open_ in kept["planes"]:
            if plane.get("near") and all(open_.get(k) == plane.get(k)
                                         for k in ("near", "kind", "url", "window")):
                return open_, True
        kept["planes"].append(plane)
        _write(kept)
    return plane, False


def drop(plane_id: str) -> bool:
    """Close one plane and forget where it was. Whether there was one by that id."""
    with _lock:
        kept = space()
        left = [p for p in kept["planes"] if p["id"] != plane_id]
        if len(left) == len(kept["planes"]):
            return False
        kept["planes"] = left
        kept["poses"].pop(f"plane:{plane_id}", None)
        _write(kept)
    return True


def given(plane_id: str, near: str | None) -> dict | None:
    """Hand a plane to another session: the plane as it was before, or None when there is none."""
    with _lock:
        kept = space()
        plane = next((p for p in kept["planes"] if p["id"] == plane_id), None)
        if plane is None:
            return None
        was = dict(plane)
        plane["near"] = near
        _write(kept)
    return was


def started(session_id: str, by: str) -> None:
    """`session_id` was started by the session `by` and stands beside it until it is moved."""
    with _lock:
        kept = space()
        kept.setdefault("beside", {})[session_id] = by
        _write(kept)


def has_plane(plane_id: str) -> bool:
    return any(p["id"] == plane_id for p in space()["planes"])


# ponytail: a `session:<id>` pose outlives its session, so poses grow by one per session ever
# placed. Prune against the listing if space.json ever gets big enough to notice.
def place(key: str, pose: dict) -> None:
    with _lock:
        kept = space()
        kept["poses"][key] = pose
        _write(kept)


def _write(kept: dict) -> None:
    kept["rev"] += 1
    final = data_dir() / SPACE
    half = final.with_name(f"{SPACE}.part")
    half.write_text(json.dumps(kept, indent=2, ensure_ascii=False) + "\n")
    os.replace(half, final)
