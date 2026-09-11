"""The iTerm pane a session sits in, and what to say when iTerm will not answer.

`it2 session list --json` maps a tty to a pane, and that map is the only reason a session is
addressable by keyboard rather than only down its inbox socket. It is cached because one call
costs ~0.5 s and the phone polls every few; it backs off because when iTerm is not answering,
every call costs the whole timeout and nothing about the answer changes in the next minute.

A machine that is not this Mac has no pane at all, and that is a listing with an empty map
rather than a failure — `live.live_sessions` already keeps every session when there are none.
"""

from __future__ import annotations

import json
import subprocess
import time
from dataclasses import dataclass

from ..log import log

PANE_TTL = 3.0  # seconds; one `it2` call costs ~0.5 s and the phone polls every few
# When iTerm will not answer, every call costs the full timeout. Back off instead of paying
# that on each request: nothing about the answer changes in the next minute.
PANE_RETRY_AFTER = 60.0
# One call costs ~1 s from a terminal. The old 4 s was not enough headroom for a job launchd
# had put in the slow lane, and every miss cost the pane data and the keyboard with it.
PANE_TIMEOUT = 12
_pane_cache: tuple[float, dict] = (0.0, {})
_pane_error: str | None = None


@dataclass(slots=True)
class Pane:
    iterm_session_id: str
    window_id: str
    tab_id: str
    title: str



def forget() -> None:
    """Drop the cached pane map, so the next lookup asks iTerm again.

    For the one caller that knows the map is stale rather than merely old: a window opened a
    second ago is a pane this cache was built before, and a session reported with no pane reads
    as a session that cannot be typed into.
    """
    global _pane_cache
    _pane_cache = (0.0, {})


def status() -> str:
    """What the phone should be told about the iTerm side: "ok" or why panes are missing."""
    return _pane_error or "ok"


def lookup() -> dict[str, Pane]:
    """tty short name -> iTerm pane. Empty when iTerm or its Python API is unavailable."""
    global _pane_cache
    fetched_at, cached = _pane_cache
    age = time.monotonic() - fetched_at
    if age < (PANE_TTL if cached else PANE_RETRY_AFTER):
        return cached
    found = _fetch_panes()
    _pane_cache = (time.monotonic(), found)
    return found


def _fetch_panes() -> dict[str, Pane]:
    global _pane_error
    try:
        out = subprocess.run(
            ["it2", "session", "list", "--json"],
            capture_output=True,
            text=True,
            # iTerm2 asks for Python API approval the first time a new client connects;
            # until someone clicks it, this call blocks. Give up fast and list panes as
            # unknown rather than making the phone wait.
            timeout=PANE_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired:
        _pane_error = "iTerm did not answer in time — approve the Python API in iTerm2"
        log.warning("panes unavailable: it2 timed out")
        return {}
    except OSError as error:
        _pane_error = f"cannot run it2: {error}"
        log.warning("panes unavailable: %s", error)
        return {}
    if out.returncode != 0:
        _pane_error = f"it2 exited {out.returncode}: {out.stderr.strip()[:120]}"
        log.warning("panes unavailable: %s", _pane_error)
        return {}
    try:
        listing = json.loads(out.stdout)
    except json.JSONDecodeError:
        _pane_error = "it2 answered something that is not JSON"
        log.warning("panes unavailable: unparseable it2 output")
        return {}
    _pane_error = None
    panes: dict[str, Pane] = {}
    for s in listing:
        tty = str(s.get("tty", "")).removeprefix("/dev/")
        if not tty:
            continue
        panes[tty] = Pane(
            iterm_session_id=s.get("id", ""),
            window_id=s.get("window_id", ""),
            tab_id=str(s.get("tab_id", "")),
            title=(s.get("name") or "").strip(),
        )
    return panes
