"""The universal half: whatever keeps the list, the consumer sees `Project`."""

import json

from deckhand_daemon.projects import sources


def _atlas(**over):
    row = {
        "name": "shop",
        "path": "/Users/jj/dev/web/shop",
        "relativePath": "web/shop",
        "description": "the shop",
        "type": "node",
        "isLocal": True,
        "host": "m2",
        "modifiedAt": "2026-09-01T10:00:00.000Z",
    }
    return row | over


def test_the_persons_own_file_beats_atlas(tmp_path, monkeypatch, claude_home):
    monkeypatch.setattr(sources, "_atlas_api", lambda: [sources.Project("no", "/no")])
    written = tmp_path / "data" / "projects.json"
    written.parent.mkdir(parents=True, exist_ok=True)
    written.write_text(json.dumps([{"name": "mine", "path": "/Users/jj/mine"}]))
    sources.forget()
    found, source = sources.catalog()
    assert source == "file"
    assert [p.name for p in found] == ["mine"]


def test_atlas_answers_before_its_cache(monkeypatch, claude_home):
    monkeypatch.setattr(sources, "_written", list)
    monkeypatch.setattr(sources, "_atlas_api", lambda: sources._from_atlas([_atlas()]))
    monkeypatch.setattr(sources, "_atlas_cache", lambda: [sources.Project("stale", "/stale")])
    sources.forget()
    found, source = sources.catalog()
    assert source == "atlas"
    assert [p.name for p in found] == ["shop"]


def test_the_cache_carries_the_list_when_atlas_is_down(tmp_path, monkeypatch, claude_home):
    cache = tmp_path / "atlas-cache.json"
    cache.write_text(json.dumps({"projects": [_atlas()]}))
    monkeypatch.setenv("DECKHAND_ATLAS_CACHE", str(cache))
    monkeypatch.setattr(sources, "_written", list)
    monkeypatch.setattr(sources, "_atlas_api", list)
    sources.forget()
    found, source = sources.catalog()
    assert source == "atlas-cache"
    assert found[0].relative == "web/shop"


def test_another_machines_folders_are_offered_and_say_whose_they_are():
    """atlas catalogues the rig and the Ubuntu box too, and a hand can now start a session in
    either. `host` is atlas's id and deckhand's alike, so nothing maps it."""
    rows = [_atlas(), _atlas(name="rig", path="C:\\dev\\thing", isLocal=None, host="fractal")]
    found = sources._from_atlas(rows)
    assert [(p.name, p.machine) for p in found] == [("shop", "m2"), ("rig", "fractal")]


def test_a_hand_written_list_names_no_machine_and_that_means_this_one():
    """`isLocal` is present-and-true locally and *absent* elsewhere, never false — so a row with
    no host at all is a folder somebody wrote down here, not one of unknown provenance."""
    assert sources._project({"name": "shop", "path": "/Users/jj/dev/web/shop"}).machine == ""


def test_archived_work_is_never_a_row():
    rows = [_atlas(), _atlas(name="old", path="/Users/jj/dev/_archive/2026/old"),
            _atlas(name="flagged", archived=True)]
    assert [p.name for p in sources._from_atlas(rows)] == ["shop"]


def test_the_newest_touch_of_the_two_is_what_orders_the_list(monkeypatch, claude_home):
    """A folder nobody has edited since a session talked about it all afternoon is still the
    folder you were working in."""
    rows = [
        _atlas(name="quiet", path="/a", modifiedAt="2026-09-01T10:00:00.000Z"),
        _atlas(name="talked-about", path="/b", modifiedAt="2026-08-01T10:00:00.000Z",
               claudeSessions={"lastAt": "2026-09-05T10:00:00.000Z"}),
    ]
    monkeypatch.setattr(sources, "_written", list)
    monkeypatch.setattr(sources, "_atlas_api", lambda: sources._from_atlas(rows))
    sources.forget()
    found, _ = sources.catalog()
    assert [p.name for p in found] == ["talked-about", "quiet"]


def test_a_record_with_no_folder_is_not_a_project():
    assert sources._from_atlas([_atlas(path=""), "not a dict", _atlas()]) != []
    assert len(sources._from_atlas([_atlas(path=""), _atlas()])) == 1


def test_what_a_project_is_built_with_is_carried_when_atlas_knows_it():
    """atlas classifies a project from its manifest and then throws the manifest away, so one
    word is the whole of what this Mac knows about a project's libraries. Carry that word."""
    row = _atlas(
        type="node", framework="sveltekit", runner="bun", gitBranch="develop", git="dirty",
        port=5188, domains=["utt.jurrejan.com", "www.framelink.quest"],
        beads={"open": 3, "inProgress": 1, "closed": 40},
        claudeSessions={"lastAt": "2026-09-05T10:00:00.000Z", "count": 184},
    )
    found = sources._from_atlas([row])[0]
    assert (found.framework, found.runner) == ("sveltekit", "bun")
    assert (found.branch, found.dirty) == ("develop", True)
    assert (found.issues, found.port, found.sessions) == (3, 5188, 184)
    assert found.domains == ("utt.jurrejan.com", "www.framelink.quest")
    assert found.to_json()["domains"] == ["utt.jurrejan.com", "www.framelink.quest"]


def test_atlas_saying_it_could_not_tell_is_not_a_fact_worth_carrying():
    """`unknown` is three hundred rows of five hundred. A picker that prints it three hundred
    times has printed nothing, and absent says the same thing without the room."""
    found = sources._from_atlas([_atlas(framework="unknown", runner="", type="generic")])[0]
    assert (found.framework, found.runner) == ("", "")
    # `git` has four values and only one of them is a warning, so the phone never sees the rest.
    assert sources._from_atlas([_atlas(git="clean")])[0].dirty is False
    assert sources._from_atlas([_atlas(git="no-repo")])[0].dirty is False


def test_a_source_that_knows_none_of_it_still_makes_a_project():
    """A hand-written projects.json is two keys, and it has to keep working."""
    found = sources._project({"name": "mine", "path": "/Users/jj/dev/mine"})
    assert found is not None
    assert (found.framework, found.branch, found.domains, found.issues) == ("", "", (), 0)
    # Rubbish where a number should be is nothing, not a crash and not a negative tally.
    odd = sources._project({"path": "/x", "port": "5188", "beads": {"open": -4}})
    assert (odd.port, odd.issues) == (0, 0)
