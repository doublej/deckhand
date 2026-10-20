"""The files a session touched that a person could actually open on a phone.

A transcript names every path the session read or wrote. Most are source, which the tool trace
already shows; a few are things you would want to *look* at — a screenshot it took, a report it
wrote, a clip it rendered. Those are what this collects.

The same list bounds serving one back. A path that never appeared in this session's transcript
is not readable through the daemon, which is what keeps a file endpoint from being a file
browser on someone's Mac.

A folder the person connected to the project (`settings/folders.py`) is the second door: every
openable file inside it is listed and served, whether the transcript named it or not — the
person's choice to connect it is the permission, and nothing outside it gets through.

An OpenCode session has no transcript on disk; its recent history, read over OpenCode's API, is
searched for paths in exactly the same way, so the rule is the same rule.
"""

from __future__ import annotations

import os
import re
from collections.abc import Iterable, Iterator
from dataclasses import asdict, dataclass
from itertools import islice
from pathlib import Path

from .reading.transcripts import TAIL_WINDOWS, tail_lines, transcript_path
from .sessions import opencode, opencode_turns
from .settings import folders

KINDS = {
    "image": (".png", ".jpg", ".jpeg", ".gif", ".heic", ".webp", ".bmp", ".tiff"),
    "video": (".mp4", ".mov", ".m4v"),
    "audio": (".mp3", ".wav", ".m4a", ".aac", ".flac", ".opus", ".ogg", ".aiff", ".caf"),
    "text": (".md", ".txt", ".log", ".csv", ".json", ".yaml", ".yml", ".toml"),
}
SUFFIXES = {suffix: kind for kind, suffixes in KINDS.items() for suffix in suffixes}

# A run of path characters ending in one of those extensions. Run against the raw JSONL rather
# than the parsed entries: a path is worth showing whether it was an argument, something that
# came back from a tool, or a name written in a sentence.
# Two patterns rather than one, and the reason is a measured 70x. A single
# `[\w./~-]*\.(?:png|...)` puts `.` inside the greedy prefix *and* after it, so the engine
# restarts that run at every offset of a run and backtracks through it — quadratic in the length
# of every path-shaped blob in the file. Against this session's 4 MB window it cost 1.36 seconds,
# which is the whole of what made the Files tab slow. Finding the runs first and looking for the
# suffix only inside one is linear, and matches exactly what the single pattern matched: every
# prefix of a run that ends in a known extension.
RUN = re.compile(r"[\w./~-]+")
ENDING = re.compile(r"\.(?:" + "|".join(s[1:] for s in SUFFIXES) + r")\b", re.IGNORECASE)
# Machinery, not work. A phone showing 200 files out of node_modules shows nothing.
SKIP = {".git", "node_modules", ".venv", "__pycache__", ".build", ".mypy_cache", "DerivedData"}
MAX_FILES = 60
#: A connected folder is where renders pile up, so it gets its own, larger share of the list.
MAX_CONNECTED = 120
#: ponytail: a walk stops after this many files, so a folder of a million lists the first part.
MAX_WALKED = 20_000
MAX_SUGGESTED = 8
#: transcript -> ((size, mtime, cwd), every path it names). The scan of a 4 MB tail is ~0.5-1 s
#: and was paid on every dashboard open and every `/file` download, for a file that had not
#: moved. Only the names are kept: each one is still stat-ed per call, so a file that changed
#: or went is answered as it is now. One entry per transcript, replaced when it grows.
# ponytail: never evicted; a session id's entry is a few KB and the daemon restarts often.
_named: dict[Path, tuple[tuple[int, int, str], tuple[Path, ...]]] = {}


@dataclass(slots=True)
class Asset:
    """One openable file, as the phone lists it."""

    path: str
    name: str
    kind: str
    size: int
    modified: float
    #: The connected folder it was found in; None for a file the transcript named.
    connected: str | None = None

    def to_json(self) -> dict:
        return asdict(self)


def readable_files(session_id: str, cwd: str, provider: str = "claude") -> list[Asset]:
    """Every openable file this session touched, and every one in a connected folder, newest first."""
    inside = _connected(cwd)
    named = [a for key, a in _named_files(session_id, cwd, provider) if key not in inside]
    return sorted([*named, *inside.values()], key=lambda a: a.modified, reverse=True)


def allowed(session_id: str, cwd: str, wanted: str, provider: str = "claude") -> Path | None:
    """The file at `wanted`, but only because it lies in a connected folder or the transcript named it."""
    if found := _within(cwd, wanted):
        return found
    for _, asset in _named_files(session_id, cwd, provider):
        if asset.path == wanted:
            return Path(asset.path)
    return None


