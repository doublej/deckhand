import pytest

from deckhand_daemon import push, sessions

# Held before the fixture below replaces it, so one test can still reach the real thing.
REAL_SHOW = push.show


@pytest.fixture(autouse=True)
def blank(monkeypatch, tmp_path):
    monkeypatch.setattr(push, "_seen", {})
    monkeypatch.setattr(push, "_waiting", {})
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path))
    monkeypatch.setattr(push, "_last_line", lambda sid: "shall I run the tests?")
    said = []
    # Cards paired with whether they were sent loudly, because that is the difference between
    # a card that changes on the Lock Screen and one that actually reaches the person.
    monkeypatch.setattr(push, "show", lambda card, mac, loud=False: said.append((card, loud)))
    return said


def live(*pairs):
    return [
        sessions.Session(session_id=sid, pid=0, name=sid, cwd="/tmp", status=status,
                         updated_at=0.0, tty="", pane=None)
        for sid, status in pairs
    ]


def test_a_session_that_stops_is_what_puts_a_card_up(monkeypatch, blank):
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "busy")))
    push.sweep()
    assert blank == [], "a session that is still working is not news"
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    assert [card.waiting for card, _ in blank] == [1]
    assert blank[0][0].name == "one"
    assert blank[0][0].line == "shall I run the tests?"


def test_a_session_already_idle_at_start_up_is_not_an_event(monkeypatch, blank):
    """Otherwise every restart of the daemon lights up the Lock Screen with old news."""
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    push.sweep()
    assert blank == []


def test_two_stopping_are_counted_and_the_newest_is_named(monkeypatch, blank):
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "busy"), ("two", "busy")))
    push.sweep()
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle"), ("two", "busy")))
    push.sweep()
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle"), ("two", "idle")))
    push.sweep()
    assert [card.waiting for card, _ in blank] == [1, 2]
    assert blank[-1][0].name == "two", "the card names the one that just stopped"


def test_answering_a_session_takes_it_off_the_card(monkeypatch, blank):
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "busy")))
    push.sweep()
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    push.spoke_to("one")
    assert blank[-1][0].waiting == 0


def test_a_session_that_goes_away_stops_waiting(monkeypatch, blank):
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "busy")))
    push.sweep()
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    monkeypatch.setattr(sessions, "live_sessions", lambda: live())
    push.sweep()
    assert blank[-1][0].waiting == 0


def test_without_a_key_it_says_so_rather_than_pretending(monkeypatch):
    monkeypatch.setattr(push, "signing_key", lambda: None)
    assert REAL_SHOW(push.Card(1, "one", "", 0.0), "m2-2") == (
        "no push key on this Mac — run `just sync-apns`"
    )


def test_a_session_that_stops_is_worth_being_interrupted_for(monkeypatch, blank):
    """An update carrying no alert is a silent redraw, so a card that only ever redraws never
    reaches anyone. Stopping is loud; the bookkeeping around it is not."""
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "busy")))
    push.sweep()
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    assert blank[-1][1] is True
    push.spoke_to("one")
    assert blank[-1][1] is False, "answering it is not news"
    monkeypatch.setattr(sessions, "live_sessions", lambda: live())
    push.sweep()
    assert blank[-1][1] is False, "a session going away is not news either"


def test_only_a_loud_card_carries_an_alert():
    card = push.Card(1, "one", "shall I run the tests?", 0.0)
    assert "alert" not in push._update(card, False)["aps"]
    alert = push._update(card, True)["aps"]["alert"]
    assert alert == {"title": "one", "body": "shall I run the tests?", "sound": "default"}
    assert "loud" not in card.state(), "the content state is the Swift struct and nothing else"
