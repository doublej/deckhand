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
import time
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path

from .log import log
from .reading.transcripts import TAIL_WINDOWS, parse_line, tail_lines, transcript_path

PANE_TTL = 3.0  # seconds; one `it2` call costs ~0.5 s and the phone polls every few
# When iTerm will not answer, every call costs the full timeout. Back off instead of paying
# that on each request: nothing about the answer changes in the next minute.
PANE_RETRY_AFTER = 60.0
# One call costs ~1 s from a terminal. The old 4 s was not enough headroom for a job launchd
# had put in the slow lane, and every miss cost the pane data and the keyboard with it.
PANE_TIMEOUT = 12
_pane_cache: tuple[float, dict] = (0.0, {})
_pane_error: str | None = None


def iterm_status() -> str:
    """What the phone should be told about the iTerm side: "ok" or why panes are missing."""
    return _pane_error or "ok"


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
    socket_path: str = ""  # its own peer inbox; how text gets in. Local to the Mac.

    def to_json(self) -> dict:
        d = asdict(self)
        d.pop("socket_path")
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
    global _pane_cache
    fetched_at, cached = _pane_cache
    age = time.monotonic() - fetched_at
    if age < (PANE_TTL if cached else PANE_RETRY_AFTER):
        return cached
    panes = _fetch_panes()
    _pane_cache = (time.monotonic(), panes)
    return panes


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
                socket_path=rec.get("messagingSocketPath", ""),
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


# How far back to look for the last request's token usage. Small on purpose: it is the last
# assistant entry in the file, and this is read for every session on every listing.
USAGE_WINDOW = 256 * 1024
# What Claude Code compacts at when nothing says otherwise. The real number is
# `autoCompactWindow` in the person's own settings, which is what is read first — this is only
# the floor under a machine that has never set one.
DEFAULT_WINDOW = 200_000
# A turn Claude Code wrote itself rather than one a model answered — an interrupt, an API error.
# It carries a usage dict of zeros, so stopping at one reports an empty context window and names
# `<synthetic>` as the model. The real last request is the entry before it.
SYNTHETIC = "<synthetic>"


@dataclass(slots=True)
class LastRequest:
    """What the session's last request filled, and what answered it."""

    used: int = 0
    model: str = ""
    effort: str = ""

    def to_json(self, window: int) -> dict:
        """The fragment a session's listing entry carries. Absent rather than empty when the
        transcript has not said yet: a row with no model is one nothing has answered."""
        return {
            "context": {"used": self.used, "limit": window},
            "model": self.model or None,
            "effort": self.effort or None,
        }


def last_request(session_id: str) -> LastRequest:
    """How much of the context window the session's last request filled, and what answered it.

    Every assistant entry carries the usage of the request that produced it, and the whole
    prompt is what was billed as input: what was newly written, what was newly cached, and what
    was read back from cache. Output is not in the window — it is what came out of it.

    The model and the reasoning effort sit on that same entry, which is why they cost nothing:
    the scan that finds the usage has already found both. A sidechain is skipped for the usage
    and for them alike — a subagent runs whatever model it was given, not the session's.

    Read over a small window, because this is asked for every session on every listing and the
    answer is always in the last few entries of the file.
    """
    path = transcript_path(session_id)
    if path is None:
        return LastRequest()
    for window in (USAGE_WINDOW, TAIL_WINDOWS[1]):
        for raw in reversed(tail_lines(path, window)):
            entry = parse_line(raw)
            if entry is None or entry.get("type") != "assistant" or entry.get("isSidechain"):
                continue
            message = entry.get("message", {})
            usage = message.get("usage")
            if not isinstance(usage, dict) or message.get("model") == SYNTHETIC:
                continue
            return LastRequest(
                used=sum(
                    value
                    for key in ("input_tokens", "cache_creation_input_tokens",
                                "cache_read_input_tokens")
                    if isinstance(value := usage.get(key), int)
                ),
                model=message.get("model") or "",
                effort=entry.get("effort") or "",
            )
    return LastRequest()


def context_window() -> int:
    """The limit this Mac is configured to compact at, out of Claude Code's own settings."""
    settings = sessions_dir().parent / "settings.json"
    try:
        configured = json.loads(settings.read_text()).get("autoCompactWindow")
    except (OSError, json.JSONDecodeError, AttributeError):
        return DEFAULT_WINDOW
    return configured if isinstance(configured, int) and configured > 0 else DEFAULT_WINDOW


# The statusline's own cache, rewritten every minute by the `com.claude.statusline-cache` agent.
# Deckhand counts no tokens of its own: it reads the object the terminal statusline is already
# reading, so the phone and the Mac cannot quote different numbers at each other.
WEEK_CACHE = "statusline-cache.json"


def week_usage() -> dict | None:
    """How much of the week's token window is spent, how far through the week that is, and how
    long until it resets.

    `pct_used` runs past 100 on a heavy week — the budget is an estimate, not a ceiling — so
    nothing here clamps it. `pct_elapsed` is what makes it mean anything: 152% spent at 51%
    through is the fact, the 152 alone is not.

    None rather than zeros whenever there is nothing true to say: no cache (another Mac, or the
    agent was never installed here), no week object in it, a field missing, or a window that has
    already closed. A frozen cache answering for a week that ended on Sunday is worse than
    answering nothing at all.
    """
    cache = sessions_dir().parent / WEEK_CACHE
    try:
        week = json.loads(cache.read_text())["week"]
        ends = datetime.fromisoformat(week["end"])
        spent = {
            "pct_used": round(week["pct_used"]),
            "pct_elapsed": round(week["pct_elapsed"]),
            "days_remaining": float(week["days_remaining"]),
        }
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError):
        return None
    return spent if ends > datetime.now(UTC) else None
