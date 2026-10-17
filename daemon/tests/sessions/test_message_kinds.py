"""Every kind of thing a harness writes reaches a turn, whichever harness wrote it."""

from deckhand_daemon.reading import entries
from deckhand_daemon.sessions import codex_turns, opencode_turns

NOW = 1_792_230_000_000


def test_codex_thinking_falls_back_to_the_raw_reasoning_when_no_summary_was_written():
    played = {"startedAt": 1, "items": [
        {"type": "reasoning", "summary": [], "content": ["Checking the schema", "x" * 9000]},
        {"type": "agentMessage", "text": "Done."}]}
    reply = codex_turns._turns(played)[-1]
    assert reply.thoughts[0] == "Checking the schema"
    assert len(reply.thoughts[1]) == codex_turns.WHOLE


def test_a_codex_round_that_failed_or_was_stopped_says_so():
    failed = {"startedAt": 1, "status": "failed", "error": {"message": "usage limit reached"},
              "items": [{"type": "commandExecution", "command": "just check"}]}
    assert codex_turns._turns(failed)[-1].text == "Stopped: usage limit reached"
    assert codex_turns._turns({"status": "interrupted", "items": []})[-1].text == "Stopped."


def test_a_codex_dot_names_what_it_looked_at_and_what_came_back():
    viewed = codex_turns._tool("imageView", {"type": "imageView", "path": "/tmp/shot.png"})
    searched = codex_turns._tool("webSearch", {"type": "webSearch", "query": "tmux",
                                               "results": ["tmux.github.io"]})
    assert viewed.detail == "/tmp/shot.png"
    assert searched.result == "tmux.github.io"


def test_an_opencode_run_that_failed_before_any_step_says_why():
    turns = opencode_turns._turns([
        {"id": "u", "type": "user", "time": {"created": NOW}, "text": "Go on."},
        {"id": "i", "type": "idle", "time": {"created": NOW + 1}, "outcome": "failed",
         "error": {"message": "OAuth access token has been revoked"}},
    ])
    assert turns[-1].text == "Stopped: OAuth access token has been revoked"


def test_opencodes_older_task_tool_links_its_child_and_thinking_is_capped():
    task = {"type": "tool", "id": "call-task", "name": "task", "time": {"created": NOW},
            "state": {"status": "completed", "input": {"description": "find callers"},
                      "metadata": {"sessionId": "ses_child"}}}
    turns = opencode_turns._turns([
        {"id": "a", "type": "assistant", "time": {"created": NOW},
         "content": [{"type": "reasoning", "text": "y" * 9000}, task,
                     {"type": "text", "text": "Found them."}]}])
    assert turns[0].tools[0].tool_id == "ses_child"
    assert len(turns[0].thoughts[0]) == opencode_turns.WHOLE


def test_claudes_compaction_summary_is_not_the_person():
    summary = {"type": "user", "isCompactSummary": True,
               "message": {"content": "This session is being continued from a previous one."}}
    assert entries.wrote_of(summary) == "the compaction"
