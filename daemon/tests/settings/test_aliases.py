"""The Mac-wide word list: the swap itself, what it refuses to store, and the round trip.

The swap is the half worth holding down. It is the same code the `words` filter runs, so a
regression here breaks two features, and every case below is one somebody would actually hit:
a word inside a longer word, a two-word phrase, a replacement with a backslash in it.
"""

from __future__ import annotations

import json

from deckhand_daemon import transcribe
from deckhand_daemon.settings import aliases


def test_a_phrase_is_swapped_whole_and_nothing_inside_a_word_is(claude_home):
    words, notes = aliases.swap("the deck hand on the deckhandle", [["deck hand", "deckhand"]])
    assert words == "the deckhand on the deckhandle"
    assert notes == ['swapped "deck hand" for "deckhand"']


def test_case_is_ignored_on_the_way_in_and_taken_as_written_on_the_way_out(claude_home):
    words, _ = aliases.swap("Deck Hand and deck hand", [["deck hand", "deckhand"]])
    assert words == "deckhand and deckhand"


def test_a_word_ending_in_punctuation_cannot_match_the_front_of_the_next_one(claude_home):
    """`\\b` would: it is defined against word characters, so "c++" would match "c" in "c+".
    This is why `_whole` uses two lookarounds rather than a word boundary."""
    words, notes = aliases.swap("c++ and c+ plus", [["c++", "C++"]])
    assert words == "C++ and c+ plus"
    assert len(notes) == 1


def test_a_backslash_in_the_replacement_is_not_a_group_reference(claude_home):
    r"""`re.subn` reads `\1` in a replacement *string* as a group. A person typing a Windows path
    into the right-hand box must get the path, not a crash or somebody else's word."""
    words, _ = aliases.swap("open see one", [["see one", r"C:\1"]])
    assert words == r"open C:\1"


def test_an_alias_that_never_fires_says_nothing(claude_home):
    words, notes = aliases.swap("nothing to do here", [["deck hand", "deckhand"]])
    assert (words, notes) == ("nothing to do here", [])


def test_a_row_with_nothing_on_its_left_is_not_an_instruction_to_rewrite_every_gap(claude_home):
    words, notes = aliases.swap("leave this alone", [["", "X"], ["   ", "Y"]])
    assert (words, notes) == ("leave this alone", [])


def test_a_missing_or_broken_file_is_no_aliases_rather_than_an_error(claude_home):
    assert aliases.load() == []
    aliases.path().write_text("{not json")
    assert aliases.load() == []


def test_what_is_stored_is_rows_of_two_with_the_later_answer_winning(claude_home):
    kept = aliases.save([
        ["deck hand", "deckhand"],
        ["you tea tea", "utt"],
        "not a pair",
        ["one side"],
        ["", "nothing to match"],
        ["Deck Hand", "Deckhand"],
    ])
    # One row per word, keyed on the heard side case-folded, and the later answer keeps the
    # earlier one's place rather than moving to the bottom of the list.
    assert kept == [["Deck Hand", "Deckhand"], ["you tea tea", "utt"]]
    assert json.loads(aliases.path().read_text())["aliases"] == kept
    assert aliases.load() == kept


def test_only_the_right_hand_side_goes_into_the_hints(claude_home):
    """A hint is a word to bias the recogniser *towards*. Handing it the misheard half would be
    asking for the mistake."""
    aliases.save([["deck hand", "deckhand"], ["um", ""]])
    assert aliases.spoken() == ["deckhand"]


def test_applied_is_load_and_swap_together(claude_home):
    aliases.save([["deck hand", "deckhand"]])
    assert aliases.applied("ask the deck hand") == ("ask the deckhand", [
        'swapped "deck hand" for "deckhand"'])


def test_the_list_goes_out_and_comes_back(client, token):
    head = {"x-deckhand-token": token}
    assert client.get("/aliases", headers=head).json()["aliases"] == []
    sent = {"aliases": [["deck hand", "deckhand"], ["", "dropped"]]}
    written = client.put("/aliases", json=sent, headers=head).json()
    assert written["aliases"] == [["deck hand", "deckhand"]]
    assert client.get("/aliases", headers=head).json()["aliases"] == written["aliases"]


def test_aliases_need_the_token(client):
    assert client.get("/aliases").status_code == 401
    assert client.put("/aliases", json={"aliases": []}).status_code == 401


def test_an_alias_reaches_the_card_as_prepared_words_and_a_note(client, token, monkeypatch):
    """The whole point of the Mac-wide list, end to end.

    `transcript` stays exactly what utt said, because the phone diffs utt's `raw` against it to
    name which of *utt's* stages changed something — the swap appearing there would put this
    Mac's own word list under utt's name, which is the one thing `Rewrites` exists to avoid.
    What was swapped goes in `notes`, which the card draws as the quiet line under the words,
    and the swapped sentence is `prepared`.
    """
    aliases.save([["deck hand", "deckhand"]])
    monkeypatch.setattr(transcribe, "transcribe",
                        lambda clip, hints: transcribe.Heard(text="ask the deck hand"))
    body = _upload(client, token, "?deliver=false")

    assert body["transcript"] == "ask the deck hand"
    assert body["prepared"] == "ask the deckhand"
    assert body["notes"] == ['swapped "deck hand" for "deckhand"']


def test_an_alias_is_in_the_hints_the_next_clip_is_transcribed_with(client, token, monkeypatch):
    """The other half of the fix: the word it should have been is the best hint there is for not
    mishearing it next time. Only the right-hand side — handing utt the misheard half would be
    asking for the mistake."""
    aliases.save([["deck hand", "deckhand"], ["um", ""]])
    seen: list[str] = []

    def heard(clip, hints):
        seen.extend(hints)
        return transcribe.Heard(text="ship it")

    monkeypatch.setattr(transcribe, "transcribe", heard)
    _upload(client, token, "?deliver=false")

    assert "deckhand" in seen
    assert "deck hand" not in seen


def _upload(client, token, query: str = "") -> dict:
    """One clip for whichever session the fixtures made live, which is the one on the listing."""
    head = {"x-deckhand-token": token}
    session = client.get("/sessions", headers=head).json()["sessions"][0]["session_id"]
    return client.post(f"/sessions/{session}/audio{query}",
                       files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")},
                       headers=head).json()
