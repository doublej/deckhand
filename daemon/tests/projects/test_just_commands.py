"""The `just` recipes a project offers, and running one for real — a real `just`, a real
justfile, a real subprocess. Mocking the subprocess layer here would only prove the mock works;
`just` is on every machine this daemon runs on, so there is nothing to gain by pretending."""

import time

import pytest

from deckhand_daemon.projects import commands

JUSTFILE = """\
# say hello
[group('demo')]
hello:
    echo hi

deploy target="prod":
    echo {{target}}

build target:
    echo {{target}}

watch *args:
    echo {{args}}

_hidden:
    echo nope
"""


@pytest.fixture
def project(tmp_path, monkeypatch):
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))
    (tmp_path / "justfile").write_text(JUSTFILE)
    return str(tmp_path)


def test_lists_public_recipes_with_their_doc_group_and_whether_they_need_args(project):
    listing = commands.list_recipes(project)
    assert listing["has_justfile"] is True
    by_name = {r["name"]: r for r in listing["recipes"]}
    assert "_hidden" not in by_name
    assert by_name["hello"] == {"name": "hello", "doc": "say hello", "group": "demo",
                                 "needs_args": False}
    assert by_name["deploy"]["needs_args"] is False  # has a default
    assert by_name["build"]["needs_args"] is True  # no default, one positional
    assert by_name["watch"]["needs_args"] is False  # *args takes zero or more


def test_a_folder_with_no_justfile_offers_nothing(tmp_path, monkeypatch):
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))
    assert commands.list_recipes(str(tmp_path)) == {"has_justfile": False, "recipes": []}


def test_running_a_recipe_is_seen_through_to_its_exit_and_its_output(project):
    commands.run(project, "hello")
    result = _wait_until_done(project, "hello")
    assert result["running"] is False
    assert result["exit_code"] == 0
    assert "hi" in result["log"]


def test_stopping_a_long_running_recipe_ends_it(project):
    _add_recipe(project, "wait:\n    sleep 30\n")
    commands.run(project, "wait")
    time.sleep(0.3)
    assert commands.status(project, "wait")["running"] is True
    assert commands.stop(project, "wait") is True
    result = _wait_until_done(project, "wait")
    assert result["running"] is False


def test_stopping_nothing_says_so(project):
    assert commands.stop(project, "hello") is False


def test_a_recipe_started_twice_replaces_the_first_run(project):
    _add_recipe(project, "wait:\n    sleep 30\n")
    commands.run(project, "wait")
    first_pid = commands.status(project, "wait")["pid"]
    commands.run(project, "wait")
    second_pid = commands.status(project, "wait")["pid"]
    assert first_pid != second_pid
    commands.stop(project, "wait")
    _wait_until_done(project, "wait")


def _add_recipe(project: str, recipe_source: str) -> None:
    with open(project + "/justfile", "a") as handle:
        handle.write("\n" + recipe_source)


def _wait_until_done(path: str, recipe: str, timeout: float = 5.0) -> dict:
    deadline = time.monotonic() + timeout
    result = commands.status(path, recipe)
    while result["running"] and time.monotonic() < deadline:
        time.sleep(0.05)
        result = commands.status(path, recipe)
    return result
