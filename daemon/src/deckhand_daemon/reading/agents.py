"""The subagents a session has started, and each one's own transcript.

**A subagent is not a tool call, and Claude Code already agrees.** It writes one beside the
session's transcript rather than inside it:

```
~/.claude/projects/<project>/<sessionId>/subagents/agent-<id>.jsonl       its whole conversation
~/.claude/projects/<project>/<sessionId>/subagents/agent-<id>.meta.json   {agentType, description,
                                                                           toolUseId, spawnDepth,
                                                                           model?}
```

Measured on 2026-09-13, not assumed, and three of those facts are load-bearing:

- **`toolUseId` is the join, and a named teammate has none.** Where it is written it is the `id`
  of the `tool_use` block in the parent's own transcript, so a row in the conversation and a
  folder on disk are two views of one thing. An agent spawned with a `name:` is written a meta
  file with no `toolUseId` key at all — 1888 of 3651 on this Mac — and for those the name is the
  join, because Claude Code writes it into both files. See `_parent`. Nothing here diffs
  timestamps or matches on descriptions.
- **A named teammate's id has hyphens in it** (`agent-<name>-<hex>`), which is why `_safe` allows
  one. It once did not, and every named agent's conversation came back empty.
- **The tool is called `Agent`, not `Task`.** Older transcripts say `Task`; both are read, because
  the name is only a fallback — the meta index is what actually decides.
- **A subagent's rows carry the *parent's* `sessionId`** and `isSidechain: true`, and are otherwise
  shaped exactly like a session's own. That is why `transcripts._scan` reads one unchanged and
  there is no second parser here.

**Running is the absence of a result, and the session being in a turn.** No heartbeat, no mtime
threshold, nothing that goes wrong when a machine is slow.

Both halves are needed and the second was learned the expensive way. The parent's results are read
off the *tail* of its transcript, as everything here is, so an agent that finished last week has no
result in the window — and on the first live run that made 16 of one session's 45 agents read as
still going, in a session sitting idle at its prompt. The fix is not a bigger window: **a subagent
runs inside its parent's turn**, so a session that is not in one has nothing running by
construction. `turn_ended` already answers that off the same tail and was already argued for at
length, so this costs one more read of a file that is about to be read anyway.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path

from .transcripts import (
    TAIL_WINDOWS,
    Turn,
    _scan,
    parse_line,
    tail_lines,
    transcript_path,
    turn_ended,
)

#: What the tool is called in the parent's transcript, old spelling and new.
AGENT_TOOLS = ("Agent", "Task")


@dataclass(slots=True)
class Agent:
    """One subagent a session started, as the phone needs it."""

    id: str
    #: The `tool_use` block that started it, which is how a dot in the conversation finds this row.
    tool_use_id: str
    #: `Explore`, `Plan`, `general-purpose` — whatever was asked for.
    kind: str
    #: The one line the parent wrote about what it wanted, which is the only human-written
    #: description of this agent anywhere.
    description: str
    #: The model it was given, where one was named. Empty means the default was taken.
    model: str = ""
    #: 1 for an agent this session started. Deeper means an agent started by an agent — Claude
    #: Code allows it, and a phone that showed those flat would be lying about who asked for what.
    depth: int = 1
    #: No `tool_result` for `tool_use_id` yet. See the module docstring.
    running: bool = False
    #: How many things it has said and how much it has run, so a row means something before it
    #: is opened. Cheap: both come out of the same scan.
    turns: int = 0
    steps: int = 0
    updated_at: float = 0.0

    def to_json(self) -> dict:
        return asdict(self)


def _folder(session_id: str) -> Path | None:
    """Where this session's subagents are kept, or None if it has never started one.

    Derived from the transcript rather than rebuilt from the project name: the folder Claude Code
    encodes into a project directory is not something to spell twice.
    """
    path = transcript_path(session_id)
    if path is None:
        return None
    kept = path.with_suffix("") / "subagents"
    return kept if kept.is_dir() else None


def spawned(session_id: str) -> list[Agent]:
    """Every subagent this session has started, newest first.

    Off disk in one pass. The meta files are tiny and there are rarely more than a handful, so
    this is a directory listing and a few small reads — cheap enough to answer on the same poll
    that draws the conversation.
    """
    folder = _folder(session_id)
    if folder is None:
        return []
    # Nothing is running in a session that is not in a turn. See the module docstring: without
    # this, every agent whose result has scrolled out of the tail reads as still going.
    mid_turn = turn_ended(session_id) == 0.0
    answered, started = _parent(session_id)
    found = [agent for meta in sorted(folder.glob("*.meta.json"))
             if (agent := _agent(meta, answered, started, mid_turn)) is not None]
    found.sort(key=lambda a: a.updated_at, reverse=True)
    return found


def _agent(meta: Path, answered: set[str], started: dict[str, str], mid_turn: bool
           ) -> Agent | None:
    try:
        record = json.loads(meta.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(record, dict):
        return None
    # `agent-abc.meta.json` -> `agent-abc`, which is the transcript's own name beside it.
    name = meta.name.removesuffix(".meta.json")
    tool_use_id = str(record.get("toolUseId") or "")
    # A named teammate's meta file carries no `toolUseId` at all, so the name is the join. See
    # `_parent`. Only when the id is genuinely absent — a written one is always the better answer.
    if not tool_use_id and (called := str(record.get("name") or "")):
        tool_use_id = started.get(called, "")
    agent = Agent(
        id=name,
        tool_use_id=tool_use_id,
        kind=str(record.get("agentType") or ""),
        description=str(record.get("description") or ""),
        model=str(record.get("model") or ""),
        depth=int(record.get("spawnDepth") or 1),
        running=mid_turn and bool(tool_use_id) and tool_use_id not in answered,
    )
    _count(meta.with_name(f"{name}.jsonl"), agent)
    return agent


def _count(transcript: Path, agent: Agent) -> None:
    """How much this agent has said and run. Absent file is not an error — an agent that has
    only just been started has a meta file a moment before it has a transcript."""
    if not transcript.is_file():
        return
    try:
        agent.updated_at = transcript.stat().st_mtime
    except OSError:
        return
    turns = _scan(transcript, TAIL_WINDOWS[0], sidechain=True)
    agent.turns = sum(1 for turn in turns if turn.text)
    agent.steps = sum(len(turn.tools) for turn in turns)


def _parent(session_id: str) -> tuple[set[str], dict[str, str]]:
    """What the parent's own transcript says about its agents, in one walk of the tail.

    Two questions about the same lines, so one read. **Which calls have come back**, which is what
    makes an agent finished rather than running — only the tail is read, as everywhere else here,
    and an agent whose result has scrolled out of it is not therefore running, because `spawned`
    requires the session to be mid-turn as well.

    **And which `Agent` call started the teammate of a given name**, which is the join for every
    agent spawned with a name. Measured on 2026-09-13: a named teammate's meta file has no
    `toolUseId` key in it at all — 1888 of 3651 meta files on this Mac, and every one in every
    live session that day — so the dot in the conversation and the folder on disk have nothing in
    common but the name, which Claude Code writes into both: `input.name` on the `tool_use` block
    and `name` in the meta file. Without it the phone's join finds nothing and the row is drawn
    from the tool call alone, which is a row that cannot be opened.

    The newest call of a name wins: a name is reused over a session's life and the transcript on
    disk is the one that ran last.

    The tail is the ceiling, and it is deliberate: an agent spawned far enough back that its call
    has scrolled out of the window keeps an empty `tool_use_id` and cannot be reached from the
    conversation. Measured here, 3 of 10 in a 13 MB transcript. Widening to the 32 MB window would
    buy those three at the cost of reading it on every poll that draws the conversation, so the
    phone covers the gap instead: it keys such an agent by its own id rather than losing them all
    to one empty key, and gathers up any that are still running (`Agent.loose`).
    """
    path = transcript_path(session_id)
    if path is None:
        return set(), {}
    done: set[str] = set()
    started: dict[str, str] = {}
    for raw in tail_lines(path, TAIL_WINDOWS[1]):
        entry = parse_line(raw)
        if entry is None:
            continue
        content = entry.get("message", {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if (block.get("type") == "tool_result"
                    and (found := block.get("tool_use_id"))):
                done.add(str(found))
            elif block.get("type") == "tool_use" and block.get("name") in AGENT_TOOLS:
                asked = block.get("input")
                if isinstance(asked, dict) and (called := asked.get("name")):
                    started[str(called)] = str(block.get("id") or "")
    return done, started


def read_turns(session_id: str, agent_id: str, limit: int = 8, before: int = 0
               ) -> tuple[list[Turn], bool]:
    """One subagent's own conversation, paged exactly as a session's is.

    The same `_scan` the session itself is read with, because the rows are the same rows. What is
    different is only which file, which is the whole point of Claude Code keeping them apart.
    """
    folder = _folder(session_id)
    if folder is None or not _safe(agent_id):
        return [], False
    path = folder / f"{agent_id}.jsonl"
    if not path.is_file():
        return [], False
    turns: list[Turn] = []
    wanted = limit + before
    for window in TAIL_WINDOWS:
        turns = _scan(path, window, sidechain=True)
        if len(turns) > wanted:
            break
    end = max(0, len(turns) - before)
    start = max(0, end - limit)
    return turns[start:end], start > 0


def _safe(agent_id: str) -> bool:
    """An id off the wire names a file, so it is checked rather than trusted.

    A hyphen is allowed, and leaving it out is what made this route answer an empty conversation
    for every agent anybody had. An unnamed agent is `agent-` and hex, but a **named** one is
    `agent-<name>-<hex>` — 1889 of 3651 on this Mac, and all of them refused here, so a row that
    opened showed "Nothing was written down". What is refused is what could name a different
    file: a separator, a dot, a traversal.
    """
    return (bool(agent_id) and agent_id.startswith("agent-") and len(agent_id) > 6
            and all(char.isalnum() or char == "-" for char in agent_id[6:]))
