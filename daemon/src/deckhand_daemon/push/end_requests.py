"""An agent asking the person to end sessions: one Allow/Deny alert, and nothing ends without it.

No MCP or manager tool ends a session (`mcp/refused.py`), and that stays true: this ends nothing
by itself. It names the sessions on the person's Lock Screen, and only their tap — signed by the
phone's key and checked as a decision's is (`callbacks.answered`) — ends them, each by
`sessions/ending.py` on the machine it runs on. Deny, or no tap within a day, and nothing happens.

What is kept is each session's id, machine and name at the moment of asking, so a tap hours later
needs no warm listing; the machine that ends one looks it up again right before the signal.
"""

from __future__ import annotations

from fastapi import HTTPException

from ..log import log
from ..sessions import ending
from . import callbacks, sending

MAX = 8


def _bad(why: str) -> HTTPException:
    return HTTPException(status_code=400, detail=why)


def chosen(wanted: list[str], rows: list[dict]) -> list[dict]:
    """Each name or id in `wanted` as one listed Claude session with a process. 400 for any that
    is not exactly one, so the alert never names a session other than the one meant."""
    if not 0 < len(wanted) <= MAX:
        raise _bad(f"name 1 to {MAX} sessions")
    # One id is one session, however many listings carry it: a machine can answer twice.
    rows = list({r.get("session_id"): r for r in rows}.values())
    picked = []
    for one in dict.fromkeys(wanted):
        found = [r for r in rows if r.get("session_id") == one] or [
            r for r in rows if r.get("name") == one]
        if len(found) != 1:
            many = ", ".join(f"{r['session_id']} on {r.get('machine')}" for r in found)
            raise _bad(f"{one!r} names {len(found)} sessions{': ' + many if many else ''}")
        row = found[0]
        if row.get("provider", "claude") != "claude" or not row.get("pid"):
            raise _bad(f"{row.get('name')} is a {row.get('provider')} session, with no process "
                       f"of its own to end")
        picked.append({"id": row["session_id"], "machine": row.get("machine", ""),
                       "name": row.get("name", "")})
    return picked


def asked(wanted: list[str], why: str, asker: str, rows: list[dict]) -> dict:
    """Send the alert. `{id, sessions}`; 400 for a request off, 502/503 when it could not go."""
    why = " ".join(why.split())
    if not why:
        raise _bad("say why these should end")
    ends = chosen(wanted, rows)
    count = f"{len(ends)} session{'s' if len(ends) > 1 else ''}"
    named = ", ".join(f"{e['name']} ({e['machine']})" if e["machine"] else e["name"] for e in ends)
    alert = {"title": sending.shortened(f"{asker or 'A session'} asks to end {count}",
                                        sending.ASKING),
             "line": sending.shortened(f"{named} — {why}", sending.ASKING),
             "category": callbacks.CATEGORIES[frozenset({"approve", "deny"})],
             "labels": {"approve": "End", "deny": "Keep"}}
    nid = callbacks.sent(alert, {"ends": ends, "actions": ["approve", "deny"]})
    log.info("end request %s from %s: %s", nid, asker or "?", named)
    return {"id": nid, "sessions": [e["name"] for e in ends]}


def tapped(ends: list[dict], action: str) -> dict:
    """The person's answer, already proven. Allow ends each session; anything else ends none.
    `{status, error}` as a loopback caller's would be."""
    if action != "approve":
        return {"status": 200, "error": None}
    # A session that went before the tap is what the tap asked for, so it is not a failure.
    failed = [f"{e['name']}: {why}" for e in ends
              if (why := ending.end_by(e["machine"], e["id"])) and why != ending.GONE]
    return {"status": 200, "error": "; ".join(failed) or None}
