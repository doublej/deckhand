"""Whether a person is at this Mac, and therefore who owns it right now.

The fact this module produces is not decoration. `deliver.py` says the sharp version of it in
its own first paragraph: on the keyboard route **the daemon is holding JJ's keyboard for him**.
That is exactly right when nobody is at the keyboard and wrong when somebody is, because two
things typing into one pane interleave and neither notices. Today `auto` takes the keyboard
whenever the session has a pane — a test of whether a *window* exists, never of whether a
*person* does.

`docs/ownership.md` argues the whole design out. This is the half the daemon needs: the fact.
Nothing here draws anything, and nothing here changes a route — wiring it into `deliver` changes
how a person's words arrive, which is an authority decision and JJ's to make.

Three states rather than two, because the third is the one worth having. Idle at the Mac with
the phone in hand is a person who can be reached; idle at the Mac and silent on the phone is a
person who cannot. Only the second means a Lock Screen card is the best anyone can do.
"""

from __future__ import annotations

import subprocess
import time

#: No keyboard or mouse for this long and the Mac counts as unattended. Deliberately asymmetric
#: with the way back: any input at all sets `HIDIdleTime` to zero, so the person takes the Mac
#: back the instant they touch it, with nothing to wait through. Two minutes is slow enough that
#: reading the screen does not hand the machine away.
IDLE_AFTER = 120.0
#: The phone counts as here if the Mac has heard from it this recently. It says *reachable*, not
#: *present* — a phone polling from a desk looks exactly like a phone in a hand, and this cannot
#: tell them apart. Nothing should be built on it that a wrong answer would make unsafe.
PHONE_RECENT = 300.0
TIMEOUT = 2.0

_phone_seen: float | None = None


def seen() -> None:
    """The phone just made an authenticated request. Called from the token guard, so it costs
    one assignment on a path every request already takes and needs no route of its own."""
    global _phone_seen
    _phone_seen = time.time()


def idle_seconds() -> float | None:
    """Seconds since the last keyboard or mouse event, or None when the Mac will not say.

    `ioreg` reports nanoseconds as a plain integer. Parsed off the raw line rather than through
    a locale-aware format, because this Mac is nl_NL and a decimal comma would turn 977 seconds
    into something that is not a number.
    """
    try:
        out = subprocess.run(["/usr/sbin/ioreg", "-c", "IOHIDSystem"],
                             capture_output=True, text=True, timeout=TIMEOUT, check=False).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    for line in out.splitlines():
        if "HIDIdleTime" not in line:
            continue
        _, _, value = line.partition("=")
        try:
            return int(value.strip()) / 1_000_000_000
        except ValueError:
            return None
    return None


def locked() -> bool:
    """Whether the screen is locked. The key is absent entirely when it is not, so presence of
    the name is the whole test — there is no false value to read."""
    try:
        out = subprocess.run(["/usr/sbin/ioreg", "-n", "Root", "-d1", "-a"],
                             capture_output=True, text=True, timeout=TIMEOUT, check=False).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return "CGSSessionScreenIsLocked" in out


def owner() -> str:
    """`person`, `deckhand` or `nobody`.

    Unknown idleness reads as `person`: this is the answer a caller would act on by keeping its
    hands off the keyboard, and a Mac that will not say whether anyone is at it is not one to
    start typing into.
    """
    idle = idle_seconds()
    if idle is None:
        return "person"
    if idle < IDLE_AFTER and not locked():
        return "person"
    if _phone_seen is not None and time.time() - _phone_seen < PHONE_RECENT:
        return "deckhand"
    return "nobody"


def state() -> dict:
    """What `/health` carries, so the phone can say who has the Mac without guessing."""
    idle = idle_seconds()
    return {"owner": owner(),
            "idle": round(idle, 1) if idle is not None else None,
            "locked": locked(),
            "phone": round(time.time() - _phone_seen, 1) if _phone_seen else None}
