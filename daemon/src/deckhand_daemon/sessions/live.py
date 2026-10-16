"""Which Claude Code sessions are alive right now, and which tmux pane each one sits in.

Claude Code writes ~/.claude/sessions/<pid>.json for every running session (sessionId, cwd,
name, busy/idle). Those files outlive the process, so a record only counts once that pid is
still the process that wrote it. `tmux list-panes -a` then maps the pid's tty to a tmux pane,
which is what makes a session addressable from the phone.

**Two ways of asking whether a pid is still that session**, and the Windows one is the better
of them. macOS and Linux ask `ps` and take any pid whose command line has `claude` in it, which
a recycled pid can fool. Windows has no `ps`, so the record's own `procStart` is compared
against the pid's real creation time — a pid handed to something else since has a different
one, and no heuristic is involved. The POSIX side is not changed to match: `procStart` is a
date string on macOS and clock ticks on Linux, two more formats to parse for a case that has
not bitten in a year of running.

The pane half of this lives in `panes.py` and the token counting in `usage.py`; `__init__.py`
re-exports all three, so `sessions.live_sessions()` and `sessions.pane_status()` read the same
from outside as they always did.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path

from .. import config, fleet
from ..log import log
from ..reading.transcripts import turn_ended
from . import codex, opencode, panes, project
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
    # `claude`; `codex` for a thread in the Codex app server; `opencode` for a session in the
    # OpenCode service. Neither of the other two has a pid, a tty, a pane or a socket: their words
    # go in through their own server's API. See `codex.py` and `opencode.py`.
    provider: str = "claude"
    # Whether a client on this Mac has it open. Only OpenCode answers it: a session there outlives
    # every window showing it, so this is whether a TUI has it as a TUI tab (`opencode_tabs.py`).
    # None for the other two, and for an OpenCode Mac that cannot tell. A Claude session is
    # listed only while its process runs, so it is always open.
    in_client: bool | None = None

    def to_json(self) -> dict:
        d = asdict(self)
        d.pop("socket_path")
        d["folder"] = Path(self.cwd).name
        d["project"] = project.of(self.cwd)
        return d


def _processes(pids: set[int]) -> dict[int, str]:
    """pid -> tty short name (`ttys014`), for those of `pids` still running claude.

    Asked about the pids that have a session record rather than about the whole machine, which
    is all that was ever read out of it. `command=` makes `ps` pull each process's entire argv
    out of the kernel one by one: over the 1254 processes on this Mac that measured 1.8-3.5 s,
    paid on every call — and `live_sessions` is on nearly every route, so it was most of what
    `/sessions` cost. The eight pids with a record answer in 0.2 s and the join is unchanged.

    `check=False` because a record outliving its process is the normal case and `ps -p` exits 1
    when it cannot find one of them; the pids it did find are on stdout either way.

    Empty on Windows, which has neither `ps` nor a tty: there, `_still_running` answers per
    record instead, and a tty of "" is right rather than missing — nothing on that machine has
    a pane for it to name.
    """
    if sys.platform == "win32" or not pids:
        return {}
    out = subprocess.run(
        ["ps", "-o", "pid=,tty=,command=", "-p", ",".join(str(p) for p in sorted(pids))],
        capture_output=True,
        text=True,
        check=False,
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


def _records() -> list[dict]:
    """Every interactive session record on this Mac, whether or not its pid is still running.

    Read before `ps` rather than alongside it, because the pids in them are what `ps` is asked
    about. An unreadable file is skipped: Claude Code writes these while the daemon reads them.
    Every config dir is read, not just `~/.claude`: see `config.claude_homes`.
    """
    found: list[dict] = []
    for path in (p for home in config.claude_homes() for p in (home / "sessions").glob("*.json")):
        try:
            rec = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if isinstance(rec.get("pid"), int) and rec.get("kind") == "interactive":
            found.append(rec)
    return found


#: The whole listing, and whether tmux answered when it was built. Cached because building it
#: costs two subprocesses — `ps` for the pid join, `tmux` for the panes — and nearly every route
#: in the daemon asks for it. Without this the phone paid for both on every poll of every route:
#: the session page alone re-reads turns every 1.1 s, the rail every 4 s and the deck every 6 s,
#: each arriving as its own threadpool thread sitting on a subprocess. Forty of those is the
#: whole pool, and then everything queues behind them, `/health` included.
LISTING_TTL = 2.0
_listing: tuple[float, list[Session], bool] = (0.0, [], False)
#: One thread builds, the rest take what it built. The lock is not an optimisation on top of the
#: cache, it is most of the point: a bare TTL lets forty threads miss together and run forty
#: `ps` calls, which is the pile-up this exists to stop happening at all.
_building = threading.Lock()


def forget_listing() -> None:
    """Drop the cached listing, so the next call reads the records and asks `ps` again.

    For the callers that know it is stale rather than merely old — a session started a second
    ago cannot be in a listing built before it existed, and `projects.starting` is sitting in a
    loop waiting for exactly that. Same reason `panes.forget` exists, one layer up.
    """
    global _listing
    _listing = (0.0, [], False)


def _listed() -> tuple[list[Session], bool]:
    """The cached listing, rebuilt when it is older than `LISTING_TTL`."""
    global _listing
    built_at, found, answered = _listing
    if time.monotonic() - built_at < LISTING_TTL:
        return found, answered
    with _building:
        # Somebody may have built it while this thread waited for the lock. Taking theirs is
        # the whole reason for waiting.
        built_at, found, answered = _listing
        if time.monotonic() - built_at < LISTING_TTL:
            return found, answered
        found, answered = _build()
        _listing = (time.monotonic(), found, answered)
    return found, answered


def live_sessions(paned_only: bool = True) -> list[Session]:
    """Live interactive Claude sessions, most recently active first.

    The pane filter is applied here rather than inside `_build`, so one cached listing answers
    both callers. `paned_only` drops the sessions tmux has no pane for, and only while tmux
    answered at all: a lookup that came back with nothing is tmux being unavailable, which
    keeps every session rather than hiding all of them.
    """
    found, answered = _listed()
    if paned_only and answered:
        # A Codex thread or an OpenCode session never has a pane. The rule is about Claude
        # sessions tmux cannot see, not about sessions that were never in a terminal at all.
        return [s for s in found if s.pane is not None or s.provider != "claude"]
    # A new list every time, because the one behind it is now shared between every caller and
    # a caller that sorted it in place would quietly reorder the rail for everybody.
    return list(found)


def _build() -> tuple[list[Session], bool]:
    """Every live session with its pane attached, and whether tmux answered at all.

    Built unfiltered on purpose. The pane filter used to run inside this loop, which meant a
    live session tmux had no pane for was missing from `found` — and `found` is what the three
    maps below are pruned against, so that session's own `/clear` tracking was dropped while it
    was still running. Filtering after the fact is both the shareable answer and the right one.
    """
    records = _records()
    procs = _processes({rec["pid"] for rec in records})
    found_panes = panes.lookup()
    machine = fleet.here()  # every record under this root belongs to the machine we are on
    found: list[Session] = []
    for rec in records:
        pid = rec["pid"]
        if not _still_running(pid, procs, rec.get("procStart", "")):
            continue
        session_id = rec.get("sessionId", "")
        if session_id:
            if (was := _current.get(pid)) and was != session_id:
                _retired[was] = pid
            _current[pid] = session_id
        tty = procs.get(pid, "")
        pane = found_panes.get(tty)
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
    # After the pid bookkeeping, which is about processes neither of the others has, and before
    # the sort, so every kind shares one clock. Both `records` never raise and back off on their own.
    found.extend(Session(**record, machine=machine) for record in codex.records())
    found.extend(Session(**record, machine=machine) for record in opencode.records())
    found.sort(key=lambda s: s.updated_at, reverse=True)
    return [s for s in found if s.session_id], bool(found_panes)


def focus(session: Session) -> bool:
    """Show the session's pane in the tmux client on the Mac: its window, then the pane in it."""
    if session.pane is None:
        return False
    pane = session.pane.iterm_session_id
    for verb in ("select-window", "select-pane"):
        r = subprocess.run(["tmux", verb, "-t", pane], capture_output=True, text=True, timeout=10, check=False)
        if r.returncode != 0:
            return False
    return True
