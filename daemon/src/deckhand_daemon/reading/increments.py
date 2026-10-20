"""What a scan found in a growing transcript, kept and extended rather than redone.

Both discovery scans — the addresses (`addresses/finding.py`) and the files (`files.py`) — read
the tail of a transcript and pull things out of every line. They used to re-read the whole window
whenever the file changed, and a transcript changes on every turn: a working session paid a
4 MB scan, and a JSON parse of every line, on each poll. Here a file is read once from the start
of its window, and after that **only the bytes appended since** — a turn's worth.

Three bounds keep it light whatever a session does:

- the first read starts at most `window` bytes from the end, so a week-long transcript costs
  the same as an hour-long one;
- a line longer than `LONGEST` is skipped unread — those are base64 screenshots and whole files
  printed by a tool, megabytes that never hold anything worth listing;
- what is kept is capped at `keep` items, oldest dropped first.

A file that shrank or was replaced (another inode) starts again.
"""

from __future__ import annotations

import os
from collections.abc import Callable, Hashable
from dataclasses import dataclass, field
from pathlib import Path

LONGEST = 256 * 1024


@dataclass(slots=True)
class _State[T]:
    inode: int
    offset: int
    #: The window began inside a line, so the first one read is a fragment.
    cut: bool
    found: list[T] = field(default_factory=list)


class Increments[T]:
    """`scan` run once per complete line, over each file's window and then its growth."""

    def __init__(self, scan: Callable[[bytes, Hashable], list[T]], window: int, keep: int) -> None:
        self.scan, self.window, self.keep = scan, window, keep
        self._files: dict[tuple[Path, Hashable], _State[T]] = {}

    def read(self, path: Path, context: Hashable = None) -> list[T]:
        """Everything found in `path`'s window so far, oldest first. `context` is handed to
        `scan` and keys the cache with the path, for a scan whose answer depends on it."""
        try:
            stat = path.stat()
        except OSError:
            return []
        key = (path, context)
        state = self._files.get(key)
        if state is None or state.inode != stat.st_ino or stat.st_size < state.offset:
            start = max(0, stat.st_size - self.window)
            state = self._files[key] = _State(stat.st_ino, start, cut=start > 0)
        if stat.st_size > state.offset:
            self._extend(path, state, context)
        return state.found

    def _extend(self, path: Path, state: _State[T], context: Hashable) -> None:
        with path.open("rb") as f:
            f.seek(state.offset)
            chunk = f.read()
        end = chunk.rfind(b"\n")
        if end < 0:
            return  # no whole line yet: the writer is mid-line
        lines = chunk[:end].split(b"\n")
        if state.cut:
            lines, state.cut = lines[1:], False
        for line in lines:
            if line and len(line) <= LONGEST:
                state.found.extend(self.scan(line, context))
        state.offset += end + 1
        if len(state.found) > self.keep:
            del state.found[: len(state.found) - self.keep]


def subagents(transcript: Path, count: int) -> list[Path]:
    """The `count` most recently written subagent transcripts beside this one, newest first —
    where `agents.py` finds them: a folder named after the transcript, beside it."""
    return newest(list((transcript.with_suffix("") / "subagents").glob("*.jsonl")), count)


def newest(paths: list[Path], count: int) -> list[Path]:
    """The `count` most recently written of these, newest first; a file that vanished is skipped."""
    dated = []
    for path in paths:
        try:
            dated.append((os.stat(path).st_mtime, path))
        except OSError:
            continue
    return [path for _, path in sorted(dated, reverse=True)[:count]]
