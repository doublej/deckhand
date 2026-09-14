"""The subagents a session started, read off the files Claude Code keeps beside its transcript."""

import json
import os
import time

from deckhand_daemon.reading import agents

SESSION = "aaaa1111-2222-3333-4444-555566667777"


def _spawn(claude_home, name, *, tool_use_id, kind="Explore", description="look around",
           rows=(), model=None, depth=1, called=None, shape=None, transcript=True):
    """One subagent on disk: the meta file Claude Code writes at spawn, and its transcript.

    `tool_use_id=None` is the named teammate's meta file, which has no such key at all; `called`
    is the `name:` it was spawned with, which is then the only join there is. `transcript=False`
    is the agent spawned a moment ago, whose meta file is there before its conversation is.
    """
    folder = claude_home / "projects" / "-Users-jj-dev" / SESSION / "subagents"
    folder.mkdir(parents=True, exist_ok=True)
    meta = {"agentType": kind, "description": description, "spawnDepth": depth}
    if tool_use_id is not None:
        meta["toolUseId"] = tool_use_id
    if called:
        meta["name"] = called
    if model:
        meta["model"] = model
    if shape:
        meta["requestShape"] = shape
    (folder / f"{name}.meta.json").write_text(json.dumps(meta))
    if transcript:
        (folder / f"{name}.jsonl").write_text("\n".join(json.dumps(row) for row in rows) + "\n")
    return folder


def _unwritten_for(folder, name, seconds):
    """Push an agent's files back in time. mtime is the backstop half of `running`: a transcript
    that ends mid-step belongs to a killed agent as often as to a live one."""
    then = time.time() - seconds
    for suffix in (".jsonl", ".meta.json"):
        path = folder / f"{name}{suffix}"
        if path.exists():
            os.utime(path, (then, then))


def _said(text, sidechain=True):
    return {"type": "assistant", "isSidechain": sidechain, "timestamp": "2026-09-13T10:00:00.000Z",
            "message": {"content": [{"type": "text", "text": text}]}}


def _ran(name, tool_id):
    return {"type": "assistant", "isSidechain": True, "timestamp": "2026-09-13T10:00:01.000Z",
            "message": {"content": [{"type": "tool_use", "id": tool_id, "name": name,
                                     "input": {"pattern": "x"}}]}}


def _transcript(claude_home, rows):
    path = claude_home / "projects" / "-Users-jj-dev" / f"{SESSION}.jsonl"
    path.write_text("\n".join(json.dumps(row) for row in rows) + "\n")


def test_a_session_that_has_started_none_has_none(claude_home):
    _transcript(claude_home, [_said("nothing to delegate", sidechain=False)])
    assert agents.spawned(SESSION) == []


def test_an_agent_is_read_off_its_meta_file(claude_home):
    _transcript(claude_home, [_said("delegating", sidechain=False)])
    _spawn(claude_home, "agent-a1", tool_use_id="toolu_1", kind="Plan",
           description="design the thing", model="opus",
           rows=[_said("here is the plan"), _ran("Grep", "toolu_inner")])
    found = agents.spawned(SESSION)
    assert [(a.kind, a.description, a.model, a.depth) for a in found] == [
        ("Plan", "design the thing", "opus", 1)
    ]
    assert found[0].tool_use_id == "toolu_1"


def _answered(tool_use_id):
    """The parent's `tool_result` for an Agent call. Written when a *foreground* agent comes
    back — and at spawn for a background one, which is why it cannot decide this alone."""
    return {"type": "user", "timestamp": "2026-09-13T10:00:02.000Z",
            "message": {"content": [{"type": "tool_result", "tool_use_id": tool_use_id,
                                     "content": "started"}]}}


