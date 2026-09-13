"""The queue: what is owed a briefing, in what order, and what costs nothing at all."""

import json

import pytest

from deckhand_daemon import briefings, sessions

SID = "aaaa1111-2222-3333-4444-555566667777"
OTHER = "bbbb1111-2222-3333-4444-555566667777"


@pytest.fixture(autouse=True)
def fresh():
    briefings._bumped.clear()
    briefings._cursor = 0


def transcript(claude_home, session_id, entries):
    path = claude_home / "projects" / "-Users-jj-dev" / f"{session_id}.jsonl"
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n")
    return path


def said(text):
    return {"type": "user", "message": {"content": text}, "timestamp": "2026-09-09T10:00:00Z"}


def did(text):
    return {"type": "assistant", "message": {"content": [{"type": "text", "text": text}]},
            "timestamp": "2026-09-09T10:00:01Z"}


def test_a_session_with_nothing_new_is_never_asked_about_again(claude_home):
    """The whole point. It used to pay a model run every two minutes for standing still."""
    transcript(claude_home, SID, [said("build it"), did("built")])
    assert briefings._due(SID) is True

    briefings.save(SID, {
        "summary": "Built it", "hash": briefings._hash(SID),
        "mtime": briefings.transcripts.transcript_path(SID).stat().st_mtime,
    })

    assert briefings._due(SID) is False
    assert briefings._next() is None


def test_a_transcript_that_moved_without_new_activity_costs_a_read_not_a_model(claude_home):
    """Claude Code appends plenty that is not activity. The hash is the second gate."""
    path = transcript(claude_home, SID, [said("build it"), did("built")])
    briefings.save(SID, {"hash": briefings._hash(SID), "mtime": path.stat().st_mtime})

    # Same conversation, one more byte of file: the mtime gate opens, the hash gate holds.
    path.write_text(path.read_text() + json.dumps({"type": "attachment"}) + "\n")

    assert briefings._due(SID) is False


def test_a_transcript_that_moved_for_nothing_is_settled_rather_than_left_stale(claude_home):
    """The second gate's answer has to be written down, or `stale` never goes out again.

    `stale` costs a `stat` now, which is only the right answer while the mtime it compares
    against is kept current. A file that moved without saying anything is exactly the case that
    writes no briefing, so if the worker did not settle it here the phone would show a spinner
    for a session nothing was ever going to be written about.
    """
    path = transcript(claude_home, SID, [said("build it"), did("built")])
    briefings.save(SID, {"summary": "Built it", "hash": briefings._hash(SID),
                         "mtime": path.stat().st_mtime})

    path.write_text(path.read_text() + json.dumps({"type": "attachment"}) + "\n")
    assert briefings.of(SID)["stale"] is True  # the cheap gate cannot know better yet

    assert briefings._due(SID) is False  # the worker opens the expensive gate and settles it

    assert briefings.load(SID)["mtime"] == path.stat().st_mtime
    assert briefings.of(SID)["stale"] is False
    assert briefings.load(SID)["summary"] == "Built it"  # settling keeps the briefing itself


def test_real_work_puts_a_session_back_in_the_queue(claude_home):
    path = transcript(claude_home, SID, [said("build it"), did("built")])
    briefings.save(SID, {"hash": briefings._hash(SID), "mtime": path.stat().st_mtime})

    path.write_text(path.read_text() + json.dumps(did("and shipped it")) + "\n")

    assert briefings._due(SID) is True


def test_opening_a_session_puts_it_at_the_front(claude_home):
    """Both are owed one; the one somebody is looking at is written first."""
    transcript(claude_home, SID, [said("one"), did("did one")])
    transcript(claude_home, OTHER, [said("two"), did("did two")])

    briefings.bump(OTHER)

    assert briefings._next() == OTHER


def test_the_cycle_moves_on_so_one_busy_session_cannot_starve_the_rest(claude_home):
    transcript(claude_home, SID, [said("one"), did("did one")])
    transcript(claude_home, OTHER, [said("two"), did("did two")])

    first = briefings._next()
    second = briefings._next()

    assert {first, second} == {SID, OTHER}


def test_a_bump_for_a_session_with_nothing_new_writes_nothing(claude_home):
    """Opening a quiet session is not a reason to buy a briefing about nothing."""
    path = transcript(claude_home, SID, [said("build it"), did("built")])
    briefings.save(SID, {"hash": briefings._hash(SID), "mtime": path.stat().st_mtime})
    transcript(claude_home, OTHER, [said("two"), did("did two")])

    briefings.bump(SID)

    assert briefings._next() == OTHER


def test_the_last_briefing_survives_a_restart(claude_home):
    """A reinstalled app, or a restarted daemon, is handed what the Mac already knew."""
    briefings.save(SID, {"summary": "Built it", "headline": "Built it", "written_at": 1.0})

    kept = briefings.of(SID)

    assert kept["summary"] == "Built it"
    assert kept["headline"] == "Built it"
    assert kept["writtenAt"] == 1.0


def test_stale_is_this_session_and_not_a_walk_of_the_whole_queue(claude_home):
    """`stale` used to ask whether this id was in the queue, which listed every live session and
    read every one of their transcripts — once per session, from a route that calls this once
    per session. Same answer, one session's worth of work: nothing has happened, so nothing is
    on its way; then real work lands and a newer briefing is owed.
    """
    path = transcript(claude_home, SID, [said("build it"), did("built")])
    briefings.save(SID, {
        "summary": "Built it", "hash": briefings._hash(SID), "mtime": path.stat().st_mtime,
    })

    assert briefings.of(SID)["stale"] is False

    path.write_text(path.read_text() + json.dumps(did("and shipped it")) + "\n")

    assert briefings.of(SID)["stale"] is True


def test_a_briefing_for_a_session_that_is_gone_is_not_on_its_way(claude_home):
    """The store outlives the session, and a briefing nothing will ever write is not pending."""
    assert briefings.of("dddd1111-2222-3333-4444-555566667777")["stale"] is False


def test_a_session_never_written_about_says_so(claude_home):
    kept = briefings.of("cccc1111-2222-3333-4444-555566667777")

    assert kept["summary"] is None
    assert kept["writtenAt"] is None


def test_a_dead_session_is_not_in_the_queue(claude_home):
    """`live_sessions` is the only source of what exists; the store outlives the session."""
    briefings.save("dddd1111-2222-3333-4444-555566667777", {"summary": "old"})
    briefings.bump("dddd1111-2222-3333-4444-555566667777")

    assert briefings._next() != "dddd1111-2222-3333-4444-555566667777"


def test_the_sessions_it_walks_are_the_live_ones(claude_home):
    """Guards the fixture's own shape: the two live records are the two it should consider."""
    assert {s.session_id for s in sessions.live_sessions()} == {SID, OTHER}
