"""The queue: what is owed a briefing, in what order, and what costs nothing at all."""

import json
import time

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


def test_one_fast_session_cannot_buy_a_model_every_few_seconds(claude_home):
    """The floor that was missing. `GAP` bounds the worker; nothing bounded how often it wrote
    about the *same* session, so one session turning over took every slot — measured at a median
    of 26 seconds between two briefings of one session, 59% of them under 30."""
    path = transcript(claude_home, SID, [said("build it"), did("built")])
    briefings.save(SID, {"summary": "Built it", "hash": "old", "mtime": 0.0,
                         "written_at": time.time()})
    path.write_text(path.read_text() + json.dumps(did("and more")) + "\n")

    # Genuinely new work, and still not worth buying again this soon.
    assert briefings._due(SID) is False
    # And the phone is told one is coming, because it is.
    assert briefings.of(SID)["stale"] is True

    briefings.save(SID, {"summary": "Built it", "hash": "old", "mtime": 0.0,
                         "written_at": time.time() - briefings.SAME_SESSION - 1})
    assert briefings._due(SID) is True


def test_the_floor_never_delays_a_session_that_has_none(claude_home):
    """A first briefing is the one that is worth buying the moment it is owed."""
    transcript(claude_home, SID, [said("build it"), did("built")])
    assert briefings.load(SID) == {}
    assert briefings._due(SID) is True


def test_a_session_inside_its_floor_lets_another_have_the_slot(claude_home):
    """The floor is what un-starves the rest: the busy one is skipped, not queued in front."""
    transcript(claude_home, SID, [said("build it"), did("built")])
    transcript(claude_home, OTHER, [said("and this"), did("done")])
    briefings.save(SID, {"summary": "recent", "hash": "old", "mtime": 0.0,
                         "written_at": time.time()})
    briefings.bump(SID)
    assert briefings._next() == OTHER


def test_a_bump_inside_the_floor_waits_rather_than_being_thrown_away(claude_home):
    """`_next` pops, so a refusal used to destroy the request — harmless while the only
    refusals meant "nothing to say", and not once the floor refuses too. Opening a session is
    the one moment its briefing is worth more than any other's; at the measured 26-second median
    most bumps land inside the floor, so this is nearly every one of them."""
    transcript(claude_home, SID, [said("build it"), did("built")])
    transcript(claude_home, OTHER, [said("and this"), did("done")])
    briefings.save(SID, {"summary": "recent", "hash": "old", "mtime": 0.0,
                         "written_at": time.time() - 30})
    briefings.bump(SID)

    assert briefings._next() == OTHER
    assert briefings._bumped == [SID]  # still asked for, not forgotten

    briefings.save(SID, {"summary": "recent", "hash": "old", "mtime": 0.0,
                         "written_at": time.time() - briefings.SAME_SESSION - 1})
    assert briefings._next() == SID


def test_a_bump_for_a_session_that_has_gone_quiet_is_still_dropped(claude_home):
    """Only "too soon" waits. A bump with nothing behind it is a request nothing can answer, and
    holding it would block every bump behind it."""
    transcript(claude_home, SID, [said("build it"), did("built")])
    briefings.save(SID, {"summary": "said", "hash": briefings._hash(SID), "mtime": 0.0,
                         "written_at": time.time() - briefings.SAME_SESSION - 1})
    briefings.bump(SID)

    assert briefings._next() is None
    assert briefings._bumped == []


def test_a_later_bump_takes_the_front_and_costs_the_one_behind_it_nothing(claude_home):
    """A pushed-back request does lose its place — `bump` inserts at the front, which is what
    makes it a promotion. It is not starved by that: either the new front is written about,
    which frees the queue, or it is refused and the cycle reaches everything anyway.

    Measured over 10 simulated minutes with a phone parked on one session and both working:
    ten briefings each, which is exactly what a 60 s floor allows either of them.
    """
    transcript(claude_home, SID, [said("build it"), did("built")])
    transcript(claude_home, OTHER, [said("and this"), did("done")])
    old = time.time() - briefings.SAME_SESSION - 1
    briefings.save(SID, {"summary": "a", "hash": "old", "mtime": 0.0, "written_at": old})
    briefings.save(OTHER, {"summary": "b", "hash": "old", "mtime": 0.0, "written_at": time.time()})

    briefings.bump(SID)
    briefings.bump(OTHER)  # arrives later, so it goes in front of SID
    assert briefings._bumped == [OTHER, SID]

    # OTHER is inside its floor and goes back, which ends the bump loop before SID is reached.
    # The cycle is what serves SID, and that is the point: losing the front of the queue costs
    # a session its promotion, never its briefing.
    assert briefings._next() == SID
    # Both are still queued — SID's own request was never popped. Harmless: `bump` dedupes, so
    # this can never hold more ids than there are live sessions, and a request with nothing
    # behind it is dropped the next time it reaches the front.
    assert set(briefings._bumped) == {OTHER, SID}


def test_bumping_one_session_over_and_over_is_one_request(claude_home):
    """The phone asks `/summary` every five seconds while a page is open, which is faster than
    the worker sweeps. That must not become a queue of twenty identical requests."""
    transcript(claude_home, SID, [said("build it"), did("built")])
    briefings.save(SID, {"summary": "a", "hash": "old", "mtime": 0.0, "written_at": time.time()})
    for _ in range(20):
        briefings.bump(SID)
    assert briefings._bumped == [SID]

    briefings._next()
    assert briefings._bumped == [SID]  # pushed back, still exactly one

    briefings.save(SID, {"summary": "a", "hash": "old", "mtime": 0.0,
                         "written_at": time.time() - briefings.SAME_SESSION - 1})
    assert briefings._next() == SID  # and honoured once the floor is out
