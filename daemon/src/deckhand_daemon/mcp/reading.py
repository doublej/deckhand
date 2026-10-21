"""Another session's conversation, read as text: a turn or a page of them, or the whole of it.

Out of `server.py` when that file reached its line budget. Over the daemon's own `/turns` route,
like the rest, and cut down to what was said — the route also carries every tool call and
thought, which is what makes a transcript too long to read and not what an agent asks it for.
`server.py` registers it.
"""

from __future__ import annotations

from . import here


async def read_session(session: str, turns: int = 1, before: int = 0) -> dict:
    """Another session on this Mac's conversation, by name or id: who spoke, what they said,
    when — text only: no tool calls, thinking or turns without words. The last `turns`; `0` is
    the whole transcript. `older` is the `before` that reads the page before this one, null at
    the start."""
    listed = await here.reach("GET", "/sessions")
    if "error" in listed:
        return listed
    live = listed.get("sessions", [])
    if (match := here.match(session, live)) is None:
        return {"error": here.no_such(session, live), "code": "NO_SUCH_SESSION"}
    # Pages of the route's own 200, newest first; each page is in order, so it goes in front.
    # ponytail: a turn said mid-walk shifts the count, so a whole read can repeat one at a seam.
    got: list[dict] = []
    skip, more = max(0, before), True
    while more and (turns <= 0 or len(got) < turns):
        limit = 200 if turns <= 0 else min(200, turns - len(got))
        answered = await here.reach("GET", f"/sessions/{match['session_id']}/turns",
                                    params={"limit": limit, "before": skip})
        if "error" in answered:
            return answered
        page, more = answered["turns"], answered["more"]
        if not page:
            break
        got = [{k: t[k] for k in ("role", "text", "timestamp", "written_by") if t.get(k)}
               for t in page if t.get("text")] + got
        skip += len(page)
    return {"session": match["session_id"], "name": match.get("name"), "turns": got,
            "older": skip if more else None}
