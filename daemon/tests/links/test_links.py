"""The edges read off the receivers' transcripts, and the one route over them.

Beside the feature rather than in `test_api.py`, which is at its size target — the same reason
`filters/test_endpoints.py` sits where it does. The route tests share this module's `enqueue`
and `write` rather than importing them across test files.
"""

import json
import time
from datetime import UTC, datetime

from fastapi.testclient import TestClient

from deckhand_daemon import sessions
from deckhand_daemon.app import app
from deckhand_daemon.links.edges import read_links

WARM = "aaaa1111-2222-3333-4444-555566667777"  # pid 4242, live
COLD = "bbbb1111-2222-3333-4444-555566667777"  # pid 4243, live
DEAD = "cccc1111-2222-3333-4444-555566667777"  # pid 9999, record on disk but not running


def stamp(seconds_ago: float) -> str:
    return datetime.fromtimestamp(time.time() - seconds_ago, UTC).strftime("%Y-%m-%dT%H:%M:%S.%f")[
        :-3
    ] + "Z"


def enqueue(from_pid, *, ago=10, operation="enqueue", hop=False, body="do the thing"):
    """One peer message as the receiver's transcript records it."""
    hop_chain = ' hop-chain="4a0ea4a88d8e1b10790fc053"' if hop else ""
    header = (
        f'<cross-session-message from="uds:/tmp/cc-socks/{from_pid}.sock"'
        f'{hop_chain} from-name="sender" from-mode="bypass">'
    )
    return {
        "type": "queue-operation",
        "operation": operation,
        "timestamp": stamp(ago),
        "content": f"{header}\n{body}",
    }


def queued_prompt(ago=10, text="a prompt the person queued"):
    """An enqueue that is not peer traffic: no header, so no edge."""
    return {
        "type": "queue-operation",
        "operation": "enqueue",
        "timestamp": stamp(ago),
        "content": text,
    }


def write(home, entries, session_id=WARM):
    path = home / "projects" / "-Users-jj-dev" / f"{session_id}.jsonl"
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n")
    return path


def read(home, within=300.0):
    return read_links(sessions.live_sessions(), within)


def client(token):
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    return c


def test_an_enqueue_is_a_directed_edge_from_sender_to_receiver(claude_home):
    write(claude_home, [enqueue(4243, ago=12)])
    found = read(claude_home)
    assert [(e.source, e.target, e.count) for e in found] == [(COLD, WARM, 1)]
    assert found[0].latest > time.time() - 60


def test_only_enqueue_counts(claude_home):
    """dequeue is the session consuming the message and remove is a cancellation."""
    write(
        claude_home,
        [
            enqueue(4243, ago=12),
            enqueue(4243, ago=11, operation="dequeue"),
            enqueue(4243, ago=10, operation="remove"),
        ],
    )
    assert [e.count for e in read(claude_home)] == [1]


def test_a_queued_prompt_is_not_a_peer_message(claude_home):
    write(claude_home, [queued_prompt()])
    assert read(claude_home) == []


def test_the_daemons_own_delivery_is_not_a_peer_message(claude_home):
    """deliver.py writes a raw user frame, so what arrives carries no header at all."""
    write(
        claude_home,
        [
            queued_prompt(text="JJ, spoken: have a look at the build"),
            {
                "type": "user",
                "message": {"content": "JJ, spoken: hello"},
                "timestamp": stamp(5),
            },
        ],
    )
    assert read(claude_home) == []


def test_a_sender_that_is_no_longer_running_draws_nothing(claude_home):
    """Both ends have to be on the listing — there is nothing to draw a link to."""
    write(claude_home, [enqueue(9999, ago=12)])
    assert read(claude_home) == []
    assert DEAD not in {e.source for e in read(claude_home)}


def test_messages_older_than_the_window_are_dropped(claude_home):
    write(claude_home, [enqueue(4243, ago=20), enqueue(4243, ago=5000)])
    found = read(claude_home, within=300)
    assert [e.count for e in found] == [1]


def test_the_window_is_clamped_to_something_scannable(claude_home):
    """A silly window is clamped rather than refused — the floor reads as 30 s, not as never."""
    write(claude_home, [enqueue(4243, ago=20)])
    assert read(claude_home, within=99_999)  # capped at an hour, and finds it
    assert read(claude_home, within=0.0)  # raised to 30 s, so a 20 s old message still counts
    write(claude_home, [enqueue(4243, ago=45)])
    assert read(claude_home, within=0.0) == []  # past the floor, so nothing


def test_traffic_both_ways_is_two_edges(claude_home):
    write(claude_home, [enqueue(4243, ago=30)], session_id=WARM)
    write(claude_home, [enqueue(4242, ago=10)], session_id=COLD)
    found = read(claude_home)
    assert {(e.source, e.target) for e in found} == {(COLD, WARM), (WARM, COLD)}
    # newest first, so the app can lean on the order
    assert found[0].latest >= found[1].latest


def test_a_burst_is_one_edge_with_a_count(claude_home):
    write(claude_home, [enqueue(4243, ago=n) for n in range(1, 64)])
    found = read(claude_home)
    assert len(found) == 1
    assert found[0].count == 63


def test_hop_chain_is_counted_but_still_an_edge(claude_home):
    write(claude_home, [enqueue(4243, ago=12), enqueue(4243, ago=11, hop=True)])
    found = read(claude_home)
    assert (found[0].count, found[0].relayed) == (2, 1)


def test_attributes_are_read_by_name_not_by_position(claude_home):
    """hop-chain sits between `from` and `from-name`, and older messages have no from-mode."""
    odd = {
        "type": "queue-operation",
        "operation": "enqueue",
        "timestamp": stamp(9),
        "content": '<cross-session-message from-name="sender" from="uds:/tmp/cc-socks/4243.sock">\nhi',
    }
    write(claude_home, [odd])
    assert [(e.source, e.target) for e in read(claude_home)] == [(COLD, WARM)]


def test_a_session_never_links_to_itself(claude_home):
    write(claude_home, [enqueue(4242, ago=12)])
    assert read(claude_home) == []


def test_a_header_that_is_only_mentioned_in_passing_is_not_an_arrival(claude_home):
    """A session quoting the header in its own text is not a message arriving."""
    write(
        claude_home,
        [
            queued_prompt(
                text='see the <cross-session-message from="uds:/tmp/cc-socks/4243.sock"> bit'
            )
        ],
    )
    assert read(claude_home) == []


def test_a_burst_of_transcript_does_not_hide_an_older_message_in_the_window(claude_home):
    """The tail widens until it reaches past the cutoff, the way read_turns does."""
    filler = [
        {
            "type": "assistant",
            "message": {"content": [{"type": "text", "text": "x" * 900}]},
            "timestamp": stamp(30),
        }
        for _ in range(900)
    ]
    write(claude_home, [enqueue(4243, ago=120)] + filler)
    assert [e.count for e in read(claude_home, within=300)] == [1]


def test_links_are_served_for_the_asked_for_window(token, claude_home):
    write(claude_home, [enqueue(4243, ago=12)])
    body = client(token).get("/sessions/links?within=300").json()
    assert body["within"] == 300
    assert [(e["source"], e["target"]) for e in body["links"]] == [(COLD, WARM)]


def test_links_refuses_a_window_it_cannot_scan(token):
    assert client(token).get("/sessions/links?within=99999").status_code == 422
    assert client(token).get("/sessions/links?within=2").status_code == 422


def test_links_is_not_mistaken_for_a_session_id(token, claude_home):
    """`/sessions/links` must not be routed as `/sessions/{session_id}/…`."""
    assert client(token).get("/sessions/links").status_code == 200
