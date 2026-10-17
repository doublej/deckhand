"""An OpenCode session's history, read into the turns a Claude transcript is read into.

OpenCode projects a session as a timeline of typed messages: the person's (`user`), input that was
not the person's (`synthetic`), one `assistant` message per model step, and markers between them
(`idle`, `compaction`, a model or agent switch). An assistant message's `content` is its
reasoning, its words and its tool calls, in the order they happened. Deckhand's `Turn` is one
thing said, carrying what was done on the way to it — so tool calls and reasoning are collected
until the next words and handed to them, which is how `reading.transcripts` reads a Claude
session and `codex_turns` a Codex one. Work with no words after it yet is a turn with no words.

**A subagent is a child session**, and the tool call that started it names the child in its
metadata. The dot carries the child's id as its `tool_id`, and the child's row carries the same
id as its `tool_use_id`, so the phone joins the two the way it joins a Claude `Agent` call to its
transcript, with no index of either side kept here.

Tool names stay OpenCode's own (`shell`, `read`, `edit`); the phone knows both spellings.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime

from ..reading.agents import Agent
from ..reading.readable import MAX_LINE
from ..reading.transcripts import Tool, Turn
from . import opencode
from .opencode_input import SAID

#: As in `reading.transcripts`: a dot's one line, and the whole of a call or of its answer.
DETAIL = 140
WHOLE = 4000
#: Messages asked for per page, and pages at most per read: a page of turns can be hundreds of
#: steps when a run calls a tool per step.
PAGE = 100
PAGES = 8
#: Messages read for `/raw`, which counts lines rather than turns.
RAW_MESSAGES = 200
#: The input field worth showing for each tool, in the order the phone would want to read it.
FIELDS = ("command", "path", "filePath", "pattern", "description", "url", "query", "prompt",
          "code")


def page_turns(session_id: str, limit: int, before: int) -> tuple[list[Turn], bool]:
    """A page as `transcripts.page_turns` answers one: oldest first, and whether there is more."""
    turns, older = _read(session_id, limit + before + 1)
    end = max(0, len(turns) - before)
    start = max(0, end - limit)
    return turns[start:end], start > 0 or older


def raw_lines(session_id: str, limit: int) -> list[str]:
    """The same history as `/raw` lines, in `reading.readable`'s clock and labels."""
    lines: list[str] = []
    for turn in _turns(_messages(session_id, RAW_MESSAGES)[0]):
        clock = turn.timestamp[11:19] or " " * 8
        lines.extend(f"{clock}   ← {tool.name} {tool.detail}".rstrip() for tool in turn.tools)
        if turn.text:
            who = turn.written_by.upper() or ("YOU" if turn.role == "user" else "OPENCODE")
            lines.append(f"{clock} {who} {' '.join(turn.text.split())[:MAX_LINE]}")
    return lines[-limit:]


def activity(session_id: str, cap: int = 12_000) -> str:
    """What the session has done since it was last spoken to, in the lines
    `activity.activity_since_last_user` writes, so a briefing reads both providers alike."""
    events: list[str] = []
    for turn in _turns(_messages(session_id, RAW_MESSAGES)[0]):
        if turn.role == "user":
            events = []  # spoken to: everything before that is old news
            continue
        events.extend(f"ran {tool.name}: {tool.detail}" for tool in turn.tools)
        if turn.text.strip():
            events.append(f"said: {turn.text.strip()[:600]}")
    return "\n".join(events)[-cap:]


def texts(session_id: str) -> list[str]:
    """The recent history as text, for `files` to find the paths in."""
    return [json.dumps(m, ensure_ascii=False) for m in _messages(session_id, RAW_MESSAGES)[0]]


def children(session_id: str, running: set[str] | None = None) -> list[Agent]:
    """The subagents this session started, newest first, as the phone's agent rows."""
    answer = opencode.request("GET", "/api/session",
                     query={"parentID": session_id, "order": "desc", "limit": 50})
    if running is None:
        running = set(opencode.request("GET", "/api/session/active").get("data") or {})
    found = []
    for info in answer.get("data") or []:
        if not isinstance(info, dict) or not info.get("id"):
            continue
        model = info.get("model") or {}
        found.append(Agent(
            id=str(info["id"]), tool_use_id=str(info["id"]), kind=str(info.get("agent") or ""),
            description=str(info.get("title") or ""), model=str(model.get("id") or ""),
            running=info["id"] in running,
            updated_at=float((info.get("time") or {}).get("updated") or 0) / 1000))
    return found


def _read(session_id: str, wanted: int) -> tuple[list[Turn], bool]:
    """At least `wanted` turns from the end when there are that many, oldest first, and whether
    older messages exist beyond what was read."""
    messages: list[dict] = []
    query: dict = {"order": "desc", "limit": PAGE}
    older = False
    for _ in range(PAGES):
        page = opencode.request("GET", f"/api/session/{session_id}/message", query=query)
        messages.extend(m for m in page.get("data") or [] if isinstance(m, dict))
        cursor = (page.get("cursor") or {}).get("next")
        older = bool(cursor)
        if not cursor or len(_turns(list(reversed(messages)))) >= wanted:
            break
        query = {"cursor": cursor, "limit": PAGE}
    return _turns(list(reversed(messages))), older


