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
from dataclasses import asdict, dataclass, field
from pathlib import Path

# A session deep in a tool run can push its last words far back, so widen until turns appear.
TAIL_WINDOWS = (512 * 1024, 4 * 1024 * 1024, 32 * 1024 * 1024)
MAX_TEXT = 4000
_NOISE = re.compile(r"<(system-reminder|command-message|command-name|command-args)>.*?</\1>", re.DOTALL)
# The envelope a queued message travels in: one session addressing another, or the daemon saying
# who spoke. Tags only — whatever they wrap is the message.
_WRAPPER = re.compile(r"</?[a-z][\w-]*(?:\s[^>]*)?>", re.IGNORECASE)
# Not everything that reaches a session is a person. Claude Code queues its own notices — a
# finished background task, a reminder — and those are machinery, not something anybody said.
MACHINE = re.compile(r"^\s*<\s*(?:task-notification|system-reminder|local-command-\w+)\b", re.IGNORECASE)


# The input field worth showing for each tool, in the order the phone would want to read it.
# Anything not listed falls back to the first short string in the input.
TOOL_DETAIL = ("command", "file_path", "pattern", "path", "description", "prompt", "url", "query")
MAX_DETAIL = 140
# The whole call and whatever came back, for the phone's fully-unfolded view. Capped because
# a single Read can be a megabyte and this rides over the LAN on every poll.
MAX_FULL = 4000



@dataclass(slots=True)
class Tool:
    """One thing the session ran, small enough to sit under a message as a dot."""

    name: str
    detail: str
    succeeded: bool = True
    # The whole call and the whole answer, for when a dot is not enough.
    call: str = ""
    result: str = ""


@dataclass(slots=True)
class Turn:
    role: str
    text: str
    timestamp: str
    # What the session ran on the way to saying this. Attached to the message that follows
    # them, because that is where they read as "how it got here" rather than as noise.
    tools: list[Tool] = field(default_factory=list)

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


def text_of(entry: dict) -> str | None:
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
    text = _NOISE.sub("", "\n".join(p for p in parts if p))
    # The keyboard route types ctrl-U before the words to clear whatever was half-written in the
    # prompt, and that control character is part of the entry Claude Code writes down.
    text = "".join(c for c in text if c.isprintable() or c.isspace()).strip()
    return text[:MAX_TEXT] if text else None


def unwrap(text: str) -> str:
    """The words themselves, out of whatever envelope carried them to the session.

    Deckhand's own socket route labels what it delivers, and a message from another session
    arrives inside a tag. Neither is what the person said, and neither belongs on the phone.
    """
    body = _WRAPPER.sub("", text)
    # Control characters and all: the keyboard route types ctrl-U before the words to clear
    # whatever was half-written in the prompt, and that ctrl-U travels with the message.
    body = "".join(c for c in body if c.isprintable() or c.isspace()).strip()
    _, marker, spoken = body.partition("transcribed:")
    return " ".join((spoken if marker else body).split())[:MAX_TEXT]


def absorbed(entry: dict) -> str | None:
    """Something said to a session that was already working, out of the entry that records it.

    A message that arrives mid-run never becomes a `user` entry — it is handed straight to the
    running turn and written down as a `queued_command` attachment instead. So it *is* in the
    transcript, at the moment it arrived, under a type nothing here was reading. Missing that is
    what made those messages look lost: the phone kept its own copy and showed it at the end of
    the conversation, where three answered prompts read as three that had gone unread.
    """
    if entry.get("type") != "attachment":
        return None
    attachment = entry.get("attachment")
    if not isinstance(attachment, dict) or attachment.get("type") != "queued_command":
        return None
    prompt = attachment.get("prompt")
    if not isinstance(prompt, str) or MACHINE.match(prompt):
        return None
    return unwrap(prompt) or None


def activity_since_last_user(session_id: str, cap: int = 12_000) -> str:
    """What the session has done since the person last spoke, as plain text to summarise.

    Unlike `read_turns` this keeps the tool calls: what a session did is mostly what it ran.
    """
    path = transcript_path(session_id)
    if path is None:
        return ""
    lines = tail_lines(path, TAIL_WINDOWS[1])
    events: list[str] = []
    for raw in lines:
        entry = parse_line(raw)
        if entry is None or entry.get("isSidechain"):
            continue
        if entry.get("type") == "user" and text_of(entry) is not None:
            events = []  # the person spoke: everything before that is old news
            continue
        events.extend(describe(entry))
    return "\n".join(events)[-cap:]


def describe(entry: dict) -> list[str]:
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
    return page_turns(session_id, limit)[0]


