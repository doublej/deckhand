"""The headset's groups and iTerm's tab groups: which side moved, and what the headset is told."""

from __future__ import annotations

from deckhand_daemon.space import stored, tabs


def test_the_side_that_moved_is_carried_and_the_headset_wins_a_tie():
    last = {"a": {"d": "g1", "i": "T1"}, "b": {"d": None, "i": None}, "c": {"d": "g1", "i": "T1"}}
    now = {"a": ("g2", "T1"), "b": (None, "T1"), "c": ("g1", "T1"), "new": (None, "T2")}
    assert tabs.decide(now, last) == ({"a": "g2"}, {"b": "T1", "new": "T2"})
    both = {"a": ("g2", "T9")}
    assert tabs.decide(both, last) == ({"a": "g2"}, {})


def test_a_new_session_carries_whichever_side_has_a_group():
    assert tabs.decide({"a": ("g1", None)}, {}) == ({"a": "g1"}, {})
    assert tabs.decide({"a": (None, "T1")}, {}) == ({}, {"a": "T1"})
    assert tabs.decide({"a": (None, None)}, {}) == ({}, {})


def test_joining_a_tab_group_stands_beside_who_is_already_there(claude_home):
    stored.place("session:a", {"x": 0, "y": 1, "z": -1, "yaw": 0, "group": "g1"})
    stored.place("session:b", {"x": 1, "y": 1, "z": -1, "yaw": 0})
    after = tabs.pull({"a": ("g1", "T1"), "b": (None, "T1")}, {"b": "T1"})
    kept = stored.space()
    assert after == {"b": None}
    assert "session:b" not in kept["poses"]
    assert kept["beside"] == {"b": "a"}


def test_a_new_tab_group_stands_the_rest_beside_the_first(claude_home):
    stored.place("session:a", {"x": 0, "y": 1, "z": -1, "yaw": 0, "group": "old"})
    after = tabs.pull({"a": ("old", "T1"), "b": (None, "T1")}, {"a": "T1", "b": "T1"})
    kept = stored.space()
    assert after == {"a": None, "b": None}
    assert "group" not in kept["poses"]["session:a"]
    assert kept["beside"] == {"b": "a"}


def test_leaving_a_tab_group_leaves_the_headset_group_where_it_stands(claude_home):
    stored.place("session:a", {"x": 0, "y": 1, "z": -1, "yaw": 0, "group": "g1"})
    assert tabs.pull({"a": ("g1", None)}, {"a": None}) == {"a": None}
    assert stored.space()["poses"]["session:a"] == {"x": 0, "y": 1, "z": -1, "yaw": 0}
