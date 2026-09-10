import json
from datetime import UTC, datetime, timedelta

from deckhand_daemon import sessions

SID = "aaaa1111-2222-3333-4444-555566667777"


def write_transcript(home, entries, session_id=SID):
    path = home / "projects" / "-Users-jj-dev" / f"{session_id}.jsonl"
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n")
    return path


def user(text, **kw):
    return {"type": "user", "message": {"content": text}, **kw}


def assistant(blocks, message_usage=None, model=None, **kw):
    """The model is on the message; the effort and `isSidechain` are on the entry around it."""
    message = {"content": blocks}
    if message_usage is not None:
        message["usage"] = message_usage
    if model is not None:
        message["model"] = model
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

    assert sessions.last_request(SID).used == 315_225


def test_a_transcript_with_no_usage_reports_nothing_rather_than_guessing(claude_home):
    write_transcript(claude_home, [user("hello")])

    assert sessions.last_request(SID).used == 0


def test_the_model_and_the_effort_come_off_the_same_entry_as_the_usage(claude_home):
    """Which is the whole reason they are free: no second pass over the transcript."""
    write_transcript(
        claude_home,
        [
            assistant([], message_usage={"input_tokens": 1}, model="claude-opus-5",
                      effort="xhigh"),
            assistant([], message_usage={"input_tokens": 9}, model="claude-sonnet-5",
                      effort="medium"),
        ],
    )

    ran = sessions.last_request(SID)
    assert (ran.used, ran.model, ran.effort) == (9, "claude-sonnet-5", "medium")


def test_a_subagents_entry_is_not_the_sessions_model(claude_home):
    write_transcript(
        claude_home,
        [
            assistant([], message_usage={"input_tokens": 7}, model="claude-opus-5", effort="high"),
            assistant([], message_usage={"input_tokens": 400}, model="claude-haiku-4-5",
                      effort="low", isSidechain=True),
        ],
    )

    ran = sessions.last_request(SID)
    assert (ran.used, ran.model) == (7, "claude-opus-5")


def test_an_interrupt_is_stepped_over_rather_than_read_as_an_empty_window(claude_home):
    """Claude Code writes its own `<synthetic>` turn for an interrupt, with a usage of zeros.

    Stopping at one reported 0 of 450k and `<synthetic>` as the model, which is a session that
    looks freshly compacted and running nothing.
    """
    write_transcript(
        claude_home,
        [
            assistant([], message_usage={"input_tokens": 120_000}, model="claude-sonnet-5",
                      effort="xhigh"),
            assistant([], message_usage={"input_tokens": 0, "cache_read_input_tokens": 0},
                      model="<synthetic>"),
        ],
    )

    ran = sessions.last_request(SID)
    assert (ran.used, ran.model, ran.effort) == (120_000, "claude-sonnet-5", "xhigh")


def test_the_window_is_the_one_this_mac_is_configured_to_compact_at(claude_home):
    (claude_home / "settings.json").write_text('{"autoCompactWindow": 450000}')

    assert sessions.context_window() == 450_000


def test_no_setting_falls_back_rather_than_dividing_by_nothing(claude_home):
    assert sessions.context_window() == sessions.DEFAULT_WINDOW


def write_week(home, **fields):
    ends = datetime.now(UTC) + timedelta(days=3.5)
    week = {"end": ends.isoformat(), "pct_used": 152, "pct_elapsed": 51, "days_remaining": 3.5}
    (home / sessions.WEEK_CACHE).write_text(json.dumps({"week": week | fields}))


def test_the_week_is_read_straight_off_the_statuslines_own_cache(claude_home):
    """Including past 100: the budget is an estimate and a heavy week goes through it."""
    write_week(claude_home)

    assert sessions.week_usage() == {"pct_used": 152, "pct_elapsed": 51, "days_remaining": 3.5}


def test_no_cache_on_this_mac_says_nothing_rather_than_nothing_spent(claude_home):
    assert sessions.week_usage() is None


def test_a_window_that_has_already_closed_says_nothing(claude_home):
    """A frozen cache still answers; what it answers is about a week that ended."""
    write_week(claude_home, end=(datetime.now(UTC) - timedelta(hours=1)).isoformat())

    assert sessions.week_usage() is None


def test_a_cache_missing_a_field_says_nothing_rather_than_guessing_a_zero(claude_home):
    (claude_home / sessions.WEEK_CACHE).write_text(json.dumps({"week": {"pct_used": 40}}))

    assert sessions.week_usage() is None