def _messages(session_id: str, count: int) -> tuple[list[dict], bool]:
    """The newest `count` messages, oldest first, and whether older ones exist."""
    page = opencode.request("GET", f"/api/session/{session_id}/message",
                   query={"order": "desc", "limit": count})
    found = [m for m in page.get("data") or [] if isinstance(m, dict)]
    return list(reversed(found)), bool((page.get("cursor") or {}).get("next"))


def _turns(messages: list[dict]) -> list[Turn]:
    """The timeline as Deckhand's turns: each thing said, with what came before it."""
    found: list[Turn] = []
    tools: list[Tool] = []
    thoughts: list[str] = []
    for message in messages:
        kind = message.get("type")
        when = _stamp(message.get("time"))
        if kind == "synthetic" and SAID not in (message.get("metadata") or {}):
            # OpenCode's own note — a background result, "the server restarted", AGENTS.md —
            # is something that happened in the run, not something somebody said to it.
            text = str(message.get("text") or "")
            tools.append(Tool(name=str(message.get("description") or "OpenCode"),
                              detail=" ".join(text.split())[:DETAIL], result=text[:WHOLE],
                              tool_id=str(message.get("id") or "")))
        elif kind in ("user", "synthetic"):
            if tools or thoughts:
                found.append(Turn(role="assistant", text="", timestamp=when, tools=tools,
                                  thoughts=thoughts))
                tools, thoughts = [], []
            found.append(_said(message, when))
        elif kind == "assistant":
            for part in message.get("content") or []:
                if not isinstance(part, dict):
                    continue
                if part.get("type") == "reasoning" and part.get("text"):
                    thoughts.append(str(part["text"])[:WHOLE])
                elif part.get("type") == "tool":
                    tools.append(_tool(part))
                elif part.get("type") == "text" and str(part.get("text") or "").strip():
                    found.append(Turn(role="assistant", text=str(part["text"]), timestamp=when,
                                      tools=tools, thoughts=thoughts))
                    tools, thoughts = [], []
            if error := message.get("error"):
                found.append(Turn(role="assistant", text=f"Stopped: {_error(error)}",
                                  timestamp=when, tools=tools, thoughts=thoughts))
                tools, thoughts = [], []
        elif kind == "shell":
            output = (message.get("output") or {}).get("output") or ""
            tools.append(Tool(name="shell", detail=str(message.get("command") or "")[:DETAIL],
                              succeeded=message.get("exit") in (0, None),
                              call=str(message.get("command") or "")[:WHOLE],
                              result=str(output)[:WHOLE], tool_id=str(message.get("id") or "")))
        elif kind == "idle" and (error := message.get("error")) and not (
                found and found[-1].text.startswith("Stopped:")):
            # A run that failed before any step could say so: a revoked token, a dead provider.
            found.append(Turn(role="assistant", text=f"Stopped: {_error(error)}", timestamp=when,
                              tools=tools, thoughts=thoughts))
            tools, thoughts = [], []
        elif kind == "compaction" and message.get("status") == "completed":
            tools.append(Tool(name="compaction", detail=str(message.get("reason") or ""),
                              result=str(message.get("summary") or "")[:WHOLE],
                              tool_id=str(message.get("id") or "")))
    if tools or thoughts:
        found.append(Turn(role="assistant", text="", timestamp=found[-1].timestamp if found else "",
                          tools=tools, thoughts=thoughts))
    return found


def _said(message: dict, when: str) -> Turn:
    """The person's words, or input that was not theirs, labelled with who it was."""
    if message.get("type") == "user":
        return Turn(role="user", text=str(message.get("text") or ""), timestamp=when)
    unwrapped = (message.get("metadata") or {}).get(SAID)
    return Turn(role="user", text=str(unwrapped or message.get("text") or ""), timestamp=when,
                written_by=str(message.get("description") or "OpenCode"))


def _tool(part: dict) -> Tool:
    """One tool call as a dot under the next words."""
    state = part.get("state") or {}
    given = state.get("input") if isinstance(state.get("input"), dict) else {}
    detail = next((str(given[k]) for k in FIELDS if isinstance(given.get(k), str) and given[k]),
                  "")
    status = state.get("status")
    result = "\n".join(str(c.get("text") or "") for c in state.get("content") or []
                       if isinstance(c, dict) and c.get("type") == "text")
    if status == "error":
        result = _error(state.get("error")) + (f"\n{result}" if result else "")
    meta = state.get("metadata") or {}
    child = meta.get("sessionID") or meta.get("sessionId")  # `task`, the older tool, spells it so
    return Tool(
        name=str(part.get("name") or "tool"),
        detail=" ".join(detail.split())[:DETAIL],
        succeeded=status != "error",
        call=json.dumps(given, ensure_ascii=False)[:WHOLE],
        result=result[:WHOLE],
        # A subagent's dot carries its child session's id, which is the id of its agent row.
        tool_id=str(child or part.get("id") or ""),
    )


def _error(error: object) -> str:
    return str(error.get("message") or error.get("type") or "an error") if isinstance(
        error, dict) else str(error or "an error")


def _stamp(times: object) -> str:
    """OpenCode counts milliseconds; the phone reads ISO 8601 with fractional seconds."""
    millis = times.get("created") if isinstance(times, dict) else None
    if not isinstance(millis, int | float) or not millis:
        return ""
    return datetime.fromtimestamp(millis / 1000, UTC).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
