import json
from pathlib import Path

from deckhand_daemon.reading import transcripts

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


def test_a_mid_run_message_carrying_a_picture_is_still_a_turn(claude_home):
    """The shape that made a message with a screenshot vanish off the phone.

    A typed prompt is filed as a plain string. One that carries a picture is filed as a list of
    content blocks instead, with `imagePasteIds` beside it — so reading only the string form
    dropped exactly the messages that had a screenshot attached, which is the kind JJ sends when
    something on screen is wrong. Taken from a live transcript: `[{"type": "text", "text": …}]`.
    """
    write_transcript(
        claude_home,
        [
            queued_command([{"type": "text", "text": "\x15Feedback on the attached picture"}]),
            assistant([{"type": "text", "text": "Looking"}]),
        ],
    )

    assert [(t.role, t.text) for t in transcripts.read_turns(SID)] == [
        ("user", "Feedback on the attached picture"),
        ("assistant", "Looking"),
    ]


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


def test_a_page_of_turns_walks_backwards_from_the_end(claude_home, monkeypatch):
    """The phone reads a conversation from the bottom, so the cursor counts from the end. A
    transcript only grows at the end, which is what makes that cursor stable while it does."""
    from deckhand_daemon.reading import transcripts

    said = [f"line {n}" for n in range(1, 13)]
    monkeypatch.setattr(transcripts, "_scan",
                        lambda path, window: [transcripts.Turn(role="assistant", text=t, timestamp="")
                                              for t in said])
    monkeypatch.setattr(transcripts, "transcript_path", lambda sid: Path("/does/not/matter"))

    newest, more = transcripts.page_turns("sid", limit=4)
    assert [t.text for t in newest] == ["line 9", "line 10", "line 11", "line 12"]
    assert more is True

    older, more = transcripts.page_turns("sid", limit=4, before=4)
    assert [t.text for t in older] == ["line 5", "line 6", "line 7", "line 8"]
    assert more is True

    oldest, more = transcripts.page_turns("sid", limit=4, before=8)
    assert [t.text for t in oldest] == ["line 1", "line 2", "line 3", "line 4"]
    # Nothing before the first page, which is how the phone knows to stop asking.
    assert more is False

    # Past the start is empty rather than an error or a wrapped page.
    beyond, more = transcripts.page_turns("sid", limit=4, before=99)
    assert beyond == []
    assert more is False


def test_reading_the_tail_still_means_the_tail(claude_home, monkeypatch):
    """`read_turns` is every other caller in the daemon and its shape must not have moved."""
    from deckhand_daemon.reading import transcripts

    monkeypatch.setattr(transcripts, "_scan",
                        lambda path, window: [transcripts.Turn(role="assistant", text=str(n), timestamp="")
                                              for n in range(6)])
    monkeypatch.setattr(transcripts, "transcript_path", lambda sid: Path("/does/not/matter"))
    assert [t.text for t in transcripts.read_turns("sid", 2)] == ["4", "5"]


def test_thinking_rides_with_the_message_it_produced(tmp_path, monkeypatch):
    """A thinking block belongs to the turn it led to, exactly as a tool call does — it is how
    the session got to what it says next, not a message of its own."""
    line = json.dumps({
        "type": "assistant",
        "timestamp": "t",
        "message": {"content": [
            {"type": "thinking", "thinking": "  weighing it up  ", "signature": "sig"},
            {"type": "text", "text": "here is the answer"},
        ]},
    })
    path = tmp_path / "s.jsonl"
    path.write_text(line + "\n")
    monkeypatch.setattr(transcripts, "transcript_path", lambda _: path)
    turns, _ = transcripts.page_turns("s", 4)
    assert len(turns) == 1
    assert turns[0].text == "here is the answer"
    # Stripped, because the model pads them and a leading blank line is a blank first row.
    assert turns[0].thoughts == ["weighing it up"]


def test_a_run_still_going_carries_what_it_has_thought_so_far(tmp_path, monkeypatch):
    """This is the whole of how thinking arrives live: no push, no second route. A session
    mid-turn has thoughts and no words, and the phone re-reads this page every few seconds."""
    line = json.dumps({
        "type": "assistant",
        "timestamp": "t",
        "message": {"content": [{"type": "thinking", "thinking": "still going", "signature": "s"}]},
    })
    path = tmp_path / "s.jsonl"
    path.write_text(line + "\n")
    monkeypatch.setattr(transcripts, "transcript_path", lambda _: path)
    turns, _ = transcripts.page_turns("s", 4)
    assert [t.thoughts for t in turns] == [["still going"]]
    assert turns[-1].text == ""


def test_redacted_thinking_is_not_an_empty_disclosure(tmp_path, monkeypatch):
    """It carries an encrypted blob and no words, so a heading over it would promise nothing."""
    line = json.dumps({
        "type": "assistant",
        "timestamp": "t",
        "message": {"content": [
            {"type": "redacted_thinking", "data": "AAAA"},
            {"type": "text", "text": "done"},
        ]},
    })
    path = tmp_path / "s.jsonl"
    path.write_text(line + "\n")
    monkeypatch.setattr(transcripts, "transcript_path", lambda _: path)
    turns, _ = transcripts.page_turns("s", 4)
    assert turns[0].thoughts == []
