"""`/camera`: a JPEG in, the newest picture out to every viewer, and the count that starts the
headset's stream."""

from __future__ import annotations

import asyncio

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon.app import app
from deckhand_daemon.space import camera as routes

JPEG = b"\xff\xd8\xff\xe0picture\xff\xd9"


@pytest.fixture
def feed(monkeypatch):
    """A feed of its own per test: its event binds to the loop that first waits on it."""
    fresh = routes.Feed()
    monkeypatch.setattr(routes, "feed", fresh)
    return fresh


@pytest.fixture
def client(token):
    return TestClient(app, headers={"x-deckhand-token": token})


def test_nothing_has_come_yet(client, feed):
    assert client.get("/camera").json() == {"live": False, "viewers": 0, "at": None}


def test_a_frame_is_kept_and_answers_who_watches(client, feed):
    assert client.post("/camera/frames", content=JPEG).json() == {"viewers": 0}
    state = client.get("/camera").json()
    assert state["live"] and state["at"] > 0
    assert feed.jpeg == JPEG


def test_a_picture_goes_stale(client, feed, monkeypatch):
    client.post("/camera/frames", content=JPEG)
    monkeypatch.setattr(routes.time, "time", lambda: feed.at + routes.LIVE_S + 1)
    assert client.get("/camera").json()["live"] is False


@pytest.mark.parametrize(
    ("body", "code"), [(b"GIF89a", 400), (b"", 400), (routes.SOI + b"x" * routes.MAX_BYTES, 413)]
)
def test_only_a_jpeg_is_a_frame(client, feed, body, code):
    assert client.post("/camera/frames", content=body).status_code == code
    assert feed.seq == 0


def test_every_route_needs_the_token(token, feed):
    anon = TestClient(app)
    assert anon.get("/camera").status_code == 401
    assert anon.post("/camera/frames", content=JPEG).status_code == 401
    assert anon.get("/camera/stream").status_code == 401


def test_a_viewer_gets_the_last_picture_then_each_new_one_and_counts_while_it_watches():
    async def watch():
        feed = routes.Feed()
        feed.put(JPEG)
        stream = routes.parts(feed, gone=_never)
        first = await anext(stream)
        assert first.startswith(b"--frame\r\nContent-Type: image/jpeg\r\n")
        assert first.endswith(JPEG + b"\r\n")
        assert feed.viewers == 1
        waiting = asyncio.ensure_future(anext(stream))
        await asyncio.sleep(0)
        assert not waiting.done()
        feed.put(JPEG + b"2")
        assert (await waiting).endswith(JPEG + b"2\r\n")
        await stream.aclose()
        assert feed.viewers == 0

    asyncio.run(watch())


def test_a_viewer_that_left_while_nothing_came_stops_counting(monkeypatch):
    monkeypatch.setattr(routes, "WAKE_S", 0.01)

    async def watch():
        feed = routes.Feed()

        async def gone():
            return True

        assert [p async for p in routes.parts(feed, gone)] == []
        assert feed.viewers == 0

    asyncio.run(watch())


async def _never() -> bool:
    return False
