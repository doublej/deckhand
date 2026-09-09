import json

from deckhand_daemon import asked

SID = "aaaa1111-2222-3333-4444-555566667777"


def write_transcript(home, entries, session_id=SID):
    path = home / "projects" / "-Users-jj-dev" / f"{session_id}.jsonl"
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n")
    return path


def user(text, **kw):
    return {"type": "user", "message": {"content": text}, "timestamp": "2026-09-09T10:00:00Z", **kw}


def queue(operation, content=None, **kw):
    entry = {"type": "queue-operation", "operation": operation, **kw}
    if content is not None:
        entry["content"] = content
    return entry


def test_what_is_still_in_the_inbox(claude_home):
    write_transcript(
        claude_home,
        [
            queue("enqueue", "make the tabs bigger"),
            queue("enqueue", "and check the icon"),
            queue("remove", "make the tabs bigger", reason="absorbed_mid_turn"),
        ],
    )

    assert asked.queued(SID) == ["and check the icon"]


def test_a_drained_queue_is_empty(claude_home):
    write_transcript(
        claude_home,
        [queue("enqueue", "one"), queue("enqueue", "two"), queue("popAll", "two")],
    )

    assert asked.queued(SID) == []


def test_a_dequeue_takes_the_oldest_because_it_names_nothing(claude_home):
    write_transcript(claude_home, [queue("enqueue", "one"), queue("enqueue", "two"), queue("dequeue")])

    assert asked.queued(SID) == ["two"]


def test_the_envelope_comes_off_before_the_phone_sees_it(claude_home):
    write_transcript(
        claude_home,
        [
            queue("enqueue", "Spoken by JJ into the deckhand app — his own words, "
                             "transcribed:\n\n  move the button   down\n"),
            queue("enqueue", '<cross-session-message from="uds:/tmp/x.sock">hello</cross-session-message>'),
        ],
    )

    assert asked.queued(SID) == ["move the button down", "hello"]


def test_a_queued_message_is_an_ask_even_though_it_is_not_a_turn(claude_home):
    write_transcript(
        claude_home,
        [user("the first thing"), queue("enqueue", "the thing it has not seen")],
    )

    blob = asked.asks_of(SID)
    assert "ASKED: the first thing" in blob
    assert "ASKED: the thing it has not seen\n  not picked up yet" in blob
