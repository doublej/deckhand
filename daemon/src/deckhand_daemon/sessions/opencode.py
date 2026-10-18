"""The OpenCode sessions on this Mac, over the OpenCode service's own HTTP API.

OpenCode 2 is a client and a server. Every TUI, `opencode run` and desktop window is a client of
one background service per user, which owns the sessions, runs their agent loops and answers an
HTTP API (`/api/...`, described by its own `/openapi.json`). That makes it the easiest provider
here to reach: no pid record, no pane, no socket file. The service writes its address and a
password into `~/.local/state/opencode/service.json`, and everything below is one HTTP call. Read
off OpenCode 2.0.31 and the OpenAPI document it served on 2026-10-16.

**Found, never started.** The registration is read and the service is asked; an absent or stale
one is a listing with no OpenCode rows. Starting the service is OpenCode's business (`opencode
service start`, or opening any client), and a daemon that spawned it would own a process nobody
asked for.

**Basic auth as `opencode` with the registration's password**, which is what
`@opencode/client/service`'s `headers()` builds. Re-read whenever the file changes, because
`opencode service restart` moves both the port and the password.

**Which sessions count as live is JJ's choice, made on 2026-10-16:** a root session that is running
now, that a TUI on this Mac has open as a TUI tab, or that was touched in the last two hours.
OpenCode keeps every session it ever had, so "the process is alive", which is the rule for
Claude, means nothing here. Each row says which of them a TUI has open (`in_client`, worked out
in `opencode_tabs.py`), so the phone can tell what is still open from what merely happened
lately. Children (`parentID`) are a session's subagents, and the phone reads them under that
session (`opencode_turns.children`).

`opencode_input.py` is everything that changes a session and `opencode_turns.py` everything that
reads one; this file is the link, the listing and starting one.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import TYPE_CHECKING

import httpx

from ..log import log
from . import opencode_tabs

if TYPE_CHECKING:
    from .live import Session
    from .usage import LastRequest

#: What the listing waits, per call, before the service counts as not answering. The listing is
#: built under the lock every route waits on, so this is what a hung service costs `/sessions`.
TIMEOUT = 2.0
#: What a call the person made waits: starting a session, reading its turns, putting words in.
WAIT = 15.0
#: After a listing got no answer, how long before the listing asks again. Codex's rule: a service
#: that has gone costs its timeout once, never once per poll.
RETRY_AFTER = 30.0
#: How long after its last activity an idle session stays on the phone.
LIVE_FOR = 2 * 60 * 60
#: Root sessions read per page of the listing, newest first, and how many pages at most.
PAGE = 50
PAGES = 3
#: One client for the daemon's life. `httpx.request` builds a client and an SSL context per call,
#: which was a third of a listing's time spent on a plain-HTTP loopback service.
_client = httpx.Client()
#: How often a running session's context figure is read again. Its `updated` moves every step.
USAGE_EVERY = 10.0
#: How long the model catalogue's context limits are kept. They change when a provider does.
MODELS_FOR = 600.0
USER = "opencode"
PROVIDER = "opencode"


class OpenCodeError(RuntimeError):
    """OpenCode answered, and the answer was no."""


class Unreachable(OpenCodeError):
    """The service is not registered, not there, or did not answer in time."""


def owns(session_id: str) -> bool:
    """Whether an id is an OpenCode session's, for a caller holding an id and no `Session`.
    OpenCode prefixes every session id `ses_`; Claude Code's and Codex's are UUIDs."""
    return session_id.startswith("ses_")


def registration_path() -> Path:
    if given := os.environ.get("DECKHAND_OPENCODE_SERVICE"):
        return Path(given)
    state = os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state"
    return Path(state) / "opencode" / "service.json"


#: The registration as last read, keyed on the file's mtime.
_registered: tuple[float, dict] = (0.0, {})
#: When the listing last asked, and whether it was answered. `/health` reads the second half.
_asked: tuple[float, bool] = (0.0, False)
#: session id -> (its `updated` when read, when read, what its last request filled, and the
#: (provider, model) that filled it).
_usage: dict[str, tuple[float, float, LastRequest, tuple[str, str]]] = {}
#: (when read, (providerID, model id) -> context limit).
_limits: tuple[float, dict[tuple[str, str], int]] = (0.0, {})
#: session id -> the root session it is a subagent of (itself for a root). A parent never changes.
_roots: dict[str, str] = {}
#: Ids the service answered "not found" for — a deleted session a TUI's tabs still name. Asking
#: again on every listing was 14 000 404s a session in OpenCode's own log in a day.
_gone: set[str] = set()


def _service() -> dict:
    """The service's registration: `url` and `password`, re-read when the file changes."""
    global _registered
    path = registration_path()
    try:
        changed = path.stat().st_mtime
    except OSError:
        raise Unreachable("OpenCode's service has not registered on this Mac") from None
    if _registered[0] != changed:
        try:
            found = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as error:
            raise Unreachable(f"OpenCode's registration cannot be read: {error}") from error
        _registered = (changed, found if isinstance(found, dict) else {})
    if not _registered[1].get("url"):
        raise Unreachable("OpenCode's registration names no address")
    return _registered[1]


