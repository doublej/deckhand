"""Whether a session can begin here, and what is refused before anything is opened."""

import json

import pytest

from deckhand_daemon.projects import routes, sources, starting


@pytest.fixture
def trusted_home(claude_home, monkeypatch):
    """Claude Code's own record of the folders it has been told to trust."""
    (claude_home.parent / "claude.json").write_text(json.dumps({
        "projects": {
            "/Users/jj/dev/web/shop": {"hasTrustDialogAccepted": True},
            "/Users/jj/dev/web/cold": {"hasTrustDialogAccepted": False},
        }
    }))
    return claude_home


def test_trust_is_read_off_claude_codes_own_record(trusted_home):
    assert starting.trusted() == {"/Users/jj/dev/web/shop"}


def test_an_untrusted_folder_is_refused_before_a_window_is_opened(trusted_home, monkeypatch, tmp_path):
    """The trust question can only be answered at the Mac, so opening a terminal to ask it from
    another room leaves a window stranded at a prompt nobody will ever see."""
    opened = []
    monkeypatch.setattr(starting, "_run", lambda command: opened.append(command))
    folder = tmp_path / "cold"
    folder.mkdir()
    monkeypatch.setattr(starting, "trusted", set)
    session, error = starting.start(str(folder))
    assert session is None
    assert "not been trusted" in error
    assert opened == []  # nothing was run at all


def test_a_folder_that_is_not_there_is_refused_too(trusted_home, monkeypatch):
    monkeypatch.setattr(starting, "_run", lambda command: pytest.fail("should not run anything"))
    session, error = starting.start("/Users/jj/dev/web/gone")
    assert session is None
    assert "not a folder" in error


def test_a_name_already_taken_is_numbered(claude_home):
    """A star, a hidden row and a filter chain are all filed under the name, so two live
    sessions called `shop` would share all three."""
    running = starting.live_sessions(iterm_only=False)
    assert [s.name for s in running] == ["warm-okapi", "cold-otter"]
    assert starting.free_name("shop", running) == "shop"
    assert starting.free_name("warm-okapi", running) == "warm-okapi-2"


def test_the_listing_is_the_whole_permission(trusted_home, monkeypatch):
    """A folder the project list does not name cannot be started in, however real it is."""
    monkeypatch.setattr(sources, "catalog", lambda: ([sources.Project("shop", "/Users/jj/dev/web/shop")], "atlas"))
    monkeypatch.setattr(starting, "start", lambda cwd: pytest.fail("should never be reached"))
    import anyio
    with pytest.raises(Exception) as raised:
        anyio.run(routes.start_project_session, "/etc")
    assert "not in the project list" in str(raised.value)


def test_a_row_says_whether_it_can_be_started(trusted_home, monkeypatch, no_hands):
    monkeypatch.setattr(sources, "catalog", lambda: ([
        sources.Project("shop", "/Users/jj/dev/web/shop"),
        sources.Project("cold", "/Users/jj/dev/web/cold"),
    ], "atlas"))
    import anyio
    rows = anyio.run(routes.list_projects)["projects"]
    assert [(r["name"], r["trusted"]) for r in rows] == [("shop", True), ("cold", False)]
    # The two sessions in the fixture both sit in /Users/jj/dev/web/shop.
    assert rows[0]["live"] == 2


def test_a_folder_on_another_machine_is_offered_but_not_trusted_by_this_one(
    trusted_home, monkeypatch, no_hands
):
    """Trust is answered at a keyboard, so this Mac's answer says nothing about Fractal's. A
    machine that is asleep contributes none, and its rows read as "cannot start here yet"."""
    monkeypatch.setattr(sources, "catalog", lambda: ([
        sources.Project("shop", "/Users/jj/dev/web/shop"),
        sources.Project("rig", "C:\\dev\\thing", machine="fractal"),
    ], "atlas"))
    import anyio
    rows = anyio.run(routes.list_projects)["projects"]
    assert [(r["name"], r["machine"], r["trusted"]) for r in rows] == [
        ("shop", "", True), ("rig", "fractal", False)
    ]


def test_starting_a_folder_over_there_goes_to_that_machines_hand(trusted_home, monkeypatch):
    """Which machine is derived from the catalogue, never taken off the request: the listing is
    the whole permission, and a machine named by the caller is a target this Mac never offered."""
    monkeypatch.setattr(sources, "catalog", lambda: (
        [sources.Project("rig", "C:\\dev\\thing", machine="fractal")], "atlas"))
    monkeypatch.setattr(starting, "start", lambda cwd: pytest.fail("that folder is not here"))
    asked = {}

    async def fake_call(machine, method, path, **kwargs):
        asked.update({"machine": machine, "path": path, "body": kwargs.get("json")})
        return {"session": {"name": "rig", "machine": "fractal"}, "error": None}

    monkeypatch.setattr(routes.proxy, "call", fake_call)
    import anyio
    answer = anyio.run(routes.start_project_session, "C:\\dev\\thing")
    assert asked["machine"] == "fractal"
    assert asked["path"] == "/projects/session"
    assert asked["body"]["path"] == "C:\\dev\\thing"
    assert answer["session"]["machine"] == "fractal"


def test_a_machine_that_is_asleep_says_so_rather_than_failing_silently(trusted_home, monkeypatch):
    monkeypatch.setattr(sources, "catalog", lambda: (
        [sources.Project("rig", "C:\\dev\\thing", machine="fractal")], "atlas"))

    async def unreachable(machine, method, path, **kwargs):
        return None

    monkeypatch.setattr(routes.proxy, "call", unreachable)
    import anyio
    with pytest.raises(Exception) as raised:
        anyio.run(routes.start_project_session, "C:\\dev\\thing")
    assert "not reachable" in str(raised.value)
