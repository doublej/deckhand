"""`/terminal/theme`: iTerm's font, spacing and colours, from its preferences or a pane's profile."""

from __future__ import annotations

import plistlib
from pathlib import Path
from types import SimpleNamespace

import pytest

from deckhand_daemon import saying
from deckhand_daemon.space import theme

PREFS = Path(__file__).with_name("iterm-prefs.plist")
WIRE = {
    "font",
    "fg",
    "bg",
    "bold",
    "cursor",
    "selection",
    "ansi",
    "lineSpacing",
    "charSpacing",
    "brightBold",
}


def prefs() -> dict:
    return plistlib.loads(PREFS.read_bytes())


@pytest.fixture
def listed(monkeypatch):
    async def live(session_id):
        return SimpleNamespace(pane=SimpleNamespace(iterm_session_id="P1"), name="s")

    monkeypatch.setattr(saying, "live_session", live)
    monkeypatch.setattr(theme, "default_profile", lambda: theme.default_of(prefs()))


def test_the_default_profile_is_the_one_its_guid_names():
    assert theme.default_of(prefs())["Guid"] == "SECOND"
    unnamed = {**prefs(), "Default Bookmark Guid": "GONE"}
    assert theme.default_of(unnamed)["Guid"] == "FIRST"


def test_separate_colours_follow_the_macs_appearance():
    profile = theme.default_of(prefs())
    dark, light = theme.parse(profile, dark=True), theme.parse(profile, dark=False)
    assert dark["fg"] == "#c0caf5"
    assert light["fg"] == "#000000"
    assert dark["ansi"][1] == "#bb0000"
    assert light["ansi"][1] == "#ff0000"
    # A colour kept only once is that colour in either appearance.
    assert dark["bg"] == light["bg"] == "#1a1b26"
    assert dark["ansi"][0] is None
    assert len(dark["ansi"]) == 16


def test_one_set_of_colours_reads_the_plain_keys():
    profile = {**theme.default_of(prefs()), theme.SEPARATE: False}
    assert theme.parse(profile, dark=True)["fg"] == "#808080"


def test_the_font_is_split_from_its_size_and_spacing_is_kept():
    found = theme.parse(theme.default_of(prefs()), dark=False)
    assert found["font"] == {"family": "JetBrainsMonoNF-Regular", "size": 18.0}
    assert found["lineSpacing"] == 1.2
    assert found["charSpacing"] == 1.0
    assert found["brightBold"] is False
    assert theme.parse({}, dark=False)["font"] == {"family": "Monaco", "size": 12.0}


def test_a_component_is_clamped_and_rounded():
    assert theme.hex_of({"Red Component": 1.2, "Green Component": 0.5}) == "#ff8000"
    assert theme.hex_of(None) is None


def test_unapproved_it_is_the_default_profile_and_iterm_is_never_asked(
    client, head, listed, iterm_api
):
    answered = client.get("/terminal/theme?session=any", headers=head).json()
    assert set(answered) == WIRE
    assert answered["font"]["family"] == "JetBrainsMonoNF-Regular"
    assert iterm_api.connects == 0


def test_approved_it_is_the_sessions_own_profile(client, head, listed, iterm_api, approved):
    iterm_api.profile = {"Normal Font": "Hack-Regular 14"}
    answered = client.get("/terminal/theme?session=any", headers=head).json()
    assert answered["font"] == {"family": "Hack-Regular", "size": 14.0}
    plain = client.get("/terminal/theme", headers=head).json()
    assert plain["font"]["family"] == "JetBrainsMonoNF-Regular"