def test_running_is_what_the_agents_own_file_is_still_doing(claude_home):
    """A finished agent's last entry is the answer it was started for: an assistant entry of
    `text` and no `tool_use`. One still going ends mid-step. Measured over every subagent
    transcript on this Mac — 3549 of the 3638 untouched for a day end on that entry, and the live
    ones sampled the same minute ended on a `tool_use`.

    The parent cannot be asked, and this is the case that proves it: `agent-busy` has its
    `tool_result` in the parent's own transcript and is working all the same.
    """
    _transcript(claude_home, [
        _said("off you go", sidechain=False),
        _answered("toolu_done"),
        _answered("toolu_busy"),
        _said("and now I wait", sidechain=False),
    ])
    _spawn(claude_home, "agent-done", tool_use_id="toolu_done", rows=[_said("finished")])
    _spawn(claude_home, "agent-busy", tool_use_id="toolu_busy",
           rows=[_said("on it"), _ran("Grep", "toolu_inner")])
    running = {a.id: a.running for a in agents.spawned(SESSION)}
    assert running == {"agent-done": False, "agent-busy": True}
    # The same answer the cheap way, which is what the idle check asks.
    assert agents.alive(SESSION)


def test_a_background_agent_runs_on_while_its_session_sits_idle(claude_home):
    """The disproven invariant, and the bug it caused. A subagent was held to run inside its
    parent's turn, so an idle session had none by construction — and the idle check looks at
    exactly the sessions that have stopped, so every agent read as stopped when it mattered.

    Measured 2026-09-14: session 8aa790b3 idle, its teammate's transcript 4.5 MB and written
    that same second. The old rule said 0 of 18 running; this one says the two that were.
    """
    _transcript(claude_home, [_said("all done", sidechain=False)])  # nothing owed: the turn ended
    _spawn(claude_home, "agent-team", tool_use_id=None, called="scout",
           rows=[_said("looking"), _ran("Grep", "toolu_inner")])
    assert [a.running for a in agents.spawned(SESSION)] == [True]
    assert agents.alive(SESSION)


def test_an_agent_that_stopped_mid_step_is_not_running_for_ever(claude_home):
    """A killed agent leaves a transcript that ends mid-step and never finishes it, so the file's
    own age is the backstop. 900 s, from the p99.99 of the gaps between one agent's consecutive
    entries (673 s over 262691 of them) — long, because a live agent inside one model call writes
    nothing at all and reading that as finished is the failure that costs something."""
    _transcript(claude_home, [_said("all done", sidechain=False)])
    folder = _spawn(claude_home, "agent-killed", tool_use_id="toolu_gone",
                    rows=[_said("thinking"), _ran("Bash", "toolu_inner")])
    _unwritten_for(folder, "agent-killed", agents.STALE / 2)
    assert [a.running for a in agents.spawned(SESSION)] == [True]
    _unwritten_for(folder, "agent-killed", agents.STALE + 60)
    assert [a.running for a in agents.spawned(SESSION)] == [False]
    assert not agents.alive(SESSION)


def test_an_agent_with_no_transcript_yet_has_answered_nothing(claude_home):
    """Claude Code writes the meta file a moment before the conversation, and a phone that read
    that gap as "finished" would let the idle check interrupt a session at the instant it
    delegated. The meta file is the clock until there is a transcript to be the clock."""
    _transcript(claude_home, [_said("off you go", sidechain=False)])
    folder = _spawn(claude_home, "agent-new", tool_use_id="toolu_new", transcript=False)
    assert [a.running for a in agents.spawned(SESSION)] == [True]
    assert agents.alive(SESSION)
    _unwritten_for(folder, "agent-new", agents.STALE + 60)
    assert [a.running for a in agents.spawned(SESSION)] == [False]


def test_a_foreground_call_the_parent_answered_is_finished_whatever_its_file_says(claude_home):
    """The one thing the parent's result still decides. `requestShape: "foreground"` is a call
    the parent *waited* on, so its `tool_result` means the agent is done even where the agent's
    own file was left mid-step — an interrupted one is exactly that shape. It confirms and never
    contradicts: on a background call, or an older meta file with no shape in it at all (3441 of
    3701 on this Mac), the file is the only answer."""
    _transcript(claude_home, [_said("off you go", sidechain=False), _answered("toolu_fg")])
    _spawn(claude_home, "agent-fg", tool_use_id="toolu_fg", shape="foreground",
           rows=[_said("half way"), _ran("Grep", "toolu_inner")])
    assert [a.running for a in agents.spawned(SESSION)] == [False]