def request(method: str, path: str, body: dict | None = None, *, query: dict | None = None,
            timeout: float = WAIT) -> dict:
    """Call the service once. The seam every caller goes through and every test replaces.

    `{}` for an answer with no body. A list comes back as `{"data": [...]}`, so every caller reads
    one shape. A 401 is the registration going stale under a restart, and is `Unreachable`.
    """
    service = _service()
    password = service.get("password")
    try:
        answered = _client.request(
            method, str(service["url"]).rstrip("/") + path, json=body, params=query,
            auth=(USER, str(password)) if password else None, timeout=timeout)
    except httpx.HTTPError as error:
        raise Unreachable(f"OpenCode's service is not answering: {error}") from error
    if answered.status_code == 401:
        raise Unreachable("OpenCode's service refused its own registration's password")
    if answered.status_code >= 400:
        raise OpenCodeError(_said(answered))
    if not answered.content:
        return {}
    try:
        found = answered.json()
    except ValueError:
        raise OpenCodeError("OpenCode answered with something that is not JSON") from None
    return found if isinstance(found, dict) else {"data": found}


def _said(answered: httpx.Response) -> str:
    """OpenCode's own sentence: its errors carry `message` beside a `_tag`."""
    try:
        body = answered.json()
    except ValueError:
        body = None
    said = body.get("message") if isinstance(body, dict) else None
    return str(said or answered.text.strip() or answered.status_code)[:200]


def located(cwd: str) -> dict:
    """The `location` query a location-scoped route takes, in the deepObject form it declares."""
    return {"location[directory]": cwd}


def answered() -> bool:
    """Whether the service answered the last listing that asked it. False before any has."""
    return _asked[1]


def records() -> list[dict]:
    """The root sessions running now, open in a TUI, or touched lately, as session records.

    Never raises: OpenCode being absent, down or hung is a listing with no OpenCode rows in it,
    never a listing without the Claude ones. After a failure it does not ask again for
    `RETRY_AFTER`.
    """
    global _asked
    at, ok = _asked
    if at and not ok and time.monotonic() - at < RETRY_AFTER:
        return []
    try:
        # A root is busy while any of its subagents runs: a turn that left background subagents
        # going reads idle on its own, and its row would say so while the work goes on.
        running = _roots_of(set(request("GET", "/api/session/active", timeout=TIMEOUT)
                                .get("data") or {}))
        opened = opencode_tabs.open_sessions(registration_path().parent)
        closed = opencode_tabs.closed()
        found = [info for info in _recent((running | (opened or set())) - set(closed))
                 if _updated(info) > closed.get(info["id"], -1)]
    except OpenCodeError as error:
        if ok or not at:
            log.warning("opencode sessions unavailable: %s", error)
        _asked = (time.monotonic(), False)
        return []
    _asked = (time.monotonic(), True)
    for gone in set(_usage) - {info.get("id") for info in found}:
        del _usage[gone]
    return [record(info, info["id"] in running, None if opened is None else info["id"] in opened)
            for info in found]


def _recent(kept: set[str]) -> list[dict]:
    """Every live root session: newest pages until one is older than the cutoff, plus anything
    running or open in a TUI that those pages did not reach."""
    cutoff = (time.time() - LIVE_FOR) * 1000
    found: dict[str, dict] = {}
    cursor = None
    for _ in range(PAGES):
        query = {"cursor": cursor} if cursor else {"limit": PAGE, "order": "desc", "parentID": "null"}
        page = request("GET", "/api/session", query=query, timeout=TIMEOUT)
        rows = [info for info in page.get("data") or [] if isinstance(info, dict)]
        for info in rows:
            if _live(info, kept, cutoff):
                found[info["id"]] = info
        cursor = (page.get("cursor") or {}).get("next")
        if not cursor or not rows or _updated(rows[-1]) < cutoff:
            break
    for session_id in kept - set(found) - _gone:
        try:
            info = request("GET", f"/api/session/{session_id}", timeout=TIMEOUT).get("data") or {}
        except Unreachable:
            raise
        except OpenCodeError:
            _gone.add(session_id)
            continue
        if _live(info, kept, cutoff):
            found[session_id] = info
    return list(found.values())


def root_of(session_id: str) -> str:
    """The root session a subagent belongs to, up its `parentID`s; a root is its own."""
    seen = [session_id]
    while seen[-1] not in _roots and len(seen) < 8:
        info = request("GET", f"/api/session/{seen[-1]}", timeout=TIMEOUT).get("data") or {}
        if not info.get("parentID"):
            _roots[seen[-1]] = seen[-1]
            break
        seen.append(str(info["parentID"]))
    root = _roots.get(seen[-1], seen[-1])
    _roots.update(dict.fromkeys(seen, root))
    return root


def _roots_of(running: set[str]) -> set[str]:
    """The root sessions with anything running under them. One that has gone is dropped."""
    found = set()
    for session_id in running:
        try:
            found.add(root_of(session_id))
        except Unreachable:
            raise
        except OpenCodeError:
            continue
    return found


