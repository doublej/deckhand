import json

from deckhand_daemon import sessions

SID = "aaaa1111-2222-3333-4444-555566667777"


def write_transcript(home, entries, session_id=SID):
    path = home / "projects" / "-Users-jj-dev" / f"{session_id}.jsonl"
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n")
    return path


def user(text, **kw):
    return {"type": "user", "message": {"content": text}, **kw}


def assistant(blocks, message_usage=None, **kw):
    message = {"content": blocks}
    if message_usage is not None:
        message["usage"] = message_usage
    return {"type": "assistant", "message": message, **kw}


def test_the_context_is_what_the_last_request_filled(claude_home):
    """Input, newly cached and read back from cache are the prompt; output is not in it."""
    write_transcript(
        claude_home,
        [
            assistant([{"type": "text", "text": "early"}], message_usage={"input_tokens": 10}),
            assistant(
                [{"type": "text", "text": "latest"}],
                message_usage={
                    "input_tokens": 2,
                    "cache_creation_input_tokens": 1_731,
                    "cache_read_input_tokens": 313_492,
                    "output_tokens": 631,
                },
            ),
        ],
    )

    assert sessions.context_used(SID) == 315_225


def test_a_transcript_with_no_usage_reports_nothing_rather_than_guessing(claude_home):
    write_transcript(claude_home, [user("hello")])

    assert sessions.context_used(SID) == 0


def test_the_window_is_the_one_this_mac_is_configured_to_compact_at(claude_home):
    (claude_home / "settings.json").write_text('{"autoCompactWindow": 450000}')

    assert sessions.context_window() == 450_000


def test_no_setting_falls_back_rather_than_dividing_by_nothing(claude_home):
    assert sessions.context_window() == sessions.DEFAULT_WINDOW
