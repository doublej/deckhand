"""Ending a Claude session by its process: SIGTERM to its pid, on the machine it runs on.

`exit` types `/exit` into a pane, the way the person would at the keyboard. A session with no
pane — on another machine, or one tmux cannot see — has nothing to type into, so before this the
person could end it only from its own terminal. This is the same press for those, and Claude Code
answers SIGTERM by quitting the way `/exit` does.

**Signalled where it runs, after a fresh listing there.** A pid is that session only while `ps`
shows it under that record, so the lookup is repeated right before the signal: that is what stops
a recycled pid ending something else. A remote session goes to its hand by id, which re-lists and
signals there; nothing crosses the wire but the id.

**The person's press alone**: the phone's exit, or their signed Allow on an agent's request
(`push/end_requests.py`). No MCP or manager tool ends a session.
"""

from __future__ import annotations

import os
import signal

from .. import fleet
from ..fleet import remote
from ..log import log
from .live import Session, live_sessions

GONE = "that session is no longer running"


def end(session: Session) -> str | None:
    """Stop that session's process. None once it was signalled, or why not."""
    if session.provider != "claude" or session.pid <= 0:
        return f"{session.name} has no process of its own to end"
    return end_by(session.machine, session.session_id)


def end_by(machine: str, session_id: str) -> str | None:
    """`end`, for a session known only by its machine and id — a tap that arrives hours later."""
    if machine and machine != fleet.here():
        return remote.end_on(machine, session_id)
    return end_here(session_id)


def end_here(session_id: str) -> str | None:
    """SIGTERM to the pid this machine lists for that session right now."""
    live = next((s for s in live_sessions(paned_only=False) if s.session_id == session_id), None)
    if live is None or live.provider != "claude" or live.pid <= 0:
        return GONE
    try:
        os.kill(live.pid, signal.SIGTERM)
    except ProcessLookupError:
        return f"{live.name} had already gone"
    except PermissionError:
        return f"{live.name}'s process is not this user's to end"
    log.info("ended %s (pid %d) by SIGTERM", live.name, live.pid)
    return None
