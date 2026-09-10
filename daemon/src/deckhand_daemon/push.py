"""Puts a card on the phone's Lock Screen when a session stops and waits for you.

The phone cannot do this itself. A backgrounded app gets no promise of running again soon, so
the only thing that can update a Live Activity while the app is closed is a push — which means
APNs, which means this daemon holds the tokens and does the sending.

Two tokens, two jobs. An *activity* token updates the card already on screen. A *start* token
(iOS 17.2+) raises a new one when there is none: after the system ends one, after a reboot,
after the app is force-quit. Without the second, the card only ever exists while the app is
open, which is the opposite of what it is for.

The signing key is an APNs .p8 from the developer account, read through onenv. It is not the
pairing token and not utt's: a different secret for a different counterparty.
"""

from __future__ import annotations

import asyncio
import json
import time
from dataclasses import dataclass
from pathlib import Path

from . import artifacts, config, sessions
from .log import log
from .reading import transcripts
from .settings import wants

# Development, to match the app's `aps-environment`. A production-signed build talks to the
# other host, and a token minted for one is rejected by the other.
HOST = "api.sandbox.push.apple.com"
TOPIC = "dev.jurrejan.deckhand.push-type.liveactivity"
TEAM = "KA6433FU8U"
# APNs will not take a token older than an hour; refreshing well inside that is free.
JWT_LIFETIME = 45 * 60
TIMEOUT = 10


@dataclass(frozen=True)
class Card:
    """What the Lock Screen shows. The field names are the Swift struct's, exactly."""

    waiting: int
    name: str
    line: str
    when: float

    def state(self) -> dict:
        return {"waiting": self.waiting, "name": self.name, "line": self.line, "when": self.when}


def tokens_path() -> Path:
    return config.data_dir() / "push-tokens.json"


def remember(token: str, kind: str) -> None:
    """The phone re-registers on every launch; tokens change without warning."""
    held = tokens()
    if held.get(kind) == token:
        return
    held[kind] = token
    tokens_path().write_text(json.dumps(held, indent=2))
    tokens_path().chmod(0o600)
    log.info("lock screen: %s token registered", kind)


