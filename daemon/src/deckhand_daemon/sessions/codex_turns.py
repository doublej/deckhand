"""A Codex thread's history, read into the turns a Claude transcript is read into.

A Codex `Turn` is a round — the person's message and everything done answering it — where
Deckhand's `Turn` is one message. So one round becomes several: the person's message, then one
turn per `agentMessage`, each carrying the tools and the reasoning that came before it, the way
`reading.transcripts` hands a Claude session's tool calls to the message that follows them. Work
with no message after it yet is a turn with no words, which is how a run in flight reads there.

`itemsView: "full"` is what puts a round's items inline, so `thread/items/list` is never needed;
without it the list answers a summary (the person's message and the last reply). Ephemeral
threads refuse the call outright, and that refusal reaches the phone as a refusal rather than as
a conversation with nothing in it.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime

from ..reading.agents import Agent
from ..reading.readable import MAX_LINE
from ..reading.transcripts import Tool, Turn
from . import codex

#: As in `reading.transcripts`: a dot's one line, and the whole of a call or of its answer.
DETAIL = 140
WHOLE = 4000
#: Rounds read for `/raw`, which counts lines rather than turns.
RAW_ROUNDS = 50
#: The statuses an item fails with. An item with no status succeeded by being there.
FAILED = ("failed", "declined")
#: What a `subAgentActivity` says last about a child that is no longer working.
FINISHED = ("completed", "interrupted")


def page_turns(thread_id: str, limit: int, before: int) -> tuple[list[Turn], bool]:
    """A page as `transcripts.page_turns` answers one: oldest first, and whether there is more."""
    turns, older = _read(thread_id, limit + before)
    end = max(0, len(turns) - before)
    start = max(0, end - limit)
    return turns[start:end], start > 0 or older


def raw_lines(thread_id: str, limit: int) -> list[str]:
    """The same history as `/raw` lines, in `reading.readable`'s clock and labels."""
    lines: list[str] = []
    for turn in _read(thread_id, RAW_ROUNDS)[0]:
        clock = turn.timestamp[11:19] or " " * 8
        lines.extend(f"{clock}   ← {tool.name} {tool.detail}".rstrip() for tool in turn.tools)
        if turn.text:
            who = "YOU" if turn.role == "user" else "CODEX"
            lines.append(f"{clock} {who} {' '.join(turn.text.split())[:MAX_LINE]}")
    return lines[-limit:]


def children(thread_id: str) -> list[Agent]:
    """The subagents this thread started, newest first, as the phone's agent rows.

    Codex names each child thread in a `subAgentActivity` item — `started` once, then
    `interacted` and finally `completed` or `interrupted` — and the child is a thread of its own
    that `thread/turns/list` reads like any other, loaded or not.
    """
    answer = codex.request("thread/turns/list",
                           {"threadId": thread_id, "limit": RAW_ROUNDS, "itemsView": "full"})
    found: dict[str, Agent] = {}
    for played in reversed(answer.get("data") or []):
        for item in played.get("items") or [] if isinstance(played, dict) else []:
            if not isinstance(item, dict) or item.get("type") != "subAgentActivity":
                continue
            child, kind = str(item.get("agentThreadId") or ""), item.get("kind")
            if kind == "started" and child:
                path = str(item.get("agentPath") or "")
                found[child] = Agent(id=child, tool_use_id=child, kind=path.rsplit("/", 1)[-1],
                                     description=path, model=str(item.get("model") or ""),
                                     updated_at=float(played.get("startedAt") or 0))
            if child in found:
                found[child].running = kind not in FINISHED
    return list(reversed(found.values()))


def _read(thread_id: str, count: int) -> tuple[list[Turn], bool]:
    """The newest `count` rounds as turns, oldest first, and whether older rounds exist."""
    # ponytail: full items for every round asked for, on every poll of the page; one busy round
    # measured 375 KB. Read summaries and fetch a round's items when it is opened, if that shows.
    answer = codex.request(
        "thread/turns/list", {"threadId": thread_id, "limit": count, "itemsView": "full"})
    rounds = [r for r in reversed(answer.get("data") or []) if isinstance(r, dict)]
    return [turn for r in rounds for turn in _turns(r)], bool(answer.get("nextCursor"))


