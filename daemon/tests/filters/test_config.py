"""Where a chain is kept: one file, a chain per terminal, and what survives a rename.

The runner's own behaviour is `test_filters.py`. This is the store underneath it, which is where
the per-terminal keying and the one migration live.
"""

import json

import pytest

from deckhand_daemon.filters import config

# A key is `machine/name`. Built through `key` rather than spelled out, so these follow
# whatever machine this Mac calls itself instead of hard-coding one.
TERMINAL = config.key("", "warm-okapi")
OTHER = config.key("", "cold-otter")


@pytest.fixture
def store(tmp_path, monkeypatch):
    """A filters.json of its own: a test must never read or write the real one."""
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))


def test_a_chain_nobody_has_saved_is_empty(store):
    assert config.load(TERMINAL) == []


def test_a_chain_that_is_the_wrong_shape_loads_as_empty(store):
    config.path().write_text(json.dumps({"steps": "words"}))

    assert config.load(TERMINAL) == []


def test_saving_fills_in_what_a_step_left_out(store):
    saved = config.save(TERMINAL, [{"filter": "words"}, {"filter": "", "on": True}])

    assert saved == [{"filter": "words", "on": True, "settings": {}}]
    assert config.load(TERMINAL) == saved


def test_saving_an_empty_chain_is_the_absence_of_one(store):
    config.save(TERMINAL, [{"filter": "words"}])

    assert config.save(TERMINAL, []) == []
    assert json.loads(config.path().read_text()) == {"chains": {}}


def test_two_terminals_keep_their_own_chains_in_the_one_file(store):
    config.save(TERMINAL, [{"filter": "words", "settings": {"pairs": [["a", "b"]]}}])
    config.save(OTHER, [{"filter": "words", "on": False}])

    assert config.load(TERMINAL)[0]["settings"] == {"pairs": [["a", "b"]]}
    assert config.load(OTHER) == [{"filter": "words", "on": False, "settings": {}}]


def test_a_rename_carries_the_chain_the_way_a_star_is_carried(store):
    """Keyed by name, so a rename is the one thing that can lose a chain. It must not."""
    config.save(TERMINAL, [{"filter": "words"}])

    assert config.renamed(TERMINAL, config.key("", "warm-okapi-2")) is True
    assert config.load(config.key("", "warm-okapi-2")) == [{"filter": "words", "on": True, "settings": {}}]
    assert config.load(TERMINAL) == []


def test_a_rename_onto_a_name_that_already_has_a_chain_keeps_the_live_ones(store):
    """`Preferences.renamed` overwrites for the same reason: the live session's is the real one."""
    config.save(TERMINAL, [{"filter": "words", "settings": {"pairs": [["live", "one"]]}}])
    config.save(config.key("", "taken"), [{"filter": "words", "settings": {"pairs": [["old", "one"]]}}])

    config.renamed(TERMINAL, config.key("", "taken"))

    assert config.load(config.key("", "taken"))[0]["settings"] == {"pairs": [["live", "one"]]}


def test_a_rename_with_no_chain_to_carry_changes_nothing(store):
    assert config.renamed(TERMINAL, config.key("", "something-else")) is False
    assert config.renamed(TERMINAL, TERMINAL) is False
    assert not config.path().exists()


def test_the_old_mac_wide_chain_is_not_carried_over_but_is_kept(store):
    """It has no terminal to belong to, and copying it onto every one would be a bill."""
    was = {"steps": [{"filter": "craft", "on": True, "settings": {}}]}
    config.path().write_text(json.dumps(was))

    assert config.load(TERMINAL) == []

    # Nothing is lost: the file is beside the new one, and the log says so.
    assert not config.path().exists()
    assert json.loads(config.path().with_suffix(".global.json").read_text()) == was


def test_the_old_chain_is_only_retired_once(store):
    config.path().write_text(json.dumps({"steps": [{"filter": "words"}]}))
    config.load(TERMINAL)

    # A second load finds no file at all rather than saying the same thing on every prompt.
    assert config.load(TERMINAL) == []
    assert config.save(TERMINAL, [{"filter": "words"}])
    assert json.loads(config.path().read_text())["chains"][TERMINAL]


def test_a_chain_saved_before_the_network_is_filed_under_this_machine(store):
    """Every bare name was written when this Mac was the only one, so that is where it belongs.

    Written back rather than translated on each read: an unprefixed key left in the file is one
    the next save or rename would file a second time under the new shape.
    """
    config.path().write_text(json.dumps({"chains": {"warm-okapi": [{"filter": "words"}]}}))

    assert config.load(TERMINAL) == [{"filter": "words", "on": True, "settings": {}}]
    assert list(json.loads(config.path().read_text())["chains"]) == [TERMINAL]


def test_the_same_name_on_two_machines_is_two_chains(store):
    """The collision this key exists to stop: names come from the folder, so two machines make
    `deckhand` without trying, and one shared chain would filter words on a machine nobody set."""
    config.save(config.key("m2", "deckhand"), [{"filter": "here"}])
    config.save(config.key("ubuntu", "deckhand"), [{"filter": "there"}])

    assert config.load(config.key("m2", "deckhand"))[0]["filter"] == "here"
    assert config.load(config.key("ubuntu", "deckhand"))[0]["filter"] == "there"