def test_a_subagents_own_words_are_read_although_every_row_is_a_sidechain(claude_home):
    """Every row of an agent's transcript carries `isSidechain: true`. Dropping those is right
    while reading the session — its agents' chatter is not its conversation — and wrong while
    reading the agent, where it is the only thing there is."""
    _transcript(claude_home, [_said("delegating", sidechain=False)])
    _spawn(claude_home, "agent-a1", tool_use_id="toolu_1",
           rows=[_said("looking"), _ran("Grep", "toolu_inner"), _said("here is what I found")])
    turns, more = agents.read_turns(SESSION, "agent-a1")
    assert [t.text for t in turns] == ["looking", "here is what I found"]
    assert not more
    # And the counts on the row agree with the conversation behind it.
    found = agents.spawned(SESSION)[0]
    assert (found.turns, found.steps) == (2, 1)


def test_an_id_off_the_wire_cannot_name_a_file_of_its_own_choosing(claude_home):
    """The id names a file, so it is checked rather than trusted."""
    _transcript(claude_home, [_said("hi", sidechain=False)])
    _spawn(claude_home, "agent-a1", tool_use_id="toolu_1", rows=[_said("hello")])
    for bad in ("../../../etc/passwd", "agent-../secrets", "agent-a/b", "", "notanagent",
                "agent-", "agent-a.b"):
        assert agents.read_turns(SESSION, bad) == ([], False)


def test_a_named_teammates_hyphens_do_not_make_its_id_unsafe(claude_home):
    """A named agent's id is `agent-<name>-<hex>`, and refusing the hyphen refused every one of
    them: the row opened and said nothing was written down. 1889 of 3651 on this Mac."""
    _transcript(claude_home, [_said("hi", sidechain=False)])
    _spawn(claude_home, "agent-adaemon-map-fc38", tool_use_id="toolu_1",
           rows=[_said("mapped the daemon")])
    turns, _ = agents.read_turns(SESSION, "agent-adaemon-map-fc38")
    assert [t.text for t in turns] == ["mapped the daemon"]


def test_a_named_teammate_is_joined_by_name_because_its_meta_file_has_no_tool_use_id(claude_home):
    """Claude Code writes no `toolUseId` for an agent spawned with a `name:`, so the phone's join
    found nothing and the row could not be opened. The name is in both files."""
    _transcript(claude_home, [
        {"type": "assistant", "timestamp": "2026-09-13T10:00:00.000Z",
         "message": {"content": [{"type": "tool_use", "id": "toolu_team", "name": "Agent",
                                  "input": {"name": "daemon-map", "subagent_type": "Explore",
                                            "description": "map it"}}]}},
        _said("started it", sidechain=False),
    ])
    _spawn(claude_home, "agent-adaemon-map-fc38", tool_use_id=None, called="daemon-map",
           rows=[_said("mapped")])
    found = agents.spawned(SESSION)
    assert [a.tool_use_id for a in found] == ["toolu_team"]


def test_a_written_tool_use_id_beats_the_name_index(claude_home):
    """The name is the fallback, never the first answer: an unnamed agent's own id is the join
    Claude Code wrote down, and a name collision must not be able to move it."""
    _transcript(claude_home, [
        {"type": "assistant", "timestamp": "2026-09-13T10:00:00.000Z",
         "message": {"content": [{"type": "tool_use", "id": "toolu_other", "name": "Agent",
                                  "input": {"name": "scout", "description": "look"}}]}},
        _said("started it", sidechain=False),
    ])
    _spawn(claude_home, "agent-a1", tool_use_id="toolu_mine", called="scout",
           rows=[_said("hello")])
    assert agents.spawned(SESSION)[0].tool_use_id == "toolu_mine"


def test_a_tool_call_carries_the_id_that_joins_it_to_its_agent(claude_home):
    """The phone does the join: a dot says its own tool id, the agent row says which id started
    it. Nothing indexes the subagent folder on every turn that is read."""
    from deckhand_daemon.reading import transcripts
    _transcript(claude_home, [
        {"type": "assistant", "timestamp": "2026-09-13T10:00:00.000Z",
         "message": {"content": [{"type": "tool_use", "id": "toolu_1", "name": "Agent",
                                  "input": {"subagent_type": "Explore", "description": "look"}}]}},
        _said("done", sidechain=False),
    ])
    turns = transcripts.read_turns(SESSION)
    tools = [tool for turn in turns for tool in turn.tools]
    assert [(t.name, t.tool_id) for t in tools] == [("Agent", "toolu_1")]
