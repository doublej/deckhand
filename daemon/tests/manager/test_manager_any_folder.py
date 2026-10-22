"""The manager's one wide door: a folder the person names, catalogued or not.

Everywhere else in this daemon the listing is the permission. Here it is not, so the interesting
assertions are which gates yield and which do not — and that nothing else in the daemon moved.
"""

from __future__ import annotations

import asyncio

import pytest

from deckhand_daemon.manager import opening
from deckhand_daemon.projects import sources, starting


@pytest.fixture
def network(monkeypatch):
    """This Mac is `m2` and the only other machine is Ubuntu."""
    class Machine:
        def __init__(self, ident):
            self.id = ident

    monkeypatch.setattr(opening.registry, "here", lambda: "m2")
    monkeypatch.setattr(opening.registry, "machines",
                        lambda: [Machine("m2"), Machine("ubuntu")])
    monkeypatch.setattr(sources, "catalog", lambda: ([], "test"))


@pytest.fixture
def opens(monkeypatch):
    """`starting.start` records what it was asked to open instead of opening it."""
    asked: list[tuple[str, bool]] = []

    def fake(cwd, *, person_named_it=False, model=""):
        asked.append((cwd, person_named_it))
        return _session(cwd), None

    monkeypatch.setattr(opening.starting, "start", fake)
    return asked


def _session(cwd: str):
    from deckhand_daemon.sessions import Session

    return Session(session_id="x", pid=1, name="tmp", cwd=cwd, status="idle",
                   updated_at=0.0, tty="", pane=None, machine="m2")


def test_a_folder_that_is_not_a_project_opens_anyway(claude_home, network, opens, tmp_path):
    """The whole point: no catalogue row, no trust entry, and it still opens."""
    answer = asyncio.run(opening.begin(str(tmp_path), ""))["content"][0]["text"]
    assert opens == [(str(tmp_path.resolve()), True)]
    assert str(tmp_path) in answer


def test_the_home_folder_is_what_a_tilde_means(claude_home, network, opens):
    asyncio.run(opening.begin("~", ""))
    opened, named = opens[0]
    assert opened == str(__import__("pathlib").Path.home().resolve()) and named is True


def test_a_path_that_is_not_a_folder_is_refused(claude_home, network, opens):
    answer = asyncio.run(opening.begin("/no/such/folder", ""))["content"][0]["text"]
    assert "not a folder on this Mac" in answer and opens == []


def test_a_name_is_still_looked_up_and_still_gated(claude_home, network, opens, monkeypatch):
    """A name has no person pointing at a folder behind it, so both gates stand."""
    monkeypatch.setattr(sources, "catalog",
                        lambda: ([sources.Project(name="shop", path="/Users/jj/dev/web/shop",
                                                  relative="web/shop", machine="m2")], "test"))
    monkeypatch.setattr(opening.starting, "trusted", set)
    answer = asyncio.run(opening.begin("shop", ""))["content"][0]["text"]
    assert "never been trusted" in answer and opens == []


def test_a_path_on_another_machine_crosses_unexpanded(claude_home, network, opens, monkeypatch):
    """`~` means that machine's home, so it travels as typed and is expanded over there."""
    sent: list[tuple[str, str]] = []

    async def over_there(machine, path, model=""):
        sent.append((machine, path))
        return {"name": "home", "cwd": "/home/jurrejan"}, None

    monkeypatch.setattr(opening.project_routes, "start_over_there", over_there)
    answer = asyncio.run(opening.begin("~", "ubuntu"))["content"][0]["text"]
    assert sent == [("ubuntu", "~")]
    assert "/home/jurrejan" in answer and "on ubuntu" in answer
    assert opens == []


def test_the_trust_check_does_not_cross_the_wire(claude_home):
    """Measured: Ubuntu draws the trust dialog where this Mac does not, on the same 2.1.278 and
    the same `hasTrustDialogAccepted: false`. A hand obeying a waived gate is a tmux window
    sitting on a question nobody can answer, so the waiver stops at this Mac."""
    from pathlib import Path as P

    from deckhand_daemon.projects import tmux

    assert "person_named_it" not in P(tmux.__file__).read_text().split('"""', 2)[2]
    hand = (P(tmux.__file__).parent.parent / "fleet" / "hand.py").read_text()
    assert "named" not in hand.split("def start_here")[1].split("return {")[0].split('"""')[0]


def test_a_machine_that_does_not_exist_is_named_rather_than_dialled(claude_home, network, opens):
    answer = asyncio.run(opening.begin("/tmp", "nas"))["content"][0]["text"]
    assert "no machine called 'nas'" in answer and "ubuntu" in answer and opens == []


def test_the_phones_own_route_did_not_widen(claude_home, token, no_hands, monkeypatch):
    """The picker is unchanged: a folder atlas never listed is still refused there."""
    from fastapi.testclient import TestClient

    from deckhand_daemon.app import app

    monkeypatch.setattr(sources, "catalog", lambda: ([], "test"))
    client = TestClient(app)
    client.headers["x-deckhand-token"] = token
    answer = client.post("/projects/session", json={"path": "/tmp"})
    assert answer.status_code == 400
    assert "not in the project list" in answer.json()["detail"]


def test_only_the_manager_asks_to_skip_the_trust_record(claude_home):
    """`person_named_it` has one caller. A second one is a gate switched off somewhere nobody
    reading that file would look."""
    from pathlib import Path as P

    daemon = P(starting.__file__).parent.parent
    callers = [f for f in daemon.rglob("*.py")
               if "person_named_it=True" in f.read_text()]
    assert [f.name for f in callers] == ["opening.py"]
