"""`POST /notify`: an alert with no session behind it, whose buttons answer a caller on this Mac.

atlas asks the person something that is no session's — a visitor wanting into a dev hostname —
and wants the answer back. It goes up as a **Lock Screen card** with the caller's two labels on
inline buttons, filed as the session `notify:<id>`, which no session id is spelled like. A phone
that cannot take a card yet (no start token) gets one alert instead, under a category the app
registered at launch — an alert cannot carry buttons, so the action set has to be one it knows.
Either tap comes back signed by the phone's key and checked exactly as a decision's is
(`answering.proven`). Only then does this Mac POST the caller's own body to the caller's own URL,
and the card comes down.

**The callback never leaves this Mac.** URL and body are kept here by notify id and never go into
the APNs payload, so neither a caller nor a phone can redirect where the daemon posts. The URL must
be plain http to 127.0.0.1 or localhost, and is posted as rebuilt from its checked parts, with no
redirects and no proxy: anything looser makes this route a way to make the daemon POST anywhere.

**One id, one callback.** The first tap's result is kept and every later tap — a second device, a
retry — is answered from it, never posted again. A 404 means it was decided elsewhere and is
dropped quietly; anything else is retried once and then said on the phone. Kept 24 hours.
"""

from __future__ import annotations

import json
import secrets
import threading
import time
from urllib.parse import urlsplit

import httpx
from fastapi import HTTPException

from .. import config
from ..decisions import answering
from ..log import log
from . import sending

#: Action sets the app has buttons for, by their ids, and the category it registered for each
#: (`DecisionNotes.register`). Labels are the caller's and only checked: the app draws its own.
CATEGORIES = {frozenset({"approve", "deny"}): "CALLBACK_ALLOW_DENY"}
CAP = 4096
MAX_ACTIONS = 4
KEEP = 24 * 3600
HOSTS = ("127.0.0.1", "localhost")
#: What stands in the callback body for the tapped action's id.
ACTION = "$action"
#: The signed payload's `session` for a notify. No session id is spelled like it.
SIGNED_AS = "notify"
RETRY_AFTER = 3.0
TIMEOUT = 5.0

# ponytail: one lock for every notify, held through the callback; per-id locks if taps ever queue.
_lock = threading.Lock()


def _bad(why: str) -> HTTPException:
    return HTTPException(status_code=400, detail=why)


def parsed(raw: bytes) -> dict:
    """The request, checked: `{title, line, category, actions, url, body}`. 400 for anything off."""
    if len(raw) > CAP:
        raise _bad(f"the body is over {CAP} bytes")
    try:
        said = json.loads(raw)
    except ValueError:
        raise _bad("the body is not JSON") from None
    if not isinstance(said, dict):
        raise _bad("the body is not a JSON object")
    title, line = (sending.shortened(said.get(key) if isinstance(said.get(key), str) else "",
                                     sending.ASKING) for key in ("title", "line"))
    if not (title and line):
        raise _bad("a notify needs a title and a line")
    actions = said.get("actions")
    if (not isinstance(actions, list) or not 0 < len(actions) <= MAX_ACTIONS or not all(
            isinstance(one, dict) and isinstance(one.get("id"), str)
            and isinstance(one.get("label"), str) and one["label"].strip() for one in actions)):
        raise _bad(f"actions must be 1 to {MAX_ACTIONS} of {{id, label}}")
    ids = [one["id"] for one in actions]
    category = CATEGORIES.get(frozenset(ids)) if len(set(ids)) == len(ids) else None
    if category is None:
        raise _bad(f"the phone has no buttons for the actions {ids}")
    callback = said.get("callback")
    if not isinstance(callback, dict) or not isinstance(callback.get("body"), dict):
        raise _bad("callback must be {url, body} with body a JSON object")
    return {"title": title, "line": line, "category": category, "actions": ids,
            "labels": {one["id"]: one["label"].strip() for one in actions},
            "url": _loopback(callback.get("url")), "body": callback["body"]}


def _loopback(url: object) -> str:
    """The URL rebuilt from its checked parts, so what is posted is exactly what was checked."""
    parts = urlsplit(url) if isinstance(url, str) else None
    try:
        port = parts.port if parts else None
    except ValueError:
        port = None
    # The netloc held to `host:port` alone also refuses userinfo and a padded or odd port.
    if (parts is None or parts.scheme != "http" or parts.hostname not in HOSTS or port is None
            or parts.netloc != f"{parts.hostname}:{port}"):
        raise _bad("callback.url must be http://127.0.0.1:<port>/… or http://localhost:<port>/…")
    query = f"?{parts.query}" if parts.query else ""
    return f"http://{parts.hostname}:{port}{parts.path or '/'}{query}"


def filled(value: object, action: str) -> object:
    """Every exact `"$action"` string value replaced by `action`. Keys, and strings that merely
    contain it, stay as they are."""
    if value == ACTION:
        return action
    if isinstance(value, dict):
        return {key: filled(kept, action) for key, kept in value.items()}
    if isinstance(value, list):
        return [filled(kept, action) for kept in value]
    return value


