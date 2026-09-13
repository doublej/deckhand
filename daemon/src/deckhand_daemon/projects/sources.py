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
    #: What it is built with — `sveltekit`, `fastapi`, `expo`. atlas works this out from the
    #: manifest and then throws the manifest away, so this one word is the whole of what any
    #: source on this Mac knows about a project's libraries. See the note in `_project`.
    framework: str = ""
    #: What runs it: `bun`, `uv`, `pnpm`. The one fact that decides what a person types first.
    runner: str = ""
    #: The branch it is sitting on, and whether the tree is dirty. Together because they are one
    #: question — "can I start here without standing on something" — and apart they are two rows.
    branch: str = ""
    dirty: bool = False
    #: Open beads, where the project tracks any. A folder with eleven open issues is a different
    #: proposition from one with none, and it is the only number here about the work rather than
    #: about the code.
    issues: int = 0
    #: The port it serves on, where it has one reserved.
    port: int = 0
    #: The domains it answers on. Thin on the ground — atlas knows one for about four projects in
    #: a hundred — but they are the names a person actually says out loud, so they are worth
    #: carrying and worth searching even when most rows have none.
    domains: tuple[str, ...] = ()
    #: How many Claude sessions this folder has ever had. History, not liveness: `live` is the
    #: ones running now.
    sessions: int = 0
    #: Which machine the folder is on, as atlas's own `host` — `m2`, `ubuntu`, `fractal`. Empty
    #: means this one, which is what a hand-written list with no such flag actually describes.
    #: The ids are atlas's and deckhand's alike because deckhand's registry is atlas's registry,
    #: so this joins to `Session.machine` and to `/machines` with nothing in between.
    machine: str = ""

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
            "framework": self.framework,
            "runner": self.runner,
            "branch": self.branch,
            "dirty": self.dirty,
            "issues": self.issues,
            "port": self.port,
            "domains": list(self.domains),
            "sessions": self.sessions,
            "machine": self.machine,
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
    """atlas's records — every machine's, not only this Mac's.

    This used to drop everything atlas marked as somewhere else, on the grounds that a session
    can only be started where the daemon runs and offering the rest was offering rows that could
    only fail. That was true until a hand could start one; it is not true now, and the folders on
    the other two machines are 54 of the 504 atlas holds.

    **Nothing here has to map anything.** atlas's `host` is `m2`, `ubuntu`, `fractal` — the same
    ids deckhand's own registry uses, because deckhand's registry *is* atlas's registry. Measured
    on 2026-09-13: 504 rows, `host` present on every one of them, 450/26/28.

    `isLocal` is still the honest reading of "is this one mine", but note it is present-and-true
    on local rows and *absent* on the others rather than false — so a check for `is False` finds
    nothing at all.
    """
    rows = index.get("projects", []) if isinstance(index, dict) else index
    if not isinstance(rows, list):
        return []
    return [p for row in rows if isinstance(row, dict) and (p := _project(row)) is not None]


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
    beads = row.get("beads")
    return Project(
        name=str(row.get("name") or Path(path).name),
        path=path,
        relative=str(row.get("relativePath") or ""),
        description=str(row.get("description") or ""),
        kind=str(row.get("type") or ""),
        # The later of the two: a folder whose files have not changed since a session talked
        # about it all afternoon is still the folder you were working in.
        touched_at=max(_epoch(row.get("modifiedAt")), _epoch(last_session)),
        # Everything below is carried when a source has it and absent when it does not, which is
        # the same deal `description` and `kind` are already on. A hand-written projects.json has
        # none of it and still works.
        framework=_word(row.get("framework")),
        runner=_word(row.get("runner")),
        branch=str(row.get("gitBranch") or ""),
        # atlas answers `clean`, `dirty`, `no-repo` or `error`. Only one of those is a warning,
        # and reading it as a boolean here means the phone never has to know the other three.
        dirty=row.get("git") == "dirty",
        issues=_count(beads.get("open")) if isinstance(beads, dict) else 0,
        port=_count(row.get("port")),
        domains=_names(row.get("domains")),
        sessions=_count(claude.get("count")) if isinstance(claude, dict) else 0,
        # A hand-written `projects.json` names folders somebody meant, on this Mac, and carries
        # no host — so an absent one is this machine rather than an unknown one.
        machine=str(row.get("host") or ""),
    )


def _word(value: object) -> str:
    """One of atlas's enum words, minus the one that means it could not tell.

    `unknown` is three hundred of five hundred rows, and a picker that prints it three hundred
    times has printed nothing. Absent says the same thing and takes no room.
    """
    word = str(value or "").strip()
    return "" if word in ("", "unknown", "none", "generic") else word


def _names(value: object) -> tuple[str, ...]:
    if not isinstance(value, list):
        return ()
    return tuple(name for item in value if (name := str(item or "").strip()))


def _count(value: object) -> int:
    """A number atlas wrote, or nothing. Never a negative one — these are all tallies."""
    return max(0, int(value)) if isinstance(value, int | float) else 0


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
