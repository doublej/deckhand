"""A screen row as tmux prints it with `capture-pane -e`: runs of text sharing one style, every
colour already a hex.

tmux hands a row over as text with SGR escapes wherever the style changes. The headset cannot
know the terminal's palette, so a colour leaves here resolved: 0-15 through the profile's own ANSI
colours, 16-255 through the xterm table, 24-bit as it is. A default colour is left out, and the
theme (`theme.py`) says what default looks like. Any escape that is not SGR is dropped.

A double-width character comes out of tmux once, with no placeholder after it, which is what the
headset wants: its font draws the character two columns wide itself.
"""

from __future__ import annotations

import re

#: The six levels of each channel in xterm's 6x6x6 colour cube, 16-231.
CUBE = (0, 95, 135, 175, 215, 255)
#: An SGR sequence (its parameters in group 1), or any other escape: OSC, another CSI, or two bytes.
ESCAPE = re.compile(r"\x1b(?:\[([0-9;:]*)m|\][^\x07\x1b]*(?:\x07|\x1b\\)|\[[0-9;:?<=>]*[ -/]*[@-~]|.)")
#: SGR flags: the code that sets one, and the codes that clear it.
FLAGS = {1: "b", 2: "f", 3: "i", 4: "u", 7: "v"}
CLEARS = {22: ("b", "f"), 23: ("i",), 24: ("u",), 27: ("v",)}


def xterm(index: int, ansi: list[str]) -> str:
    """One of the 256 colours: the profile's own sixteen first, then the cube, then the greys."""
    if index < 16:
        return ansi[index]
    if index < 232:
        n = index - 16
        return _hex(CUBE[n // 36], CUBE[n // 6 % 6], CUBE[n % 6])
    grey = 8 + 10 * (index - 232)
    return _hex(grey, grey, grey)


def plain(row: str) -> str:
    """The row's text with every escape taken out."""
    return ESCAPE.sub("", row)


def runs(row: str, ansi: list[str], bright_bold: bool) -> list[dict]:
    """`[{t, fg?, bg?, b?, f?, i?, u?, v?}]`, adjacent text of one style made one run.

    A trailing stretch of blanks is dropped as `lines` drops it — unless it has a background, an
    underline or is inverted, because then it is something on the screen and not nothing.
    """
    state: dict = {}
    found: list[dict] = []
    at = 0
    for match in ESCAPE.finditer(row + "\x1b[m"):  # a closing reset flushes the last stretch
        if match.start() > at:
            style = look(state, ansi, bright_bold)
            if found and {k: v for k, v in found[-1].items() if k != "t"} == style:
                found[-1]["t"] += row[at : match.start()]
            else:
                found.append({"t": row[at : match.start()], **style})
        at = match.end()
        if match.group(1) is not None:
            state = sgr(state, match.group(1))
    while found and not {"bg", "u", "v"} & found[-1].keys():
        found[-1]["t"] = found[-1]["t"].rstrip()
        if found[-1]["t"]:
            break
        found.pop()
    return found


def sgr(state: dict, params: str) -> dict:
    """The style after one SGR sequence. Colours are kept as `("i", index)` or `("rgb", hex)`
    until `look` resolves them."""
    state = dict(state)
    codes = [int(p.split(":")[0] or 0) for p in params.split(";")] if params else [0]
    colons = [p.split(":")[1:] for p in params.split(";")] if params else [[]]
    n = 0
    while n < len(codes):
        code = codes[n]
        if code == 0:
            state = {}
        elif code in FLAGS:
            # `4:0` is underline off in the colon form tmux uses for curly and dotted.
            if code == 4 and colons[n][:1] == ["0"]:
                state.pop("u", None)
            else:
                state[FLAGS[code]] = True
        elif code in CLEARS:
            for key in CLEARS[code]:
                state.pop(key, None)
        elif 30 <= code <= 37 or 90 <= code <= 97:
            state["fg"] = ("i", code - 30 if code < 90 else code - 82)
        elif 40 <= code <= 47 or 100 <= code <= 107:
            state["bg"] = ("i", code - 40 if code < 100 else code - 92)
        elif code in (39, 49):
            state.pop("fg" if code == 39 else "bg", None)
        elif code in (38, 48, 58):
            # Extended colour, `;5;n` or `;2;r;g;b`, or the same joined by colons. 58 is the
            # underline's colour, read only so its numbers are not taken for codes of their own.
            args = colons[n] or [str(c) for c in codes[n + 1 : n + 5]]
            colour, used = _extended(args)
            if colons[n] == []:
                n += used
            if colour is not None and code != 58:
                state["fg" if code == 38 else "bg"] = colour
        n += 1
    return state


def look(state: dict, ansi: list[str], bright_bold: bool) -> dict:
    """The wire's style keys for one stretch, each only when it says something."""
    found = {key: True for key in ("b", "f", "i", "u", "v") if state.get(key)}
    for side in ("fg", "bg"):
        kind, value = state.get(side, (None, None))
        if kind == "i":
            # iTerm's "Brighten bold text": bold in one of the first eight is drawn in its twin.
            bright = side == "fg" and bright_bold and state.get("b") and value < 8
            found[side] = xterm(value + 8 if bright else value, ansi)
        elif kind == "rgb":
            found[side] = value
    return found


def _extended(args: list[str]) -> tuple[tuple | None, int]:
    """The colour `5;n` or `2;[space;]r;g;b` names, and how many parameters that took."""
    numbers = [int(a) for a in args if a.isdigit()]
    if numbers[:1] == [5] and len(numbers) > 1:
        return ("i", numbers[1]), 2
    if numbers[:1] == [2] and len(numbers) > 3:
        return ("rgb", _hex(*numbers[-3:] if len(args) > 4 else numbers[1:4])), 4
    return None, 0


def _hex(red: int, green: int, blue: int) -> str:
    return f"#{red:02x}{green:02x}{blue:02x}"
