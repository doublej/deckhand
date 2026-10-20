"""The tmux pane a session sits in, and what to say when tmux will not answer.

`tmux list-panes -a` maps a tty to a pane, and that map is the only reason a session is
addressable by keyboard rather than only down its inbox socket. It is cached because the phone
polls every few seconds; it backs off because when tmux is not answering, nothing about the
answer changes in the next minute. A session in a terminal tmux does not run in has no pane.

**The pane's keys keep iTerm's names**, `iterm_session_id` and the rest, because the phone's
`Pane` decodes exactly those and an installed app cannot be told otherwise. Each holds tmux's
own value: the pane id (`%3`), the window id (`@2`), `session:window` and the pane's title.

A machine that is not this Mac has no pane at all, and that is a listing with an empty map
rather than a failure — `live.live_sessions` already keeps every session when there are none.
"""

from __future__ import annotations

import re
import subprocess
import time
from dataclasses import dataclass

from ..log import log

PANE_TTL = 3.0  # seconds; the phone polls every few
# When tmux will not answer, nothing about the answer changes in the next minute either.
PANE_RETRY_AFTER = 60.0
PANE_TIMEOUT = 12
TYPE_TIMEOUT = 15
#: One pane per line, tab-separated: tty, pane id, window id, `session:window`, and the title the
#: program in it set, which is what iTerm showed as a session's name.
FORMAT = "#{pane_tty}\t#{pane_id}\t#{window_id}\t#{session_name}:#{window_index}\t#{pane_title}"
_pane_cache: tuple[float, dict] = (0.0, {})
_pane_error: str | None = None


@dataclass(slots=True)
class Pane:
    iterm_session_id: str
    window_id: str
    tab_id: str
    title: str



def forget() -> None:
    """Drop the cached pane map, so the next lookup asks tmux again.

    For the one caller that knows the map is stale rather than merely old: a window opened a
    second ago is a pane this cache was built before, and a session reported with no pane reads
    as a session that cannot be typed into.
    """
    global _pane_cache
    _pane_cache = (0.0, {})


def status() -> str:
    """What the phone should be told about the tmux side: "ok" or why panes are missing."""
    return _pane_error or "ok"


def lookup() -> dict[str, Pane]:
    """tty short name -> tmux pane. Empty when no tmux server is running."""
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
            ["tmux", "list-panes", "-a", "-F", FORMAT],
            capture_output=True,
            text=True,
            timeout=PANE_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired:
        _pane_error = "tmux did not answer in time"
        log.warning("panes unavailable: tmux timed out")
        return {}
    except OSError as error:
        _pane_error = f"cannot run tmux: {error}"
        log.warning("panes unavailable: %s", error)
        return {}
    if out.returncode != 0:
        # No server is the usual reason: nothing is running in tmux, so nothing has a pane.
        _pane_error = f"tmux exited {out.returncode}: {out.stderr.strip()[:120]}"
        log.warning("panes unavailable: %s", _pane_error)
        return {}
    _pane_error = None
    return parse(out.stdout)


def parse(listing: str) -> dict[str, Pane]:
    """`FORMAT`'s lines as tty short name -> pane."""
    panes: dict[str, Pane] = {}
    for line in listing.splitlines():
        tty, pane, window, place, title = (line.split("\t", 4) + [""] * 5)[:5]
        if tty and pane:
            panes[tty.removeprefix("/dev/")] = Pane(
                iterm_session_id=pane, window_id=window, tab_id=place, title=title.strip()
            )
    return panes


def press(pane_id: str, burst: str) -> bool:
    """Type one burst into the pane, every byte as it is. False when tmux would not."""
    try:
        done = subprocess.run(
            # `-l`: every byte as it is, so the CSI-u keys reach the pane exactly as spelled.
            ["tmux", "send-keys", "-t", pane_id, "-l", burst],
            capture_output=True,
            text=True,
            timeout=TYPE_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as error:
        log.warning("could not type into pane %s: %s", pane_id, error)
        return False
    if done.returncode != 0:
        log.warning("tmux refused to type into %s: %s", pane_id, done.stderr.strip()[:120])
        return False
    return True


#: Claude Code's prompt box: a rule with a name in it over the box, a bare rule under it.
BOX = re.compile(r"^─+ \S.* ─ *\n((?:.*\n)*?)─+ *$", re.MULTILINE)


def screen(pane_id: str) -> str:
    """The pane's visible rows as plain text, or nothing where tmux would not read it."""
    try:
        out = subprocess.run(["tmux", "capture-pane", "-p", "-t", pane_id], capture_output=True,
                             text=True, timeout=PANE_TIMEOUT, check=False)
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout


def holds(pane_id: str, words: str) -> bool | None:
    """Whether the prompt box still holds the end of `words`; None where no box is drawn.

    The end, because that is what was typed last and what a submit takes with it. Compared with
    every space taken out, because the box wraps a line wherever it likes.
    """
    found = BOX.findall(screen(pane_id))
    if not found:
        return None
    tail = "".join(words.split())[-40:]
    return tail in "".join(found[-1].replace("❯", " ").split())
