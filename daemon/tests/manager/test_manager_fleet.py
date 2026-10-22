"""The manager and the rest of the network.

It managed one Mac and said so — asked for a session on Ubuntu it answered that no such machine
existed, which was true of its tools and never true of the network. These are the four things
that had to become true for that answer to stop being possible.
"""

from __future__ import annotations

import asyncio

import pytest

from deckhand_daemon.fleet import merge
from deckhand_daemon.manager import opening, tools
from deckhand_daemon.projects import sources

UBUNTU = {
    "session_id": "dddd1111-2222-3333-4444-555566667777",
    "pid": 3131,
    "name": "far-otter",
    "cwd": "/home/jurrejan/development/lowlands-watch",
    "status": "idle",
    "updated_at": 0.0,
    "tty": "",
    "machine": "ubuntu",
}
MACHINES = [
    {"id": "m2", "label": "M2 Pro", "os": "darwin", "reachable": True, "primary": True},
    {"id": "ubuntu", "label": "Ubuntu", "os": "linux", "reachable": True, "primary": False},
]


@pytest.fixture
def network(monkeypatch):
    """This Mac is `m2`, Ubuntu is up, and it is running one session."""
    monkeypatch.setattr(tools.registry, "here", lambda: "m2")
    monkeypatch.setattr(opening.registry, "here", lambda: "m2")
    monkeypatch.setattr(merge, "_owner", {}, raising=False)
    monkeypatch.setattr(merge, "_rows", {}, raising=False)

    async def machines():
        return MACHINES

    async def listings(local):
        merge.remembered("ubuntu", [UBUNTU])
        return list(local) + [UBUNTU]

    monkeypatch.setattr(merge, "machines", machines)
    monkeypatch.setattr(merge, "listings", listings)


def project(name: str, path: str, machine: str) -> sources.Project:
    return sources.Project(name=name, path=path, relative=path, machine=machine)


def catalogued(monkeypatch, *found):
    monkeypatch.setattr(sources, "catalog", lambda: (list(found), "test"))


def test_the_first_look_names_every_machine(claude_home, network):
    """The failure this whole change is about: a manager that never learns Ubuntu is a machine
    answers that Ubuntu is not one."""
    answer = asyncio.run(tools.listing())["content"][0]["text"]
    assert "ubuntu (Ubuntu)" in answer and "m2 (M2 Pro)" in answer
    assert "far-otter" in answer and "on ubuntu" in answer


def test_a_session_on_another_machine_answers_to_its_name(claude_home, network):
    asyncio.run(tools.listing())
    found = tools.find("far-otter")
    assert found is not None and found.machine == "ubuntu"
    assert found.pane is None  # there is no iTerm over there, so it cannot be typed into


def test_starting_a_remote_folder_goes_to_the_machine_that_has_it(claude_home, network,
                                                                  monkeypatch):
    catalogued(monkeypatch, project("lowlands-watch",
                                    "/home/jurrejan/development/lowlands-watch", "ubuntu"))
    asked: list[tuple[str, str]] = []

    async def over_there(machine, path, model=""):
        asked.append((machine, path))
        return {"name": "lowlands-watch"}, None

    monkeypatch.setattr(opening.project_routes, "start_over_there", over_there)
    monkeypatch.setattr(opening.starting, "start", _never_locally)
    answer = asyncio.run(opening.begin("lowlands-watch", ""))["content"][0]["text"]
    assert asked == [("ubuntu", "/home/jurrejan/development/lowlands-watch")]
    assert "on ubuntu" in answer


def test_one_name_on_two_machines_is_refused_rather_than_guessed(claude_home, network,
                                                                 monkeypatch):
    """Picking one quietly is how a session lands on the wrong side of the network."""
    catalogued(monkeypatch,
               project("offerte", "/Users/jj/dev/web/offerte", "m2"),
               project("offerte", "/home/jurrejan/development/offerte", "ubuntu"))
    monkeypatch.setattr(opening.starting, "start", _never_locally)
    answer = asyncio.run(opening.begin("offerte", ""))["content"][0]["text"]
    assert "more than one machine" in answer and "m2" in answer and "ubuntu" in answer


def test_naming_the_machine_settles_it(claude_home, network, monkeypatch):
    catalogued(monkeypatch,
               project("offerte", "/Users/jj/dev/web/offerte", "m2"),
               project("offerte", "/home/jurrejan/development/offerte", "ubuntu"))

    async def over_there(machine, path, model=""):
        return {"name": "offerte"}, None

    monkeypatch.setattr(opening.project_routes, "start_over_there", over_there)
    monkeypatch.setattr(opening.starting, "start", _never_locally)
    answer = asyncio.run(opening.begin("offerte", "ubuntu"))["content"][0]["text"]
    assert "on ubuntu" in answer


def test_a_machine_that_did_not_answer_is_unknown_and_not_untrusted(claude_home, network,
                                                                    monkeypatch):
    """A folder nobody could be asked about is not a folder that refused. The manager repeats
    this to a person, and the two sentences mean different things."""
    catalogued(monkeypatch, project("lowlands-watch",
                                    "/home/jurrejan/development/lowlands-watch", "ubuntu"))

    async def only_this_mac(here):
        return {here: frozenset()}

    monkeypatch.setattr(tools.project_routes, "trusted_everywhere", only_this_mac)
    answer = asyncio.run(tools.catalogue("", "ubuntu", 30))["content"][0]["text"]
    assert "did not answer" in answer and "NOT TRUSTED" not in answer


def _never_locally(*args, **kwargs):
    raise AssertionError("a folder on another machine must not be started on this Mac")
