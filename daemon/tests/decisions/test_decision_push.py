"""After the answer: who it is typed into, when it waits, and the one notification a decision gets."""

import dataclasses
import json
import time
from collections import deque

import pytest
from decision_kit import AID, SID, answering, page_html, proof_for

from deckhand_daemon import artifacts, push, saying
from deckhand_daemon.decisions import announcing, delivery
from deckhand_daemon.sessions import panes

PROMPT = "Bash command\n\n  rm -rf build\n\nDo you want to proceed?\n❯ 1. Yes\n  2. No\n"


@pytest.fixture
def alerts(monkeypatch):
    """Every decision alert: (payload, collapse id). Nothing reaches APNs."""
    sent = []
    monkeypatch.setattr(announcing.sending, "alert",
                        lambda payload, collapse="": sent.append((payload, collapse)))
    monkeypatch.setattr(announcing, "_failed", set())
    return sent


@pytest.fixture
def cards(monkeypatch):
    """Every Lock Screen card: (card, loud). Nothing reaches APNs."""
    shown = []
    monkeypatch.setattr(push, "show", lambda card, mac, loud=True: shown.append((card, loud)))
    monkeypatch.setattr(push, "end", lambda sid: shown.append(("end", sid)))
    monkeypatch.setattr(push, "_slips", {})
    monkeypatch.setattr(push, "_said", {})
    monkeypatch.setattr(push, "_alerts", deque(maxlen=50))
    return shown


def kept(decision):
    return json.loads(decision.with_name(f"{AID}.answer.json").read_text())


# --- delivery ------------------------------------------------------------------------------

def test_a_cleared_asker_is_gone_and_nothing_is_typed(phone, key, decision, typed, session,
                                                      monkeypatch):
    """`found_session` follows a `/clear` to the conversation now in that pane. An approval does
    not: that conversation never asked."""
    successor = dataclasses.replace(session, session_id="new-conversation")
    monkeypatch.setattr(saying, "found_session", lambda sid: successor)
    answered = answering(phone[0], proof_for(key, decision)).json()

    assert answered["delivered"] is False and answered["delivery_error"] == delivery.GONE
    assert typed == [] and kept(decision)["delivered"] is False
    assert kept(decision)["verified"] is True  # the answer is still the record


def test_a_pane_at_a_permission_prompt_is_not_typed_into(phone, key, decision, typed, monkeypatch):
    monkeypatch.setattr(panes, "screen", lambda pane_id: PROMPT)
    answered = answering(phone[0], proof_for(key, decision)).json()

    assert answered["delivered"] is False and answered["delivery_error"] == delivery.BLOCKED
    assert typed == []


def test_the_sweep_types_it_once_the_prompt_is_gone(phone, key, decision, typed, session,
                                                    monkeypatch, alerts):
    monkeypatch.setattr(panes, "screen", lambda pane_id: PROMPT)
    answering(phone[0], proof_for(key, decision))
    announcing.swept(session, artifacts.listing(session))
    assert typed == []

    monkeypatch.setattr(panes, "screen", lambda pane_id: "")
    announcing.swept(session, artifacts.listing(session))
    announcing.swept(session, artifacts.listing(session))

    assert len(typed) == 1 and typed[0][2:] == ("keyboard", True)
    assert kept(decision)["delivered"] is True


def test_a_lapsed_answer_is_not_retried(phone, key, decision, typed, session, monkeypatch, alerts):
    monkeypatch.setattr(panes, "screen", lambda pane_id: PROMPT)
    answering(phone[0], proof_for(key, decision))
    monkeypatch.setattr(panes, "screen", lambda pane_id: "")
    row = artifacts.listing(session)[0] | {"expires": time.time() - 1}
    announcing.swept(session, [row])
    assert typed == []


# --- the one notification ------------------------------------------------------------------

def test_a_waiting_decision_gets_one_alert_carrying_the_decision(decision, session, alerts):
    listed = artifacts.listing(session)
    announcing.swept(session, listed)
    announcing.swept(session, listed)

    assert len(alerts) == 1
    payload, collapse = alerts[0]
    assert payload["aps"]["alert"] == {"title": "warm-okapi", "body": "Ship it?"}
    assert payload["aps"]["category"] == "DECISION_CONFIRM"
    assert payload["aps"]["thread-id"] == SID
    assert payload["session"] == SID
    assert payload["link"] == f"deckhand://sessions/{SID}/slips/{AID}"
    assert payload["decision"] == {"session": SID, "artifact": AID, "hash": listed[0]["hash"],
                                   "kind": "confirm", "choices": ["Ship", "Hold"],
                                   "question": "Ship it?"}
    assert collapse == f"{SID}:{AID}"


def test_a_restart_announces_what_was_never_announced_and_nothing_twice(decision, session,
                                                                         alerts, monkeypatch):
    """The announced triples are a file, so a fresh process reads them back."""
    announcing.swept(session, artifacts.listing(session))
    monkeypatch.setattr(announcing, "_failed", set())  # a new process
    announcing.swept(session, artifacts.listing(session))
    assert len(alerts) == 1
    assert announcing.announced() == [f"{SID}:{AID}:{artifacts.listing(session)[0]['hash']}"]

    decision.write_text(page_html(action="a different action"))  # a new question
    announcing.swept(session, artifacts.listing(session))
    assert len(alerts) == 2


def test_an_alert_that_failed_is_tried_again_and_logged_once(decision, session, monkeypatch,
                                                             caplog):
    tried = []
    monkeypatch.setattr(announcing.sending, "alert",
                        lambda payload, collapse="": tried.append(1) or "no device token")
    monkeypatch.setattr(announcing, "_failed", set())
    for _ in range(3):
        announcing.swept(session, artifacts.listing(session))
    assert len(tried) == 3 and announcing.announced() == []
    assert sum("no device token" in r.message for r in caplog.records) == 1


def test_a_long_collapse_id_is_hashed_to_fit_apns():
    assert len(announcing.collapse_id(SID, "x" * 64)) == 64
    assert announcing.collapse_id(SID, "short") == f"{SID}:short"


def test_the_live_activity_moves_silently_with_the_hash(decision, session, cards):
    push._slips[SID] = set()  # not the first sweep
    push._slipped(session, artifacts.listing(session))

    card, loud = cards[0]
    assert loud is False and not push._alerts  # nothing for the Mac's /alerts either
    state = card.state()
    assert state["line"] == "Ship it?" and state["slip"] == AID
    assert (state["accept"], state["decline"]) == ("Ship", "Hold")
    assert state["hash"] == artifacts.listing(session)[0]["hash"]


def test_calling_for_attention_folds_into_an_open_decision(decision, session, cards):
    assert push.called(session, "the build is done") is None
    assert cards[0][1] is False and not push._alerts


def test_calling_for_attention_with_nothing_open_still_rings(session, cards):
    assert push.called(session, "the build is done") is None
    assert cards[0][1] is True and len(push._alerts) == 1


def test_a_lapsed_decision_leaves_the_card_and_waits_on_nobody(decision, session, cards):
    push._slips[SID] = {AID}
    decision.write_text(page_html(expires=time.time() - 1))
    listed = artifacts.listing(session)
    push._slipped(session, listed)

    assert listed[0]["expired"] is True
    assert cards == [("end", SID)]
    assert artifacts.counted(session)["artifacts_waiting"] == 0
