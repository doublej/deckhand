"""Which addresses matter, and the one reason each does — so the phone can show a few, not sixty.

Three tiers, in the order the phone draws them:

- **important** — shared in the conversation within the last three hours (an agent telling the
  person, or the person saying it), or this project's own: its atlas hostname, its website, its
  staging domain. An address of *another* project counts only when the session said or used it
  — a session that printed atlas's whole hostname list did not mean thirty-seven of them.
- **recent** — used by a tool call within those three hours, or shared longer ago.
- **rest** — only ever printed by a tool, or used long ago: a URL inside an old file that a
  session read is still listed, just out of the way.

"Within three hours" is of the session's own last activity, not of now: a session left
overnight still has a last thing it shared, and that is still the thing worth seeing first.
Newest first inside a tier.
"""

from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit

from . import atlas
from .checking import Check
from .finding import Found

RECENT = 3 * 3600
TIERS = {"important": 0, "recent": 1, "rest": 2}
STAGING = re.compile(r"(^|[.-])(staging|stage|preview|acc|test)([.-]|$)")


def rank(found: list[Found], checked: dict[str, Check], known: list[atlas.Known],
         home: atlas.Known | None, active: float) -> list[dict]:
    """The rows the phone draws, tiered and ordered, each with its check and atlas's word."""
    rows = []
    for row in found:
        check = checked.get(row.origin)
        # Written without a scheme, `self.local` is code ending in a domain's ending; only the
        # lookup tells the two apart.
        if check and row.kind == "domain" and check.reach == "none":
            continue
        registered = atlas.match(known, row.origin)
        tier, why = _tier(row, registered, home, active)
        rows.append(row.to_json()
                    | (check.to_json() if check else {"state": "checking"})
                    | {"atlas": registered.to_json() if registered else None, "tier": tier, "why": why})
    rows.sort(key=lambda r: r["last_at"], reverse=True)
    rows.sort(key=lambda r: TIERS[r["tier"]])
    return rows


def _tier(row: Found, registered: atlas.Known | None, home: atlas.Known | None,
          active: float) -> tuple[str, str]:
    host = urlsplit(row.origin).hostname or ""
    fresh = lambda at: bool(at) and active - _epoch(at) < RECENT
    own = home is not None and (
        (registered is not None and registered.path == home.path)
        or any(host == d or host.endswith("." + d) for d in home.hosts))
    if own:
        if host == "localhost" or host[:1].isdigit():
            return "important", "This project's dev server"
        if ".atlas." in host:
            return "important", "This project's atlas hostname"
        return "important", "Staging" if STAGING.search(host) else "This project's site"
    if fresh(row.shared_at):
        return "important", "Shared in the conversation"
    if registered is not None and row.said:
        return "important", f"Atlas · {registered.name}"
    if fresh(row.used_at):
        return "recent", "Used by the session"
    if row.shared_at:
        return "recent", "Shared earlier"
    return "rest", "Seen in tool output" if not row.said else "Used earlier"


def project_of(cwd: str, known: list[atlas.Known]) -> atlas.Known | None:
    """The atlas project this session works in: its folder, or the nearest one above it."""
    here = Path(cwd)
    owners = [k for k in known if k.path and (here == Path(k.path) or Path(k.path) in here.parents)]
    return max(owners, key=lambda k: len(k.path), default=None)


def _epoch(stamp: str) -> float:
    try:
        return datetime.fromisoformat(stamp).timestamp()
    except ValueError:
        return 0.0
