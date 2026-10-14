"""What one session can see of the space from where it stands, and telling it what it was given.

An agent opens pages beside itself and starts sessions beside itself; to do either sensibly it has
to know what is there already. `around` answers from the two facts the headset draws from — the
listing and `space.json` — by the headset's own rule for who is in a group: a kept pose's `group`,
else the project's (`project.group`) while two or more of its terminals are live. A page or window
is in its kept pose's group, else in its `near` session's.

`tell` is the other direction. A page or window the *person* hands a session — opened with that
session as `near`, or moved to it — is something the session should know is there, because what
he says looking at it now comes to it. Said down the socket, as the idle check is: it is the
daemon speaking, not him.
"""

from __future__ import annotations

from collections import Counter

from .. import deliver, prompts, sessions
from ..log import log

GIVEN = prompts.load("space-given")


def _session_groups(kept: dict, rows: list[dict]) -> dict[str, str | None]:
    """Every listed session's group, by the headset's rule."""
    live = Counter(row["project"]["group"] for row in rows)
    groups: dict[str, str | None] = {}
    for row in rows:
        pose = kept["poses"].get(f"session:{row['session_id']}")
        default = row["project"]["group"] if live[row["project"]["group"]] > 1 else None
        groups[row["session_id"]] = pose.get("group") if pose is not None else default
    return groups


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
    """Say to `session` that the person put `plane` beside it. A session that cannot be reached
    still has the plane; the failure is logged, never raised into the request that opened it."""
    what = (f"the page {plane['title']} ({plane['url']})" if plane["kind"] == "web"
            else f"the Mac window {plane['title']}")
    _, error = deliver.deliver(session, GIVEN.filled(what=what, id=plane["id"]),
                               route=GIVEN.settings["route"])
    if error:
        log.warning("could not tell %s about plane %s: %s", session.name, plane["id"], error)
