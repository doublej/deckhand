"""The pairing window: a six-digit code the person at the Mac opens, and a client types once.

**Nothing on the LAN can open one.** `POST /pair/open` needs this Mac's own token, which the
`just pair` recipe and the utt page read off disk; until somebody there asks, every `POST /pair`
is a 410. That is the whole reason this is a code read off the Mac's screen rather than a dialog
asking the Mac to approve a stranger: a dialog is opened *by the stranger*, as often as it likes,
and a person who has clicked twenty of them away clicks the twenty-first.

**What a guesser gets:** `TRIES` wrong codes close the window, so five chances in a million per
window, each window opened by a person standing at the Mac. `BURST` caps every attempt from
anywhere, so a flood costs a 429 and a log line rather than a hot loop. A guesser *can* close a
window by burning its tries — that is a person opening another one, not a way in.

One window at a time, in memory: a restart closes it, which is the safe direction to fail.
"""

from __future__ import annotations

import secrets
import time
from collections import deque
from dataclasses import dataclass

#: How long a code is good for, in seconds.
LASTS = 300
#: Wrong codes before the window closes.
TRIES = 5
#: Pairing attempts accepted per minute, from everywhere together.
BURST = 20


class Refused(Exception):
    """A pairing attempt that does not pair, with the status and sentence it answers."""

    def __init__(self, status: int, detail: str) -> None:
        super().__init__(detail)
        self.status = status
        self.detail = detail


@dataclass
class Window:
    code: str
    closes: float
    tries: int = TRIES


_open: Window | None = None
_attempts: deque[float] = deque()


def open_window() -> Window:
    """Open a window, replacing any open one: the code on the screen is the only one that works."""
    global _open
    _open = Window(code=f"{secrets.randbelow(10**6):06d}", closes=time.time() + LASTS)
    return _open


def current() -> Window | None:
    global _open
    if _open is not None and time.time() >= _open.closes:
        _open = None
    return _open


def take(code: str) -> None:
    """Spend the open window on `code`, or refuse. Success closes it: one code, one device."""
    global _open
    now = time.time()
    while _attempts and now - _attempts[0] > 60:
        _attempts.popleft()
    if len(_attempts) >= BURST:
        raise Refused(429, "too many pairing attempts; wait a minute")
    _attempts.append(now)
    window = current()
    if window is None:
        raise Refused(410, "no pairing code is open on this Mac; open one there with `just pair`")
    typed = "".join(ch for ch in code if ch.isdigit())
    if secrets.compare_digest(typed, window.code):
        _open = None
        return
    window.tries -= 1
    if window.tries <= 0:
        _open = None
        raise Refused(410, "too many wrong codes; open a new one on the Mac")
    raise Refused(403, "that is not the code on the Mac")


def spaced(code: str) -> str:
    """`482 913`: two halves are what a person reads off one screen and types into another."""
    return f"{code[:3]} {code[3:]}"
