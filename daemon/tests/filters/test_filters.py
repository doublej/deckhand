import asyncio

import pytest

from deckhand_daemon import filters
from deckhand_daemon.filters import config, registry, words

run = asyncio.run


@pytest.fixture
def chain(tmp_path, monkeypatch):
    """A data dir and a register of its own: a test must not inherit the real filters."""
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setattr(registry, "_known", {})


def marker(name, *, adds="", note="", stop=False, boom=False, seen=None):
    """A filter that does one visible thing, so the chain's own behaviour is what is measured."""

    def apply(prompt, settings):
        if seen is not None:
            seen.append(name)
        if boom:
            raise RuntimeError("a typo in somebody's replacement list")
        return filters.Verdict(text=prompt.text + adds if adds else None, note=note, stop=stop)

    return registry.register(filters.Filter(name=name, title=name, summary=name, apply=apply))


# Which terminal the words were spoken at. A chain belongs to one, so every test that saves a
# chain and then runs one has to agree on whose chain it is.
TERMINAL = "warm-okapi"


def said(text="hello", terminal=TERMINAL, **rest):
    return filters.Prompt(text=text, session_id="aaaa", session_name=terminal, **rest)


def test_the_chain_runs_in_the_order_it_is_written(chain):
    marker("a", adds="+a")
    marker("b", adds="+b")

    config.save(TERMINAL, [{"filter": "a"}, {"filter": "b"}])
    assert run(filters.run(said("x"))).text == "x+a+b"

    config.save(TERMINAL, [{"filter": "b"}, {"filter": "a"}])
    assert run(filters.run(said("x"))).text == "x+b+a"


def test_a_step_that_is_off_is_stepped_over(chain):
    marker("a", adds="+a")
    marker("b", adds="+b")
    config.save(TERMINAL, [{"filter": "a", "on": False}, {"filter": "b"}])

    assert run(filters.run(said("x"))).text == "x+b"


def test_a_stop_ends_the_chain_and_says_why(chain):
    ran = []
    marker("first", adds="+first", seen=ran)
    marker("gate", note="already logged as #12", stop=True, seen=ran)
    marker("never", adds="+never", seen=ran)
    config.save(TERMINAL, [{"filter": "first"}, {"filter": "gate"}, {"filter": "never"}])

    outcome = run(filters.run(said("x")))

    assert outcome.delivered is False
    assert outcome.stopped_by == "gate"
    assert outcome.reason == "already logged as #12"
    # Whatever the text became, nothing is delivered — and nothing after the gate ever ran.
    assert ran == ["first", "gate"]


def test_a_stop_with_nothing_to_say_still_gets_a_reason(chain):
    """A message that vanishes without a reason is the bug the whole chain exists to avoid."""
    marker("mute", stop=True)
    config.save(TERMINAL, [{"filter": "mute"}])

    assert run(filters.run(said("x"))).reason == "mute stopped it"


def test_a_filter_that_raises_is_survived_and_the_words_go_through(chain):
    marker("boom", boom=True)
    marker("after", adds="+after")
    config.save(TERMINAL, [{"filter": "boom"}, {"filter": "after"}])

    outcome = run(filters.run(said("what I actually said")))

    assert outcome.delivered is True
    assert outcome.text == "what I actually said+after"
    assert "boom failed and was skipped" in outcome.notes


def test_a_filter_that_answers_with_nonsense_is_treated_as_broken(chain):
    registry.register(filters.Filter(name="odd", title="odd", summary="odd", apply=lambda p, s: None))
    config.save(TERMINAL, [{"filter": "odd"}])

    outcome = run(filters.run(said("x")))

    assert outcome.text == "x"
    assert outcome.notes == ["odd failed and was skipped"]


def test_an_async_filter_is_awaited(chain):
    async def slowly(prompt, settings):
        await asyncio.sleep(0)
        return filters.Verdict(text=prompt.text.upper(), note="shouted it")

    registry.register(filters.Filter(name="slow", title="slow", summary="slow", apply=slowly))
    config.save(TERMINAL, [{"filter": "slow"}])

    outcome = run(filters.run(said("quiet")))

    assert outcome.text == "QUIET"
    assert outcome.notes == ["shouted it"]


