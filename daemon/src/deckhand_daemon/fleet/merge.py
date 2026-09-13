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


# The last listing's rows for sessions that are not on this Mac, so the daemon can find one
# without asking its machine again. `session()` rebuilds a `Session` from a row.
_rows: dict[str, dict] = {}


def remembered(machine_id: str, rows: list[dict]) -> None:
    for row in rows:
        if sid := row.get("session_id"):
            _owner[sid] = machine_id
            if machine_id != registry.here():
                _rows[sid] = row


def session(session_id: str):
    """A remote session as a `Session`, or None. Rebuilt from the last listing rather than
    fetched, because every caller is already on a code path that just listed.

    **No `socket_path`, and that is right.** The socket is a path on the machine that owns it and
    means nothing here; `deliver.deliver` hands a remote session to its hand by id instead. A
    `pane` of None is right for the same reason — there is no iTerm over there, so the keyboard
    route refuses exactly as it does for a local session that has no pane.
    """
    from ..sessions import Session

    row = _rows.get(session_id)
    if row is None:
        return None
    return Session(
        session_id=row.get("session_id", ""),
        pid=row.get("pid", 0),
        name=row.get("name", ""),
        cwd=row.get("cwd", ""),
        status=row.get("status", "unknown"),
        updated_at=row.get("updated_at", 0.0),
        tty=row.get("tty", ""),
        pane=None,
        machine=row.get("machine", ""),
    )


def remote_rows() -> list[dict]:
    """Every remote session the last listing saw, as its row.

    The phone polls `/sessions` every few seconds, so this is never more than that stale — which
    is why `/projects` counts what is running in a folder out of here rather than paying a second
    fan-out to every machine for a number that is already on this Mac.
    """
    return list(_rows.values())


def forget(machine_id: str) -> None:
    for sid in [s for s, m in _owner.items() if m == machine_id]:
        del _owner[sid]
        _rows.pop(sid, None)


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
            # The one machine the phone can name without asking anything else. It is what the
            # phone's own favourites and hidden rows were always filed under, back when a name
            # was the whole key, so it is what their migration prefixes them with.
            "primary": True,
        }
    ]
    rows.extend(link.to_json() for link in links.links().values())
    return rows


#: How often to ask every machine how it is. Two jobs, and it is the same ask for both: a link
#: that died is remade here rather than in front of the phone, and a hand that would otherwise
#: sit unspoken-to hears from its daemon well inside its own `FORGOTTEN_AFTER`.
KEEP_WARM = 60.0


async def warm() -> None:
    """Open every link that is down, and wait generously for the hands behind them.

    Without this the first `/sessions` after a restart pays the whole ssh handshake for every
    machine at once, which is the one request a person is watching.

    `WARM_TIMEOUT` rather than the ordinary one, and that is the whole point of doing it here: a
    machine slow to start its hand is worth waiting for when nobody is waiting for the answer.
    Ubuntu's cold `uv run` was measured at 61 s, against the 20 s a call in front of the phone
    can afford.
    """
    from . import link as links

    opened = [one for one in links.links().values() if links.start(one)]
    await asyncio.gather(*(proxy.ready(one, proxy.WARM_TIMEOUT) for one in opened))


async def keep_warm() -> None:
    """Warm every link, then go on doing it for as long as this daemon runs.

    **Not a health probe with a second opinion.** `proxy.ready` marks a link up or down exactly
    as a real call does, through the same two functions, so this cannot disagree with what the
    phone is told — it only means nobody had to wait to find out.

    It is also what keeps a hand from timing itself out: a hand exits after five minutes of
    silence, which is the one thing that frees the port when an ssh session is left half-open
    at the far end, and this is the heartbeat that says the daemon is still here.
    """
    said: list[str] = []
    while True:
        await warm()
        from . import link as links

        up = sorted(one.machine.id for one in links.links().values() if one.ready)
        if up != said:
            log.info("fleet: %d link(s) up%s", len(up), f" ({', '.join(up)})" if up else "")
            said = up
        await asyncio.sleep(KEEP_WARM)
