import asyncio

import pytest

from deckhand_daemon import filters
from deckhand_daemon.filters import crafting

run = asyncio.run


def spoken(text):
    return filters.Prompt(
        text=text, session_id="s1", session_name="deckhand", cwd="/Users/jj/dev", route="socket",
        source="spoken",
    )


@pytest.fixture
def skill(tmp_path, monkeypatch):
    """A skill file that exists, because its absence is a separate case below."""
    page = tmp_path / "SKILL.md"
    page.write_text("# Prompt Crafter\n")
    monkeypatch.setattr(crafting, "SKILL", page)
    return page


@pytest.fixture
def never_runs(monkeypatch):
    """Proof that a skipped craft costs nothing: the model is not merely unused, it is unreachable."""
    async def explode(prompt, target):
        raise AssertionError("the model was called for words that should have been left alone")

    monkeypatch.setattr(crafting, "_run", explode)


def answers(monkeypatch, text=None, trouble=None):
    async def fake(prompt, target):
        return text, trouble

    monkeypatch.setattr(crafting, "_run", fake)


def test_a_short_line_is_sent_as_it_was_said(skill, never_runs):
    """"yes" and "carry on" are the commonest things said to a session and the worst candidates
    for rewriting — there is no structure to add and a model run would be pure cost."""
    verdict = run(crafting._craft(spoken("carry on"), {}))
    assert verdict.text is None
    assert verdict.note == ""


def test_the_floor_is_a_setting_and_a_long_line_goes_through(skill, monkeypatch):
    answers(monkeypatch, text="Investigate why the build fails, then fix it.")
    verdict = run(crafting._craft(spoken("why is the build broken fix it"), {"floor": 3}))
    assert verdict.text == "Investigate why the build fails, then fix it."
    assert verdict.note == "rewritten as a prompt"


def test_a_nonsense_floor_falls_back_rather_than_raising(skill, never_runs):
    """A settings file is a person's typing. A bad number must not stop them speaking."""
    assert run(crafting._craft(spoken("carry on"), {"floor": "twelve"})).text is None


def test_a_skill_that_is_not_installed_says_so_and_changes_nothing(tmp_path, monkeypatch):
    monkeypatch.setattr(crafting, "SKILL", tmp_path / "nowhere" / "SKILL.md")
    verdict = run(crafting._craft(spoken(" ".join(["word"] * 20)), {}))
    assert verdict.text is None
    assert "not installed" in verdict.note


def test_the_words_survive_every_way_the_model_can_fail(skill, monkeypatch):
    """The one promise this filter makes. A filter that can eat what somebody said is worse than
    no filter, so every failure returns None — which the runner reads as "unchanged"."""
    said = " ".join(["word"] * 20)
    for trouble in ["the model did not answer within 60s", "claude-agent-sdk is not installed"]:
        answers(monkeypatch, trouble=trouble)
        verdict = run(crafting._craft(spoken(said), {}))
        assert verdict.text is None
        assert trouble in verdict.note


def test_a_model_that_changed_nothing_is_not_reported_as_a_change(skill, monkeypatch):
    """The skill is told to hand back words that are already a clear prompt exactly as they are,
    so this is the ordinary case and not a failure. No note, because nothing happened."""
    said = "Read the transcript reader and explain how it finds a session's JSONL file."
    answers(monkeypatch, text=said)
    verdict = run(crafting._craft(spoken(said), {}))
    assert verdict.text is None
    assert verdict.note == ""


def test_an_empty_answer_is_not_mistaken_for_an_empty_prompt(skill, monkeypatch):
    answers(monkeypatch, text=None)
    assert run(crafting._craft(spoken(" ".join(["word"] * 20)), {})).text is None


def test_the_filter_describes_itself_to_the_phone_without_being_run():
    """The phone draws this page from the Mac's description, so the description is the contract."""
    craft = next(f for f in filters.known() if f["name"] == "craft")
    assert craft["title"] == "Prompt crafting"
    kinds = {field["key"]: field["kind"] for field in craft["fields"]}
    assert kinds == {"target": "text", "floor": "number"}
