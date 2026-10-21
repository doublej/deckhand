"""Whether the person is at this Mac, on the phone or in the headset: `laptop`, `phone` or `headset`.

The fact this module produces is not decoration. `deliver.py` says the sharp version of it in
its own first paragraph: on the keyboard route **the daemon is holding JJ's keyboard for him**.
That is exactly right when nobody is at the keyboard and wrong when somebody is, because two
things typing into one pane interleave and neither notices. `auto` used to take the keyboard
whenever the session had a pane — a test of whether a *window* exists, never of whether a
*person* does.

`docs/ownership.md` argues the whole design out. This is the half the daemon needs: the fact.
Nothing here draws anything: utt draws the cover, off `cover()` on `/health`. `deliver` reads
`where()` for one decision — `auto` stops typing into a pane the person is sitting at — and JJ
made that call on 2026-10-11, because it changes how a person's words arrive.

Two states, by JJ's choice (2026-10-11): there was a third, `nobody`, for an idle Mac and a
silent phone, and it answered no question a caller actually asks. Where to reach the person has
two answers, the pane or the phone. Whether the phone is in use survives only as the cover's
gate, where a wrong answer would put a sign over someone's film.

`headset` came third (2026-10-14), because JJ reads the panes in the headset and wanted every
statusline small while he does. Unlike the phone it is not "touched last": the headset says so
every ten seconds while it is worn, so a fresh beat *is* the person, and it wins over a Mac whose
keyboard the window planes are pressing for him. For anything that types, it is the phone: not
`laptop`, so `auto` still takes the keyboard.
"""

from __future__ import annotations

import subprocess
import time

from fastapi import APIRouter, Header, HTTPException

#: No keyboard or mouse for this long and the Mac counts as unattended. Deliberately asymmetric
#: with the way back: any input at all sets `HIDIdleTime` to zero, so the person takes the Mac
#: back the instant they touch it, with nothing to wait through. Two minutes is slow enough that
#: reading the screen does not hand the machine away.
IDLE_AFTER = 120.0
#: The phone counts as in use if the Mac has heard from it this recently. It says *reachable*, not
#: *present* — a phone polling from a desk looks exactly like a phone in a hand, and this cannot
#: tell them apart. Only the cover reads it, and a wrong answer there is a sign, not a lock.
PHONE_RECENT = 300.0
#: The headset beats every ten seconds while it is on a head and stops the moment it comes off,
#: so three missed beats and it is not being worn.
HEADSET_LIVE = 30.0
TIMEOUT = 2.0
#: How long one pair of `ioreg` readings answers `state()`. `/health` and `/presence` together
#: ask about twice a second, for facts that change on a human timescale.
FACTS_FOR = 1.0
_facts: tuple[float, float | None, bool] = (float("-inf"), None, False)

_phone_seen: float | None = None
#: When the person last touched the app — not when it last polled. The app says so itself,
#: through `POST /presence/phone`, because a poll from a phone on a desk is not a person.
_phone_touched: float | None = None
_headset_beat: float | None = None

router = APIRouter()


def seen(request) -> None:
    """The phone just made an authenticated request. Called from the token guard, so it costs
    one assignment on a path every request already takes and needs no route of its own.

    The loopback is never the phone: it is a session's own `deckhand` command or MCP server, and
    an agent asking where the person is must not put utt's cover up by asking. The phone reaches
    this Mac over the LAN or through the NAS.
    ponytail: a hand on another machine is not loopback either; give it its own stamp if one
    ever starts calling this Mac with the token."""
    global _phone_seen
    if request.client is None or request.client.host not in ("127.0.0.1", "::1", "localhost"):
        _phone_seen = time.time()


