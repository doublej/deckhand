"""Where the list of projects on this Mac comes from, whatever is keeping it.

A project is a name and a folder. That is the whole of what starting a session in one needs, so
it is all this insists on — everything else a source happens to know (what it is for, what kind
of thing it is, when it was last touched) is carried when it is there and absent when it is not.

Three sources, read in order, and the first that answers anything wins:

1. `projects.json` in Deckhand's own data dir. Nobody writes that file by accident, so a person
   who has written one means it, and it beats anything found for them.
2. **atlas**, over HTTP on :47891. This is the first-class one: atlas is already the thing that
   knows every project on this Mac, and its record carries the description and the last time
   anything happened in the folder — which is what makes a list of five hundred rows a list you
   can use rather than an alphabetical wall.
3. atlas's own scan cache on disk, for when the atlas daemon is down. Same records, one scan old.

So the universal part is real rather than decorative: the consumer above this knows only
`Project`, and a Mac with no atlas at all is one file away from a working picker.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from ..config import data_dir
from ..log import log

ATLAS_URL = "http://127.0.0.1:47891/api/projects"
# One request per source at most, and never a slow one: this sits in front of a picker somebody
# just opened, and an atlas that is not answering should cost a blink, not a wait.
ATLAS_TIMEOUT = 3.0
# What atlas itself caches its scan for. Matching it means the phone never sees a staler list
# than the terminal would, and a picker that is opened and closed twice costs one fetch.
TTL = 60.0

_cache: tuple[float, list[Project], str] = (0.0, [], "")


@dataclass(slots=True)
class Project:
    """One folder a session could be started in."""

    name: str
    path: str
    #: Where it sits under the dev root — `multi-stack/deckhand`. What a person recognises it by,
    #: since the leading `/Users/<someone>/dev` is the same on every row and reads as noise.
    relative: str = ""
    description: str = ""
    kind: str = ""
    #: When anything last happened here, as epoch seconds. Nothing else can order this list
    #: usefully: alphabetical puts five hundred rows in front of you and the one you want in
    #: the middle of them.
    touched_at: float = 0.0
    #: How many live Claude sessions are already in this folder. Filled in by the route, not
    #: here — it is a fact about the sessions, and it changes every few seconds.
    live: int = 0
    #: Whether Claude Code has been trusted in this folder. Also filled in by the route, and on
    #: the row rather than only in the refusal: a picker that lets you tap four hundred rows and
    #: tells you afterwards which ones could never have worked is a worse picker than one that
    #: says so first.
    trusted: bool = False

    def to_json(self) -> dict:
        return {
            "name": self.name,
            "path": self.path,
            "relative": self.relative,
            "description": self.description,
            "kind": self.kind,
            "touched_at": self.touched_at,
            "live": self.live,
            "trusted": self.trusted,
        }


def catalog() -> tuple[list[Project], str]:
    """Every project this Mac knows about, and which source said so.

    The source travels with the list because it is the difference between "atlas told me" and
    "atlas is down and this is what it last knew" — a phone showing a stale list should be able
    to say so rather than quietly showing yesterday.
    """
    global _cache
    fetched_at, cached, source = _cache
    if cached and time.monotonic() - fetched_at < TTL:
        return cached, source
    for name, read in (("file", _written), ("atlas", _atlas_api), ("atlas-cache", _atlas_cache)):
        found = read()
        if found:
            found.sort(key=lambda p: p.touched_at, reverse=True)
            _cache = (time.monotonic(), found, name)
            log.info("project list: %d from %s", len(found), name)
            return found, name
    _cache = (time.monotonic(), [], "none")
    return [], "none"


def forget() -> None:
    """Drop the cached list. Called after starting a session, whose whole point is that the
    folder has just become somewhere a session is running."""
    global _cache
    _cache = (0.0, [], "")


def _written() -> list[Project]:
    """The person's own list: `[{"name": …, "path": …}]`, or the same under a `projects` key."""
    path = data_dir() / "projects.json"
    try:
        written = json.loads(path.read_text())
    except FileNotFoundError:
        return []
    except (OSError, json.JSONDecodeError) as error:
        log.warning("projects.json is there but unreadable: %s", error)
        return []
    rows = written.get("projects", []) if isinstance(written, dict) else written
    return [p for row in rows if (p := _project(row)) is not None]


def _atlas_api() -> list[Project]:
    try:
        with urllib.request.urlopen(ATLAS_URL, timeout=ATLAS_TIMEOUT) as answer:
            index = json.loads(answer.read())
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as error:
        log.info("atlas did not answer, falling back to its cache: %s", error)
        return []
    return _from_atlas(index)


def _atlas_cache() -> list[Project]:
    override = os.environ.get("DECKHAND_ATLAS_CACHE")
    path = Path(override) if override else Path.home() / "dev" / ".atlas-cache.json"
    try:
        return _from_atlas(json.loads(path.read_text()))
    except (OSError, json.JSONDecodeError):
        return []


def _from_atlas(index: object) -> list[Project]:
    """atlas's records, minus the ones that are not on this Mac.

    atlas catalogues the rig and the Ubuntu box as well, and their folders come through as
    `C:\\dev\\...` and `/home/jurrejan/development/...`. A session can only be started where this
    daemon is running, so offering those would be offering rows that can only ever fail —
    `isLocal` is atlas's own answer to which is which. Only the atlas sources are filtered this
    way: a list somebody wrote by hand names folders they meant, and carries no such flag.
    """
    rows = index.get("projects", []) if isinstance(index, dict) else index
    if not isinstance(rows, list):
        return []
    here = [row for row in rows if isinstance(row, dict) and row.get("isLocal") is True]
    return [p for row in here if (p := _project(row)) is not None]


def _project(row: object) -> Project | None:
    """One record from any source, or None if it is not a folder worth offering.

    Archived work is dropped here rather than by the source, because only one of the three
    filters it: the dev root's own rule is that anything under an `_archive/` is a dead copy,
    and a picker that offers one is a picker that will eventually start a session in it.
    """
    if not isinstance(row, dict):
        return None
    path = str(row.get("path") or "").strip()
    if not path or row.get("archived") is True or "/_archive/" in path:
        return None
    claude = row.get("claudeSessions")
    last_session = claude.get("lastAt") if isinstance(claude, dict) else None
    return Project(
        name=str(row.get("name") or Path(path).name),
        path=path,
        relative=str(row.get("relativePath") or ""),
        description=str(row.get("description") or ""),
        kind=str(row.get("type") or ""),
        # The later of the two: a folder whose files have not changed since a session talked
        # about it all afternoon is still the folder you were working in.
        touched_at=max(_epoch(row.get("modifiedAt")), _epoch(last_session)),
    )


def _epoch(stamp: object) -> float:
    """An ISO timestamp as atlas writes it, or already a number, or nothing at all."""
    if isinstance(stamp, int | float):
        return float(stamp)
    if not isinstance(stamp, str) or not stamp:
        return 0.0
    try:
        return datetime.fromisoformat(stamp).timestamp()
    except ValueError:
        return 0.0
