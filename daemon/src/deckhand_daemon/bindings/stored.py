"""The two documents: `bindings.json` and `feedback.json`, in the data dir.

`bindings.json` is `{"bindings": [{"pattern", "path", "last_used"}]}` and `feedback.json` is
`{"<folder>": [entry, ...]}`. An entry's screenshot and its crop are JPEGs in `feedback-shots/`
beside them, named by the entry's `id`, and the entry holds only their absolute paths.

Read whole and written whole, like `settings/wants.py`, but through `os.replace`, so a crash
mid-write leaves the last good file rather than half of one.

Every change is read, modify, write, so one lock covers both files: two entries posted in the same
instant would otherwise each read the list without the other, and one of them would be lost.
A file that is there and unreadable raises rather than reading as empty, because the next write
would then replace everything kept in it.
"""

from __future__ import annotations

import json
import os
import threading
from datetime import UTC, datetime
from pathlib import Path

from ..config import data_dir
from . import patterns

BINDINGS = "bindings.json"
FEEDBACK = "feedback.json"
SHOTS = "feedback-shots"

_lock = threading.Lock()


def now() -> str:
    """ISO 8601 UTC to the millisecond with a `Z`, the shape `reading/asked.py` writes."""
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def bindings() -> list[dict]:
    return _read(BINDINGS, {"bindings": []})["bindings"]


def bind(pattern: str, path: str) -> dict:
    """Keep (pattern, path), or find it kept already. Either way it was just used."""
    with _lock:
        kept = bindings()
        binding = next((b for b in kept if b["pattern"] == pattern and b["path"] == path), None)
        if binding is None:
            binding = {"pattern": pattern, "path": path, "last_used": None}
            kept.append(binding)
        binding["last_used"] = now()
        _write(BINDINGS, {"bindings": kept})
    return binding


def unbind(pattern: str, path: str) -> bool:
    """Drop that pair. Whether there was one to drop."""
    with _lock:
        kept = bindings()
        left = [b for b in kept if (b["pattern"], b["path"]) != (pattern, path)]
        if len(left) != len(kept):
            _write(BINDINGS, {"bindings": left})
    return len(left) != len(kept)


def feedback(folder: str) -> list[dict]:
    """One folder's entries, oldest first: the order they were appended in."""
    return _read(FEEDBACK, {}).get(folder, [])


# ponytail: rewrites the whole of feedback.json for every entry, so each one costs every entry
# ever kept. Move to one appended JSONL per project if it grows.
def add_feedback(entry: dict) -> dict:
    """Append one entry under its folder, and mark the binding it came through as used."""
    with _lock:
        kept = _read(FEEDBACK, {})
        kept.setdefault(entry["path"], []).append(entry)
        _write(FEEDBACK, kept)
        every = bindings()
        mine = [b for b in every if b["path"] == entry["path"]]
        if best := patterns.matching(mine, entry["url"]):
            best[0]["last_used"] = entry["created_at"]
            _write(BINDINGS, {"bindings": every})
    return entry


def entry(entry_id: str) -> dict | None:
    """The entry with that id, in whichever folder. Entries kept before ids existed have none."""
    return _with_id(_read(FEEDBACK, {}), entry_id)


def shot(entry_id: str, kind: str) -> Path:
    """Where an entry's `screenshot` or `crop` lives. Only ever called with a kept or new id."""
    name = f"{entry_id}.jpg" if kind == "screenshot" else f"{entry_id}-crop.jpg"
    return data_dir() / SHOTS / name


def save_shot(entry_id: str, kind: str, jpeg: bytes) -> str:
    """Write the image and answer its absolute path, the string the entry keeps."""
    final = shot(entry_id, kind)
    final.parent.mkdir(exist_ok=True)
    half = final.with_name(f"{final.name}.part")
    half.write_bytes(jpeg)
    os.replace(half, final)
    return str(final.resolve())


def set_crop(entry_id: str, jpeg: bytes) -> dict | None:
    """Keep a crop for that entry, replacing any before it. None when no entry has that id."""
    with _lock:
        kept = _read(FEEDBACK, {})
        found = _with_id(kept, entry_id)
        if found is None:
            return None
        found["crop"] = save_shot(entry_id, "crop", jpeg)
        _write(FEEDBACK, kept)
    return found


def _with_id(kept: dict, entry_id: str) -> dict | None:
    return next((e for entries in kept.values() for e in entries if e.get("id") == entry_id), None)


def _read(name: str, empty: dict) -> dict:
    try:
        return json.loads((data_dir() / name).read_text())
    except FileNotFoundError:
        return empty


def _write(name: str, document: dict) -> None:
    final = data_dir() / name
    half = final.with_name(f"{name}.part")
    half.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
    os.replace(half, final)
