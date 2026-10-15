"""Every phone, headset and browser this Mac has paired, each with a token of its own.

**The token itself is never kept.** `devices.json` holds a SHA-256 of each one, so the file says
which devices there are and grants nothing to whoever reads it — the device holds the only copy,
and losing it is re-pairing, not recovery. A device token is 192 bits from `secrets`: it no longer
has to be typable, because nobody types it.

**Revoking one is deleting its row**, and it stops working on the very next request: the check
reads the rows this process holds, and a delete writes through them.

**`seen` is written at most every few minutes.** The phone asks something every few seconds, and
a file rewritten per request is a disk busy for nothing; the stamp is only ever read by a person
deciding which row is the phone they lost.
"""

from __future__ import annotations

import hashlib
import json
import secrets
import time
from pathlib import Path

from .. import config

#: How stale a kept `seen` may get before a request writes it again, in seconds.
SEEN_EVERY = 300

_cache: tuple[Path, list[dict]] | None = None


def _path() -> Path:
    return config.data_dir() / "devices.json"


def _rows() -> list[dict]:
    """The rows for *this* data folder — a test moves the folder, and must not see the last one's."""
    global _cache
    path = _path()
    if _cache is None or _cache[0] != path:
        loaded = json.loads(path.read_text()) if path.exists() else {}
        _cache = (path, list(loaded.get("devices", [])))
    return _cache[1]


def _keep(rows: list[dict]) -> None:
    path = _path()
    partial = path.with_suffix(".json.part")
    partial.write_text(json.dumps({"devices": rows}, indent=2))
    partial.chmod(0o600)
    partial.replace(path)


def _digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def public(row: dict) -> dict:
    """A row as it may be shown: everything but the hash."""
    return {key: value for key, value in row.items() if key != "hash"}


def mint(name: str, kind: str) -> tuple[str, dict]:
    """A new device and the only copy of its token, which goes back to it and nowhere else."""
    token = secrets.token_urlsafe(24)
    now = int(time.time())
    row = {"id": secrets.token_hex(4), "name": name, "kind": kind, "paired": now, "seen": now,
           "hash": _digest(token)}
    rows = _rows()
    rows.append(row)
    _keep(rows)
    return token, public(row)


def known(token: str) -> dict | None:
    """The device this token belongs to, stamped as seen, or None."""
    if not token:
        return None
    wanted = _digest(token)
    for row in _rows():
        if secrets.compare_digest(row["hash"], wanted):
            now = int(time.time())
            if now - row.get("seen", 0) > SEEN_EVERY:
                row["seen"] = now
                _keep(_rows())
            return row
    return None


def listing() -> list[dict]:
    return [public(row) for row in _rows()]


def forget(device_id: str) -> dict | None:
    """Take one device's token away. The row it was, or None when there was no such device."""
    rows = _rows()
    for row in rows:
        if row["id"] == device_id:
            rows.remove(row)
            _keep(rows)
            return public(row)
    return None