def tokens() -> dict[str, str]:
    try:
        held = json.loads(tokens_path().read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return held if isinstance(held, dict) else {}


def signing_key() -> tuple[str, str] | None:
    """The APNs key and its id, or None. Materialised to a file for the same reason utt's
    token once was: 1Password cannot ask for a fingerprint under launchd, so `just sync-apns`
    puts it where the daemon can read it."""
    key = config.data_dir() / "apns.p8"
    ident = config.data_dir() / "apns-key-id"
    if not (key.exists() and ident.exists()):
        return None
    try:
        return key.read_text(), ident.read_text().strip()
    except OSError as error:
        log.warning("could not read the push key: %s", error)
        return None


_bearer: tuple[str, float] | None = None


def bearer() -> str | None:
    """APNs refuses a token older than an hour and refuses being handed a fresh one too
    often, so it is minted on a timer rather than per request."""
    global _bearer
    if _bearer and time.time() < _bearer[1]:
        return _bearer[0]
    held = signing_key()
    if not held:
        return None
    import jwt  # only needed when a key exists, and it drags in cryptography

    key, ident = held
    now = int(time.time())
    token = jwt.encode({"iss": TEAM, "iat": now}, key, algorithm="ES256",
                       headers={"kid": ident})
    _bearer = (token, now + JWT_LIFETIME)
    return token


def show(card: Card, mac: str, loud: bool = False) -> str | None:
    """Update the card, or raise one if none is on screen. Returns an error, or None.

    Update first, start second: an update to a card that is gone is refused cheaply, whereas
    starting one that already exists would put two identical cards on the Lock Screen.

    `loud` is the difference between a card that changes and a card that reaches you. An update
    with no `alert` is a silent redraw: iOS swaps the numbers on the Lock Screen and never lights
    the screen, plays a sound or raises a banner. It is the right default — most updates here are
    the card's own bookkeeping — and it was also the whole of it, so nothing ever interrupted.
    """
    if not (auth := bearer()):
        return "no push key on this Mac — run `just sync-apns`"
    held = tokens()
    if token := held.get("activity"):
        if not (error := _post(token, _update(card, loud), auth, "update")):
            return None
        log.info("lock screen: the open card would not take it (%s), starting a new one", error)
    if token := held.get("start"):
        return _post(token, _start(card, mac), auth, "start")
    return "the phone has not handed this Mac a Lock Screen token yet"


def _update(card: Card, loud: bool) -> dict:
    aps = {"timestamp": int(card.when), "event": "update", "content-state": card.state()}
    if loud:
        aps["alert"] = _alert(card)
    return {"aps": aps}


def _alert(card: Card) -> dict:
    """What makes the phone light up and make a noise. Live Activities need no notification
    permission of their own, so this asks for nothing the person has not already allowed by
    leaving the card switched on."""
    return {"title": card.name or "Deckhand", "body": card.line or "waiting for you",
            "sound": "default"}


def _start(card: Card, mac: str) -> dict:
    # `attributes-type` is the Swift type's bare name. Rename `Deck` and this string has to
    # move with it, because nothing checks that they still agree.
    return {"aps": {"timestamp": int(card.when), "event": "start",
                    "content-state": card.state(),
                    "attributes-type": "Deck", "attributes": {"mac": mac},
                    "alert": _alert(card)}}


def _post(token: str, payload: dict, auth: str, kind: str) -> str | None:
    import httpx  # HTTP/2 only: APNs refuses anything else

    headers = {"authorization": f"bearer {auth}", "apns-topic": TOPIC,
               "apns-push-type": "liveactivity", "apns-priority": "10"}
    try:
        with httpx.Client(http2=True, timeout=TIMEOUT) as client:
            answer = client.post(f"https://{HOST}/3/device/{token}", json=payload,
                                 headers=headers)
    except httpx.HTTPError as error:
        return f"APNs unreachable: {error}"
    if answer.status_code == 200:
        log.info("lock screen: %s delivered", kind)
        return None
    # APNs says why in the body, and the reason is the only useful part of a failure.
    reason = (answer.json() or {}).get("reason", answer.text) if answer.content else answer.text
    return f"APNs refused the {kind} ({answer.status_code}): {reason}"


# --- when there is something to say -------------------------------------------------------
#
# A session going from busy to idle is the moment worth a card: it has stopped, and it is
# waiting for you. Nothing else here is an event — a session that has been idle for an hour is
# not news, and a busy one is not either.

POLL = 5.0
_seen: dict[str, str] = {}
_waiting: dict[str, float] = {}
#: How many slips each session had waiting last sweep. A *new* one is the event; a slip that has
#: been sitting there all afternoon is not, which is the same rule `_seen` applies to busy.
_slips: dict[str, int] = {}
#: What an agent asked to be told, per session, where one asked. Beats `_last_line`, because an
#: agent that used its own words meant them.
_said: dict[str, str] = {}


async def watch() -> None:
    """Poll for sessions that have just stopped. Runs beside the plugin watcher."""
    while True:
        await asyncio.sleep(POLL)
        try:
            await asyncio.to_thread(sweep)
        except OSError as error:
            log.warning("lock screen sweep failed: %s", error)


def sweep() -> None:
    live = sessions.live_sessions()
    alive = {s.session_id for s in live}
    # Two reasons to send, and only one of them is worth interrupting a person for.
    loud = False
    left = False
    for session in live:
        was, now = _seen.get(session.session_id), session.status
        _seen[session.session_id] = now
        # `was` is None the first time we see a session, and a session that was already idle
        # when the daemon started is not something that just happened.
        if was == "busy" and now != "busy":
            # Asked per folder rather than once for the Mac: the card is the only thing here a
            # person has an opinion about project by project, and "not this one" is the shape
            # that opinion takes.
            if not wants.resolved(session.cwd).finished:
                log.info("lock screen: %s stopped, but this folder is set quiet", session.name)
                continue
            _waiting[session.session_id] = time.time()
            loud = True
            log.info("lock screen: %s stopped and is waiting", session.name)
        loud = _slipped(session) or loud
    for gone in set(_waiting) - alive:
        del _waiting[gone]
        _said.pop(gone, None)
        left = True
    for gone in set(_seen) - alive:
        del _seen[gone]
    for gone in set(_slips) - alive:
        del _slips[gone]
    if loud or left:
        announce(live, loud=loud)


def _slipped(session) -> bool:
    """Whether this session has just put a slip on the phone that nothing has answered.

    A directory listing per session per sweep, which is the honest cost of noticing a file
    appear without watching the filesystem. It is a handful of `stat` calls against a folder the
    session itself wrote to seconds ago, so it is warm.
    # ponytail: polled; a real watcher if this ever shows up in the log's timings.
    """
    waiting = int(artifacts.counted(session).get("artifacts_waiting", 0) or 0)
    was = _slips.get(session.session_id)
    _slips[session.session_id] = waiting
    # `was` is None the first time, and slips that were already sitting there when the daemon
    # started are not something that just happened.
    if was is None or waiting <= was:
        return False
    if not wants.resolved(session.cwd).slips:
        log.info("lock screen: %s has a slip waiting, but this folder is set quiet", session.name)
        return False
    _waiting[session.session_id] = time.time()
    log.info("lock screen: %s is waiting on a slip", session.name)
    return True


def called(session, line: str) -> str | None:
    """An agent asking for you outright, in its own words. Returns an error, or None.

    The one trigger here a session decides for itself, which is why it is the one with a folder
    switch that can refuse it outright rather than merely stay quiet: everything else on this
    Lock Screen is the Mac noticing something, and this is a program asking to interrupt you.
    """
    if not wants.resolved(session.cwd).called:
        return "this folder is set not to be interrupted"
    _waiting[session.session_id] = time.time()
    _said[session.session_id] = " ".join(line.split())[:120]
    announce(sessions.live_sessions(), loud=True)
    return None


def spoke_to(session_id: str) -> None:
    """You answered it, so it is no longer waiting — whether or not you did it from the card."""
    _said.pop(session_id, None)
    if _waiting.pop(session_id, None) is not None:
        announce(sessions.live_sessions())


def announce(live: list, loud: bool = False) -> None:
    by_id = {s.session_id: s for s in live}
    newest = max(_waiting, key=lambda sid: _waiting[sid], default=None)
    session = by_id.get(newest) if newest else None
    card = Card(
        waiting=len(_waiting),
        name=session.name if session else "",
        line=(_said.get(newest) or _last_line(newest)) if newest else "",
        when=time.time(),
    )
    mac = config.base_url().removeprefix("http://").split(":")[0]
    if error := show(card, mac, loud):
        log.info("lock screen: %s", error)


def _last_line(session_id: str) -> str:
    """The first sentence of what it last said, which is usually the question it is asking."""
    turns = transcripts.read_turns(session_id, 3)
    said = next((t.text for t in reversed(turns) if t.role == "assistant" and t.text), "")
    first = " ".join(said.split())
    return first[:120] + ("…" if len(first) > 120 else "")
