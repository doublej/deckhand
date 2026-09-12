"""A hand's surface, and — mostly — what is not on it.

The refusals are the design: a hand holds what is only on its own disk, the daemon holds
everything that decides. That is enforced by the routes not existing, and a test that only
checked the happy path would not notice the day one of them came back.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon import config
from deckhand_daemon.fleet import hand

# Every route the daemon serves that a hand must not. The first group is judgement — a filter
# chain, standing orders, the switches, the manager — which lives in one place on purpose. The
# second is pane work, and a hand has no pane.
REFUSED = [
    ("GET", "/settings"),
    ("PUT", "/settings"),
    ("GET", "/filters"),
    ("GET", "/briefings"),
    ("GET", "/sessions/abc/summary"),
    ("PUT", "/sessions/abc/orders"),
    ("POST", "/sessions/abc/say"),
    ("POST", "/sessions/abc/audio"),
    ("POST", "/sessions/abc/notify"),
    ("POST", "/sessions/abc/image"),
    ("POST", "/live/token"),
    ("GET", "/manager"),
    ("POST", "/manager/say"),
    ("POST", "/sessions/abc/focus"),
    ("POST", "/sessions/abc/control"),
    ("POST", "/sessions/abc/name"),
    ("GET", "/projects"),
    ("POST", "/projects/session"),
]


@pytest.fixture
def client(claude_home):
    return TestClient(hand.app)


@pytest.mark.parametrize(("method", "path"), REFUSED)
def test_a_hand_does_not_serve_it(client, method, path):
    """404, not 403 — the route is absent rather than declined, so there is nothing to switch on."""
    r = client.request(method, path, headers={config.TOKEN_HEADER: config.token()})
    assert r.status_code == 404, f"{method} {path} answered {r.status_code}"


@pytest.mark.parametrize(("method", "path"), REFUSED)
def test_the_daemon_does_serve_it(claude_home, method, path):
    """The other half, and the half that makes the first one mean anything.

    A list of routes nobody serves would pass the test above for ever and prove nothing — it
    would still pass on the day a route was renamed out from under it. This asserts every entry
    is a power the daemon really has, so REFUSED stays a list of powers *withheld*.

    Asked of the app rather than of its route table on purpose: FastAPI keeps an included router
    as one `_IncludedRouter` node instead of flattening its routes up, so walking `app.routes`
    reports `/settings` and seven others as absent while the app answers them perfectly well.
    A wrong token tells the two apart with no such ambiguity — 401 is a route, 404 is not.
    """
    from deckhand_daemon import app as daemon

    client = TestClient(daemon.app)  # not `with`: no lifespan, so no watchers start
    r = client.request(method, path, headers={config.TOKEN_HEADER: "not the token"})
    assert r.status_code != 404, f"{method} {path} is not a daemon route at all"


def test_health_is_open_and_names_the_machine(client):
    """The daemon polls this to know the hand has finished binding: an ssh forward is up before
    the process behind it is listening, so the first proxied call would otherwise be refused."""
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["name"] == "deckhand-hand"
    assert r.json()["machine"]


def test_everything_else_needs_the_token(client):
    assert client.get("/sessions").status_code == 401


def test_sessions_are_listed_without_any_pane_data(client):
    """`iterm_only=False`: on the Mac that flag hides a session whose pane is missing among panes
    that were found. Here there are no panes anywhere and every session is still reachable."""
    r = client.get("/sessions", headers={config.TOKEN_HEADER: config.token()})
    assert r.status_code == 200
    listed = r.json()["sessions"]
    assert listed, "the fixture's sessions should all be listed"
    assert all(s["machine"] for s in listed), "every session names its machine"


def test_deliver_takes_the_socket_and_is_never_asked_which(client, monkeypatch):
    """The primitive: exact bytes, socket only. A route argument is not refused here — it is
    absent, so an agent cannot ask to arrive as the person and be told no."""
    seen: dict = {}

    def fake(session, text, route="auto"):
        seen.update(text=text, route=route)
        return "socket", None

    monkeypatch.setattr(hand.deliver, "deliver", fake)
    sid = client.get("/sessions", headers={config.TOKEN_HEADER: config.token()}).json()["sessions"][
        0
    ]["session_id"]
    r = client.post(
        f"/sessions/{sid}/deliver",
        json={"text": "the exact words"},
        headers={config.TOKEN_HEADER: config.token()},
    )
    assert r.status_code == 200
    assert r.json() == {"delivered": True, "delivered_by": "socket", "error": None}
    assert seen == {"text": "the exact words", "route": "socket"}


def test_deliver_passes_the_words_through_untouched(client, monkeypatch):
    """No filter chain and no standing orders on this side. The daemon ran both before calling,
    and running either twice is the shape of bug that looks like it works."""
    seen: dict = {}
    monkeypatch.setattr(
        hand.deliver, "deliver", lambda s, t, route="auto": (seen.update(text=t), "socket", None)[1:]
    )
    sid = client.get("/sessions", headers={config.TOKEN_HEADER: config.token()}).json()["sessions"][
        0
    ]["session_id"]
    words = "  leading and trailing space, a /slash, and CAPITALS  "
    client.post(
        f"/sessions/{sid}/deliver",
        json={"text": words},
        headers={config.TOKEN_HEADER: config.token()},
    )
    assert seen["text"] == words


class TestAHandThatHasBeenForgotten:
    """The failure measured on 2026-09-12, and the only thing that can answer it.

    A hand started at 18:44 was still holding port 4181 seventeen hours later. Its stdin was a
    pipe from an `sshd: jurrejan@notty` with no client left — the Mac's ssh had gone without
    closing the connection, and sshd held the session open, so `_die_with_the_link` never saw
    the EOF it waits for. Every hand started after that failed to bind and exited, while
    `/health` went on answering from the stale one: the link read up and the listing was a day
    old, with nothing anywhere saying so.
    """

    def test_anything_at_all_counts_as_hearing_from_the_daemon(self, monkeypatch):
        """`/health` included, which is the one the keepalive actually sends."""
        monkeypatch.setattr(hand, "_heard", 0.0)
        client = TestClient(hand.app)

        client.get("/health")

        assert hand._heard > 0.0

    def test_a_refused_call_counts_too(self, monkeypatch):
        """A wrong token is still the daemon talking — and a hand that exited over one would
        take the port with it every time the two disagreed."""
        monkeypatch.setattr(hand, "_heard", 0.0)
        client = TestClient(hand.app)

        assert client.get("/sessions", headers={"x-deckhand-token": "wrong"}).status_code == 401
        assert hand._heard > 0.0

    def test_the_silence_it_waits_for_is_longer_than_the_daemons_heartbeat(self):
        """The two numbers are a pair: a hand must only ever reach this when the daemon has
        really gone, never because one keepalive was late."""
        from deckhand_daemon.fleet import merge

        assert hand.FORGOTTEN_AFTER > merge.KEEP_WARM * 2
