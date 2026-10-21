"""Reaching a session that is on another machine — the two shapes of it, both synchronous.

`deliver_to` is called from inside `deliver.deliver`, which every caller in the daemon already
reaches through `asyncio.to_thread`, so blocking here blocks a worker rather than the loop.

`forward` is the read path: a request for a remote session's transcript, files or slips, handed
to the hand that has the disk and answered verbatim. Its one caller is on the event loop and puts
it in a thread for the same reason.
"""

from __future__ import annotations

import httpx

from ..config import TOKEN_HEADER, token
from ..log import log
from . import link as links

TIMEOUT = 8.0


def _base(machine_id: str) -> str | None:
    link = links.links().get(machine_id)
    if link is None or not link.alive:
        return None
    return link.base_url


def deliver_to(machine_id: str, session_id: str, message: str,
               person: bool = False) -> tuple[bool, str | None]:
    """Put words into a session on another machine, down that machine's own inbox socket.

    **The daemon has already run everything that decides** — the filter chain, the standing
    orders, the delivery record — so the hand is handed the exact words and does the one thing it
    is for. Running any of that twice would be the shape of bug that looks like it works.

    Socket only, and not because this asks for it: a hand has no pane, so there is nothing else
    it could do. `deliver.deliver` has already refused the keyboard route by then, and refused a
    slash command, both for the same reason — no pane.
    """
    base = _base(machine_id)
    if base is None:
        return False, f"{machine_id} is not reachable"
    try:
        r = httpx.post(
            f"{base}/sessions/{session_id}/deliver",
            json={"text": message, "person": person},
            headers={TOKEN_HEADER: token()},
            timeout=TIMEOUT,
        )
    except (httpx.HTTPError, OSError) as error:
        if link := links.links().get(machine_id):
            links.went_down(link, f"{error.__class__.__name__}: {error}")
        return False, f"could not reach {machine_id}: {error}"
    if r.status_code == 404:
        return False, "that session is no longer running on that machine"
    if r.status_code >= 400:
        return False, f"{machine_id} answered {r.status_code}"
    body = r.json()
    if not body.get("delivered"):
        return False, body.get("error") or f"{machine_id} did not deliver it"
    log.info("delivered %d chars to %s on %s", len(message), session_id[:8], machine_id)
    return True, None


def end_on(machine_id: str, session_id: str) -> str | None:
    """End a session on another machine: its hand re-lists and signals the pid there
    (`sessions/ending.py`). None once it did, or why not."""
    base = _base(machine_id)
    if base is None:
        return f"{machine_id} is not reachable"
    try:
        r = httpx.post(f"{base}/sessions/{session_id}/end", headers={TOKEN_HEADER: token()},
                       timeout=TIMEOUT)
    except (httpx.HTTPError, OSError) as error:
        if link := links.links().get(machine_id):
            links.went_down(link, f"{error.__class__.__name__}: {error}")
        return f"could not reach {machine_id}: {error}"
    if r.status_code == 404:
        return f"{machine_id}'s hand is too old to end a session — restart it"
    if r.status_code >= 400:
        return f"{machine_id} answered {r.status_code}"
    return r.json().get("error")


def forward(machine_id: str, method: str, path: str, query: str = "", body: bytes = b"",
            content_type: str = "") -> httpx.Response | None:
    """Hand a request straight to the machine that has the disk, and answer with what it says.

    None when the machine is unreachable, which the caller turns into a 503 rather than an empty
    page: a transcript that cannot be read is not a transcript with nothing in it. The body goes
    across too: a slip's answer is a `POST` with the answer in it, and forwarding it empty was a
    422 for every slip on another machine.
    """
    base = _base(machine_id)
    if base is None:
        return None
    url = f"{base}{path}{'?' + query if query else ''}"
    try:
        headers = {TOKEN_HEADER: token()} | ({"content-type": content_type} if content_type else {})
        return httpx.request(method, url, headers=headers, content=body or None, timeout=TIMEOUT)
    except (httpx.HTTPError, OSError) as error:
        if link := links.links().get(machine_id):
            links.went_down(link, f"{error.__class__.__name__}: {error}")
        return None
