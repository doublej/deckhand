"""A screen row as runs: colours resolved the way iTerm draws them, columns where iTerm has them."""

from __future__ import annotations

from iterm2 import api_pb2

from deckhand_daemon.space import styled

ANSI = [f"#0000{n:02x}" for n in range(16)]


def row(text: str, widths: list[int], *styles: api_pb2.CellStyle) -> api_pb2.LineContents:
    """`widths` is code points per cell, one entry per cell."""
    return api_pb2.LineContents(
        text=text,
        code_points_per_cell=[
            api_pb2.CodePointsPerCell(num_code_points=w, repeats=1) for w in widths
        ],
        style=styles,
    )


def test_the_first_sixteen_go_through_the_profiles_palette():
    assert styled.colour(api_pb2.CellStyle(fgStandard=3), "fg", ANSI) == ANSI[3]
    assert styled.colour(api_pb2.CellStyle(bgStandard=12), "bg", ANSI) == ANSI[12]


def test_the_rest_of_the_256_follow_the_xterm_table():
    assert styled.xterm(16, ANSI) == "#000000"
    assert styled.xterm(21, ANSI) == "#0000ff"
    assert styled.xterm(196, ANSI) == "#ff0000"
    assert styled.xterm(231, ANSI) == "#ffffff"
    assert styled.xterm(232, ANSI) == "#080808"
    assert styled.xterm(255, ANSI) == "#eeeeee"


def test_24_bit_passes_through():
    rgb = api_pb2.RGBColor(red=1, green=2, blue=255)
    assert styled.colour(api_pb2.CellStyle(fgRgb=rgb), "fg", ANSI) == "#0102ff"


def test_default_and_alternate_colours_are_left_out():
    default = api_pb2.AlternateColor.Value("DEFAULT")
    assert styled.look(api_pb2.CellStyle(), ANSI, True) == {}
    alternate = api_pb2.CellStyle(fgAlternate=default, bgAlternate=default)
    assert styled.look(alternate, ANSI, True) == {}


def test_bold_in_the_first_eight_is_drawn_bright_when_the_profile_says_so():
    bold_red = api_pb2.CellStyle(fgStandard=1, bold=True)
    assert styled.look(bold_red, ANSI, True) == {"fg": ANSI[9], "b": True}
    assert styled.look(bold_red, ANSI, False) == {"fg": ANSI[1], "b": True}


def test_adjacent_cells_of_one_style_are_one_run():
    red = api_pb2.CellStyle(fgStandard=1, repeats=2)
    still_red = api_pb2.CellStyle(fgStandard=1, repeats=1)
    marked = api_pb2.CellStyle(bgStandard=2, italic=True, underline=True, inverse=True, repeats=1)
    found = styled.runs(row("abcd", [1, 1, 1, 1], red, still_red, marked), ANSI, False)
    assert found == [
        {"t": "abc", "fg": ANSI[1]},
        {"t": "d", "bg": ANSI[2], "i": True, "u": True, "v": True},
    ]


def test_a_wide_character_drops_the_placeholder_after_it():
    assert styled.runs(row("中文x", [1, 0, 1, 0, 1]), ANSI, False) == [{"t": "中文x"}]
    assert styled.runs(row("中\x00x", [1, 1, 1]), ANSI, False) == [{"t": "中x"}]


def test_an_unwritten_cell_is_a_space_and_keeps_its_column():
    assert styled.runs(row("a\x00b", [1, 1, 1]), ANSI, False) == [{"t": "a b"}]
    assert styled.runs(row("ab", [1, 0, 1]), ANSI, False) == [{"t": "a b"}]


def test_combining_marks_stay_in_their_cell():
    assert styled.cells(row("ña", [2, 1])) == ["ñ", "a"]


def test_trailing_blanks_go_unless_they_show():
    plain = api_pb2.CellStyle(repeats=4)
    assert styled.runs(row("ab  ", [1] * 4, plain), ANSI, False) == [{"t": "ab"}]
    bar = api_pb2.CellStyle(bgStandard=4, repeats=2)
    found = styled.runs(row("ab  ", [1] * 4, api_pb2.CellStyle(repeats=2), bar), ANSI, False)
    assert found == [{"t": "ab"}, {"t": "  ", "bg": ANSI[4]}]
    assert styled.runs(row("   ", [1] * 3, plain), ANSI, False) == []
