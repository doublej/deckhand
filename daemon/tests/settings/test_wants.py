"""What the person has set this Mac to do, and what it means in one folder.

The interesting half is resolution: a global answer, a folder's own answer laid over it per key,
and the difference between "this folder says no" and "this folder has no opinion".
"""

from __future__ import annotations

import json

from deckhand_daemon.settings import wants

SHOP = "/Users/jj/dev/web/shop"


def test_nothing_set_is_everything_on_except_the_expensive_one(claude_home):
    whole = wants.document()
    assert (whole["finished"], whole["slips"], whole["called"], whole["chase"]) == (
        True, True, True, True)
    # Reading every subagent transcript is more work than most sessions can justify, so it is the
    # one thing here that has to be asked for.
    assert whole["subagents"] is False
    assert whole["projects"] == {}
    # The phone draws its model pickers from this rather than from a list of its own.
    assert whole["offers"]["session"] == list(wants.SESSION_MODELS)


def test_a_folder_overrides_one_answer_and_follows_the_rest(claude_home):
    wants.save({"finished": True, "chase": True, "summary_model": "",
                "projects": {SHOP: {"finished": False}}})
    here = wants.resolved(SHOP)
    assert here.finished is False
    # Not restated, so still whatever the Mac says — and it keeps following it when that changes.
    assert here.chase is True
    wants.save({"finished": True, "chase": False, "projects": {SHOP: {"finished": False}}})
    assert wants.resolved(SHOP).chase is False
    assert wants.resolved(SHOP).finished is False
    # A folder nobody has an opinion about is the global answer, whole.
    assert wants.resolved("/Users/jj/dev/somewhere-else").finished is True


def test_a_folder_with_no_opinion_is_not_kept_as_one(claude_home):
    """`null` everywhere is what "follow the Mac" looks like on the wire, and an empty override
    left in the document would be a row on a screen that means nothing."""
    written = wants.save({"projects": {SHOP: {"finished": None, "chase": None}}})
    assert written["projects"] == {}


def test_a_model_this_mac_does_not_offer_is_refused(claude_home):
    """It would become a `--model` flag on a real launch line, or an id the SDK rejects — both
    of them failing a long way from the screen that set it."""
    written = wants.save({"session_model": "gpt-9", "summary_model": "claude-opus-5"})
    assert written["session_model"] == ""
    assert written["summary_model"] == "claude-opus-5"
    # The empty string is an answer: it means "the default", and it survives.
    assert wants.save({"summary_model": ""})["summary_model"] == ""


def test_what_comes_back_is_what_was_stored_not_what_was_sent(claude_home):
    written = wants.save({"finished": False, "nonsense": 1, "projects": {"": {"chase": False}}})
    assert "nonsense" not in written
    assert written["projects"] == {}
    assert json.loads(wants.path().read_text())["finished"] is False


def test_an_unreadable_file_is_the_defaults_rather_than_a_broken_daemon(claude_home):
    wants.path().write_text("{not json")
    assert wants.document()["finished"] is True
    assert wants.resolved(SHOP).chase is True