def test_a_chain_naming_a_filter_this_mac_no_longer_has_is_noted_not_fatal(chain):
    marker("real", adds="+real")
    config.save(TERMINAL, [{"filter": "ghost"}, {"filter": "real"}])

    outcome = run(filters.run(said("x")))

    assert outcome.text == "x+real"
    assert outcome.notes == ["ghost is not a filter on this Mac"]


def test_one_filter_can_appear_twice_with_different_settings(chain):
    registry.register(words.WORDS)
    config.save(TERMINAL, [
        {"filter": "words", "settings": {"pairs": [["deck hand", "deckhand"]]}},
        {"filter": "words", "settings": {"pairs": [["tu y", "TUI"]]}},
    ])

    outcome = run(filters.run(said("the deck hand tu y")))

    assert outcome.text == "the deckhand TUI"
    assert outcome.notes == ['swapped "deck hand" for "deckhand"', 'swapped "tu y" for "TUI"']


# --- whose chain it is ------------------------------------------------------------------------


def test_a_corrupt_chain_loads_as_empty_rather_than_stopping_anyone_speaking(chain):
    config.path().write_text("{this was half written when the Mac went to sleep")

    assert config.load(TERMINAL) == []
    assert run(filters.run(said("x"))).text == "x"


def test_a_chain_is_one_terminals_and_not_anothers(chain):
    """The whole point of the change: the same words go through different steps per terminal."""
    marker("a", adds="+a")
    config.save(TERMINAL, [{"filter": "a"}])

    assert run(filters.run(said("x"))).text == "x+a"
    assert run(filters.run(said("x", terminal="cold-otter"))).text == "x"
    assert config.load("cold-otter") == []


def test_a_prompt_with_no_terminal_behind_it_filters_through_nothing(chain):
    marker("a", adds="+a")
    config.save(TERMINAL, [{"filter": "a"}])

    assert run(filters.run(said("x", terminal=""))).text == "x"


# --- the word filter -------------------------------------------------------------------------


def swapped(text, pairs):
    return words.WORDS.apply(said(text), words.WORDS.settings({"pairs": pairs}))


def test_a_misheard_word_is_swapped_however_it_was_said():
    verdict = swapped("Deck hand, and deck hand again", [["deck hand", "deckhand"]])

    assert verdict.text == "deckhand, and deckhand again"
    assert verdict.note == 'swapped "deck hand" for "deckhand"'
    assert verdict.stop is False


def test_the_replacement_is_written_exactly_as_it_was_configured():
    """Case is ignored coming in and taken as written going out: "tu y" is never "Tui"."""
    assert swapped("tu y and TU Y", [["tu y", "TUI"]]).text == "TUI and TUI"


def test_only_whole_words_are_swapped():
    verdict = swapped("intuition is not tui", [["tui", "TUI"]])

    assert verdict.text == "intuition is not TUI"


def test_a_pair_ending_in_punctuation_does_not_run_into_the_next_word():
    assert swapped("c++ and c++x", [["c++", "C++"]]).text == "C++ and c++x"


def test_a_filter_that_changed_nothing_says_nothing():
    verdict = swapped("nothing to fix here", [["deck hand", "deckhand"]])

    assert verdict.text is None
    assert verdict.note == ""


def test_junk_in_the_pairs_is_ignored_rather_than_raising():
    verdict = swapped("deck hand", [["deck hand"], "oops", ["", "x"], ["deck hand", "deckhand"]])

    assert verdict.text == "deckhand"


def test_the_phone_is_told_what_the_word_filter_takes():
    described = next(f for f in filters.known() if f["name"] == "words")

    assert described["title"] == "Word replacement"
    assert described["fields"][0] == {
        "key": "pairs",
        "label": "Replacements",
        "kind": "pairs",
        "default": (),
        "hint": 'What was heard, and what you meant: "deck hand" becomes "deckhand"',
    }
