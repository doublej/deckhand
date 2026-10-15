"""A tmux row as runs: SGR escapes turned into resolved colours and flags, everything else dropped."""

from __future__ import annotations

from deckhand_daemon.space import styled

ANSI = [f"#0000{n:02x}" for n in range(16)]


def test_the_first_sixteen_go_through_the_profiles_palette():
    assert styled.runs("\x1b[33ma\x1b[104mb", ANSI, False) == [
        {"t": "a", "fg": ANSI[3]},
        {"t": "b", "fg": ANSI[3], "bg": ANSI[12]},
    ]
    assert styled.runs("\x1b[95ma", ANSI, False) == [{"t": "a", "fg": ANSI[13]}]


def test_the_rest_of_the_256_follow_the_xterm_table():
    assert styled.xterm(16, ANSI) == "#000000"
    assert styled.xterm(21, ANSI) == "#0000ff"
    assert styled.xterm(196, ANSI) == "#ff0000"
    assert styled.xterm(231, ANSI) == "#ffffff"
    assert styled.xterm(232, ANSI) == "#080808"
    assert styled.xterm(255, ANSI) == "#eeeeee"
    assert styled.runs("\x1b[38;5;196ma", ANSI, False) == [{"t": "a", "fg": "#ff0000"}]


def test_24_bit_passes_through_in_either_spelling():
    assert styled.runs("\x1b[38;2;1;2;255ma", ANSI, False) == [{"t": "a", "fg": "#0102ff"}]
    assert styled.runs("\x1b[48:2::1:2:255ma", ANSI, False) == [{"t": "a", "bg": "#0102ff"}]


def test_an_underline_colour_is_read_past_not_taken_for_codes():
    assert styled.runs("\x1b[58;5;1;3ma", ANSI, False) == [{"t": "a", "i": True}]


def test_reset_and_default_colours_are_left_out():
    assert styled.runs("\x1b[31ma\x1b[0mb\x1b[32mc\x1b[39md", ANSI, False) == [
        {"t": "a", "fg": ANSI[1]},
        {"t": "b"},
        {"t": "c", "fg": ANSI[2]},
        {"t": "d"},
    ]


def test_bold_in_the_first_eight_is_drawn_bright_when_the_profile_says_so():
    assert styled.runs("\x1b[1;31ma", ANSI, True) == [{"t": "a", "fg": ANSI[9], "b": True}]
    assert styled.runs("\x1b[1;31ma", ANSI, False) == [{"t": "a", "fg": ANSI[1], "b": True}]


def test_flags_set_and_clear():
    found = styled.runs("\x1b[2;3;4;7ma\x1b[22;23;24;27mb", ANSI, False)
    assert found == [{"t": "a", "f": True, "i": True, "u": True, "v": True}, {"t": "b"}]
    assert styled.runs("\x1b[4:3ma\x1b[4:0mb", ANSI, False) == [{"t": "a", "u": True}, {"t": "b"}]


def test_other_escapes_are_dropped_and_wide_text_is_kept_whole():
    row = "\x1b]8;;https://x\x1b\\中文\x1b]8;;\x1b\\x\x1b[?25l"
    assert styled.plain(row) == "中文x"
    assert styled.runs(row, ANSI, False) == [{"t": "中文x"}]


def test_trailing_blanks_go_unless_they_show():
    assert styled.runs("ab  ", ANSI, False) == [{"t": "ab"}]
    assert styled.runs("ab\x1b[44m  ", ANSI, False) == [{"t": "ab"}, {"t": "  ", "bg": ANSI[4]}]
    assert styled.runs("   ", ANSI, False) == []
