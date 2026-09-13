"""Calling a hand, and keeping its link honest while doing so.

Every call goes to `127.0.0.1:<forwarded port>`, which is the far side of an ssh tunnel. That
means an unreachable machine looks like a refused connection on loopback and answers in
milliseconds rather than after a TCP timeout — the sleeping-Ubuntu problem atlas paid for once
already, solved here by never touching the network directly.

**A call is also the health check.** One that succeeds marks the link up; one that fails marks it
down and schedules a retry. There is no separate poller, because a probe that ran beside real
traffic would be a second opinion able to disagree with it.
"""

from __future__ import annotations

import asyncio

import httpx

from ..config import TOKEN_HEADER, token
from ..log import log
from . import link as links

# A hand reads files and writes one socket; nothing it does is slow. Long enough to survive a
# transcript scan on a busy machine, short enough that the phone's listing is not held up by one
# machine having a bad moment.
TIMEOUT = 8.0
# How long to keep asking a freshly opened link before giving up on this round. The ssh forward
# binds before the hand behind it has started listening, so the first call after `start` is
# expected to be refused.
READY_TIMEOUT = 20.0
# The same wait at start-up, where nobody is watching. Measured: a cold `uv run` on Ubuntu — 155
# days of uptime, a load average around 2 — takes longer than 20 s often enough that the machine
# read "not reachable" after every restart of this daemon and only came back minutes later, on
# whichever call happened to find the hand finally listening. There is no phone waiting on
# `warm`, so it can afford to wait for the answer rather than be told the wrong one.
WARM_TIMEOUT = 90.0


async def call(machine_id: str, method: str, path: str, **kwargs) -> dict | None:
    """One request to one hand. None when the machine is not reachable — never an exception.

    A caller merging several machines' answers must not lose the ones that worked because one
    was asleep, so a dead machine is an absence here rather than a failure.
    """
    link = links.links().get(machine_id)
    if link is None:
        return None
    # `start` answering False means the link is still serving a backoff, and then nothing else
    # may happen: `ready` would fail it a second time for an attempt that was never made, and
    # every one of those pushes the next attempt further away. With a phone polling every few
    # seconds the retry then never fires at all, and a machine that dropped overnight stays
    # unreachable for exactly as long as somebody is watching it.
    if not link.alive and not (links.start(link) and await ready(link)):
        return None
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            r = await client.request(
                method, f"{link.base_url}{path}", headers={TOKEN_HEADER: token()}, **kwargs
            )
    except (httpx.HTTPError, OSError) as error:
        links.went_down(link, f"{error.__class__.__name__}: {error}")
        return None
    links.came_up(link)
    if r.status_code >= 400:
        # The hand answered, so the link is fine — this is a 404 for a session that has gone, or
        # a 401 if the two ever disagreed about the token. Either is the caller's to interpret.
        log.info("%s answered %d for %s %s", machine_id, r.status_code, method, path)
        return None
    return r.json()


async def ready(link: links.Link, timeout: float = READY_TIMEOUT) -> bool:
    """Wait for the hand behind a freshly opened forward to start answering `/health`.

    The forward is up before the process behind it binds, so without this the first call after
    opening a link is always refused and the machine looks down when it is merely starting.
    """
    deadline = asyncio.get_running_loop().time() + timeout
    async with httpx.AsyncClient(timeout=2.0) as client:
        while asyncio.get_running_loop().time() < deadline:
            if not link.alive:
                # What the link already said, rather than a read of its pipe: that read blocks
                # until EOF, on the event loop, and the pipe is drained by `link._drain` anyway.
                links.went_down(link, links.useful_error(links.said(link)))
                return False
            try:
                r = await client.get(f"{link.base_url}/health")
                if r.status_code == 200:
                    links.came_up(link)
                    return True
            except (httpx.HTTPError, OSError):
                pass
            await asyncio.sleep(0.4)
    links.went_down(link, "hand did not answer /health in time")
    return False


async def every(method: str, path: str, **kwargs) -> dict[str, dict]:
    """Ask every remote machine the same thing at once, and keep whatever answered.

    Concurrent rather than in turn: three machines asked one after another would put the slowest
    one's latency in front of the phone on every listing.
    """
    ids = list(links.links())
    if not ids:
        return {}
    answers = await asyncio.gather(*(call(i, method, path, **kwargs) for i in ids))
    return {i: a for i, a in zip(ids, answers, strict=True) if a is not None}