def _live(info: dict, kept: set[str], cutoff: float) -> bool:
    if not info.get("id") or info.get("parentID") or (info.get("time") or {}).get("archived"):
        return False
    return info["id"] in kept or _updated(info) >= cutoff


def _updated(info: dict) -> float:
    return float((info.get("time") or {}).get("updated") or 0)


def record(info: dict, busy: bool, in_client: bool | None = None) -> dict:
    """One session in the shape `live.Session` is built from. `in_client` is None where nobody
    asked which TUI has it open: one session fetched for the MCP, or one just started."""
    session_id = str(info.get("id") or "")
    cwd = folder_of(info)
    title = " ".join(str(info.get("title") or "").split())
    return {
        "session_id": session_id,
        "pid": 0,
        # A name is a key for stars and filter chains, and a folder's bare name is the Claude
        # session's there. OpenCode titles a session after its first prompt; until then it has none.
        "name": title or f"{Path(cwd).name}-opencode-{session_id[-4:]}",
        "cwd": cwd,
        "status": "busy" if busy else "idle",
        "updated_at": _updated(info) / 1000,  # milliseconds, like Claude's own records
        "tty": "",
        "pane": None,
        "provider": PROVIDER,
        "in_client": in_client,
    }


def folder_of(info: dict) -> str:
    """The folder a session works in: its location, and the subfolder it was opened in."""
    directory = str((info.get("location") or {}).get("directory") or "")
    subpath = str(info.get("subpath") or "")
    return str(Path(directory) / subpath) if directory and subpath else directory


def fetch(session_id: str) -> dict | None:
    """One session's record by id, asked of the service directly. None when it has none.

    For the MCP server inside an OpenCode session, which knows its session id from the call and
    nothing else, and must not depend on the daemon's listing to learn its own folder.
    """
    try:
        info = request("GET", f"/api/session/{session_id}", timeout=TIMEOUT).get("data")
        running = request("GET", "/api/session/active", timeout=TIMEOUT).get("data") or {}
    except OpenCodeError as error:
        log.info("opencode session %s unavailable: %s", session_id, error)
        return None
    return record(info, session_id in running) if isinstance(info, dict) else None


def start(cwd: str) -> dict:
    """A new session in `cwd`, answered with its record.

    No model, agent or permissions: those are OpenCode's own configuration, and that is the answer
    the Codex start already gave for the same question.
    """
    info = request("POST", "/api/session", {"location": {"directory": cwd}}).get("data")
    if not isinstance(info, dict) or not info.get("id"):
        raise OpenCodeError("OpenCode answered without the session it started")
    log.info("started opencode session %s in %s", info["id"], cwd)
    return record(info, False)


def last_request(session: Session) -> tuple[LastRequest, int]:
    """What the session's last request filled, and the window it filled it in.

    The last assistant message that has finished carries the tokens of the request behind it;
    input plus both halves of the cache is the prompt, as `usage.last_request` counts a Claude
    one. Read again only when the session has moved, and a running one at most every
    `USAGE_EVERY`, because this is asked for every OpenCode row on every listing.
    """
    from .usage import LastRequest  # here, because `usage` imports `live`, which imports this

    moved = session.updated_at
    held = _usage.get(session.session_id)
    if held and (held[0] == moved or time.monotonic() - held[1] < USAGE_EVERY):
        return held[2], _limit(held[3])
    try:
        answer = request("GET", f"/api/session/{session.session_id}/message",
                         query={"type": "assistant", "order": "desc", "limit": 4}, timeout=TIMEOUT)
    except OpenCodeError:
        return (held[2], _limit(held[3])) if held else (LastRequest(), 0)
    found, which = LastRequest(), ("", "")
    for message in answer.get("data") or []:
        tokens = message.get("tokens") if isinstance(message, dict) else None
        if not isinstance(tokens, dict):
            continue  # still streaming: its usage is written when the step ends
        cache = tokens.get("cache") or {}
        model = message.get("model") or {}
        variant = str(model.get("variant") or "")
        which = (str(model.get("providerID") or ""), str(model.get("id") or ""))
        found = LastRequest(
            used=int(tokens.get("input") or 0) + int(cache.get("read") or 0)
            + int(cache.get("write") or 0),
            model=which[1],
            effort="" if variant == "default" else variant,
        )
        break
    _usage[session.session_id] = (moved, time.monotonic(), found, which)
    return found, _limit(which)


def _limit(which: tuple[str, str]) -> int:
    """The context window of that (provider, model), out of OpenCode's own catalogue."""
    global _limits
    if not which[1]:
        return 0
    at, known = _limits
    if not at or time.monotonic() - at > MODELS_FOR:
        try:
            listed = request("GET", "/api/model", timeout=TIMEOUT).get("data") or []
        except OpenCodeError:
            listed = None
        if listed is not None:
            known = {(str(m.get("providerID")), str(m.get("id"))): int((m.get("limit") or {})
                     .get("context") or 0) for m in listed if isinstance(m, dict)}
            _limits = (time.monotonic(), known)
    return known.get(which, 0)
