"""One listing out of several machines, and the map that says which machine owns a session.

The phone asks the daemon and the daemon answers for the whole network. It never learns a hand
exists: `machine` is a field on a row, not an address.

**Routing is by session id, so no route URL changes.** `sessionId` is a UUID Claude Code minted,
unique across machines by construction, which is why `/sessions/{id}/turns` means the same thing
whichever machine the session is on.
"""

from __future__ import annotations

import asyncio

from ..log import log
from . import proxy, registry

# id -> machine, learned from the last listing. Rebuilt every listing rather than kept current,
# because a session that has gone should stop resolving rather than resolve to a dead pid on a
# machine that has since been asked about something else.
_owner: dict[str, str] = {}


def owner(session_id: str) -> str:
    """Which machine that session was last seen on, or "" for this Mac / not known.

    An empty answer means "handle it locally", which is the right default in every case: before
    the first listing, for a session on this Mac, and for an id nothing recognises — the last of
    which then 404s here rather than being posted at three machines in turn.
    """
    return _owner.get(session_id, "")


def remembered(machine_id: str, rows: list[dict]) -> None:
    for row in rows:
        if sid := row.get("session_id"):
            _owner[sid] = machine_id


def forget(machine_id: str) -> None:
    for sid in [s for s, m in _owner.items() if m == machine_id]:
        del _owner[sid]


async def listings(local: list[dict]) -> list[dict]:
    """This Mac's sessions plus every reachable machine's, newest first.

    A machine that is asleep contributes nothing and is not an error — the rail would rather show
    two machines' sessions than fail because a third is off. `/machines` is where a person finds
    out one is missing, and that is deliberate: the listing answers "what can I talk to", the
    machines page answers "what is there".
    """
    here = registry.here()
    remembered(here, local)
    answers = await proxy.every("GET", "/sessions")
    rows = list(local)
    for machine_id, body in answers.items():
        theirs = body.get("sessions", [])
        remembered(machine_id, theirs)
        rows.extend(theirs)
    for machine_id in set(_owner.values()) - set(answers) - {here}:
        # Unreachable now: drop its ids rather than leave them resolving to a machine nothing
        # can reach, which would turn every request for them into a timeout instead of a 404.
        forget(machine_id)
    rows.sort(key=lambda r: r.get("updated_at", 0), reverse=True)
    return rows


async def links_of(local: list[dict], within: float) -> list[dict]:
    """Every machine's edges, concatenated. Never joined across machines, because `AF_UNIX` does
    not cross one — a session here cannot have messaged a session there."""
    answers = await proxy.every("GET", f"/sessions/links?within={within}")
    found = list(local)
    for body in answers.values():
        found.extend(body.get("links", []))
    return found


async def machines() -> list[dict]:
    """Every machine and whether it is reachable right now.

    Reachability is each link's own state — the link being up is the machine being up — so this
    costs nothing beyond what the listing already paid for.
    """
    from . import link as links

    here = registry.primary()
    rows = [
        {
            "id": here.id,
            "label": here.label,
            "os": here.os,
            "reachable": True,  # this daemon is answering, so this machine is up
            "error": "",
        }
    ]
    rows.extend(link.to_json() for link in links.links().values())
    return rows


async def warm() -> None:
    """Open every link at start-up rather than on the first listing that needs one.

    Without this the first `/sessions` after a restart pays the whole ssh handshake for every
    machine at once, which is the one request a person is watching.
    """
    from . import link as links

    for one in links.links().values():
        links.start(one)
    await asyncio.gather(*(proxy.ready(one) for one in links.links().values()))
    up = [one.machine.id for one in links.links().values() if one.ready]
    log.info("fleet: %d link(s) up%s", len(up), f" ({', '.join(up)})" if up else "")