def idle_seconds() -> float | None:
    """Seconds since the last keyboard or mouse event, or None when the Mac will not say.

    Asked for the one key on the one class (`-r -k -d 1`) rather than the whole IOHIDSystem
    subtree. `ioreg` reports nanoseconds as a plain integer. Parsed off the raw line rather than through
    a locale-aware format, because this Mac is nl_NL and a decimal comma would turn 977 seconds
    into something that is not a number.
    """
    try:
        out = subprocess.run(["/usr/sbin/ioreg", "-r", "-c", "IOHIDSystem", "-k", "HIDIdleTime", "-d", "1"],
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


def where() -> str:
    """`laptop`, `phone` or `headset`: where a person reaching for this Mac would be found right now.

    Unknown idleness reads as `laptop`: this is the answer a caller would act on by keeping its
    hands off the keyboard, and a Mac that will not say whether anyone is at it is not one to
    start typing into.
    """
    return _where(idle_seconds(), locked(), _since(_phone_touched), _since(_headset_beat))


def _since(stamp: float | None) -> float | None:
    return time.time() - stamp if stamp is not None else None


def _where(idle: float | None, screen_locked: bool, touched: float | None = None,
           headset: float | None = None) -> str:
    """The same answer, out of facts already in hand. Separate so `state` can read each of
    them exactly once — see there for what that was costing.

    Whichever was touched last wins: the phone the moment the app is used, the laptop the moment
    a key is pressed. With neither, two minutes untouched hands the Mac to the phone. A headset
    still beating is ahead of all of it."""
    if headset is not None and headset < HEADSET_LIVE:
        return "headset"
    if screen_locked:
        return "phone"
    if idle is None:
        return "laptop"
    if touched is not None and touched < idle:
        return "phone"
    return "laptop" if idle < IDLE_AFTER else "phone"


def cover(now: dict) -> dict | None:
    """What utt's cover says, or None to keep it down, out of one `state()`. Up only when the
    Mac has sat untouched for `IDLE_AFTER` and the phone is actually being used: an untouched Mac
    alone is also someone watching a film on it, and a phone picked up for a second at the desk
    is not a reason to sign over the screen — both are the false positive `docs/ownership.md`
    says must never happen."""
    away = now["locked"] or (now["idle"] is not None and now["idle"] >= IDLE_AFTER)
    if now["where"] != "phone" or not away or now["phone"] is None or now["phone"] > PHONE_RECENT:
        return None
    return {"title": "Deckhand has this Mac",
            "detail": "It is being driven from the phone. Touch anything to take it back."}


def state() -> dict:
    """What `/health` and `/presence` carry, so the phone and every session can say where the
    person is without guessing.

    **Each fact is read once.** This used to call `owner()` beside `idle_seconds()` and
    `locked()`, so one `/health` spawned `ioreg` three or four times over for two answers.
    Neither is cheap: `ioreg` walks the whole IO registry, and the two invocations print 351 KB
    and 206 KB here. Measured against each other in one process, one `state()` went from
    141 ms to 67 ms; on a cold registry it was 406 ms. The phone asks every four seconds, on
    a threadpool thread, for a fact that changes on a human timescale — so the two `ioreg`
    readings are also kept for `FACTS_FOR`. Only those: the phone's and headset's stamps are
    read fresh, so `POST /presence/phone` shows on the very next answer.
    """
    global _facts
    read_at, idle, screen_locked = _facts
    if time.monotonic() - read_at >= FACTS_FOR:
        idle, screen_locked = idle_seconds(), locked()
        _facts = (time.monotonic(), idle, screen_locked)
    touched = _since(_phone_touched)
    seen_ago = _since(_phone_seen)
    beat = _since(_headset_beat)
    return {"where": _where(idle, screen_locked, touched, beat),
            "idle": round(idle, 1) if idle is not None else None,
            "locked": screen_locked,
            "phone": round(seen_ago, 1) if seen_ago is not None else None,
            "touched": round(touched, 1) if touched is not None else None,
            "headset": round(beat, 1) if beat is not None else None}


@router.get("/presence")
def where_the_person_is() -> dict:
    """`where` is `laptop`, `phone` or `headset`: where a session should reach the person."""
    return state()


@router.post("/presence/phone", status_code=204)
def phone_in_hand(x_deckhand_caller: str = Header(default="")) -> None:
    """The person just touched the app. It says so at most every ten seconds and on coming to
    the front, and from then until a key is pressed at the Mac, `where` is `phone`.

    Refused to a caller that says it is an agent: `phone` is what turns `auto` into the keyboard,
    and an agent claiming the person is away is an agent choosing to type as them."""
    if x_deckhand_caller == "agent":
        raise HTTPException(status_code=403, detail="only the phone says it is in a hand")
    global _phone_touched
    _phone_touched = time.time()


@router.post("/presence/headset", status_code=204)
def headset_on() -> None:
    """The headset is being worn: it beats every ten seconds while it is, and for `HEADSET_LIVE`
    after the last beat `where` is `headset`."""
    global _headset_beat
    _headset_beat = time.time()
