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


def activity_since_last_user(session_id: str, cap: int = 12_000) -> str:
    """What the session has done since the person last spoke, as plain text to summarise.

    Unlike `read_turns` this keeps the tool calls: what a session did is mostly what it ran.
    """
    path = transcript_path(session_id)
    if path is None:
        return ""
    lines = _tail_lines(path, TAIL_WINDOWS[1])
    events: list[str] = []
    for raw in lines:
        entry = _parse(raw)
        if entry is None or entry.get("isSidechain"):
            continue
        if entry.get("type") == "user" and _text_of(entry) is not None:
            events = []  # the person spoke: everything before that is old news
            continue
        events.extend(_describe(entry))
    return "\n".join(events)[-cap:]


def _describe(entry: dict) -> list[str]:
    """One line per thing the session did, in the order it did them."""
    if entry.get("type") != "assistant":
        return []
    content = entry.get("message", {}).get("content")
    if not isinstance(content, list):
        return []
    lines = []
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "text" and block.get("text", "").strip():
            lines.append(f"said: {block['text'].strip()[:600]}")
        elif block.get("type") == "tool_use":
            detail = json.dumps(block.get("input", {}))[:200]
            lines.append(f"ran {block.get('name', 'a tool')}: {detail}")
    return lines


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


def _tail_lines(path: Path, window: int) -> list[bytes]:
    """The last `window` bytes of the file, split into whole lines."""
    with path.open("rb") as f:
        size = f.seek(0, os.SEEK_END)
        f.seek(max(0, size - window))
        chunk = f.read()
    lines = chunk.split(b"\n")
    return lines[1:] if size > window else lines  # first line of a partial read is a fragment


def _parse(raw: bytes) -> dict | None:
    if not raw.strip():
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def _scan(path: Path, window: int) -> list[Turn]:
    """Parse the conversation turns in the last `window` bytes of the transcript."""
    turns: list[Turn] = []
    for raw in _tail_lines(path, window):
        entry = _parse(raw)
        if entry is None:
            continue
        if entry.get("type") not in ("user", "assistant"):
            continue
        text = _text_of(entry)
        if text is None:
            continue
        turns.append(Turn(role=entry["type"], text=text, timestamp=entry.get("timestamp", "")))
    return turns
