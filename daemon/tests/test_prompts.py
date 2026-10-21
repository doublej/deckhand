"""Every prompt the daemon ships loads, and nothing it sends still has a hole in it."""

import pytest

from deckhand_daemon import prompts

SHIPPED = ("briefing", "crafting", "idle-check", "space-given", "space-taken")


@pytest.mark.parametrize("name", SHIPPED)
def test_every_shipped_prompt_loads_with_a_body_and_a_name(name):
    loaded = prompts.load(name)
    assert loaded.settings["name"] == name
    assert loaded.settings["description"].strip()
    assert len(loaded.body) > 200, "a prompt this short is a fence in the wrong place"


def test_the_briefing_carries_the_three_tool_descriptions():
    """They are prompt, so they live in the agent's own file rather than in a decorator."""
    described = prompts.load("briefing").settings["tools"]
    assert set(described) == {"add_task", "set_task_state", "drop_task"}
    assert all(text.strip() for text in described.values())


def test_a_placeholder_left_unfilled_would_be_sent_to_a_live_session():
    """The failure this guards: rename {listed} in the file and the daemon ships the word."""
    filled = prompts.load("idle-check").filled(
        name="quiet-gannet", listed="t1 [todo] ship it")
    assert "t1 [todo] ship it" in filled
    assert "quiet-gannet" in filled
    assert "{" not in filled

    crafted = prompts.load("crafting").filled(
        profile="Be direct.", target="opus-5", cwd="/tmp", name="quiet-gannet")
    assert "{" not in crafted


def test_a_brace_in_the_body_is_text_and_not_a_format_field(tmp_path, monkeypatch):
    """Why `filled` is replacement and not str.format: somebody will paste JSON into a prompt."""
    monkeypatch.setattr(prompts, "FOLDER", tmp_path)
    (tmp_path / "braces.md").write_text(
        '---\nname: braces\n---\n\nReturn {"ok": true} for {who}.\n')
    assert prompts.load("braces").filled(who="JJ") == 'Return {"ok": true} for JJ.'


@pytest.mark.parametrize("written", [
    "no fence at all\n",
    "---\nname: unclosed\n\nthe body runs on forever\n",
])
def test_a_malformed_file_is_loud_rather_than_half_read(tmp_path, monkeypatch, written):
    monkeypatch.setattr(prompts, "FOLDER", tmp_path)
    (tmp_path / "broken.md").write_text(written)
    with pytest.raises(ValueError):
        prompts.load("broken")
