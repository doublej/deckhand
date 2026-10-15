"""The headset's groups and tmux's `@group`: which side moved, and what each side is told."""

from __future__ import annotations

from deckhand_daemon.space import groups, stored


def test_the_side_that_moved_is_carried_and_tmux_wins_a_tie():
    last = {"a": {"d": "g1", "i": "T1"}, "b": {"d": None, "i": None}, "c": {"d": "g1", "i": "T1"}}
    now = {"a": ("g2", "T1"), "b": (None, "T1"), "c": ("g1", "T1"), "new": (None, "T2")}
    assert groups.decide(now, last) == ({"a": "g2"}, {"b": "T1", "new": "T2"})
    assert groups.decide({"a": ("g2", "T9")}, last) == ({}, {"a": "T9"})


def test_a_new_session_carries_whichever_side_has_a_group_and_both_is_agreeing():
    assert groups.decide({"a": ("g1", None)}, {}) == ({"a": "g1"}, {})
    assert groups.decide({"a": (None, "T1")}, {}) == ({}, {"a": "T1"})
    assert groups.decide({"a": ("g1", "T1")}, {}) == ({}, {})
    assert groups.decide({"a": (None, None)}, {}) == ({}, {})


def test_joining_a_tmux_group_stands_beside_who_is_already_there(claude_home):
    stored.place("session:a", {"x": 0, "y": 1, "z": -1, "yaw": 0, "group": "g1"})
    stored.place("session:b", {"x": 1, "y": 1, "z": -1, "yaw": 0})
    after = groups.pull({"a": ("g1", "T1"), "b": (None, "T1")}, {"b": "T1"})
    kept = stored.space()
    assert after == {"b": None}
    assert "session:b" not in kept["poses"]
    assert kept["beside"] == {"b": "a"}


def test_leaving_a_tmux_group_leaves_the_headset_group_where_it_stands(claude_home):
    stored.place("session:a", {"x": 0, "y": 1, "z": -1, "yaw": 0, "group": "g1"})
    assert groups.pull({"a": ("g1", None)}, {"a": None}) == {"a": None}
    assert stored.space()["poses"]["session:a"] == {"x": 0, "y": 1, "z": -1, "yaw": 0}


def test_a_headset_group_is_named_for_its_project_unless_a_member_has_a_name(monkeypatch):
    calls = []
    monkeypatch.setattr(groups, "_set", lambda w, o, v: calls.append((w, o, v)))
    windows = {"a": "@1", "b": "@2", "c": "@3", "x": "@9"}
    projects = {s: {"key": "multi-stack/deckhand", "color": "#00afff"} for s in windows}
    now = {"a": ("g1", None), "b": ("g1", None), "c": (None, "drieluik"), "x": (None, "deckhand")}
    held = {"a": "g1", "b": "g1", "c": None, "x": None}
    groups.push(now, windows, held, {"a": "g1", "b": "g1", "c": None}, {"@2": "#ff0000"}, projects)
    assert calls == [("@3", "@group", None), ("@1", "@group", "deckhand 2"), ("@2", "@group", "deckhand 2")]
    calls.clear()
    now = {"a": ("g1", None), "b": ("g1", "drieluik")}
    groups.push(now, windows, {"a": "g1", "b": "g1"}, {"a": "g1"}, {}, projects)
    assert calls == [("@1", "@group", "drieluik"), ("@1", "@group_color", "#00afff"),
                     ("@2", "@group_color", "#00afff")]


def test_a_window_listing_reads_unset_as_none():
    listing = "@1\tdrieluik\t#ff0000\n@2\t\t\n"
    assert groups.parse(listing) == {"@1": ("drieluik", "#ff0000"), "@2": (None, None)}


def test_a_whole_group_renamed_in_tmux_moves_nothing_in_the_headset(claude_home):
    stored.place("session:a", {"x": 0, "y": 1, "z": -1, "yaw": 0, "group": "g1"})
    stored.place("session:b", {"x": 1, "y": 1, "z": -1, "yaw": 0, "group": "g1"})
    rev = stored.space()["rev"]
    now = {"a": ("g1", "drieluik"), "b": ("g1", "drieluik")}
    assert groups.pull(now, {"a": "drieluik", "b": "drieluik"}) == {}
    assert stored.space()["rev"] == rev


def test_joining_where_the_headset_already_has_you_moves_nothing(claude_home):
    stored.place("session:b", {"x": 1, "y": 1, "z": -1, "yaw": 0, "group": "g1"})
    assert groups.pull({"a": ("g1", "T1"), "b": ("g1", "T1")}, {"b": "T1"}) == {}
    assert "session:b" in stored.space()["poses"]


def test_a_rename_brings_who_had_no_headset_group_beside_it(claude_home):
    stored.place("session:a", {"x": 0, "y": 1, "z": -1, "yaw": 0, "group": "g1"})
    now = {"a": ("g1", "drieluik"), "c": (None, "drieluik")}
    assert groups.pull(now, {"a": "drieluik", "c": "drieluik"}) == {"c": None}
    assert stored.space()["poses"]["session:a"]["group"] == "g1"
    assert stored.space()["beside"] == {"c": "a"}
