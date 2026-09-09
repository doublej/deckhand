import json

from deckhand_daemon import transcripts

SID = "aaaa1111-2222-3333-4444-555566667777"


def write_transcript(home, entries, session_id=SID):
    path = home / "projects" / "-Users-jj-dev" / f"{session_id}.jsonl"
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n")
    return path


def user(text, **kw):
    return {"type": "user", "message": {"content": text}, "timestamp": "2026-09-09T10:00:00Z", **kw}


def assistant(blocks, message_usage=None, **kw):
    message = {"content": blocks}
    if message_usage is not None:
        message["usage"] = message_usage
    return {
        "type": "assistant",
        "message": message,
        "timestamp": "2026-09-09T10:00:01Z",
        **kw,
    }


def test_reads_the_last_rounds_in_order(claude_home):
    write_transcript(
        claude_home,
        [
            {"type": "agent-name", "agentName": "warm-okapi"},
            user("first"),
            assistant([{"type": "thinking", "thinking": "hmm"}]),
            assistant([{"type": "text", "text": "answer"}]),
        ],
    )
    turns = transcripts.read_turns(SID)
    assert [(t.role, t.text) for t in turns] == [("user", "first"), ("assistant", "answer")]


def test_tool_traffic_and_subagents_are_not_conversation(claude_home):
    write_transcript(
        claude_home,
        [
            user([{"type": "tool_result", "content": "ok"}]),
            assistant([{"type": "tool_use", "name": "Bash", "input": {}}]),
            assistant([{"type": "text", "text": "sub"}], isSidechain=True),
            user("visible"),
        ],
    )
    assert [t.text for t in transcripts.read_turns(SID)] == ["visible"]


def test_system_reminders_are_stripped(claude_home):
    write_transcript(claude_home, [user("keep me<system-reminder>noise\nmore</system-reminder>")])
    assert transcripts.read_turns(SID)[0].text == "keep me"


def test_limit_returns_the_newest_turns(claude_home):
    write_transcript(claude_home, [user(f"m{i}") for i in range(10)])
    assert [t.text for t in transcripts.read_turns(SID, limit=3)] == ["m7", "m8", "m9"]


def test_huge_transcript_reads_only_the_tail(claude_home):
    filler = [assistant([{"type": "text", "text": "x" * 900}]) for _ in range(1200)]
    write_transcript(claude_home, filler + [user("latest")])
    turns = transcripts.read_turns(SID, limit=2)
    assert turns[-1].text == "latest"


def test_unknown_session_has_no_transcript(claude_home):
    assert transcripts.read_turns("dddd1111-2222-3333-4444-555566667777") == []
    assert transcripts.transcript_path("../../etc/passwd") is None


def test_words_buried_under_a_long_tool_run_are_still_found(claude_home):
    tool_call = assistant([{"type": "tool_use", "name": "Bash", "input": {"command": "x" * 900}}])
    write_transcript(claude_home, [user("said this before the tool storm")] + [tool_call] * 1200)
    turns = transcripts.read_turns(SID, limit=2)
    assert turns[0].text == "said this before the tool storm"
    # The run is still going and the session has not spoken since, so the last turn has no
    # words -- which is the honest reading of a session mid-tool-storm, not an empty message.
    assert turns[-1].text == ""
    assert turns[-1].tools, "a run in flight should still say that it is running"


def test_what_it_ran_is_attached_to_what_it_said_next(claude_home):
    write_transcript(claude_home, [
        user("check the build"),
        assistant([{"type": "tool_use", "id": "t1", "name": "Bash",
                    "input": {"command": "just  build"}}]),
        {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]},
         "timestamp": "2026-09-09T10:00:02Z"},
        assistant([{"type": "tool_use", "id": "t2", "name": "Read",
                    "input": {"file_path": "/tmp/x.swift"}}]),
        {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "t2", "is_error": True, "content": "no"}]},
         "timestamp": "2026-09-09T10:00:03Z"},
        assistant([{"type": "text", "text": "the build is green"}]),
    ])
    turns = transcripts.read_turns(SID)
    # Twenty calls should not become twenty entries: they belong to the message they led to.
    assert [t.text for t in turns] == ["check the build", "the build is green"]
    ran = turns[-1].tools
    assert [(t.name, t.detail, t.succeeded) for t in ran] == [
        ("Bash", "just build", True),
        ("Read", "/tmp/x.swift", False),
    ]


