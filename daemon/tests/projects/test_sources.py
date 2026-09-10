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


def test_another_machines_folders_are_not_offered():
    """atlas catalogues the rig and the Ubuntu box too, and this Mac cannot start a session in
    `C:\\dev`. Only atlas's records are filtered this way — a hand-written list has no flag."""
    rows = [_atlas(), _atlas(name="rig", path="C:\\dev\\thing", isLocal=None)]
    assert [p.name for p in sources._from_atlas(rows)] == ["shop"]


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
