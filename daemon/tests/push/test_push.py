import re
from collections import deque
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon import briefings, push, sessions
from deckhand_daemon.app import app

# Held before the fixture below replaces them, so one test can still reach the real things.
REAL_SHOW = push.show
REAL_END = push.end


@pytest.fixture(autouse=True)
def blank(monkeypatch, tmp_path):
    monkeypatch.setattr(push, "_slips", {})
    monkeypatch.setattr(push, "_open", {})
    monkeypatch.setattr(push, "_said", {})
    monkeypatch.setattr(push, "_alerts", deque(maxlen=50))
    monkeypatch.setattr(push.sending, "_raised", {})
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path))
    monkeypatch.setattr(push, "_last_line", lambda sid: "shall I run the tests?")
    monkeypatch.setattr(briefings, "load", lambda sid: {})
    monkeypatch.setattr(push, "artifacts", Slips({}))
    monkeypatch.setattr(push, "tasks", Asks({}))
    said = []
    monkeypatch.setattr(push, "show", lambda card, mac, loud=True: said.append(card))
    monkeypatch.setattr(push, "end", lambda sid: said.append(("end", sid)))
    return said


class Slips:
    """Stands in for `artifacts`: how many slips each session has waiting, by session id, and
    which of them are confirms — `s0`, `s1`, … oldest first."""

    def __init__(self, waiting, confirms=()):
        self.waiting = waiting
        self.confirms = set(confirms)

    def listing(self, session):
        count = self.waiting.get(session.session_id, 0)
        return [{"id": f"s{n}", "title": f"Ship s{n}?", "answered": False}
                for n in reversed(range(count))]

    def page(self, session, artifact_id):
        if artifact_id not in self.confirms:
            return "<p>a page</p>"
        return '<button id="no">Hold</button><button id="yes" class="primary">Ship it</button>'

    def answered(self, session, artifact_id):
        return {"answer": True}


class Asks:
    """Stands in for `tasks`: how many asks are still open on each session's list."""

    def __init__(self, open_now, done=()):
        self.open_now = open_now
        self.done = list(done)

    def load(self, session_id):
        return ([{"id": f"t{n}", "text": f"ask {n}", "state": "todo"}
                 for n in range(self.open_now.get(session_id, 0))]
                + [{"id": f"d{n}", "text": text, "state": "done"}
                   for n, text in enumerate(self.done)])


def live(*pairs):
    return [
        sessions.Session(session_id=sid, pid=0, name=sid, cwd="/tmp", status=status,
                         updated_at=0.0, tty="", pane=None)
        for sid, status in pairs
    ]


def card(kind=push.ASKING, line="shall I run the tests?", **ask):
    return push.Card(session="one", name="one", kind=kind, line=line, when=0.0, **ask)


def posts(monkeypatch):
    """Every APNs post this Mac makes, as (token, event, payload). The real `show` and `end`."""
    sent = []

    def caught(token, payload, auth, kind):
        sent.append((token, kind, payload))

    monkeypatch.setattr(push.sending, "bearer", lambda: "auth")
    monkeypatch.setattr(push, "show", REAL_SHOW)
    monkeypatch.setattr(push, "end", REAL_END)
    monkeypatch.setattr(push.sending, "_post", caught)
    return sent


# --- what raises a card, and what no longer does -------------------------------------------

def test_a_turn_ending_never_raises_a_card(monkeypatch, blank):
    """The trigger this file was rewritten to delete: it fired 294 times in 28 hours."""
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "busy")))
    push.sweep()
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    push.sweep()
    assert blank == []


def test_a_new_slip_asks(monkeypatch, blank):
    slips = Slips({})
    monkeypatch.setattr(push, "artifacts", slips)
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    assert blank == [], "a slip already sitting there when the daemon started is not news"
    slips.waiting["one"] = 1
    push.sweep()
    assert [c.kind for c in blank] == [push.ASKING]
    assert blank[0].session == "one" and blank[0].name == "one"
    assert blank[0].line == "shall I run the tests?"