def page_turns(session_id: str, limit: int = 8, before: int = 0) -> tuple[list[Turn], bool]:
    """`limit` turns ending `before` turns from the end, and whether older ones exist.

    The phone reads a conversation from the bottom and walks backwards, so the cursor is a count
    from the *end* rather than an id or an offset from the start. That is not laziness: a
    transcript only ever grows at the end, so the thirtieth-from-last turn is still the
    thirtieth-from-last a minute later even though the session has said three more things. An
    offset from the start would have to be recomputed every time the file grew, and an id would
    mean an index this daemon does not keep.

    The whole of a session's history is on this Mac and always was — nothing about a phone
    restart loses any of it. What was missing was a way to ask for more than the tail.
    """
    path = transcript_path(session_id)
    if path is None:
        return [], False
    wanted = limit + before
    turns: list[Turn] = []
    for window in TAIL_WINDOWS:
        turns = _scan(path, window)
        # One more than asked for, so "is there an older page" is answered by the same read
        # rather than by a second one.
        if len(turns) > wanted:
            break
    end = max(0, len(turns) - before)
    start = max(0, end - limit)
    return turns[start:end], start > 0


def tail_lines(path: Path, window: int) -> list[bytes]:
    """The last `window` bytes of the file, split into whole lines."""
    with path.open("rb") as f:
        size = f.seek(0, os.SEEK_END)
        f.seek(max(0, size - window))
        chunk = f.read()
    lines = chunk.split(b"\n")
    return lines[1:] if size > window else lines  # first line of a partial read is a fragment


def parse_line(raw: bytes) -> dict | None:
    if not raw.strip():
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def _scan(path: Path, window: int) -> list[Turn]:
    """Parse the conversation turns in the last `window` bytes, with what was run between them.

    Tool calls are collected as they appear and handed to the next message that has something
    to say, so a run of twenty of them is one row under one message rather than twenty entries
    of its own. A run still in flight at the end of the file gets a turn with no words, which
    is exactly what it is: the session is working and has not spoken yet.

    Anything said to the session mid-run is a turn too, in the place it arrived — see `absorbed`.
    """
    turns: list[Turn] = []
    ran: list[tuple[str, Tool]] = []
    answers: dict[str, tuple[str, bool]] = {}
    for raw in tail_lines(path, window):
        entry = parse_line(raw)
        if entry is None:
            continue
        if (interjection := absorbed(entry)) is not None:
            # No tools hung on it: a mid-run message lands inside somebody else's run, and
            # splitting that run in two around it would cut it off from its own results.
            turns.append(Turn(role="user", text=interjection, timestamp=entry.get("timestamp", "")))
            continue
        if entry.get("type") not in ("user", "assistant"):
            continue
        answers.update(_answers(entry))
        ran.extend(_tools_of(entry))
        text = text_of(entry)
        if text is None:
            continue
        turns.append(Turn(role=entry["type"], text=text, timestamp=entry.get("timestamp", ""),
                          tools=_settle(ran, answers)))
        ran = []
    if ran:
        turns.append(Turn(role="assistant", text="", timestamp="", tools=_settle(ran, answers)))
    return turns


def _settle(ran: list[tuple[str, Tool]], answers: dict[str, tuple[str, bool]]) -> list[Tool]:
    """A result arrives after the call that asked for it, so it is known only by now."""
    settled = []
    for tool_id, tool in ran:
        result, failed = answers.get(tool_id, ("", False))
        tool.succeeded = not failed
        tool.result = result
        settled.append(tool)
    return settled


def _answers(entry: dict) -> dict[str, tuple[str, bool]]:
    """Tool results come back as a user entry; the id is what ties one to its call."""
    content = entry.get("message", {}).get("content")
    if entry.get("type") != "user" or not isinstance(content, list):
        return {}
    answers = {}
    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_result":
            continue
        if tool_id := block.get("tool_use_id"):
            answers[tool_id] = (_result_text(block.get("content")), bool(block.get("is_error")))
    return answers


def _result_text(content: object) -> str:
    """A result is a string, or the blocks a tool answered with. Images have no text to show."""
    if isinstance(content, str):
        return content[:MAX_FULL]
    if isinstance(content, list):
        parts = [
            block.get("text", "")
            for block in content
            if isinstance(block, dict) and block.get("type") == "text"
        ]
        return "\n".join(p for p in parts if p)[:MAX_FULL]
    return ""


def _tools_of(entry: dict) -> list[tuple[str, Tool]]:
    content = entry.get("message", {}).get("content")
    if entry.get("type") != "assistant" or not isinstance(content, list):
        return []
    return [
        (
            block.get("id", ""),
            Tool(name=block.get("name", "tool"), detail=_detail(block), call=_call(block)),
        )
        for block in content
        if isinstance(block, dict) and block.get("type") == "tool_use"
    ]


def _call(block: dict) -> str:
    """The whole input, laid out to be read rather than parsed."""
    supplied = block.get("input")
    if not isinstance(supplied, dict) or not supplied:
        return ""
    return json.dumps(supplied, indent=2, ensure_ascii=False)[:MAX_FULL]


def _detail(block: dict) -> str:
    """The one input worth reading: the command, the file, the pattern it searched for."""
    supplied = block.get("input")
    if not isinstance(supplied, dict):
        return ""
    for key in TOOL_DETAIL:
        value = supplied.get(key)
        if isinstance(value, str) and value.strip():
            return " ".join(value.split())[:MAX_DETAIL]
    for value in supplied.values():
        if isinstance(value, str) and value.strip():
            return " ".join(value.split())[:MAX_DETAIL]
    return ""
