"""The subagents a session started, read off the files Claude Code keeps beside its transcript."""

import json

from deckhand_daemon.reading import agents

SESSION = "aaaa1111-2222-3333-4444-555566667777"


def _spawn(claude_home, name, *, tool_use_id, kind="Explore", description="look around",
           rows=(), model=None, depth=1, called=None):
    """One subagent on disk: the meta file Claude Code writes at spawn, and its transcript.

    `tool_use_id=None` is the named teammate's meta file, which has no such key at all; `called`
    is the `name:` it was spawned with, which is then the only join there is.
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
    (folder / f"{name}.meta.json").write_text(json.dumps(meta))
    (folder / f"{name}.jsonl").write_text("\n".join(json.dumps(row) for row in rows) + "\n")
    return folder


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


def _mid_turn():
    """An assistant entry that stopped to use a tool: the session owes a reply, so it is in a
    turn. This is `turn_ended`'s own reading, and `spawned` leans on it."""
    return {"type": "assistant", "timestamp": "2026-09-13T10:00:03.000Z",
            "message": {"stop_reason": "tool_use", "content": [{"type": "text", "text": "off"}]}}


def test_running_is_the_absence_of_a_result_rather_than_a_timer(claude_home):
    """The parent's transcript holds a `tool_result` for an agent that has come back, and holds
    nothing at all for one still going. No heartbeat, nothing that a slow machine breaks."""
    _transcript(claude_home, [
        _said("off you go", sidechain=False),
        {"type": "user", "timestamp": "2026-09-13T10:00:02.000Z",
         "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_done",
                                  "content": "a report"}]}},
        _mid_turn(),
    ])
    _spawn(claude_home, "agent-done", tool_use_id="toolu_done", rows=[_said("finished")])
    _spawn(claude_home, "agent-busy", tool_use_id="toolu_busy", rows=[_said("working")])
    running = {a.id: a.running for a in agents.spawned(SESSION)}
    assert running == {"agent-done": False, "agent-busy": True}


def test_nothing_is_running_in_a_session_that_is_not_in_a_turn(claude_home):
    """A subagent runs inside its parent's turn, so an idle session has none — whatever the tail
    of its transcript does or does not still hold a result for.

    Measured before this existed: one idle session read as having 16 of its 45 agents still
    going, every one of them an old agent whose result had scrolled out of the window.
    """
    _transcript(claude_home, [_said("all done", sidechain=False)])  # nothing owed: the turn ended
    _spawn(claude_home, "agent-old", tool_use_id="toolu_long_ago", rows=[_said("finished")])
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
