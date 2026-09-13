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
from datetime import datetime
from pathlib import Path

from .entries import absorbed, text_of, wrote_of

# A session deep in a tool run can push its last words far back, so widen until turns appear.
TAIL_WINDOWS = (512 * 1024, 4 * 1024 * 1024, 32 * 1024 * 1024)
# Only the last entry decides whether a turn is over, so this never widens: a window holding no
# whole entry answers "still in one", which leaves the session record's own claim standing.
TURN_TAIL = 256 * 1024


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
    #: Claude Code's own id for this call. Carried because it is the join to a subagent: a
    #: `tool_use` named `Agent` and a folder under `<sessionId>/subagents/` are two views of one
    #: thing, and `agents.Agent.tool_use_id` is the other half of it. The phone does the joining,
    #: so nothing here has to index the subagent folder on every turn it reads.
    tool_id: str = ""


@dataclass(slots=True)
class Turn:
    role: str
    text: str
    timestamp: str
    #: Who wrote it, when it was not the person: a subagent by name, another session, or the
    #: harness saying a background run stopped. Empty is the person themselves, and the phone
    #: says YOU on exactly that — a notice from an agent labelled YOU is the app putting words
    #: in JJ's mouth, which is the one attribution that has to be right.
    written_by: str = ""
    # What the session ran on the way to saying this. Attached to the message that follows
    # them, because that is where they read as "how it got here" rather than as noise.
    tools: list[Tool] = field(default_factory=list)
    # What it thought on the way there, in order. Collected exactly as the tools are and for the
    # same reason: thinking belongs to the message it produced, not to a message of its own.
    # Measured on a real transcript — 326 blocks, median 548 characters, p90 1718 — which is why
    # these travel with the turn rather than behind a second request. A page of them is tens of
    # kilobytes against tool results already capped at four thousand characters each.
    thoughts: list[str] = field(default_factory=list)

    def to_json(self) -> dict:
        return asdict(self)


def projects_dir() -> Path:
    return Path(os.environ.get("DECKHAND_CLAUDE_HOME", Path.home() / ".claude")) / "projects"


#: session id -> the file it was last found in. Finding one means asking every project folder
#: on this Mac whether it holds that name — 335 folders here, 8102 transcripts, 3.5 ms a call —
#: and nearly every read route makes one per session, twice over on a listing. Measured at 8
#: globs for one `/sessions` and 20 for one `/briefings`, which the phone polls every 4 and 12
#: seconds.
#:
#: **Remembered rather than trusted**: the kept path is checked before it is answered with, so a
#: transcript that has gone falls back to the walk and this can never name a file that is not
#: there. What it cannot notice is a *second*, newer file appearing under the same id in another
#: folder — which is what the mtime sort below is for, and which has never happened here: of the
#: 8102 transcripts on this Mac, no id is in two folders.
# ponytail: cleared wholesale at the cap rather than evicted one at a time; a session id is
# ~90 bytes and the daemon restarts often. Make it an LRU if that ever stops being true.
#:
#: Keyed by the folder as well as the id, because `projects_dir` reads an environment variable:
#: two roots with the same id in them are two different files and must not answer for each other.
_found: dict[tuple[Path, str], Path] = {}
REMEMBERED = 512