def suggested(session_id: str, cwd: str, provider: str = "claude") -> list[str]:
    """Folders this session wrote openable files into, newest first and not yet connected: what
    the phone offers to connect with a tap. The project's own folder is not one — the transcript
    already covers it, and connecting it would list the whole project."""
    connected = folders.load(cwd)
    home = folders.settled(cwd)
    found: dict[str, None] = {}
    for _, asset in _named_files(session_id, cwd, provider):
        parent = folders.settled(str(Path(asset.path).parent))
        if parent and parent != home and not any(Path(parent).is_relative_to(f) for f in connected):
            found.setdefault(parent)
    return list(found)[:MAX_SUGGESTED]


def _named_files(session_id: str, cwd: str, provider: str) -> list[tuple[tuple[int, int], Asset]]:
    """The newest openable files the transcript named, each with its identity on disk."""
    found: dict[tuple[int, int], Asset] = {}
    for candidate in _names(session_id, cwd, provider):
        # Keyed on the file itself, not its name: `CLAUDE.md` and `claude.md` are one
        # file on this disk and would otherwise be two rows saying the same thing.
        if not SKIP & set(candidate.parts) and (pair := _asset(candidate)):
            found.setdefault(pair[0], pair[1])
    newest = sorted(found.items(), key=lambda pair: pair[1].modified, reverse=True)
    return newest[:MAX_FILES]


def _connected(cwd: str) -> dict[tuple[int, int], Asset]:
    """The newest openable files inside every folder connected to this project."""
    found: dict[tuple[int, int], Asset] = {}
    for folder in folders.load(cwd):
        for candidate in islice(_walk(Path(folder)), MAX_WALKED):
            pair = _asset(candidate)
            # A symlink inside the folder pointing out of it is not inside it.
            if pair and Path(pair[1].path).is_relative_to(folder):
                pair[1].connected = folder
                found.setdefault(pair[0], pair[1])
    newest = sorted(found.items(), key=lambda pair: pair[1].modified, reverse=True)
    return dict(newest[:MAX_CONNECTED])


def _walk(root: Path) -> Iterator[Path]:
    """Every file under `root` with a suffix worth showing, machinery folders left out."""
    for parent, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP]
        yield from (Path(parent) / n for n in names if Path(n).suffix.lower() in SUFFIXES)


def _within(cwd: str, wanted: str) -> Path | None:
    """`wanted`, every symlink and `..` in it resolved, if it lies inside a connected folder."""
    if not Path(wanted).is_absolute():
        return None
    try:
        settled = Path(wanted).resolve(strict=True)
    except OSError:
        return None
    if not settled.is_file():
        return None
    for folder in folders.load(cwd):
        if settled.is_relative_to(folder) and not SKIP & set(settled.relative_to(folder).parts):
            return settled
    return None


def _names(session_id: str, cwd: str, provider: str) -> tuple[Path, ...]:
    """Every distinct path the session wrote down, in the order first named: off its
    transcript's tail, kept in `_named` until the file moves, or off OpenCode's recent history."""
    if provider == "opencode":
        try:
            return _distinct(opencode_turns.texts(session_id), cwd)
        except opencode.OpenCodeError:
            return ()
    path = transcript_path(session_id)
    if path is None:
        return ()
    try:
        stat = path.stat()
    except OSError:
        return ()
    key = (stat.st_size, stat.st_mtime_ns, cwd)
    kept = _named.get(path)
    if kept is None or kept[0] != key:
        lines = (raw.decode("utf-8", "replace") for raw in tail_lines(path, TAIL_WINDOWS[1]))
        kept = _named[path] = (key, _distinct(lines, cwd))
    return kept[1]


def _distinct(lines: Iterable[str], cwd: str) -> tuple[Path, ...]:
    return tuple(dict.fromkeys(found for line in lines for found in _candidates(line, cwd)))


def _runs(text: str) -> list[str]:
    """Every path-shaped prefix in one line: a run of path characters cut at a known extension."""
    out = []
    for run in RUN.finditer(text):
        found = run.group(0)
        out.extend(found[:end.end()] for end in ENDING.finditer(found))
    return out


def _candidates(text: str, cwd: str) -> list[Path]:
    """Every path-shaped run in one line, resolved the way the session would have meant it."""
    out = []
    for raw in _runs(text):
        if raw.startswith("~"):
            found = Path.home() / raw[2:] if raw.startswith("~/") else Path(raw)
        else:
            found = Path(raw)
        if not found.is_absolute():
            found = Path(cwd) / found
        out.append(found)
    return out


def _asset(path: Path) -> tuple[tuple[int, int], Asset] | None:
    """The file's identity and how to list it. None for anything not worth showing."""
    try:
        settled = path.resolve()
        stat = settled.stat()
    except OSError:
        return None
    if not settled.is_file() or not stat.st_size:
        return None
    return (stat.st_dev, stat.st_ino), Asset(
        path=str(settled),
        name=settled.name,
        kind=SUFFIXES.get(settled.suffix.lower(), "text"),
        size=stat.st_size,
        modified=stat.st_mtime,
    )
