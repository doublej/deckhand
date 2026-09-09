import json

from deckhand_daemon import transcripts

SID = "aaaa1111-2222-3333-4444-555566667777"


def write_transcript(home, entries, session_id=SID):
    path = home / "projects" / "-Users-jj-dev" / f"{session_id}.jsonl"
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n")
    return path


def user(text, **kw):
    return {"type": "user", "message": {"content": text}, "timestamp": "2026-09-09T10:00:00Z", **kw}


def assistant(blocks, **kw):
    return {
        "type": "assistant",
        "message": {"content": blocks},
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
    assert [t.text for t in transcripts.read_turns(SID, limit=2)] == ["said this before the tool storm"]