def transcript_path(session_id: str) -> Path | None:
    if not re.fullmatch(r"[A-Za-z0-9_-]{6,64}", session_id):
        return None
    key = (projects_dir(), session_id)
    if (kept := _found.get(key)) is not None and kept.exists():
        return kept
    matches = sorted(
        key[0].glob(f"*/{session_id}.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True
    )
    _found.pop(key, None)
    if not matches:
        return None
    if len(_found) >= REMEMBERED:
        _found.clear()
    _found[key] = matches[0]
    return matches[0]


def turn_ended(session_id: str) -> float:
    """When this session's last turn ended, or 0 while it is still in one.

    The registry's `status` is a claim Claude Code sometimes stops maintaining. Measured on this
    Mac: a session's record froze at `busy` the moment its owner started background agents, and
    four whole turns then began and ended without a single rewrite — the phone read WORKING for
    half an hour at a session sitting at its prompt waiting to be spoken to.

    **The age of the claim is not the test**, however tempting it looks. The record is written
    exactly twice a turn and never in between: measured over six minutes, a session turning over
    rewrote it five times while one mid-turn rewrote it not at all in 26 minutes. A `busy` stamp
    is therefore as old as the turn is long, and no threshold separates a frozen record from a
    long turn. Two sessions here proved it in the same minute — one stale by 1546 s and genuinely
    working, one stale by 2036 s and finished.

    The transcript answers instead, and it is a log rather than a claim: `stop_reason` is
    `tool_use` while the model is still going and `end_turn` once it has handed control back.
    On every session whose record *is* being maintained, that entry's timestamp and the
    registry's own stamp agree to within a second — which is what makes it the same fact.
    """
    path = transcript_path(session_id)
    if path is None:
        return 0.0
    for raw in reversed(tail_lines(path, TURN_TAIL)):
        entry = parse_line(raw)
        # A subagent's own rounds run in the parent's file and are not the parent's turn.
        if entry is None or entry.get("isSidechain"):
            continue
        kind = entry.get("type")
        # A prompt or a tool's answer, with nothing said after it: the model owes a reply either
        # way. Without this a turn is briefly "over" between arriving and being started on.
        if kind == "user":
            return 0.0
        if kind != "assistant":
            continue  # hook summaries, attachments and the metadata lines say nothing about it
        if entry.get("message", {}).get("stop_reason") == "tool_use":
            return 0.0
        return _at(entry.get("timestamp"))
    return 0.0


def _at(stamp: object) -> float:
    """The epoch seconds in a transcript timestamp, or 0 for one that cannot be read."""
    try:
        return datetime.fromisoformat(str(stamp)).timestamp()
    except (TypeError, ValueError):
        return 0.0


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


def _thoughts_of(entry: dict) -> list[str]:
    """Everything the session thought in one entry, in order.

    `redacted_thinking` is deliberately not read: it carries no text a person could be shown,
    only an encrypted blob, so surfacing it would be an empty disclosure with a heading on it.
    """
    content = entry.get("message", {}).get("content")
    if entry.get("type") != "assistant" or not isinstance(content, list):
        return []
    return [
        thought.strip()[:MAX_FULL]
        for block in content
        if isinstance(block, dict) and block.get("type") == "thinking"
        and (thought := str(block.get("thinking") or ""))
        and thought.strip()
    ]


def _scan(path: Path, window: int, sidechain: bool = False) -> list[Turn]:
    """Parse the conversation turns in the last `window` bytes, with what was run between them.

    Tool calls are collected as they appear and handed to the next message that has something
    to say, so a run of twenty of them is one row under one message rather than twenty entries
    of its own. A run still in flight at the end of the file gets a turn with no words, which
    is exactly what it is: the session is working and has not spoken yet.

    Anything said to the session mid-run is a turn too, in the place it arrived — see `absorbed`.
    """
    turns: list[Turn] = []
    ran: list[tuple[str, Tool]] = []
    thought: list[str] = []
    answers: dict[str, tuple[str, bool]] = {}
    for raw in tail_lines(path, window):
        entry = parse_line(raw)
        if entry is None:
            continue
        if (interjection := absorbed(entry)) is not None:
            # No tools hung on it: a mid-run message lands inside somebody else's run, and
            # splitting that run in two around it would cut it off from its own results.
            turns.append(Turn(role="user", text=interjection, written_by=wrote_of(entry),
                              timestamp=entry.get("timestamp", "")))
            continue
        if entry.get("type") not in ("user", "assistant"):
            continue
        answers.update(_answers(entry))
        ran.extend(_tools_of(entry))
        thought.extend(_thoughts_of(entry))
        text = text_of(entry, sidechain)
        if text is None:
            continue
        turns.append(Turn(role=entry["type"], text=text, written_by=wrote_of(entry),
                          timestamp=entry.get("timestamp", ""),
                          tools=_settle(ran, answers), thoughts=thought))
        ran = []
        thought = []
    # A run still in flight carries whatever it has thought so far, which is the whole of how
    # thinking arrives live: the phone re-reads this page every few seconds, and a session
    # mid-turn has thoughts and no words yet.
    if ran or thought:
        turns.append(Turn(role="assistant", text="", timestamp="",
                          tools=_settle(ran, answers), thoughts=thought))
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
            Tool(name=block.get("name", "tool"), detail=_detail(block), call=_call(block),
                 tool_id=block.get("id", "")),
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