def _path():
    return config.data_dir() / "notify-callbacks.json"


def _kept() -> dict:
    """Every callback younger than a day, by notify id."""
    try:
        held = json.loads(_path().read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(held, dict):
        return {}
    now = time.time()
    return {nid: row for nid, row in held.items() if now - row.get("at", 0) < KEEP}


def _keep(held: dict) -> None:
    part = _path().with_suffix(".json.part")
    part.write_text(json.dumps(held))
    part.chmod(0o600)
    part.replace(_path())


def payload(nid: str, asked: dict) -> dict:
    """The alert: the caller's title over its line, the category, and the id. No callback."""
    return {"aps": {"alert": {"title": asked["title"], "body": asked["line"]}, "sound": "default",
                    "category": asked["category"], "thread-id": SIGNED_AS},
            "notify": {"id": nid, "question": asked["title"]}}


def card(nid: str, asked: dict) -> sending.Card:
    """The card: the title as its name, the line under it, Yes as `approve` and No as `deny`.

    ponytail: one action set, so the two buttons are those two ids; a second category needs the
    pair carried in `CATEGORIES`."""
    labels = asked["labels"]
    return sending.Card(session=f"{SIGNED_AS}:{nid}", name=asked["title"], kind=sending.ASKING,
                        line=asked["line"], when=time.time(), notify=nid,
                        accept=labels["approve"], decline=labels["deny"])


def notify(raw: bytes) -> str:
    """Keep the callback, raise the card — or send the alert when the card cannot go up. The
    notify id; 400, 502 (APNs) or 503 (this Mac)."""
    asked = parsed(raw)
    return sent(asked, {key: asked[key] for key in ("url", "body", "actions")})


def sent(asked: dict, row: dict) -> str:
    """Keep `row` by a new notify id and raise the card `asked` describes, or its alert. A row
    with `ends` instead of `url` is answered in this daemon (`end_requests.py`), never posted."""
    nid = secrets.token_hex(8)
    row = row | {"at": time.time()}
    with _lock:
        _keep(_kept() | {nid: row})
    # The Mac's own name, as `push.announce` writes it for a session on this machine.
    mac = config.base_url().removeprefix("http://").split(":")[0]
    if (missed := sending.show(card(nid, asked), mac)) is None:
        log.info("notify %s: a card for %r", nid, asked["title"])
        return nid
    log.info("notify %s: no card (%s), sending the alert", nid, missed)
    error = sending.alert(payload(nid, asked), f"{SIGNED_AS}:{nid}")
    if error is None:
        log.info("notify %s: the phone was told %r", nid, asked["title"])
        return nid
    with _lock:
        _keep({kept: one for kept, one in _kept().items() if kept != nid})
    # `sending.alert` words its own failures: APNs' answer starts with APNs, the rest is this Mac.
    raise HTTPException(status_code=502 if error.startswith("APNs") else 503, detail=error)


def answered(nid: str, proof: object, token: str) -> dict:
    """Check the phone's signed tap, then call back once. `{action, status}`, or 502 with why."""
    _, said = answering.proven(proof, token, session=SIGNED_AS, artifact=nid)
    with _lock:
        held = _kept()
        row = held.get(nid)
        if row is None:
            raise answering.refusal(410, "EXPIRED", "this notify lapsed before it was answered")
        if "result" not in row:
            if said["value"] not in row["actions"]:
                raise answering.refusal(400, "MISMATCH", "that action is not one this offered")
            row["result"] = _answered_to(row, said["value"]) | {"action": said["value"]}
            _keep(held | {nid: row})
            sending.end(f"{SIGNED_AS}:{nid}")
            log.info("notify %s: %s, the caller answered %s", nid, said["value"],
                     row["result"]["status"] or row["result"]["error"])
    result = row["result"]
    if result["error"]:
        raise HTTPException(status_code=502, detail=result["error"])
    return {"action": result["action"], "status": result["status"]}


def _answered_to(row: dict, action: str) -> dict:
    """The caller told which button was tapped: over loopback HTTP, or here for an end request."""
    if "ends" in row:
        from . import end_requests  # it imports this module to send its alert

        return end_requests.tapped(row["ends"], action)
    return _called(row["url"], filled(row["body"], action))


def _called(url: str, body: object) -> dict:
    """POST once, and once more after a pause if that failed. `{status, error}`, status 0 when
    the caller could not be reached. 2xx is done and 404 is decided elsewhere: neither is an
    error, and neither is retried."""
    for attempt in range(2):
        if attempt:
            time.sleep(RETRY_AFTER)
        try:
            status = httpx.post(url, json=body, timeout=TIMEOUT, follow_redirects=False,
                                trust_env=False).status_code
        except httpx.HTTPError as error:
            status, why = 0, f"the caller could not be reached ({error})"
        else:
            if 200 <= status < 300 or status == 404:
                return {"status": status, "error": None}
            why = f"the caller answered {status}"
    return {"status": status, "error": why}
