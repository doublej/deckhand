"""Which addresses atlas knows: a project's domain or reserved port, a dev hostname, a service.

Three of atlas's lists, joined on the project's folder. A match names the project and, where
atlas gave it one, its hostnames — `https://<slug>.atlas.local.jurrejan.com` opens from the
phone where the `localhost:4109` the session wrote never will.

A port only means a project on *this* Mac: `localhost`, this Mac's LAN address or its own name.
The hostnames route probes every server before it answers (about five seconds, measured), so
its answer is kept for five minutes and refreshed in the background once it has gone stale;
nothing waits for it: until the first read lands, `registry` says None and the route tells the
phone its answer is not complete yet.
"""

from __future__ import annotations

import json
import socket
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from urllib.parse import urlsplit

from .. import config
from ..fleet import registry as machines
from ..log import log
from ..projects import sources

API = "http://127.0.0.1:47891/api/"
TIMEOUT = 20.0
TTL = 300.0


@dataclass(slots=True)
class Known:
    name: str
    path: str = ""
    port: int = 0
    hosts: set[str] = field(default_factory=set)
    local: str = ""
    remote: str = ""

    def to_json(self) -> dict:
        return {"name": self.name, "path": self.path, "local": self.local, "remote": self.remote}


_cache: tuple[float, list[Known]] = (0.0, [])
_refreshing = threading.Lock()


def registry() -> list[Known] | None:
    """Everything atlas has registered, at most five minutes old — None before the first read."""
    fetched_at = _cache[0]
    if (not fetched_at or time.monotonic() - fetched_at > TTL) and _refreshing.acquire(blocking=False):
        threading.Thread(target=_refresh, daemon=True).start()
    return _cache[1] if fetched_at else None


def match(known: list[Known], origin: str) -> Known | None:
    parts = urlsplit(origin)
    host = (parts.hostname or "").removeprefix("www.")
    if host in _here():
        return next((k for k in known if k.port and k.port == parts.port), None)
    return next((k for k in known if host in k.hosts), None)


def _here() -> set[str]:
    name = socket.gethostname().lower().removesuffix(".local")
    return {"localhost", name, f"{name}.local", config.lan_address()} - {""}


def _refresh() -> None:
    global _cache
    try:
        _cache = (time.monotonic(), _read())
    finally:
        _refreshing.release()


def _read() -> list[Known]:
    projects, _ = sources.catalog()
    by_path = {p.path: Known(p.name, p.path, p.port, {d.lower().removeprefix("www.") for d in p.domains})
               for p in projects if p.machine in ("", machines.here())}
    for row in _get("hostnames"):
        known = by_path.setdefault(str(row.get("path") or row.get("slug")), Known(str(row.get("slug") or "")))
        known.local, known.remote = str(row.get("local") or ""), str(row.get("remote") or "")
    found = [k for k in by_path.values() if k.port or k.hosts or k.local]
    for row in _get("services"):
        found.append(Known(str(row.get("name") or row.get("slug") or ""), port=int(row.get("port") or 0),
                           local=str(row.get("local") or ""), remote=str(row.get("remote") or "")))
    for known in found:
        known.hosts |= {h for url in (known.local, known.remote) if (h := urlsplit(url).hostname)}
    return found


def _get(what: str) -> list[dict]:
    try:
        with urllib.request.urlopen(API + what, timeout=TIMEOUT) as answer:
            body = json.loads(answer.read())
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as error:
        log.info("atlas did not answer /%s: %s", what, error)
        return []
    rows = body.get(what, []) if isinstance(body, dict) else body
    return [row for row in rows if isinstance(row, dict)] if isinstance(rows, list) else []
