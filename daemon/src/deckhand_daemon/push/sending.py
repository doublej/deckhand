"""What goes over APNs: the tokens, the payloads, and the one card each session gets.

The phone cannot do this itself. A backgrounded app gets no promise of running again soon, so
the only thing that can update a Live Activity while the app is closed is a push — which means
APNs, which means this daemon holds the tokens and does the sending.

**One card is one session, not the Mac**, and the kind is the whole of the interruption policy:
`asking` may raise a card and carries the alert, `finished` may only ever update one already on
screen and is silent. `Sources/DeckhandKit/LiveActivity.swift` argues both out; this end sends
them. What decides that there is anything to send is next door, in `__init__.py`.

Two tokens, two jobs. An *activity* token updates one card already on screen, and the phone hands
over one per card, so they are filed by session. A *start* token (iOS 17.2+) raises a new card
when that session has none: after the system ends one, after a reboot, after a force-quit. Without
the second, a card only exists while the app is open, which is the opposite of what it is for.

The signing key is an APNs .p8 from the developer account, read through onenv. It is not the
pairing token and not utt's: a different secret for a different counterparty.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

from .. import config
from ..log import log

# Development, to match the app's `aps-environment`. A production-signed build talks to the
# other host, and a token minted for one is rejected by the other.
HOST = "api.sandbox.push.apple.com"
TOPIC = "dev.jurrejan.deckhand.push-type.liveactivity"
#: A plain notification goes to the app itself, under its bare bundle id.
APP_TOPIC = "dev.jurrejan.deckhand"
#: How much of a manager message a notification carries. iOS shows four lines on the Lock Screen
#: and the rest when it is pulled down; past this the panel is the better place to read it.
MAX_TOLD = 900
TEAM = "KA6433FU8U"
# APNs will not take a token older than an hour; refreshing well inside that is free.
JWT_LIFETIME = 45 * 60
TIMEOUT = 10

#: Why a card exists. The Swift enum's own spellings, and an unknown word decodes there as the
#: quiet one — a daemon that grows a third kind can never make an older phone louder.
ASKING = "asking"
FINISHED = "finished"
#: How much of the line the card can actually draw, by kind. The line is the hero, and an `asking`
#: card gives one of its lines up to the Stop button: two lines of `Typography.lead` 17 hold about
#: 80 characters, three hold about 120. Sending more is not generosity — it is a sentence cut
#: through a third of the way in on precisely the cards that needed a person.
MAX_LINE = {ASKING: 80, FINISHED: 120}
#: What a card says when nothing better could be found. Never empty: that made a card two-thirds
#: air, which is the complaint this was rebuilt for.
NOTHING = {ASKING: "waiting for you", FINISHED: "nothing left on the list"}
#: How long a push-to-start goes unanswered before this Mac raises a second card for the same
#: session. A card raised by push is unaddressable until the phone hands its own token back, and
#: the app must be awake to observe that — measured at nine minutes on 2026-09-11, during which
#: every announce raised one more card.
QUIET = 600.0

#: When this Mac last raised a card for a session, until that card's own token comes back.
_raised: dict[str, float] = {}


@dataclass(frozen=True)
class Card:
    """One session's Lock Screen card. The field names are the Swift struct's, exactly."""

    session: str
    name: str
    kind: str
    line: str
    when: float

    def state(self) -> dict:
        return {"kind": self.kind, "line": self.line, "when": self.when}


def shortened(said: str, kind: str) -> str:
    """One line for a card of this kind, cut at a word rather than through one.

    A card ending `…prepara` reads worse than one that stops a sentence short, and the cards this
    matters most on are the `asking` ones, which have the least room.
    """
    first = " ".join(said.split())
    if len(first) <= (cap := MAX_LINE[kind]):
        return first
    cut = first[:cap - 1]
    return (cut[:cut.rfind(" ")] if " " in cut else cut).rstrip(" ,;:—-") + "…"


def tokens_path() -> Path:
    return config.data_dir() / "push-tokens.json"


def remember(token: str, kind: str, session: str = "") -> None:
    """The phone re-registers on every launch; tokens change without warning.

    An *activity* token addresses **one card**, and the phone hands one over per card —
    `LiveUpdates` walks every live activity at launch and sends the lot. One slot per kind kept
    only the last, so every other card on that Lock Screen was unreachable: nothing could update
    it and nothing could end it. They are filed by session now, because that is what a card is.
    A *start* token belongs to the app rather than to any session and arrives with no `session`
    key at all, which is why the absent one is the start slot rather than an error.
    """
    held = tokens()
    if kind == "activity":
        if not session:
            log.info("lock screen: an activity token arrived with no session, ignoring it")
            return
        cards = _cards(held)
        # Re-posting the same token still says that card is alive, so the hold lifts either way.
        _raised.pop(session, None)
        if cards.get(session) == token:
            return
        held["cards"] = {**cards, session: token}
    elif held.get(kind) == token:
        return
    else:
        held[kind] = token
    _write(held)
    log.info("lock screen: %s token registered%s", kind, f" for {session[:8]}" if session else "")


def tokens() -> dict:
    try:
        held = json.loads(tokens_path().read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return held if isinstance(held, dict) else {}


def _cards(held: dict) -> dict[str, str]:
    """One activity token per session, by session id."""
    found = held.get("cards")
    return found if isinstance(found, dict) else {}


def _write(held: dict) -> None:
    tokens_path().write_text(json.dumps(held, indent=2))
    tokens_path().chmod(0o600)


def _drop(session_id: str) -> None:
    """Forget this session's card — where one is ended, and where APNs says it is already gone."""
    _raised.pop(session_id, None)
    held = tokens()
    cards = _cards(held)
    if session_id in cards:
        _write(held | {"cards": {sid: t for sid, t in cards.items() if sid != session_id}})


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


