"""Sending a read for a remote session to the machine that has the disk.

One middleware rather than a branch in each handler. Nine routes read a session's own files, and
nine branches would be nine places for the next one to be forgotten — this is the single point
every request already passes through.

**An allow-list, never a skip-list.** Only the suffixes below are forwarded. That is the whole
safety property: a route added to the daemon tomorrow is local until somebody names it here, so
the failure mode of forgetting is "it does not work for a remote session" and never "it silently
did something on the wrong machine". The inverse list — everything the daemon keeps — would have
to be complete to be safe, and would quietly stop being complete the first time anyone added a
route without reading this file.

What is deliberately absent: `summary` (the briefing is written and kept here), `orders`,
`filters`, `notify`, `say`, `audio`, `image` — all of them things the daemon decides — and
`focus`, `control`, `name`, which are pane work a hand cannot do.
"""

from __future__ import annotations

import asyncio

from fastapi import Request
from fastapi.responses import JSONResponse, Response

from ..log import log
from . import merge, registry, remote

# Suffixes of `/sessions/{id}/…` that belong to the machine holding the files.
FORWARDED = (
    "turns",
    # Both the listing and one agent's own turns: the prefix match below carries
    # `agents/<id>/turns` along with `agents` itself.
    "agents",
    "raw",
    "context",
    "commands",
    "files",
    "file",
    "artifacts",
    "queue/clear",
)


def owner_of(path: str) -> tuple[str, str] | None:
    """(machine, session id) when this path is a remote session's own file, else None."""
    if not path.startswith("/sessions/"):
        return None
    rest = path[len("/sessions/") :]
    session_id, _, suffix = rest.partition("/")
    if not suffix or not session_id:
        return None
    if not any(suffix == f or suffix.startswith(f + "/") for f in FORWARDED):
        return None
    machine = merge.owner(session_id)
    if not machine or machine == registry.here():
        return None
    return machine, session_id


async def forward_remote_reads(request: Request, call_next):
    """Answer for a session on another machine with that machine's own answer, verbatim.

    Unreachable is a 503 and not an empty page: a transcript that cannot be read is not a
    transcript with nothing in it, and a phone showing a blank conversation for a machine that
    is merely asleep is the worst of both.
    """
    found = owner_of(request.url.path)
    if found is None:
        return await call_next(request)
    machine, _ = found
    # In a thread, because `remote.forward` is synchronous and this runs on the event loop: a
    # machine taking the full timeout would otherwise stall every other request the daemon is
    # serving, the phone's own listing included.
    answer = await asyncio.to_thread(
        remote.forward, machine, request.method, request.url.path, request.url.query
    )
    if answer is None:
        log.info("%s unreachable for %s", machine, request.url.path)
        return JSONResponse(
            {"detail": f"{machine} is not reachable"},
            status_code=503,
        )
    # Content-Length and Content-Encoding describe the upstream body, and Starlette recomputes
    # both. Passing them through is how a proxied response ends up truncated.
    headers = {
        k: v
        for k, v in answer.headers.items()
        if k.lower() not in ("content-length", "content-encoding", "transfer-encoding")
    }
    return Response(
        content=answer.content,
        status_code=answer.status_code,
        headers=headers,
        media_type=answer.headers.get("content-type"),
    )
