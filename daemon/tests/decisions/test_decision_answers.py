"""A decision's answer: every refusal in the contract's order, the write, and what is typed."""

import json
import time

import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from decision_kit import AID, SID, answering, page_html, proof_for
from fastapi.testclient import TestClient

from deckhand_daemon import artifacts, config
from deckhand_daemon.app import app
from deckhand_daemon.decisions import delivery


def code_of(answered):
    return answered.json()["detail"]["code"]


def test_a_signed_answer_is_written_verified_and_typed_as_the_person(phone, key, decision, typed):
    token, device = phone
    answered = answering(token, proof_for(key, decision))

    assert answered.status_code == 200, answered.text
    body = answered.json()
    assert body["delivered"] is True and body["delivered_by"] == "keyboard"
    kept = json.loads(decision.with_name(f"{AID}.answer.json").read_text())
    assert kept["value"] == {"answer": True} and kept["verified"] is True
    assert kept["device"] == "JJ's iPhone" and kept["fingerprint"] == device["fingerprint"]
    assert kept["delivered"] is True and kept["session"] == SID
    # The keyboard, as the person, into the asker — whatever the Settings route says.
    line = 'Decision ship-it — "Ship it?": Ship. This covers exactly: push the tag, nothing else.'
    assert typed == [(SID, line, "keyboard", True)]


@pytest.mark.parametrize("value,said", [
    ({"answer": False}, "Hold"),
    ({"reply": "only after lunch"}, 'Reply: "only after lunch"'),
    ({"answer": True, "feedbackText": "and tell Ana"}, 'Ship Note: "and tell Ana"'),
])
def test_the_line_says_the_answer_in_the_words_the_person_saw(phone, key, decision, typed,
                                                             value, said):
    answering(phone[0], proof_for(key, decision, value=value))
    assert f'"Ship it?": {said}. This covers exactly' in typed[0][1]


def test_a_pick_or_text_says_the_value_itself():
    metas = {"decision": "pick", "choices": ["develop", "main"], "action": "merge"}
    assert delivery.line("which", "Which branch?", metas, {"answer": "main"}) == (
        'Decision which — "Which branch?": main. This covers exactly: merge.')


def test_the_listing_says_who_answered_and_that_it_holds(phone, key, decision, typed, session):
    answering(phone[0], proof_for(key, decision))
    row = artifacts.listing(session)[0]
    assert row["decision"] == "confirm" and row["choices"] == ["Ship", "Hold"]
    assert row["action"] == "push the tag, nothing else" and row["hash"]
    assert row["verified"] is True and row["answered_by"] == "JJ's iPhone"
    assert row["expired"] is False and row["answered"] is True


def test_a_hand_written_answer_claiming_to_be_verified_does_not_hold(phone, decision, session):
    """The file is in the session's folder; what it cannot hold is a signature."""
    decision.with_name(f"{AID}.answer.json").write_text(json.dumps({
        "value": {"answer": True}, "verified": True, "device": "JJ's iPhone",
        "fingerprint": phone[1]["fingerprint"], "hash": "x", "proof": {}}))
    row = artifacts.listing(session)[0]
    assert row["verified"] is False and row["answered_by"] is None


def test_a_non_decision_row_carries_every_field_as_null(session, project):
    spot = project / ".deckhand" / "artifacts"
    spot.mkdir(parents=True)
    (spot / "notes.html").write_text("<title>Notes</title>")
    row = artifacts.listing(session)[0]
    assert all(row[key] is None for key in
               ("decision", "choices", "action", "expires", "hash", "verified", "answered_by",
                "expired"))


# --- the refusals, in order ----------------------------------------------------------------

def test_no_proof_is_unsigned_even_with_a_value(phone, decision, typed):
    """Page JS can no longer answer a decision: `respond` sends a value and no proof."""
    refused = answering(phone[0], body={"value": {"answer": True}})
    assert refused.status_code == 403 and code_of(refused) == "UNSIGNED"
    assert not decision.with_name(f"{AID}.answer.json").exists() and typed == []


def test_this_macs_token_has_no_key(key, decision, claude_home):
    refused = answering(config.token(), proof_for(key, decision))
    assert refused.status_code == 403 and code_of(refused) == "NO_KEY"


def test_a_signature_by_another_key_is_bad(phone, decision):
    refused = answering(phone[0], proof_for(ec.generate_private_key(ec.SECP256R1()), decision))
    assert refused.status_code == 403 and code_of(refused) == "BAD_SIGNATURE"


def test_a_proof_for_another_slip_is_a_400(phone, key, decision):
    assert answering(phone[0], proof_for(key, decision, artifact="other")).status_code == 400
    assert answering(phone[0], proof_for(key, decision, session="other")).status_code == 400


def test_an_old_proof_is_refused(phone, key, decision):
    refused = answering(phone[0], proof_for(key, decision, at=int(time.time()) - 600))
    assert refused.status_code == 403 and code_of(refused) == "OLD_PROOF"


def test_a_page_that_is_gone_is_a_404(phone, key, decision):
    proof = proof_for(key, decision)
    decision.unlink()
    assert answering(phone[0], proof).status_code == 404


def test_a_card_drawn_off_the_old_page_is_stale(phone, key, decision, typed):
    """A rewrite under the same slug is a new question; an old card's Yes must not answer it."""
    proof = proof_for(key, decision)
    decision.write_text(page_html(action="push the tag and delete the branch"))
    refused = answering(phone[0], proof)
    assert refused.status_code == 409 and code_of(refused) == "STALE"
    assert refused.json()["detail"]["hash"] == artifacts.pages.hashed(decision)
    assert typed == []


def test_a_lapsed_decision_is_gone(phone, key, decision):
    decision.write_text(page_html(expires=time.time() - 1))
    refused = answering(phone[0], proof_for(key, decision))
    assert refused.status_code == 410 and code_of(refused) == "EXPIRED"


def test_the_first_answer_wins_and_the_second_is_told_it(phone, key, decision, typed):
    answering(phone[0], proof_for(key, decision))
    second = answering(phone[0], proof_for(key, decision, value={"answer": False}))
    assert second.status_code == 409 and code_of(second) == "ANSWERED"
    assert second.json()["detail"]["answer"]["value"] == {"answer": True}
    assert len(typed) == 1


def test_any_other_page_answers_exactly_as_before(project, session, typed):
    spot = project / ".deckhand" / "artifacts" / SID
    spot.mkdir(parents=True)
    (spot / "form.html").write_text("<title>A form</title>")
    answered = TestClient(app).post(f"/sessions/{SID}/artifacts/form/answer?route=socket",
                                    json={"value": {"q": 1}},
                                    headers={config.TOKEN_HEADER: config.token()})
    assert answered.status_code == 200
    assert answered.json()["answer"]["verified"] is False
    assert typed[0][2:] == ("socket", False)
