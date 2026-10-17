"""What happened to the sessions that needed you: a numbered list on disk, read by cursor.

The manager's conversation made the same choice for the same reason. A phone in a pocket holds no
socket, so the list is the channel and the id it last saw is the whole protocol — an hour away is
one call to catch up, and a daemon restart loses nothing. Ids never start again, because the file
outlives the process; the app still treats a newest id below its own as the file having gone.

Written by `push/`'s sweep, which already notices every one of these moments for the Lock Screen,
and written before any of that sweep's switches: a folder set quiet is not to be *interrupted*,
which says nothing about whether the tray may say what happened in it.
"""

from __future__ import annotations

import json
import threading
import time

from .. import config

#: Enough for a day of a busy Mac. A row is a few hundred bytes.
KEPT = 200

_lock = threading.Lock()


def add(kind: str, session, **fields) -> dict:
    """One thing that happened, stamped with the session it happened in."""
    with _lock:
        book = _read()
        item = {"id": book["newest"] + 1, "kind": kind, "session": session.session_id,
                "name": session.name, "machine": session.machine, "when": time.time(), **fields}
        book["newest"] = item["id"]
        book["items"] = [*book["items"], item][-KEPT:]
        path = config.data_dir() / "tray.json"
        path.write_text(json.dumps(book))
    return item


def after(since: int) -> list[dict]:
    return [item for item in _read()["items"] if item["id"] > since]


def newest() -> int:
    return _read()["newest"]


def _read() -> dict:
    try:
        book = json.loads((config.data_dir() / "tray.json").read_text())
    except (OSError, json.JSONDecodeError):
        return {"newest": 0, "items": []}
    return book if isinstance(book, dict) and "items" in book else {"newest": 0, "items": []}
