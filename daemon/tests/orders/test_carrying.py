"""The two endpoints, and what actually reaches a session once a person has written some orders.

A separate file from `test_store.py` for the reason `artifacts/` splits its two: these go through
the app, and what they prove is where in the delivery path the orders are joined on — after the
filter chain, in front of the words, and still behind the paths of any pictures going with them.
"""

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon import deliver as deliver_module
from deckhand_daemon import orders
from deckhand_daemon.app import app

SID = "aaaa1111-2222-3333-4444-555566667777"


def client(token):
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    return c


@pytest.fixture
def said(monkeypatch):
    """Every delivery, as `deliver.deliver` was asked to make it. Nothing reaches a real session."""
    seen: dict = {}
    monkeypatch.setattr(
        deliver_module, "deliver",
        lambda session, text, route: (seen.update(text=text, route=route), ("keyboard", None))[1],
    )
    return seen


def test_a_prompt_reaches_a_session_with_no_orders_exactly_as_it_was(token, said):
    """The empty case at the door it actually comes through, not only in the store."""
    client(token).post(f"/sessions/{SID}/say", json={"text": "run the tests"})
    assert said["text"] == "run the tests"


def test_standing_orders_ride_on_a_prompt_the_person_sent(token, said):
    c = client(token)
    saved = c.put(f"/sessions/{SID}/orders", json={"text": "always run just check"})
    assert saved.json() == {"text": "always run just check", "limit": orders.LIMIT}

    c.post(f"/sessions/{SID}/say", json={"text": "run the tests"})

    assert "always run just check" in said["text"]
    assert said["text"].endswith("run the tests")


def test_a_picture_stays_at_the_end_and_the_orders_stay_at_the_front(token, said):
    """A path is not something anybody said, so it is the one thing that keeps the last word."""
    c = client(token)
    kept = c.post(
        f"/sessions/{SID}/image", files={"file": ("s.png", b"\x89PNG" + b"x" * 8, "image/png")}
    )
    path = kept.json()["path"]
    c.put(f"/sessions/{SID}/orders", json={"text": "always run just check"})

    c.post(f"/sessions/{SID}/say", json={"text": "look", "images": [path]})

    assert said["text"].endswith(f"attached image: {path}")
    assert said["text"].index("always run just check") < said["text"].index("look")


def test_reading_them_back_is_what_was_stored(token):
    c = client(token)
    assert c.get(f"/sessions/{SID}/orders").json() == {"text": "", "limit": orders.LIMIT}
    c.put(f"/sessions/{SID}/orders", json={"text": "  always run just check  "})
    assert c.get(f"/sessions/{SID}/orders").json()["text"] == "always run just check"


def test_a_dead_session_cannot_be_given_orders(token):
    c = client(token)
    assert c.get("/sessions/no-such-session/orders").status_code == 404
    assert c.put("/sessions/no-such-session/orders", json={"text": "hi"}).status_code == 404


def test_orders_need_the_token(claude_home):
    anon = TestClient(app)
    assert anon.get(f"/sessions/{SID}/orders").status_code == 401
    assert anon.put(f"/sessions/{SID}/orders", json={"text": "hi"}).status_code == 401
