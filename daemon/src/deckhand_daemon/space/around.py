"""What one session can see of the space from where it stands, and telling it what it was given.

An agent opens pages beside itself and starts sessions beside itself; to do either sensibly it has
to know what is there already. `around` answers from the two facts the headset draws from — the
listing and `space.json` — by the headset's own rule for who is in a group: a kept pose's `group`,
and nothing else. Only the person groups terminals; a project's terminals are no longer grouped by
default (JJ, 2026-10-15: "only mine"). A page or window is in its kept pose's group, else in its
`near` session's.

`tell` is the other direction. A page or window the *person* hands a session — opened with that
session as `near`, or moved to it — is something the session should know is there, because what
he says looking at it now comes to it. `taken` is its other half: the session a page stood beside
is told when he closes it or moves it away, because what he says there no longer comes to it.
Both go down the socket, as the idle check does: it is the daemon speaking, not him.
"""

from __future__ import annotations

from .. import deliver, prompts, sessions
from ..log import log

GIVEN = prompts.load("space-given")
TAKEN = prompts.load("space-taken")


def _session_groups(kept: dict, rows: list[dict]) -> dict[str, str | None]:
    """Every listed session's group, by the headset's rule: its kept pose's, or none."""
    poses = kept["poses"]
    return {row["session_id"]: (poses.get(f"session:{row['session_id']}") or {}).get("group")
            for row in rows}


def around(kept: dict, rows: list[dict], session_id: str) -> dict:
    """`{pose, group, beside}`: where this session stands, its group, and every session, page and
    window in that group or opened near it."""
    groups = _session_groups(kept, rows)
    mine = groups.get(session_id)
    beside: list[dict] = [
        {"session": row["session_id"], "name": row.get("name"), "folder": row.get("cwd")}
        for row in rows
        if row["session_id"] != session_id and mine is not None and groups[row["session_id"]] == mine
    ]
    for plane in kept["planes"]:
        pose = kept["poses"].get(f"plane:{plane['id']}")
        group = pose.get("group") if pose is not None else groups.get(plane.get("near") or "")
        if plane.get("near") == session_id or (mine is not None and group == mine):
            beside.append({"plane": plane["id"], "kind": plane["kind"], "title": plane["title"],
                           "url": plane["url"], "window": plane["window"], "by": plane["by"]})
    return {"pose": kept["poses"].get(f"session:{session_id}"), "group": mine, "beside": beside}


def tell(session: sessions.Session, plane: dict) -> None:
    """Say to `session` that the person put `plane` beside it."""
    _say(session, plane, GIVEN, GIVEN.filled(what=_what(plane), id=plane["id"]))


def taken(session: sessions.Session, plane: dict, how: str, to: str = "") -> None:
    """Say to `session` that the person took `plane` away from beside it. `how` is one of the
    prompt's own: `closed`, `handed` — to the session named `to` — or `loose`."""
    how = TAKEN.settings["how"][how].replace("{name}", to)
    _say(session, plane, TAKEN, TAKEN.filled(what=_what(plane), id=plane["id"], how=how))


def _what(plane: dict) -> str:
    return (f"the page {plane['title']} ({plane['url']})" if plane["kind"] == "web"
            else f"the Mac window {plane['title']}")


def _say(session: sessions.Session, plane: dict, prompt: prompts.Prompt, text: str) -> None:
    """Down the route the prompt names. A session that cannot be reached is logged, never raised
    into the request that moved the plane: the plane has moved either way."""
    _, error = deliver.deliver(session, text, route=prompt.settings["route"])
    if error:
        log.warning("could not tell %s about plane %s: %s", session.name, plane["id"], error)
