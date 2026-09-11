"""Which Claude Code sessions are alive right now, on the machine this daemon runs on.

Three files, one surface. `live.py` is the join that makes the whole app work — a record under
`~/.claude/sessions/` only counts while `ps` still shows its pid. `panes.py` is the iTerm half.
`usage.py` is what the last request filled and what the week has spent.

Everything below is re-exported so callers read `sessions.live_sessions()` as they always have.
"""

from .live import Session, focus, live_sessions, sessions_dir, succeeded_by
from .panes import Pane
from .panes import forget as forget_panes
from .panes import status as iterm_status
from .usage import (
    DEFAULT_WINDOW,
    SYNTHETIC,
    USAGE_WINDOW,
    WEEK_CACHE,
    LastRequest,
    context_window,
    last_request,
    week_usage,
)

__all__ = [
    "DEFAULT_WINDOW", "SYNTHETIC", "USAGE_WINDOW", "WEEK_CACHE", "LastRequest", "Pane",
    "Session", "context_window", "focus", "forget_panes", "iterm_status", "last_request",
    "live_sessions", "sessions_dir", "succeeded_by", "week_usage",
]
