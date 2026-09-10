import json

import pytest

from deckhand_daemon.reading import readable

SID = "aaaa1111-2222-3333-4444-555566667777"


def write(home, entries):
    path = home / "projects" / "-Users-jj-dev" / f"{SID}.jsonl"
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n")


def at(kind, **rest):
    return {"type": kind, "timestamp": "2026-09-09T10:04:12.000Z", **rest}


def test_everything_that_happened_and_none_of_the_syntax(claude_home):
    write(
        claude_home,
        [
            at("user", message={"content": "run the tests"}),
            at(
                "assistant",
                message={
                    "content": [
                        {"type": "text", "text": "Running them now"},
                        {"type": "tool_use", "name": "Bash", "input": {"command": "pytest -q"}},
                    ]
                },
            ),
            at(
                "user",
                message={
                    "content": [
                        {"type": "tool_result", "tool_use_id": "t1", "content": "90 passed"}
                    ]
                },
            ),
            at("queue-operation", operation="enqueue", content="and push it"),
        ],
    )

    lines = readable.plain_tail(SID)

    assert lines == [
        "10:04:12 YOU run the tests",
        "10:04:12 CLAUDE Running them now",
        '10:04:12   ← ran Bash: {"command": "pytest -q"}',
        "10:04:12   → ok: 90 passed",
        "10:04:12 INBOX enqueue and push it",
    ]


def test_claude_codes_own_bookkeeping_is_left_out(claude_home):
    """654 of one real day's 1,300 entries were attachments. None of them is a thing that
    happened, and a window full of them is the reason the first version showed ten lines."""
    write(
        claude_home,
        [at(kind) for kind in sorted(readable.DULL)] + [at("user", message={"content": "hello"})],
    )

    assert readable.plain_tail(SID) == ["10:04:12 YOU hello"]


@pytest.mark.parametrize("limit", [1, 2])
def test_the_newest_events_are_the_ones_that_fit(claude_home, limit):
    write(claude_home, [at("user", message={"content": f"ask {n}"}) for n in range(5)])

    assert readable.plain_tail(SID, limit) == [
        f"10:04:12 YOU ask {n}" for n in range(5 - limit, 5)
    ]
