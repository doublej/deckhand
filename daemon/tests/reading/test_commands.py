"""The names a session can be handed, read off the Mac the way Claude Code reads them."""

from __future__ import annotations

from pathlib import Path

import pytest

from deckhand_daemon.reading import commands


@pytest.fixture
def mac(tmp_path, monkeypatch) -> Path:
    """A Mac with a `~/.claude` and a project, neither of them populated yet."""
    home = tmp_path / "claude"
    home.mkdir()
    monkeypatch.setenv("DECKHAND_CLAUDE_HOME", str(home))
    (tmp_path / "project").mkdir()
    return tmp_path


def write(path: Path, front: str = "", body: str = "words") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"---\n{front}\n---\n\n{body}\n" if front else body)


def named(found: list[commands.Command]) -> list[str]:
    return [command.name for command in found]


def test_a_command_is_its_filename_and_a_skill_is_its_folder(mac):
    write(mac / "claude/commands/feature.md", "description: Start a feature branch")
    write(mac / "claude/skills/prompt-crafter/SKILL.md", "name: prompt-crafter\ndescription: Prompts")

    found = commands.commands(str(mac / "project"))

    assert named(found) == ["feature", "prompt-crafter"]
    assert [c.kind for c in found] == ["command", "skill"]
    assert found[0].description == "Start a feature branch"


def test_a_nested_command_carries_its_namespace(mac):
    """`commands/git/amend.md` is typed `/git:amend`, so that is the name offered.

    Offering `/amend` would be offering a name that does nothing, which is worse than not
    offering it at all: it fails at the far end, in a terminal nobody is looking at.
    """
    write(mac / "claude/commands/git/amend.md", "description: Amend the last commit")

    assert named(commands.commands(str(mac / "project"))) == ["git:amend"]


def test_the_project_shadows_the_mac_on_the_same_name(mac):
    """Claude Code's own precedence. Both would be a choice that does not exist."""
    write(mac / "claude/commands/deploy.md", "description: The Mac's")
    write(mac / "project/.claude/commands/deploy.md", "description: This project's")

    found = commands.commands(str(mac / "project"))

    assert len(found) == 1
    assert found[0].scope == "project"
    assert found[0].description == "This project's"


def test_commands_come_before_skills_and_each_kind_is_sorted(mac):
    for name in ("zulu", "alpha"):
        write(mac / f"claude/commands/{name}.md", "description: x")
        write(mac / f"claude/skills/{name}-skill/SKILL.md", f"name: {name}-skill\ndescription: x")

    assert named(commands.commands(str(mac / "project"))) == [
        "alpha", "zulu", "alpha-skill", "zulu-skill",
    ]


def test_a_frontmatter_name_wins_over_the_folder(mac):
    """The name Claude Code answers to is the one in the file, where the two differ."""
    write(mac / "claude/skills/some-folder/SKILL.md", "name: actually-this\ndescription: x")

    assert named(commands.commands(str(mac / "project"))) == ["actually-this"]


def test_an_argument_hint_that_is_a_list_reads_as_words(mac):
    """Some commands write it as a list, and a person is shown this string."""
    write(mac / "claude/commands/analyse.md", "argument-hint: ['a feature', 'a product']")

    assert commands.commands(str(mac / "project"))[0].hint == "a feature a product"


def test_a_file_with_no_frontmatter_is_still_a_name(mac):
    """It runs perfectly well. A missing description is a thing to say nothing about, not a
    reason to hide a command the person wrote."""
    write(mac / "claude/commands/plain.md", body="just a prompt, no frontmatter")

    found = commands.commands(str(mac / "project"))

    assert named(found) == ["plain"]
    assert found[0].description == ""


@pytest.mark.parametrize("front", ["description: [unclosed", "- not a mapping", "just a string"])
def test_frontmatter_that_will_not_parse_costs_only_its_description(mac, front):
    """A half-saved file is a name with nothing said about it, never a listing that fails."""
    write(mac / "claude/commands/half.md", front)

    found = commands.commands(str(mac / "project"))

    assert named(found) == ["half"]
    assert found[0].description == ""


def test_a_file_that_could_not_be_typed_as_a_name_is_left_out(mac):
    """A stray file in the folder is not a command, and offering it is offering a dead name."""
    write(mac / "claude/commands/READ ME.md", "description: x")
    write(mac / "claude/commands/fine.md", "description: x")

    assert named(commands.commands(str(mac / "project"))) == ["fine"]


def test_a_mac_with_neither_folder_answers_with_nothing(mac):
    """A new Mac, or a project with no `.claude` — both are ordinary, neither is an error."""
    assert commands.commands(str(mac / "project")) == []


def test_only_the_head_of_a_skill_is_read(mac):
    """A SKILL.md runs to hundreds of lines and ~190 of them are read per request."""
    body = "x" * (commands.PEEK * 4)
    write(mac / "claude/skills/big/SKILL.md", "name: big\ndescription: small", body=body)

    assert commands.commands(str(mac / "project"))[0].description == "small"