def test_answering_the_last_slip_ends_the_card(monkeypatch, blank):
    slips = Slips({"one": 1})
    monkeypatch.setattr(push, "artifacts", slips)
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    slips.waiting["one"] = 0
    push.sweep()
    assert blank == [("end", "one")]


def test_a_confirm_slip_puts_its_question_and_buttons_on_the_card(monkeypatch, blank):
    """A Yes pressed under any sentence but the question answers something nobody read."""
    slips = Slips({}, confirms={"s0"})
    monkeypatch.setattr(push, "artifacts", slips)
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    slips.waiting["one"] = 1
    push.sweep()
    assert blank[0].line == "Ship s0?"
    assert blank[0].state()["slip"] == "s0"
    assert (blank[0].accept, blank[0].decline) == ("Ship it", "Hold")


def test_any_other_slip_carries_no_buttons(monkeypatch, blank):
    slips = Slips({})
    monkeypatch.setattr(push, "artifacts", slips)
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    slips.waiting["one"] = 1
    push.sweep()
    assert "slip" not in blank[0].state()


def test_answering_one_of_two_moves_the_card_on_quietly(monkeypatch, blank):
    shown = []
    monkeypatch.setattr(push, "show", lambda card, mac, loud=True: shown.append((card, loud)))
    slips = Slips({}, confirms={"s0", "s1"})
    monkeypatch.setattr(push, "artifacts", slips)
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    slips.waiting["one"] = 1
    push.sweep()
    slips.waiting["one"] = 2
    push.sweep()
    assert shown[-1][0].slip == "s1" and shown[-1][1]
    # s1, the one on the card, is answered; s0 still waits.
    monkeypatch.setattr(slips, "listing", lambda session: [
        {"id": "s0", "title": "Ship s0?", "answered": False},
        {"id": "s1", "title": "Ship s1?", "answered": True}])
    push.sweep()
    assert shown[-1][0].slip == "s0" and not shown[-1][1]
    push.sweep()
    assert len(shown) == 3, "nothing changed, so nothing is sent"


def test_a_quiet_update_never_raises_a_card(monkeypatch):
    sent = posts(monkeypatch)
    push.remember("start-token", "start")
    assert push.show(card(), "m2", loud=False) is None
    assert sent == []


def test_a_quiet_update_carries_no_alert():
    assert "alert" not in push.sending._update(card(), loud=False)["aps"]


def test_a_session_that_goes_away_has_its_card_ended(monkeypatch, blank):
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    monkeypatch.setattr(sessions, "live_sessions", lambda: live())
    push.sweep()
    assert blank == [("end", "one")]


def test_clearing_the_whole_list_is_the_finished_event(monkeypatch, blank):
    """One ask going done is 12 an hour and is not news. The list going empty is 4, and is."""
    asks = Asks({"one": 3})
    monkeypatch.setattr(push, "tasks", asks)
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    asks.open_now["one"] = 1
    push.sweep()
    assert blank == [], "a single ask being ticked off raises nothing"
    asks.open_now["one"] = 0
    push.sweep()
    assert [c.kind for c in blank] == [push.FINISHED]


def test_a_list_that_was_empty_all_along_is_not_an_event(monkeypatch, blank):
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    push.sweep()
    push.sweep()
    assert blank == []


def test_calling_for_you_says_so_in_the_log(monkeypatch, blank, caplog):
    monkeypatch.setattr(sessions, "live_sessions", lambda: live(("one", "idle")))
    with caplog.at_level("INFO"):
        assert push.called(live(("one", "idle"))[0], "the migration needs a decision") is None
    assert [c.kind for c in blank] == [push.ASKING]
    assert blank[0].line == "the migration needs a decision"
    assert "called for you" in caplog.text, "every other trigger logs; this one never did"


