import json

from deckhand_daemon.reading import asked

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
    """Only what is still there. A message the running turn swallowed has left the inbox.

    It is not lost by leaving: Claude Code files it as a `queued_command` attachment where it
    arrived, and `transcripts.absorbed` reads it back as a turn. Keeping a second copy here put
    answered prompts at the foot of the transcript, looking like ones nobody had got to.
    """
    write_transcript(
        claude_home,
        [
            queue("enqueue", "make the tabs bigger"),
            queue("enqueue", "and check the icon"),
            queue("remove", "make the tabs bigger", reason="absorbed_mid_turn"),
        ],
    )

    assert asked.queued(SID) == [{"text": "and check the icon"}]


def test_a_message_picked_up_at_the_prompt_is_left_to_the_transcript(claude_home):
    """`dequeue` is the other ending: it becomes an ordinary user turn, so it goes from here."""
    write_transcript(
        claude_home,
        [queue("enqueue", "one"), queue("dequeue"), user("one")],
    )

    assert asked.queued(SID) == []


def test_a_drained_queue_is_empty(claude_home):
    write_transcript(
        claude_home,
        [queue("enqueue", "one"), queue("enqueue", "two"), queue("popAll", "two")],
    )

    assert asked.queued(SID) == []


def test_a_dequeue_takes_the_oldest_because_it_names_nothing(claude_home):
    write_transcript(claude_home, [queue("enqueue", "one"), queue("enqueue", "two"), queue("dequeue")])

    assert asked.queued(SID) == [{"text": "two"}]


def test_the_envelope_comes_off_before_the_phone_sees_it(claude_home):
    write_transcript(
        claude_home,
        [
            queue("enqueue", "Spoken by JJ into the deckhand app — his own words, "
                             "transcribed:\n\n  move the button   down\n"),
            queue("enqueue", '<cross-session-message from="uds:/tmp/x.sock">hello</cross-session-message>'),
            # ctrl-U, which the keyboard route types before the words to clear the prompt line.
            queue("enqueue", "\x15and this one"),
        ],
    )

    assert [item["text"] for item in asked.queued(SID)] == [
        "move the button down",
        "hello",
        "and this one",
    ]


def test_a_queued_message_is_an_ask_even_though_it_is_not_a_turn(claude_home):
    write_transcript(
        claude_home,
        [user("the first thing"), queue("enqueue", "the thing it has not seen")],
    )

    blob = asked.asks_of(SID)
    assert "ASKED: the first thing" in blob
    assert "ASKED: the thing it has not seen\n  not picked up yet" in blob


def test_claude_codes_own_notices_are_not_things_you_said(claude_home):
    """A finished background task is queued in the same inbox, and is nobody speaking.

    Dropped whole rather than unwrapped, on the way in and on the way out: a removal naming one
    would otherwise fall through to "take the oldest" and consume a real message.
    """
    notice = ("<task-notification>\n<task-id>bpy63zyfu</task-id>\n"
              "<output-file>/tmp/x.output</output-file>\ncompleted (exit code 0)\n"
              "</task-notification>")
    write_transcript(
        claude_home,
        [
            queue("enqueue", "the thing I actually said"),
            queue("enqueue", notice),
            queue("remove", notice, reason="absorbed_mid_turn"),
        ],
    )

    assert asked.queued(SID) == [{"text": "the thing I actually said"}]


def test_absorbed_messages_leave_the_inbox_however_many_there_are(claude_home):
    """The inbox is what has not been read. A run of absorbed messages empties it, not fills it."""
    entries = []
    for n in range(6):
        entries += [queue("enqueue", f"ask {n}"), queue("remove", f"ask {n}",
                                                        reason="absorbed_mid_turn")]
    entries.append(queue("enqueue", "still waiting"))
    write_transcript(claude_home, entries)

    assert asked.queued(SID) == [{"text": "still waiting"}]


def test_clearing_the_inbox_forgets_what_the_lane_still_shows(claude_home):
    """A session killed mid-queue leaves enqueues nothing will ever remove.

    The transcript is not touched — it is Claude Code's, and rewriting it is not this daemon's
    business. A line is drawn beside it and the replay starts after the line.
    """
    write_transcript(claude_home, [queue("enqueue", "left over from a dead session")])
    assert asked.queued(SID) == [{"text": "left over from a dead session"}]

    asked.clear(SID)
    assert asked.queued(SID) == []


def test_a_prompt_sent_after_the_line_still_counts(claude_home):
    """The line is a moment, not a switch: the inbox goes on working after it."""
    write_transcript(claude_home, [queue("enqueue", "stale", timestamp="2020-01-01T00:00:00.000Z")])
    asked.clear(SID)
    write_transcript(
        claude_home,
        [
            queue("enqueue", "stale", timestamp="2020-01-01T00:00:00.000Z"),
            queue("enqueue", "fresh", timestamp="2099-01-01T00:00:00.000Z"),
        ],
    )

    assert asked.queued(SID) == [{"text": "fresh"}]
