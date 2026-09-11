"""Who has the Mac, and the one reading that must never be wrong by accident."""

from __future__ import annotations

import time

from deckhand_daemon import presence


def test_nanoseconds_are_parsed_as_seconds(monkeypatch):
    """`ioreg` reports an integer of nanoseconds. This Mac is nl_NL, so a locale-aware parse
    would turn 977 seconds into something that is not a number at all."""
    monkeypatch.setattr(presence.subprocess, "run",
                        lambda *a, **k: type("R", (), {"stdout": '"HIDIdleTime" = 977192805916'})())
    assert presence.idle_seconds() == 977.192805916


def test_a_mac_that_will_not_say_reads_as_the_person_being_there(monkeypatch):
    """The safe answer is the one a caller acts on by keeping its hands off the keyboard."""
    monkeypatch.setattr(presence, "idle_seconds", lambda: None)
    assert presence.owner() == "person"


def test_a_touched_mac_belongs_to_the_person_however_awake_the_phone_is(monkeypatch):
    monkeypatch.setattr(presence, "idle_seconds", lambda: 3.0)
    monkeypatch.setattr(presence, "locked", lambda: False)
    presence.seen()
    assert presence.owner() == "person"


def test_an_idle_mac_with_a_live_phone_belongs_to_deckhand(monkeypatch):
    monkeypatch.setattr(presence, "idle_seconds", lambda: presence.IDLE_AFTER + 1)
    monkeypatch.setattr(presence, "locked", lambda: False)
    presence.seen()
    assert presence.owner() == "deckhand"


def test_an_idle_mac_and_a_silent_phone_belong_to_nobody(monkeypatch):
    """The third state is the point: nobody to reach is not the same as somebody on a phone."""
    monkeypatch.setattr(presence, "idle_seconds", lambda: presence.IDLE_AFTER + 1)
    monkeypatch.setattr(presence, "locked", lambda: False)
    monkeypatch.setattr(presence, "_phone_seen", time.time() - presence.PHONE_RECENT - 1)
    assert presence.owner() == "nobody"


def test_a_locked_screen_is_never_the_person(monkeypatch):
    """Locked means gone, whatever the idle clock says — the clock can be seconds old because
    locking the screen is itself an input event."""
    monkeypatch.setattr(presence, "idle_seconds", lambda: 1.0)
    monkeypatch.setattr(presence, "locked", lambda: True)
    presence.seen()
    assert presence.owner() == "deckhand"
