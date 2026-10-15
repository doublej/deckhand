"""What the terminal draws a pane with — font, spacing and colours — so the headset can draw it
the same.

`/screen`'s runs carry a colour only where a cell asked for one; this says what the rest look
like. tmux has no palette of its own and runs inside iTerm on this Mac, so this is iTerm's default
profile, out of its preferences — `Default Bookmark Guid` names one entry of `New Bookmarks`.

A profile with `Use Separate Colors for Light and Dark Mode` keeps two sets under ` (Light)` and
` (Dark)` keys, and iTerm draws the one the Mac's appearance picks. Components go to hex as they
are. ponytail: no colour-space conversion, so a P3 or calibrated colour is a shade off; convert
here if the headset is ever compared side by side with the Mac.
"""

from __future__ import annotations

import asyncio
import plistlib
import subprocess
import time

from fastapi import APIRouter

FRESH = 10.0
TIMEOUT = 3.0
SEPARATE = "Use Separate Colors for Light and Dark Mode"
#: iTerm's own default, for a profile that never named a font.
FONT = "Monaco 12"
COLOURS = {
    "fg": "Foreground Color",
    "bg": "Background Color",
    "bold": "Bold Color",
    "cursor": "Cursor Color",
    "selection": "Selection Color",
}
ANSI = [f"Ansi {n} Color" for n in range(16)]

router = APIRouter(tags=["space"])
_kept: tuple[float, dict] | None = None


@router.get("/terminal/theme")
async def terminal_theme() -> dict:
    """`{font: {family, size}, fg, bg, bold, cursor, selection, ansi, lineSpacing, charSpacing,
    brightBold}`. Every pane draws the same, so a `?session=` the headset still sends changes
    nothing."""
    return await asyncio.to_thread(theme)


def theme() -> dict:
    """The default profile's theme, shared for `FRESH` seconds."""
    global _kept
    if _kept and time.time() - _kept[0] < FRESH:
        return _kept[1]
    _kept = (time.time(), parse(default_profile(), dark()))
    return _kept[1]


def parse(profile: dict, dark: bool) -> dict:
    """One profile, as the plist gives it, in the wire's terms."""
    variant = (" (Dark)" if dark else " (Light)") if profile.get(SEPARATE) else ""

    def pick(key: str) -> str | None:
        return hex_of(profile.get(key + variant) or profile.get(key))

    family, _, size = str(profile.get("Normal Font") or FONT).rpartition(" ")
    return {
        "font": {"family": family, "size": float(size)},
        **{name: pick(key) for name, key in COLOURS.items()},
        "ansi": [pick(key) for key in ANSI],
        "lineSpacing": float(profile.get("Vertical Spacing", 1.0)),
        "charSpacing": float(profile.get("Horizontal Spacing", 1.0)),
        # Bold in ANSI 0-7 is drawn bright, and bold default text in `bold`. Read by `/screen`
        # for the first; the headset needs it for the second.
        "brightBold": bool(profile.get("Use Bright Bold", True)),
    }


def hex_of(colour: dict | None) -> str | None:
    """`{Red Component: 0-1, …}` → `#rrggbb`. None for a colour the profile does not have."""
    if not colour:
        return None
    channels = (colour.get(f"{name} Component", 0.0) for name in ("Red", "Green", "Blue"))
    return "#" + "".join(f"{round(min(max(c, 0.0), 1.0) * 255):02x}" for c in channels)


def default_profile() -> dict:
    """The profile a new iTerm window gets, read out of iTerm's preferences."""
    exported = subprocess.run(
        ["defaults", "export", "com.googlecode.iterm2", "-"],
        capture_output=True,
        timeout=TIMEOUT,
        check=True,
    )
    return default_of(plistlib.loads(exported.stdout))


def default_of(prefs: dict) -> dict:
    """`Default Bookmark Guid`'s entry in `New Bookmarks`; the first when that names none."""
    profiles = prefs.get("New Bookmarks") or [{}]
    wanted = prefs.get("Default Bookmark Guid")
    return next((p for p in profiles if p.get("Guid") == wanted), profiles[0])


def dark() -> bool:
    """Whether the Mac is in dark mode. The key is simply absent in light mode."""
    asked = subprocess.run(
        ["defaults", "read", "-g", "AppleInterfaceStyle"],
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
        check=False,
    )
    return asked.stdout.strip() == "Dark"