def show(card: Card, mac: str) -> str | None:
    """Update this session's card, or raise one if it has none. Returns an error, or None.

    Update first, start second: an update to a card that is gone is refused cheaply, whereas
    starting one that exists would put two cards for one session on the Lock Screen. `finished`
    stops there — a list going empty is nothing at all for a quiet Lock Screen.
    """
    if not (auth := bearer()):
        return "no push key on this Mac — run `just sync-apns`"
    held = tokens()
    if token := _cards(held).get(card.session):
        if not (error := _post(token, _update(card), auth, "update")):
            return None
        log.info("lock screen: %s's card would not take it (%s)", card.name, error)
        _drop(card.session)
    if card.kind != ASKING:
        return None
    if time.time() - _raised.get(card.session, 0.0) < QUIET:
        # A start went out and its card has not said which it is. Sending another is how three
        # cards for one session appeared inside nine minutes.
        return f"still waiting for the card this Mac raised for {card.name}"
    if token := held.get("start"):
        error = _post(token, _start(card, mac), auth, "start")
        _raised[card.session] = 0.0 if error else time.time()
        return error
    return "the phone has not handed this Mac a Lock Screen token yet"


def end(session_id: str) -> None:
    """Take this session's card off the Lock Screen. Nothing ever did and iOS takes hours. A card
    that has stopped asking has to *go*, not be updated to say nothing is waiting: parked emptiness
    is what teaches a person to swipe the whole feature away."""
    token = _cards(tokens()).get(session_id)
    _drop(session_id)
    if not token or not (auth := bearer()):
        return
    now = time.time()
    # A dismissal date already past says *now* rather than *whenever this goes stale*, which is
    # hours. The state rides along because the payload carries one; nothing reads it.
    payload = {"aps": {"timestamp": int(now), "event": "end", "dismissal-date": int(now),
                       "content-state": {"kind": FINISHED, "line": NOTHING[FINISHED],
                                         "when": now}}}
    if error := _post(token, payload, auth, "end"):
        log.info("lock screen: %s", error)


def _update(card: Card) -> dict:
    aps = {"timestamp": int(card.when), "event": "update", "content-state": card.state()}
    if card.kind == ASKING:
        aps["alert"] = _alert(card)
    return {"aps": aps}


def _alert(card: Card) -> dict:
    """What makes the phone light up and make a noise. Live Activities need no permission of their
    own, so this asks for nothing the person has not allowed by leaving the card on. Only ever
    built for `asking`: the sound rode on every loud push once."""
    return {"title": card.name or "Deckhand", "body": card.line, "sound": "default"}


def _start(card: Card, mac: str) -> dict:
    # `attributes-type` is the Swift type's bare name. Nothing at runtime checks that the two
    # still agree, so `test_push.py` reads the Swift file and does.
    return {"aps": {"timestamp": int(card.when), "event": "start",
                    "content-state": card.state(),
                    "attributes-type": "Deck",
                    "attributes": {"session": card.session, "name": card.name, "mac": mac},
                    "alert": _alert(card)}}


def told(text: str) -> str | None:
    """One manager message as a notification. Returns an error, or None.

    The *device* token is the app's own, handed over once notifications were allowed; a Live
    Activity card is per session and the manager is not one, which is why this is not a card.
    `thread-id` stacks them as one conversation, and `deckhand` is what a tap opens.
    """
    if not (token := tokens().get("device")):
        return "the phone has not allowed notifications yet"
    if not (auth := bearer()):
        return "no push key on this Mac — run `just sync-apns`"
    body = text if len(text) <= MAX_TOLD else text[:MAX_TOLD - 1].rstrip() + "…"
    payload = {"aps": {"alert": {"title": "Manager", "body": body}, "sound": "default",
                       "thread-id": "manager"},
               "deckhand": "manager"}
    error = _post(token, payload, auth, "notification", push_type="alert", topic=APP_TOPIC)
    if error:
        log.info("manager: %s", error)
    return error


def _post(token: str, payload: dict, auth: str, kind: str, *, push_type: str = "liveactivity",
          topic: str = TOPIC) -> str | None:
    import httpx  # HTTP/2 only: APNs refuses anything else

    headers = {"authorization": f"bearer {auth}", "apns-topic": topic,
               "apns-push-type": push_type, "apns-priority": "10"}
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