def test_the_whole_call_and_the_whole_answer_are_carried(claude_home):
    """A dot is enough until it is not; then the phone needs what was run and what came back
    without another round trip."""
    write_transcript(claude_home, [
        assistant([{"type": "tool_use", "id": "t1", "name": "Bash",
                    "input": {"command": "just check", "timeout": 600}}]),
        {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "t1",
             "content": [{"type": "text", "text": "All checks passed!"}]}]},
         "timestamp": "2026-09-09T10:00:02Z"},
        assistant([{"type": "text", "text": "green"}]),
    ])
    ran = transcripts.read_turns(SID)[-1].tools[0]
    assert '"command": "just check"' in ran.call
    assert '"timeout": 600' in ran.call
    assert ran.result == "All checks passed!"


def test_a_huge_result_is_cut_rather_than_sent_whole(claude_home):
    """This rides over the LAN on every poll, and one Read can be a megabyte."""
    write_transcript(claude_home, [
        assistant([{"type": "tool_use", "id": "t1", "name": "Read", "input": {"file_path": "/x"}}]),
        {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "t1", "content": "y" * 100_000}]},
         "timestamp": "2026-09-09T10:00:02Z"},
        assistant([{"type": "text", "text": "read it"}]),
    ])
    assert len(transcripts.read_turns(SID)[-1].tools[0].result) == transcripts.MAX_FULL


def test_a_tool_nobody_has_a_field_for_still_shows_something(claude_home):
    write_transcript(claude_home, [
        assistant([{"type": "tool_use", "id": "t1", "name": "Odd", "input": {"whatever": "a value"}}]),
        assistant([{"type": "text", "text": "done"}]),
    ])
    assert transcripts.read_turns(SID)[-1].tools[0].detail == "a value"


def queued_command(prompt, origin=None, **kw):
    """How Claude Code files something said to a session that was already working."""
    return {
        "type": "attachment",
        "attachment": {"type": "queued_command", "prompt": prompt,
                       "origin": origin or {"kind": "human"}},
        "timestamp": "2026-09-09T10:00:05Z",
        **kw,
    }


def test_a_message_that_arrived_mid_run_is_a_turn_where_it_arrived(claude_home):
    """The one entry that made prompts look unread.

    Something said to a busy session never becomes a `user` entry — it is handed to the running
    turn and written down as a `queued_command` attachment. Read from a live transcript: 149 of
    them, and not one also present as a user entry, so this is the only place those words are.
    """
    write_transcript(
        claude_home,
        [
            user("start on the tabs"),
            assistant([{"type": "text", "text": "On it"}]),
            queued_command("and check the icon while you are in there"),
            assistant([{"type": "text", "text": "Both done"}]),
        ],
    )

    turns = transcripts.read_turns(SID)
    assert [(t.role, t.text) for t in turns] == [
        ("user", "start on the tabs"),
        ("assistant", "On it"),
        ("user", "and check the icon while you are in there"),
        ("assistant", "Both done"),
    ]


def test_the_envelope_and_the_machinery_come_off_a_mid_run_message(claude_home):
    """Same rules as the inbox: notices are not somebody speaking, and ctrl-U is not a word."""
    notice = "<task-notification>\n<task-id>bpy63zyfu</task-id>\ndone\n</task-notification>"
    write_transcript(
        claude_home,
        [
            queued_command(notice),
            queued_command("\x15Spoken by JJ into the deckhand app, transcribed:\n\n  ship   it\n"),
        ],
    )

    assert [(t.role, t.text) for t in transcripts.read_turns(SID)] == [("user", "ship it")]


def test_a_mid_run_message_does_not_cut_a_tool_run_off_from_its_results(claude_home):
    """It lands inside somebody else's run, so the run stays whole and settles as it would have."""
    write_transcript(
        claude_home,
        [
            assistant([{"type": "tool_use", "id": "t1", "name": "Bash",
                        "input": {"command": "pytest -q"}}]),
            queued_command("actually run the UI tests too"),
            {"type": "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "t1", "content": "90 passed"}]}},
            assistant([{"type": "text", "text": "Green"}]),
        ],
    )

    turns = transcripts.read_turns(SID)
    assert [(t.role, t.text) for t in turns] == [
        ("user", "actually run the UI tests too"),
        ("assistant", "Green"),
    ]
    assert turns[0].tools == []
    assert [(t.name, t.result) for t in turns[1].tools] == [("Bash", "90 passed")]