def test_every_card_is_kept_for_the_mac_app_to_read_by_cursor(blank, token):
    """The Mac app has no push token. It reads the same cards off `GET /alerts`, after the id it
    already has, so a folder set quiet is quiet there too without a second switch."""
    one = live(("one", "idle"))[0]
    push.called(one, "the migration needs a decision")
    push.called(one, "and the tests")
    client = TestClient(app)
    client.headers["x-deckhand-token"] = token
    first = client.get("/alerts").json()
    assert [a["line"] for a in first["alerts"]] == ["the migration needs a decision",
                                                    "and the tests"]
    assert (first["alerts"][0]["session"], first["alerts"][0]["kind"]) == ("one", push.ASKING)
    later = client.get(f"/alerts?since={first['alerts'][0]['id']}").json()
    assert [a["line"] for a in later["alerts"]] == ["and the tests"]
    assert later["newest"] == first["newest"] == first["alerts"][-1]["id"]
    assert TestClient(app).get("/alerts").status_code == 401


# --- what may make a noise, and what may raise a card --------------------------------------

def test_only_asking_carries_an_alert():
    asking = push.sending._update(card())["aps"]
    assert asking["alert"] == {"title": "one", "body": "shall I run the tests?",
                               "sound": "default"}
    finished = push.sending._update(card(push.FINISHED))["aps"]
    assert "alert" not in finished, "a cleared list is worth reading, not worth a buzz"
    assert set(finished["content-state"]) == {"kind", "line", "when"}


def test_finished_may_never_raise_a_card(monkeypatch):
    sent = posts(monkeypatch)
    push.remember("start-token", "start")
    assert push.show(card(push.FINISHED), "m2-2") is None
    assert sent == [], "there is no card to update and none may be started"
    assert push.show(card(), "m2-2") is None
    assert [kind for _, kind, _ in sent] == ["start"]


def test_a_second_start_waits_for_the_first_card_to_say_which_it_is(monkeypatch):
    """A card raised by push is unaddressable until the phone hands its token back — measured at
    nine minutes, during which every announce raised one more card."""
    sent = posts(monkeypatch)
    push.remember("start-token", "start")
    assert push.show(card(), "m2-2") is None
    assert push.show(card(), "m2-2") == "still waiting for the card this Mac raised for one"
    assert len(sent) == 1
    push.remember("card-token", "activity", "one")
    assert push.show(card(), "m2-2") is None
    assert [kind for _, kind, _ in sent] == ["start", "update"]


def test_a_start_that_never_went_out_does_not_hold_off_the_next(monkeypatch):
    """Only a start APNs actually took blocks a retry. A refused one parking the session for ten
    minutes would mean no card at all for as long as the network was down."""
    tried = []

    def refused(token, payload, auth, kind):
        tried.append(kind)
        return "APNs unreachable: boom"

    monkeypatch.setattr(push.sending, "bearer", lambda: "auth")
    monkeypatch.setattr(push.sending, "_post", refused)
    push.remember("start-token", "start")
    assert REAL_SHOW(card(), "m2-2") == "APNs unreachable: boom"
    assert REAL_SHOW(card(), "m2-2") == "APNs unreachable: boom"
    assert tried == ["start", "start"]


def test_without_a_key_it_says_so_rather_than_pretending(monkeypatch):
    monkeypatch.setattr(push.sending, "signing_key", lambda: None)
    monkeypatch.setattr(push.sending, "_bearer", None)
    assert REAL_SHOW(card(), "m2-2") == "no push key on this Mac — run `just sync-apns`"


# --- one token per card, and a card that can be ended --------------------------------------

def test_a_token_is_kept_per_session():
    """The phone posts one per live card. One slot kept the last and orphaned the rest."""
    push.remember("token-one", "activity", "one")
    push.remember("token-two", "activity", "two")
    assert push.sending._cards(push.sending.tokens()) == {"one": "token-one", "two": "token-two"}


def test_an_activity_token_with_no_session_is_taken_and_dropped():
    push.remember("stray", "activity")
    assert push.sending._cards(push.sending.tokens()) == {}, "a pre-update app is accepted, never guessed at"


