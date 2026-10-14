"""A screen row as iTerm draws it: runs of text that share one style, every colour already a hex.

iTerm's API hands a row over as its text, how many code points each cell holds, and one style per
cell, run-length encoded. The headset cannot know iTerm's palette, so a colour leaves here
resolved: 0-15 through the profile's own ANSI colours, 16-255 through the xterm table, 24-bit as
it is. A default colour is left out, and the theme (`theme.py`) says what default looks like.

Two things keep the columns where iTerm has them. A cell nothing was written to comes as NUL or
as no code points at all, and is a space here either way. A double-width character is followed by
a placeholder cell holding nothing, and that one is dropped: the headset's font draws the
character two columns wide itself, and a space after it would push the rest of the row along.
"""

from __future__ import annotations

import unicodedata
from typing import TYPE_CHECKING

if TYPE_CHECKING:  # the daemon loads iterm2 only once the API is approved (`iterm.py`)
    from iterm2 import api_pb2

#: The six levels of each channel in xterm's 6x6x6 colour cube, 16-231.
CUBE = (0, 95, 135, 175, 215, 255)
#: Whatever iTerm puts in a cell that holds no character.
EMPTY = ("", "\x00")


def xterm(index: int, ansi: list[str]) -> str:
    """One of the 256 colours: the profile's own sixteen first, then the cube, then the greys."""
    if index < 16:
        return ansi[index]
    if index < 232:
        n = index - 16
        return _hex(CUBE[n // 36], CUBE[n // 6 % 6], CUBE[n % 6])
    grey = 8 + 10 * (index - 232)
    return _hex(grey, grey, grey)


def colour(
    style: api_pb2.CellStyle, side: str, ansi: list[str], bright: bool = False
) -> str | None:
    """`side` is `fg` or `bg`. None for the default colour, and for iTerm's alternates."""
    if style.HasField(f"{side}Rgb"):
        rgb = getattr(style, f"{side}Rgb")
        return _hex(rgb.red, rgb.green, rgb.blue)
    if style.HasField(f"{side}Standard"):
        index = getattr(style, f"{side}Standard")
        # iTerm's "Brighten bold text": bold in one of the first eight is drawn in its bright twin.
        return xterm(index + 8 if bright and index < 8 else index, ansi)
    return None


def look(style: api_pb2.CellStyle, ansi: list[str], bright_bold: bool) -> dict:
    """The wire's style keys for one cell, each only when it says something."""
    found = {
        "fg": colour(style, "fg", ansi, bright_bold and style.bold),
        "bg": colour(style, "bg", ansi),
        "b": style.bold,
        "f": style.faint,
        "i": style.italic,
        "u": style.underline,
        "v": style.inverse,
    }
    return {key: value for key, value in found.items() if value}


def runs(row: api_pb2.LineContents, ansi: list[str], bright_bold: bool) -> list[dict]:
    """`[{t, fg?, bg?, b?, f?, i?, u?, v?}]`, adjacent cells of one style made one run.

    A trailing stretch of blanks is dropped as `lines` drops it — unless it has a background, an
    underline or is inverted, because then it is something on the screen and not nothing.
    """
    styles = [look(style, ansi, bright_bold) for style in row.style for _ in range(style.repeats)]
    found: list[dict] = []
    before, last = "", None
    for x, text in enumerate(cells(row)):
        if text in EMPTY and _wide(before):
            before = ""
            continue
        before = text
        style = styles[x] if x < len(styles) else {}
        text = text.replace("\x00", " ") or " "
        if found and style == last:
            found[-1]["t"] += text
        else:
            found.append({"t": text, **style})
            last = style
    while found and not {"bg", "u", "v"} & found[-1].keys():
        found[-1]["t"] = found[-1]["t"].rstrip()
        if found[-1]["t"]:
            break
        found.pop()
    return found


def cells(row: api_pb2.LineContents) -> list[str]:
    """The row's text cut into what each cell holds: one code point, several, or none."""
    found, at = [], 0
    for group in row.code_points_per_cell:
        for _ in range(group.repeats):
            found.append(row.text[at : at + group.num_code_points])
            at += group.num_code_points
    return found


def _wide(text: str) -> bool:
    """A cell whose character iTerm draws two columns wide: East Asian wide or full-width, or
    asked for as an emoji. ponytail: Unicode's table, not iTerm's own width setting."""
    return bool(text) and (unicodedata.east_asian_width(text[0]) in ("W", "F") or "\ufe0f" in text)


def _hex(red: int, green: int, blue: int) -> str:
    return f"#{red:02x}{green:02x}{blue:02x}"
