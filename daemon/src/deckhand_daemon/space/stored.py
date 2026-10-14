"""`space.json`, in the data dir: `{"rev", "planes": [Plane], "poses": {key: Pose}}`.

`rev` rises on every change, so the headset can poll `GET /space` and redraw only when it moved.
Read whole and written whole through `os.replace`, like `bindings/stored.py`, so a crash mid-write
leaves the last good file. Every change is read, modify, write under one lock, or two planes
opened in the same instant would each be written over the other.

A plane's pose goes with it: closing a plane drops `plane:<id>` from `poses`.
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


def add(plane: dict) -> dict:
    with _lock:
        kept = space()
        kept["planes"].append(plane)
        _write(kept)
    return plane


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
