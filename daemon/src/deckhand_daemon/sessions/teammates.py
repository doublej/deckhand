"""A pane whose prompt box is talking to a teammate, and taking it back to the lead.

An agent team's lead lists its teammates under the box: Down reaches the list, Enter opens one,
and from then on everything typed goes to that teammate, the phone's words included. The daemon
then watches the lead's transcript for words that went into the teammate's, calls them unsent,
and the phone puts the card back to be sent again. Nothing on the phone set this and nothing on
the phone shows it, so it is read off the pane: the rule over the box carries `@name`.

**The way back was measured, not documented** (Claude Code 2.1.304, a throwaway pane): with the
box empty, Down puts the list's cursor on `main`, its first row; Enter opens it; Escape then
lets go of the list. Escape is also the key that interrupts a running turn, which it is only
when the list does *not* have the cursor — so every key here is pressed only after the screen
shows the state it belongs to, and anything unexpected stops the presses and says why. The list
is not always drawn, either: collapsed to "← 1 agent", Down reaches nothing and this gives up.
"""

from __future__ import annotations

import re
import time
from collections.abc import Callable
from typing import TYPE_CHECKING

from . import panes

if TYPE_CHECKING:
    from .live import Session

#: The rule over Claude Code's prompt box carries `@name` while the box speaks to a teammate.
TEAMMATE = re.compile(r"─ @(\S+) ─[ ]*\n❯")
#: The team list under the box with its cursor on the lead's row.
ON_MAIN = re.compile(r"^❯ [⏺◯] main\b", re.MULTILINE)
DOWN = "\x1b[B"
ENTER = "\x1b[13u"
ESCAPE = "\x1b"
SETTLE = 1.5  # seconds a key gets to show on the screen; measured well under half a second
POLL = 0.1


def addressed_to(pane_id: str) -> str | None:
    """The teammate this pane's box is talking to, or None while it talks to the lead."""
    found = TEAMMATE.findall(panes.screen(pane_id))
    return found[-1] if found else None


def bring_back(session: Session, clear: str) -> str | None:
    """Point the box back at the lead. None once it does, otherwise why it still does not.

    `clear` is the caller's way of emptying the box, so it is emptied as it is before any typing.
    """
    pane = session.pane.iterm_session_id if session.pane else ""
    teammate = pane and addressed_to(pane)
    if not teammate:
        return None
    why = f"{session.name}'s box is set to its teammate @{teammate}"
    if session.status == "busy":
        return f"{why}, and its keys are not to be pressed mid-turn"
    steps = (
        (DOWN, lambda screen: bool(ON_MAIN.search(screen))),
        (ENTER, lambda screen: not TEAMMATE.search(screen) and bool(ON_MAIN.search(screen))),
        (ESCAPE, lambda screen: not TEAMMATE.search(screen) and not ON_MAIN.search(screen)),
    )
    # Down in a box holding words moves through the words, not into the list.
    if not panes.press(pane, clear):
        return f"{why}, and tmux would not clear its box"
    for key, shows in steps:
        if not (panes.press(pane, key) and _waits_for(pane, shows)):
            return f"{why}, and taking it back to {session.name} did not go as measured"
    return None


def _waits_for(pane_id: str, shows: Callable[[str], bool]) -> bool:
    end = time.monotonic() + SETTLE
    while not shows(panes.screen(pane_id)):
        if time.monotonic() >= end:
            return False
        time.sleep(POLL)
    return True
