import json

import pytest

from deckhand_daemon import deliver, plugin


@pytest.fixture
def page(tmp_path, monkeypatch):
    """utt's plugins folder, and Deckhand's page freshly installed into it."""
    monkeypatch.setenv("DECKHAND_PLUGIN_DIR", str(tmp_path))
    monkeypatch.setattr(plugin, "_values", dict(plugin.DEFAULTS))
    monkeypatch.setattr(plugin, "_revision", -1)
    monkeypatch.setattr(plugin, "_sequence", None)
    plugin.install()
    return tmp_path


def test_the_manifest_says_who_it_is(page):
    written = json.loads((page / "deckhand.json").read_text())
    # The id has to equal the filename or utt ignores the whole manifest.
    assert written["id"] == "deckhand"
    assert written["sendsAudio"] is True
    # The API is the trespass this replaces: a plugin on the same Mac has no reason to open
    # a socket to a program it can already write a file to.
    assert written["needsApi"] is False
    # Everything dictated on that Mac, asked for by a plugin that would not use it.
    assert written["wantsTranscripts"] is False


def test_every_setting_is_one_utt_can_render(page):
    for setting in json.loads((page / "deckhand.json").read_text())["settings"]:
        assert setting["kind"] in {"bool", "string", "number", "choice"}
        if setting["kind"] == "choice":
            assert setting["value"] in setting["options"]
    assert len(plugin.manifest()["actions"]) <= 8


def test_the_page_is_written_for_the_person_not_for_us(page):
    """utt's own rows never name a key, a file or a process, and a guest matches its host."""
    written = plugin.manifest()
    prose = " ".join(
        [written["blurb"]]
        + [row.get("detail", "") for row in written["settings"] + written["actions"]]
    )
    for jargon in ("json", "socket", "launchd", "daemon", "API", "token", "iTerm"):
        assert jargon not in prose, f"{jargon!r} is our word, not theirs"


def test_a_changed_setting_is_picked_up(page):
    _values(page, 1, {"route": "typed into the terminal", "deliver": False,
                      "attribution": "JJ says:"})
    plugin._poll()
    assert plugin.route() == "keyboard"
    assert plugin.delivers() is False
    assert deliver.PREAMBLE == "JJ says:"


def test_the_same_revision_is_not_read_twice(page):
    _values(page, 1, {"route": "sent as a message"})
    plugin._poll()
    _values(page, 1, {"route": "typed into the terminal"})
    plugin._poll()
    assert plugin.route() == "socket"


def test_a_button_only_fires_when_its_count_moves(page):
    """Acting on the key alone means pressing the same button twice looks like nothing
    happened — and the file that is already there when we start is not a press."""
    pressed: list[str] = []
    plugin._act = pressed.append  # type: ignore[assignment]
    (page / "deckhand.action.json").write_text(json.dumps({"sequence": 4, "key": "openLog"}))
    plugin._poll()
    assert pressed == []
    (page / "deckhand.action.json").write_text(json.dumps({"sequence": 5, "key": "openLog"}))
    plugin._poll()
    plugin._poll()
    assert pressed == ["openLog"]


def test_a_missing_page_is_not_an_error(tmp_path, monkeypatch):
    """utt may not be installed at all, and the daemon's job is to answer a phone."""
    monkeypatch.setenv("DECKHAND_PLUGIN_DIR", str(tmp_path / "nothing" / "here"))
    plugin._poll()
    assert plugin.route() in {"auto", "keyboard", "socket"}


def _values(page, revision: int, values: dict) -> None:
    whole = dict(plugin.DEFAULTS) | values
    (page / "deckhand.values.json").write_text(
        json.dumps({"revision": revision, "values": whole})
    )