def _turns(played: dict) -> list[Turn]:
    """One round as Deckhand's turns: the person, then each reply with what came before it."""
    began = _stamp(played.get("startedAt"))
    ended = _stamp(played.get("completedAt")) or began
    found: list[Turn] = []
    tools: list[Tool] = []
    thoughts: list[str] = []
    for item in played.get("items") or []:
        kind = item.get("type") if isinstance(item, dict) else None
        if kind == "userMessage":
            found.append(Turn(role="user", text=_said(item), timestamp=began))
        elif kind == "agentMessage":
            found.append(Turn(role="assistant", text=str(item.get("text") or ""),
                              timestamp=ended, tools=tools, thoughts=thoughts))
            tools, thoughts = [], []
        elif kind == "reasoning":
            # The summary is empty unless Codex is configured to write one
            # (`model_reasoning_summary`); the raw reasoning is the fallback.
            said = item.get("summary") or item.get("content") or []
            thoughts.extend(str(line)[:WHOLE] for line in said if line)
        elif kind:
            tools.append(_tool(kind, item))
    if error := played.get("error"):
        why = error.get("message") if isinstance(error, dict) else error
        found.append(Turn(role="assistant", text=f"Stopped: {why or 'an error'}", timestamp=ended,
                          tools=tools, thoughts=thoughts))
        tools, thoughts = [], []
    elif played.get("status") == "interrupted":
        found.append(Turn(role="assistant", text="Stopped.", timestamp=ended, tools=tools,
                          thoughts=thoughts))
        tools, thoughts = [], []
    if tools or thoughts:
        found.append(Turn(role="assistant", text="", timestamp=ended, tools=tools,
                          thoughts=thoughts))
    return found


def _tool(kind: str, item: dict) -> Tool:
    """Anything a round did that is neither words nor reasoning, as a dot under the next reply."""
    changes = [change for change in item.get("changes") or [] if isinstance(change, dict)]
    call = _plain(item.get("command") or item.get("query") or item.get("arguments")
                  or [change.get("path") for change in changes] or item.get("path")
                  or item.get("prompt") or item.get("revisedPrompt") or item.get("agentPath")
                  or item.get("text") or "")
    result = _plain(item.get("aggregatedOutput") or item.get("result")
                    or [change.get("diff") for change in changes] or item.get("results")
                    or item.get("output") or item.get("contentItems") or item.get("savedPath")
                    or item.get("error") or "")
    started = kind == "subAgentActivity" and item.get("kind") == "started"
    return Tool(
        # The dot that started a subagent carries the child thread's id, its agent row's id.
        name="subagent" if started else str(item.get("tool") or kind),
        detail=" ".join(call.split())[:DETAIL],
        succeeded=item.get("status") not in FAILED and item.get("success") is not False,
        call=call[:WHOLE],
        result=result[:WHOLE],
        tool_id=str(item.get("agentThreadId") if started else item.get("id") or ""),
    )


def _said(item: dict) -> str:
    """The words of a user message. A picture in it is a path Codex was handed, not words."""
    parts = item.get("content") or []
    return "\n".join(str(part.get("text") or "") for part in parts
                     if isinstance(part, dict) and part.get("type") == "text")


def _plain(value: object) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list) and all(isinstance(part, str) for part in value):
        return "\n".join(value)
    return json.dumps(value, ensure_ascii=False)


def _stamp(seconds: object) -> str:
    """Codex counts whole seconds; a Claude transcript writes ISO with milliseconds, and the phone
    reads one shape."""
    if not isinstance(seconds, int | float) or not seconds:
        return ""
    return datetime.fromtimestamp(seconds, UTC).strftime("%Y-%m-%dT%H:%M:%S.000Z")
