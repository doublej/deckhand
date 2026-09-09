"""Which Claude Code sessions are alive right now, and which iTerm pane each one sits in.

Claude Code writes ~/.claude/sessions/<pid>.json for every running session (sessionId, cwd,
name, busy/idle). Those files outlive the process, so a record only counts once `ps` still
shows that pid running claude. `it2 session list --json` then maps the pid's tty to an iTerm
pane, which is what makes a session addressable from the phone.
"""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path


def sessions_dir() -> Path:
    return Path(os.environ.get("DECKHAND_CLAUDE_HOME", Path.home() / ".claude")) / "sessions"


@dataclass(slots=True)
class Pane:
    iterm_session_id: str
    window_id: str
    tab_id: str
    title: str


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

    def to_json(self) -> dict:
        d = asdict(self)
        d["folder"] = Path(self.cwd).name
        return d


def _processes() -> dict[int, str]:
    """pid -> tty short name (`ttys014`), for every running claude process."""
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


def _panes() -> dict[str, Pane]:
    """tty short name -> iTerm pane. Empty when iTerm or its Python API is unavailable."""
    try:
        out = subprocess.run(
            ["it2", "session", "list", "--json"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}
    if out.returncode != 0:
        return {}
    try:
        listing = json.loads(out.stdout)
    except json.JSONDecodeError:
        return {}
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


def live_sessions(iterm_only: bool = True) -> list[Session]:
    """Live interactive Claude sessions, most recently active first."""
    procs = _processes()
    panes = _panes()
    found: list[Session] = []
    for path in sessions_dir().glob("*.json"):
        try:
            rec = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        pid = rec.get("pid")
        if pid not in procs or rec.get("kind") != "interactive":
            continue
        tty = procs[pid]
        pane = panes.get(tty)
        if pane is None and iterm_only and panes:
            continue
        found.append(
            Session(
                session_id=rec.get("sessionId", ""),
                pid=pid,
                name=rec.get("name") or Path(rec.get("cwd", "")).name or f"pid {pid}",
                cwd=rec.get("cwd", ""),
                status=rec.get("status", "unknown"),
                updated_at=rec.get("updatedAt", rec.get("startedAt", 0)) / 1000,
                tty=tty,
                pane=pane,
            )
        )
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
