"""Where the person is, and the one reading that must never be wrong by accident."""

from __future__ import annotations

from deckhand_daemon import presence


def asked_from(host):
    return type("Request", (), {"client": type("Client", (), {"host": host})()})()


PHONE = asked_from("192.168.1.40")


def test_nanoseconds_are_parsed_as_seconds(monkeypatch):
    """`ioreg` reports an integer of nanoseconds. This Mac is nl_NL, so a locale-aware parse
    would turn 977 seconds into something that is not a number at all."""
    monkeypatch.setattr(presence.subprocess, "run",
                        lambda *a, **k: type("R", (), {"stdout": '"HIDIdleTime" = 977192805916'})())
    assert presence.idle_seconds() == 977.192805916


def test_a_mac_that_will_not_say_reads_as_the_person_being_at_it():
    """The safe answer is the one a caller acts on by keeping its hands off the keyboard."""
    assert presence._where(None, False) == "laptop"


def test_a_touched_mac_is_the_laptop_however_awake_the_phone_is():
    presence.seen(PHONE)
    assert presence._where(3.0, False) == "laptop"


def test_an_idle_mac_is_the_phone_whether_or_not_the_phone_has_spoken(monkeypatch):
    """Two states: an idle Mac and a silent phone is still `phone`, the only other place."""
    monkeypatch.setattr(presence, "_phone_seen", None)
    assert presence._where(presence.IDLE_AFTER + 1, False) == "phone"


def test_a_locked_screen_is_never_the_laptop():
    """Locked means gone, whatever the idle clock says — the clock can be seconds old because
    locking the screen is itself an input event."""
    assert presence._where(1.0, True) == "phone"


def test_a_touched_phone_wins_until_a_key_is_pressed_at_the_mac():
    """Whichever was touched last: the app ten seconds ago beats a Mac idle for thirty, and one
    keypress at the Mac takes it back."""
    assert presence._where(30.0, False, touched=10.0) == "phone"
    assert presence._where(2.0, False, touched=10.0) == "laptop"
    assert presence._where(None, False, touched=1.0) == "laptop"


def test_the_cover_needs_an_untouched_mac_and_a_phone_in_use():
    """An untouched Mac alone is also someone watching a film on it, and a phone picked up for a
    second at the desk is no reason to sign over the screen."""
    away = {"where": "phone", "idle": presence.IDLE_AFTER + 1, "locked": False, "phone": 3.0}
    assert presence.cover(away)["title"]
    assert presence.cover(away | {"phone": presence.PHONE_RECENT + 1}) is None
    assert presence.cover(away | {"phone": None}) is None
    assert presence.cover(away | {"idle": 20.0}) is None
    assert presence.cover(away | {"idle": 20.0, "locked": True})["title"]
    assert presence.cover(away | {"where": "laptop"}) is None


def test_only_the_phone_stamps_the_phone_as_seen(monkeypatch):
    """A session's own `deckhand` command arrives over the loopback, and asking must not raise
    the cover it is asking about."""
    monkeypatch.setattr(presence, "_phone_seen", None)
    presence.seen(asked_from("127.0.0.1"))
    presence.seen(asked_from("::1"))
    assert presence._phone_seen is None
    presence.seen(PHONE)
    assert presence._phone_seen is not None


def test_each_reading_is_taken_once_for_one_answer(monkeypatch):
    """`/health` is polled every four seconds and every `ioreg` is a subprocess walking the whole
    IO registry. `state` used to call `owner` beside its own two readings, so one request spawned
    three or four of them for two facts."""
    runs: list[str] = []
    monkeypatch.setattr(presence, "idle_seconds", lambda: runs.append("idle") or 1.0)
    monkeypatch.setattr(presence, "locked", lambda: bool(runs.append("locked")) and False)
    answer = presence.state()
    assert runs == ["idle", "locked"]
    assert answer["where"] == "laptop" and answer["locked"] is False


def test_presence_is_a_route_and_the_cover_rides_on_health(token, monkeypatch):
    from fastapi.testclient import TestClient

    from deckhand_daemon.app import app

    monkeypatch.setattr(presence, "idle_seconds", lambda: 1.0)
    monkeypatch.setattr(presence, "locked", lambda: False)
    asked = TestClient(app)
    assert asked.get("/presence").status_code == 401
    asked.headers["x-deckhand-token"] = token
    assert asked.get("/presence").json()["where"] == "laptop"
    assert asked.get("/health").json()["cover"] is None


def test_the_app_saying_it_was_touched_makes_it_the_phone(token, monkeypatch):
    from fastapi.testclient import TestClient

    from deckhand_daemon.app import app

    monkeypatch.setattr(presence, "idle_seconds", lambda: 30.0)
    monkeypatch.setattr(presence, "locked", lambda: False)
    monkeypatch.setattr(presence, "_phone_touched", None)
    asked = TestClient(app)
    asked.headers["x-deckhand-token"] = token
    assert asked.get("/presence").json()["where"] == "laptop"
    assert asked.post("/presence/phone").status_code == 204
    assert asked.get("/presence").json()["where"] == "phone"
    assert asked.get("/health").json()["cover"] is None
