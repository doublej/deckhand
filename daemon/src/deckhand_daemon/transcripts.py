"""The last few rounds of a session, read from its Claude Code transcript.

Transcripts are JSONL at ~/.claude/projects/<encoded cwd>/<sessionId>.jsonl. The encoding of
the folder name is lossy (both `/` and `_` become `-`), so the file is found by globbing for
the session id instead of by rebuilding the path. Files run to megabytes, so only the tail is
read.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import asdict, dataclass
from pathlib import Path

# A session deep in a tool run can push its last words far back, so widen until turns appear.
TAIL_WINDOWS = (512 * 1024, 4 * 1024 * 1024, 32 * 1024 * 1024)
MAX_TEXT = 4000
_NOISE = re.compile(r"<(system-reminder|command-message|command-name|command-args)>.*?</\1>", re.DOTALL)


@dataclass(slots=True)
class Turn:
    role: str
    text: str
    timestamp: str

    def to_json(self) -> dict:
        return asdict(self)


def projects_dir() -> Path:
    return Path(os.environ.get("DECKHAND_CLAUDE_HOME", Path.home() / ".claude")) / "projects"


def transcript_path(session_id: str) -> Path | None:
    if not re.fullmatch(r"[A-Za-z0-9_-]{6,64}", session_id):
        return None
    matches = sorted(
        projects_dir().glob(f"*/{session_id}.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True
    )
    return matches[0] if matches else None


def _text_of(entry: dict) -> str | None:
    """The human-readable text of one transcript entry, or None if it carries none.

    Tool calls, tool results, thinking blocks and subagent traffic are not part of the
    conversation the phone shows.
    """
    if entry.get("isSidechain") or entry.get("isMeta"):
        return None
    message = entry.get("message")
    if not isinstance(message, dict):
        return None
    content = message.get("content")
    if isinstance(content, str):
        parts = [content]
    elif isinstance(content, list):
        if any(b.get("type") == "tool_result" for b in content if isinstance(b, dict)):
            return None
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
    else:
        return None
    text = _NOISE.sub("", "\n".join(p for p in parts if p)).strip()
    return text[:MAX_TEXT] if text else None


def read_turns(session_id: str, limit: int = 8) -> list[Turn]:
    """The last `limit` conversation turns, oldest first."""
    path = transcript_path(session_id)
    if path is None:
        return []
    turns: list[Turn] = []
    for window in TAIL_WINDOWS:
        turns = _scan(path, window)
        if len(turns) >= limit:
            break
    return turns[-limit:]


def _scan(path: Path, window: int) -> list[Turn]:
    """Parse the conversation turns in the last `window` bytes of the transcript."""
    with path.open("rb") as f:
        size = f.seek(0, os.SEEK_END)
        f.seek(max(0, size - window))
        chunk = f.read()
    lines = chunk.split(b"\n")
    if size > window:
        lines = lines[1:]  # first line is a fragment
    turns: list[Turn] = []
    for raw in lines:
        if not raw.strip():
            continue
        try:
            entry = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if entry.get("type") not in ("user", "assistant"):
            continue
        text = _text_of(entry)
        if text is None:
            continue
        turns.append(Turn(role=entry["type"], text=text, timestamp=entry.get("timestamp", "")))
    return turns
