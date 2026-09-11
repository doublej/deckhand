"""Which Claude Code sessions are alive right now, and which iTerm pane each one sits in.

Claude Code writes ~/.claude/sessions/<pid>.json for every running session (sessionId, cwd,
name, busy/idle). Those files outlive the process, so a record only counts once that pid is
still the process that wrote it. `it2 session list --json` then maps the pid's tty to an iTerm
pane, which is what makes a session addressable from the phone.

**Two ways of asking whether a pid is still that session**, and the Windows one is the better
of them. macOS and Linux ask `ps` and take any pid whose command line has `claude` in it, which
a recycled pid can fool. Windows has no `ps`, so the record's own `procStart` is compared
against the pid's real creation time — a pid handed to something else since has a different
one, and no heuristic is involved. The POSIX side is not changed to match: `procStart` is a
date string on macOS and clock ticks on Linux, two more formats to parse for a case that has
not bitten in a year of running.

The pane half of this lives in `panes.py` and the token counting in `usage.py`; `__init__.py`
re-exports all three, so `sessions.live_sessions()` and `sessions.iterm_status()` read the same
from outside as they always did.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

from .. import fleet
from ..log import log
from ..reading.transcripts import turn_ended
from . import panes
from .panes import Pane


def sessions_dir() -> Path:
    return Path(os.environ.get("DECKHAND_CLAUDE_HOME", Path.home() / ".claude")) / "sessions"


@dataclass(slots=True)
class Session:
    session_id: str
    pid: int
    name: str
    cwd: str
    status: str
    updated_at: float
    tty: str
    pane: Pane | None
    socket_path: str = ""  # its own peer inbox; how text gets in. Local to the Mac.
    # Which machine this session runs on, named as atlas names it. A daemon only ever builds
    # sessions for its own machine; a hand's listing arrives already stamped with its own.
    machine: str = ""

    def to_json(self) -> dict:
        d = asdict(self)
        d.pop("socket_path")
        d["folder"] = Path(self.cwd).name
        return d


def _processes() -> dict[int, str]:
    """pid -> tty short name (`ttys014`), for every running claude process.

    Empty on Windows, which has neither `ps` nor a tty: there, `_still_running` answers per
    record instead, and a tty of "" is right rather than missing — nothing on that machine has
    a pane for it to name.
    """
    if sys.platform == "win32":
        return {}
    out = subprocess.run(
        ["ps", "-eo", "pid=,tty=,command="], capture_output=True, text=True, check=True
    ).stdout
    procs: dict[int, str] = {}
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 3:
            continue
        pid, tty, command = parts
        # Wrappers (`onenv run -- claude ...`) match too, but only pids with a session
        # file are ever looked up, and a wrapper never writes one.
        if "claude" in command:
            procs[int(pid)] = tty
    return procs


def _still_running(pid: int, procs: dict[int, str], proc_start: str) -> bool:
    """Whether the process that wrote this record is the one holding that pid now."""
    if sys.platform != "win32":
        return pid in procs
    return bool(proc_start) and _created_at(pid) == str(proc_start)


def _created_at(pid: int) -> str:
    """A Windows pid's creation time as the same FILETIME string `procStart` holds, or "".

    `ctypes` against kernel32 rather than a `Get-Process` subprocess: this runs once per record
    on every listing, and starting PowerShell costs more than the whole rest of the listing put
    together. `PROCESS_QUERY_LIMITED_INFORMATION` is the narrowest right that answers — it works
    across integrity levels, which `PROCESS_QUERY_INFORMATION` does not.
    """
    import ctypes
    from ctypes import wintypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    handle = kernel32.OpenProcess(0x1000, False, pid)
    if not handle:
        return ""
    try:
        created, exited, kernel, user = (wintypes.FILETIME() for _ in range(4))
        ok = kernel32.GetProcessTimes(
            handle,
            ctypes.byref(created),
            ctypes.byref(exited),
            ctypes.byref(kernel),
            ctypes.byref(user),
        )
        if not ok:
            return ""
        return str((created.dwHighDateTime << 32) | created.dwLowDateTime)
    finally:
        kernel32.CloseHandle(handle)


#: pid -> the conversation running under it now, and every id that has been retired from one.
#:
#: `/clear` keeps the process, the pane, the inbox socket and the name, and changes only the
#: conversation id — which is the one thing the phone is holding. A page opened before the clear
#: is left addressing an id nothing on this Mac answers to, and the person looking at it cannot
#: tell: every word on the screen still says the session is right there. This is how that prompt
#: still lands.
#:
#: Both are dropped the moment their pid stops running, and that is not tidiness: pids are
#: recycled, and an id left pointing at a dead one would resolve to whatever unrelated session
#: the OS handed that number to next. A voice clip going to the wrong session is worse than one
#: that fails.
# ponytail: in memory, so a daemon restart forgets. A phone's id is stale across a restart
# anyway; make it a file if that ever stops being true.
_current: dict[int, str] = {}
_retired: dict[str, int] = {}
#: Sessions caught claiming `busy` after their own transcript said the turn was over, so the log
#: says it once rather than on every poll. Dropped with the session, like the two maps above.
_frozen: set[str] = set()


def _reading(rec: dict, session_id: str) -> tuple[str, float]:
    """What this session is doing and since when, preferring the transcript over the registry.

    The registry says `busy` until Claude Code writes `idle`, and it does not always write it —
    see `reading.transcripts.turn_ended` for how that was measured and why the age of the claim
    cannot be the test. Nothing here ever raises a session to `busy`: a record that has stopped
    being maintained can only ever be over-claiming, and the transcript is only read to catch
    that. When it has nothing to say the record stands exactly as it did.

    The stamp moves with the status on purpose. `updated_at` is what the rail fades a row by, so
    leaving a corrected session on the moment it went busy would draw the one that just stopped
    talking as the faintest row on the screen.
    """
    status = rec.get("status", "unknown")
    updated_at = rec.get("updatedAt", rec.get("startedAt", 0)) / 1000
    if status != "busy" or not (ended := turn_ended(session_id)):
        _frozen.discard(session_id)
        return status, updated_at
    if session_id not in _frozen:
        _frozen.add(session_id)
        log.info(
            "%s still reads busy %.0f s on, but its last turn ended: listing it idle",
            rec.get("name", session_id),
            ended - updated_at,
        )
    return "idle", ended


def succeeded_by(session_id: str) -> str:
    """The conversation now running where `session_id` used to, or "".

    Only ever an id this Mac watched being retired from a pid that is still running — never a
    guess at which session someone probably meant.
    """
    pid = _retired.get(session_id)
    return _current.get(pid, "") if pid is not None else ""


def live_sessions(iterm_only: bool = True) -> list[Session]:
    """Live interactive Claude sessions, most recently active first."""
    procs = _processes()
    found_panes = panes.lookup()
    machine = fleet.here()  # every record under this root belongs to the machine we are on
    found: list[Session] = []
    for path in sessions_dir().glob("*.json"):
        try:
            rec = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        pid = rec.get("pid")
        if not isinstance(pid, int) or rec.get("kind") != "interactive":
            continue
        if not _still_running(pid, procs, rec.get("procStart", "")):
            continue
        session_id = rec.get("sessionId", "")
        if session_id:
            if (was := _current.get(pid)) and was != session_id:
                _retired[was] = pid
            _current[pid] = session_id
        tty = procs.get(pid, "")
        pane = found_panes.get(tty)
        if pane is None and iterm_only and found_panes:
            continue
        status, updated_at = _reading(rec, session_id)
        found.append(
            Session(
                session_id=session_id,
                pid=pid,
                name=rec.get("name") or Path(rec.get("cwd", "")).name or f"pid {pid}",
                cwd=rec.get("cwd", ""),
                status=status,
                updated_at=updated_at,
                tty=tty,
                pane=pane,
                socket_path=rec.get("messagingSocketPath", ""),
                machine=machine,
            )
        )
    alive = {s.pid for s in found}
    for dead in set(_current) - alive:
        del _current[dead]
    for old, pid in list(_retired.items()):
        if pid not in alive:
            del _retired[old]
    _frozen.intersection_update(s.session_id for s in found)
    found.sort(key=lambda s: s.updated_at, reverse=True)
    return [s for s in found if s.session_id]


def focus(session: Session) -> bool:
    """Bring the session's iTerm pane to the front on the Mac."""
    if session.pane is None:
        return False
    r = subprocess.run(
        ["it2", "session", "focus", session.pane.iterm_session_id],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    return r.returncode == 0
