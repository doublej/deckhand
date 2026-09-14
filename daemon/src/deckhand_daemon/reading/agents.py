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

**Running is what the agent's own file is still doing.** The parent's transcript cannot answer it
and neither can the parent's turn, and both were tried:

- **The parent's `tool_result` comes back at spawn for a background agent.** Measured 2026-09-14
  on a live session: 15 of its 18 agents were spawned in the background, and every one of them —
  including one writing its transcript at that second — already had its `tool_result` in the
  parent's tail. So `answered` means finished only for a call the parent *waited* on, and only
  `requestShape: "foreground"` says that was the case. It is on 260 of 3701 meta files here
  (7.0%), so its absence says nothing: the file decides and the join may only ever confirm.
- **A subagent does not run inside its parent's turn.** That was the old rule and it is false for
  a background agent, which keeps writing while the session sits idle — which is precisely when
  the idle check looks, so every agent read as stopped exactly when it mattered. Measured: a 4.5 MB
  teammate transcript growing at the same second as its session reported idle.

What the file says, measured over every subagent transcript on this Mac rather than assumed:

- **A finished agent's last entry is an assistant entry whose content is `text` and no
  `tool_use`.** 3549 of the 3638 transcripts untouched for a day end exactly there (97.6%); the
  other 89 end mid-step, killed, and the live ones sampled the same minute ended on a `tool_use`.
  `stop_reason` is *not* the test — it is absent from 35% of those finished entries and from the
  live ones alike, where the parent's own file always carries it.
- **And mtime, but only as a backstop.** Sampling a live agent twice 3 s apart reads identical:
  it is mid-model-call, not finished. Across 262691 gaps between consecutive entries written
  after a non-terminal one, p99.9 is 187 s and p99.99 is 673 s, so `STALE` is 900 s.

When the two disagree, still-running wins. A false "still running" is one missed question; a false
"finished" interrupts a session whose agents are working, which is the bug this shape was built
around.
"""

from __future__ import annotations

import json
import time
from dataclasses import asdict, dataclass
from pathlib import Path

from .transcripts import (
    TAIL_WINDOWS,
    TURN_TAIL,
    Turn,
    _scan,
    parse_line,
    tail_lines,
    transcript_path,
)

#: What the tool is called in the parent's transcript, old spelling and new.
AGENT_TOOLS = ("Agent", "Task")
#: How long an agent that has not handed anything back may go unwritten and still count as
#: running. Picked off the measured tail rather than guessed: p99.99 of the gaps between
#: consecutive entries is 673 s, and 900 s leaves 20 of 262691 above it. Erring long is the
#: cheap direction — it is half the idle check's own `AGAIN` floor, so at worst one question
#: waits — and it is what keeps an agent blocked in a long build from reading as finished.
STALE = 900.0


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
    #: Its own file has handed nothing back and is still being written. See the module docstring:
    #: neither the parent's results nor the parent's turn can answer this for a background agent.
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
    now = time.time()
    answered, started = _parent(session_id)
    found = [agent for meta in sorted(folder.glob("*.meta.json"))
             if (agent := _agent(meta, answered, started, now)) is not None]
    found.sort(key=lambda a: a.updated_at, reverse=True)
    return found


def alive(session_id: str, now: float | None = None) -> bool:
    """Whether any subagent of this session is still working, without reading a conversation.

    One question, one answer: this is `Agent.running` with the fan-out left off. `spawned` scans
    512 KB per agent to count what each of them said, which is megabytes for a session with forty
    of them and far too much for a sweep that runs every 30 seconds over every live session. Here
    it is a directory listing and one `stat` per agent, plus a small tail read for the few that
    were written lately. Measured over the six live sessions on this Mac and their 36 agents:
    0.9 ms warm and 17 ms on a cold cache, against 122 ms for the same six the `spawned` way.
    """
    folder = _folder(session_id)
    if folder is None:
        return False
    now = time.time() if now is None else now
    return any(_working(_beside(meta), meta, now) for meta in folder.glob("*.meta.json"))


def _beside(meta: Path) -> Path:
    """`agent-abc.meta.json` -> `agent-abc.jsonl`, the transcript Claude Code keeps next to it."""
    return meta.with_name(f"{meta.name.removesuffix('.meta.json')}.jsonl")


def _working(transcript: Path, meta: Path, now: float) -> bool:
    """Whether this agent's own files say it is still going.

    Both halves, because either alone is wrong in the expensive direction: a transcript that ends
    mid-step belongs to a killed agent as often as to a live one, and a fresh mtime is missing
    from a live agent that has been inside one model call for a minute. An agent with no
    transcript at all was spawned a moment ago, so the meta file is its clock and it is working.
    """
    written = _written(transcript) or _written(meta)
    return bool(written) and now - written <= STALE and not _handed_back(transcript)


def _written(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


def _handed_back(transcript: Path) -> bool:
    """Whether the last entry in this agent's file is its answer rather than a step towards one.

    Only the last entry counts, so this reads the same small `TURN_TAIL` a session's own turn is
    read off. An assistant entry carrying `text` and no `tool_use` is the answer it was started
    for; a tool call, a tool's result, a lone thought or a file with nothing readable in it are
    all the middle of a run. `stop_reason` is deliberately not consulted — see the module
    docstring, it is absent from a third of these files and from the live ones alike.
    """
    try:
        lines = tail_lines(transcript, TURN_TAIL)
    except OSError:
        return False
    for raw in reversed(lines):
        entry = parse_line(raw)
        if entry is None:
            continue
        if entry.get("type") != "assistant":
            return False
        content = entry.get("message", {}).get("content")
        if not isinstance(content, list):
            return False
        kinds = {block.get("type") for block in content if isinstance(block, dict)}
        return "text" in kinds and "tool_use" not in kinds
    return False


def _agent(meta: Path, answered: set[str], started: dict[str, str], now: float) -> Agent | None:
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
    # The parent's result is the older, better answer — but only for a call the parent actually
    # waited on, which is what `foreground` says and nothing else does. A background agent's call
    # is answered at spawn, so reading it as finished is the whole of the bug this replaces.
    waited_on = str(record.get("requestShape") or "") == "foreground"
    transcript = _beside(meta)
    agent = Agent(
        id=name,
        tool_use_id=tool_use_id,
        kind=str(record.get("agentType") or ""),
        description=str(record.get("description") or ""),
        model=str(record.get("model") or ""),
        depth=int(record.get("spawnDepth") or 1),
        running=(_working(transcript, meta, now)
                 and not (waited_on and tool_use_id in answered)),
    )
    _count(transcript, agent)
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

    Two questions about the same lines, so one read. **Which calls have come back**, which only
    finishes an agent the parent waited on: a background call is answered at spawn, so `_agent`
    takes this as a confirmation on a `foreground` agent and never as the answer on its own. An
    agent whose result has scrolled out of the tail loses nothing by it either way — its own file
    is what says whether it is still going.

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
