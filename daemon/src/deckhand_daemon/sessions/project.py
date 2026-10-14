"""Which project a session is in, and its colour — the statusline's answer, not a second one.

JJ's statusline (`~/.claude/statusline/statusline.sh`, the "Which project this is" block and the
`dir_palette` lines under it) gives every project a colour of its own: the repo root, written
relative to `~` when it is under `~/dev`, through `cksum`, modulo a 16-entry xterm-256 palette.
The headset tints a terminal with it and groups terminals of one project by default, so the same
project must come out the same colour in both places. `tests/sessions/test_project.py` reads the
palettes back out of the script, so an edit there fails here rather than drifting quietly.
"""

from __future__ import annotations

import subprocess
from functools import lru_cache
from pathlib import Path

DIR_PALETTE = (39, 45, 75, 81, 111, 117, 147, 159, 171, 177, 180, 209, 215, 219, 156, 114)
PAR_PALETTE = (81, 87, 117, 123, 153, 159, 183, 195, 207, 213, 224, 223, 229, 225, 194, 157)
LEGACY = Path.home() / "Documents" / "development"
DEV = Path.home() / "dev"
CUBE = (0, 95, 135, 175, 215, 255)
STANDARD = (
    "000000",
    "800000",
    "008000",
    "808000",
    "000080",
    "800080",
    "008080",
    "c0c0c0",
    "808080",
    "ff0000",
    "00ff00",
    "ffff00",
    "0000ff",
    "ff00ff",
    "00ffff",
    "ffffff",
)


@lru_cache(maxsize=512)
def _root(cwd: str) -> str:
    """The repo root, or the folder itself — a subfolder of a project is not another project."""
    out = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        timeout=2,
        check=False,
    )
    return out.stdout.strip() if out.returncode == 0 and out.stdout.strip() else cwd


def key(root: str) -> str:
    """`dev/multi-stack/deckhand` under the dev tree, the bare folder name anywhere else."""
    path = Path(root)
    if path == LEGACY or LEGACY in path.parents:
        path = DEV / path.relative_to(LEGACY)
    if path == DEV or DEV in path.parents:
        return str(path.relative_to(Path.home()))
    return path.name


def cksum(text: str) -> int:
    """POSIX `cksum`'s CRC of `text` — not zlib's CRC-32, which differs in bit order and length."""
    crc = 0
    data = text.encode()
    length = len(data)
    tail = bytearray()
    while length:
        tail.append(length & 0xFF)
        length >>= 8
    for byte in data + bytes(tail):
        crc ^= byte << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) if crc & 0x80000000 else (crc << 1)
            crc &= 0xFFFFFFFF
    return ~crc & 0xFFFFFFFF


def xterm(index: int) -> str:
    """An xterm-256 colour as `#rrggbb`."""
    if index < 16:
        return f"#{STANDARD[index]}"
    if index < 232:
        n = index - 16
        r, g, b = CUBE[n // 36], CUBE[n // 6 % 6], CUBE[n % 6]
        return f"#{r:02x}{g:02x}{b:02x}"
    gray = 8 + 10 * (index - 232)
    return f"#{gray:02x}{gray:02x}{gray:02x}"


def of(cwd: str) -> dict:
    """`{key, color, parent}` for the project `cwd` is in: its name and the statusline's colours."""
    name = key(_root(cwd)) if cwd else ""
    slot = cksum(name) % len(DIR_PALETTE)
    return {"key": name, "color": xterm(DIR_PALETTE[slot]), "parent": xterm(PAR_PALETTE[slot])}
