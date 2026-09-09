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
    """A message swallowed by the running turn is kept, because nothing else will ever show it.

    Verified against a live transcript: an `absorbed_mid_turn` removal writes no user entry, so
    forgetting it here is a prompt vanishing in front of the person who just sent it.
    """
    write_transcript(
        claude_home,
        [
            queue("enqueue", "make the tabs bigger"),
            queue("enqueue", "and check the icon"),
            queue("remove", "make the tabs bigger", reason="absorbed_mid_turn"),
        ],
    )

    assert asked.queued(SID) == [
        {"text": "make the tabs bigger", "state": "taken"},
        {"text": "and check the icon", "state": "waiting"},
    ]


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

    assert asked.queued(SID) == [{"text": "two", "state": "waiting"}]


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

    assert asked.queued(SID) == [{"text": "the thing I actually said", "state": "waiting"}]


def test_only_the_last_few_absorbed_messages_are_kept(claude_home):
    entries = []
    for n in range(6):
        entries += [queue("enqueue", f"ask {n}"), queue("remove", f"ask {n}",
                                                        reason="absorbed_mid_turn")]
    entries.append(queue("enqueue", "still waiting"))
    write_transcript(claude_home, entries)

    assert asked.queued(SID) == [
        {"text": "ask 3", "state": "taken"},
        {"text": "ask 4", "state": "taken"},
        {"text": "ask 5", "state": "taken"},
        {"text": "still waiting", "state": "waiting"},
    ]
