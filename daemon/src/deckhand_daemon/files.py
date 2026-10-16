"""The files a session touched that a person could actually open on a phone.

A transcript names every path the session read or wrote. Most are source, which the tool trace
already shows; a few are things you would want to *look* at — a screenshot it took, a report it
wrote, a clip it rendered. Those are what this collects.

The same list bounds serving one back. A path that never appeared in this session's transcript
is not readable through the daemon, which is what keeps a file endpoint from being a file
browser on someone's Mac.

An OpenCode session has no transcript on disk; its recent history, read over OpenCode's API, is
searched for paths in exactly the same way, so the rule is the same rule.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass
from pathlib import Path

from .reading.transcripts import TAIL_WINDOWS, tail_lines, transcript_path
from .sessions import opencode, opencode_turns

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


@dataclass(slots=True)
class Asset:
    """One openable file, as the phone lists it."""

    path: str
    name: str
    kind: str
    size: int
    modified: float

    def to_json(self) -> dict:
        return asdict(self)


def readable_files(session_id: str, cwd: str, provider: str = "claude") -> list[Asset]:
    """Every openable file this session touched, newest first."""
    found: dict[tuple[int, int], Asset] = {}
    tried: set[Path] = set()
    for line in _lines(session_id, provider):
        for candidate in _candidates(line, cwd):
            if candidate in tried:
                continue
            tried.add(candidate)
            # Keyed on the file itself, not its name: `CLAUDE.md` and `claude.md` are one
            # file on this disk and would otherwise be two rows saying the same thing.
            if pair := _asset(candidate):
                found.setdefault(pair[0], pair[1])
    newest = sorted(found.values(), key=lambda a: a.modified, reverse=True)
    return newest[:MAX_FILES]


def allowed(session_id: str, cwd: str, wanted: str, provider: str = "claude") -> Path | None:
    """The file at `wanted`, but only because this session's transcript named it."""
    for asset in readable_files(session_id, cwd, provider):
        if asset.path == wanted:
            return Path(asset.path)
    return None


def _lines(session_id: str, provider: str) -> list[str]:
    """What the session wrote down, as text: its transcript's tail, or OpenCode's recent history."""
    if provider == "opencode":
        try:
            return opencode_turns.texts(session_id)
        except opencode.OpenCodeError:
            return []
    path = transcript_path(session_id)
    if path is None:
        return []
    return [raw.decode("utf-8", "replace") for raw in tail_lines(path, TAIL_WINDOWS[1])]


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
    if SKIP & set(path.parts):
        return None
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