def test_ending_a_card_takes_it_off_the_screen_and_forgets_it(monkeypatch):
    sent = posts(monkeypatch)
    push.remember("card-token", "activity", "one")
    push.spoke_to("one")
    assert [(token, kind) for token, kind, _ in sent] == [("card-token", "end")]
    assert sent[0][2]["aps"]["dismissal-date"] <= sent[0][2]["aps"]["timestamp"]
    assert push.sending._cards(push.sending.tokens()) == {}
    push.spoke_to("one")
    assert len(sent) == 1, "a card that is gone is not ended twice"


# --- the line ------------------------------------------------------------------------------

def test_the_line_falls_back_to_the_briefing_and_is_never_empty(monkeypatch):
    monkeypatch.setattr(push, "_last_line", lambda sid: "")
    monkeypatch.setattr(briefings, "load", lambda sid: {"headline": "Waiting: which migration"})
    assert push._line("one", push.ASKING) == "Waiting: which migration"
    monkeypatch.setattr(briefings, "load", lambda sid: {})
    assert push._line("one", push.ASKING) == push.sending.NOTHING[push.ASKING]
    assert push._line("one", push.FINISHED) == push.sending.NOTHING[push.FINISHED]


def test_an_asking_card_gets_less_room_than_a_finished_one(monkeypatch):
    """The Stop button costs an `asking` card one line of its hero, so it holds ~80 characters
    where a `finished` card holds ~120. Sending 120 to both cuts the sentence on the cards that
    needed a person."""
    monkeypatch.setattr(briefings, "load", lambda sid: {})
    monkeypatch.setattr(push, "_last_line", lambda sid: "word " * 60)
    asking, finished = push._line("one", push.ASKING), push._line("one", push.FINISHED)
    assert len(asking) <= 80 and asking.endswith("…")
    assert 80 < len(finished) <= 120 and finished.endswith("…")


def test_a_line_is_cut_at_a_word_and_not_through_one():
    """`…prepara` reads worse than one sentence short."""
    said = push.shortened("the migration needs a decision before it can go any further " * 3,
                          push.ASKING)
    assert len(said) <= 80
    assert said.endswith("…") and not said.endswith(" …")
    assert said.removesuffix("…").split()[-1] in said.split(), "no half word on the end"
    assert push.shortened("  short   enough  ", push.ASKING) == "short enough"


def test_an_agents_own_words_are_cut_to_the_asking_card(monkeypatch, blank):
    """`called()` is the one line an agent chose itself, so it is worth checking it survives the
    smaller cap rather than arriving as a fragment."""
    long = "The database migration is ready but it will drop the old index, confirm before I run it"
    assert push.called(live(("one", "idle"))[0], long) is None
    assert len(blank[0].line) <= 80
    assert blank[0].line.startswith("The database migration is ready")


# --- the wire, which has no Swift on this side ---------------------------------------------

def test_the_card_is_the_shape_the_swift_type_decodes():
    """`attributes-type`, the field names and the kinds are the whole contract, and there is no
    Swift on the sending side to keep them in step — so read the Swift."""
    swift = (Path(__file__).parents[3] / "Sources/DeckhandKit/LiveActivity.swift").read_text()
    payload = push.sending._start(card(slip="s0", accept="Yes", decline="No", hash="h", notify="n0"), "m2-2")["aps"]
    assert f"public struct {payload['attributes-type']}: ActivityAttributes" in swift
    state = swift.split("struct ContentState")[1].split("public init")[0]
    assert set(re.findall(r"public var (\w+):", state)) == set(payload["content-state"])
    rest = swift.split("public var moment")[1]
    assert set(re.findall(r"public var (\w+):", rest)) == set(payload["attributes"])
    kinds = set(re.findall(r"^\s+case (\w+)$", rest, re.MULTILINE))
    assert {push.ASKING, push.FINISHED} == kinds
