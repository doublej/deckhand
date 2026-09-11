"""The registry reader. The cases that matter are the ones where atlas is not there, or is
there and says something this daemon cannot use — because in every one of those the daemon
still has to list the sessions on this Mac."""

from __future__ import annotations

import json

import pytest

from deckhand_daemon.fleet import registry as fleet

REGISTRY = {
    "version": 1,
    "hosts": [
        {"id": "fractal", "label": "Fractal", "ssh": "fractal", "root": "C:/dev",
         "os": "win32", "role": "satellite", "node": "node", "skipGit": True},
        {"id": "m2", "label": "M2 Pro", "ssh": None, "root": "~/dev",
         "os": "darwin", "role": "primary"},
        {"id": "ubuntu", "label": "Ubuntu", "ssh": "ubuntu", "root": "/home/jurrejan/development",
         "os": "linux", "role": "deploy", "node": "/usr/bin/node"},
    ],
}


@pytest.fixture
def registry(tmp_path, monkeypatch):
    """Point the reader at a registry we control, the way atlas's own file is shaped."""

    def write(data: object) -> None:
        path = tmp_path / "hosts.json"
        path.write_text(json.dumps(data) if not isinstance(data, str) else data)
        monkeypatch.setenv("DECKHAND_ATLAS_REGISTRY", str(path))

    return write


def test_reads_atlas_registry_primary_first(registry):
    registry(REGISTRY)
    found = fleet.machines()
    assert [m.id for m in found] == ["m2", "fractal", "ubuntu"], "primary leads, rest by id"
    assert fleet.here() == "m2"
    fractal = next(m for m in found if m.id == "fractal")
    assert (fractal.ssh, fractal.os, fractal.root) == ("fractal", "win32", "C:/dev")
    assert not fractal.is_primary


def test_a_blank_label_falls_back_to_the_id(registry):
    """Atlas validates the label for nobody and it is hand-editable, so an empty one reaches
    here. The phone renders it verbatim; it must never be handed an empty row."""
    registry({"hosts": [{"id": "m2", "label": "   ", "ssh": None}]})
    assert fleet.primary().label == "m2"


def test_no_atlas_means_a_network_of_one(registry, tmp_path, monkeypatch):
    """A missing registry is not an error. It is the world as it was before any of this."""
    monkeypatch.setenv("DECKHAND_ATLAS_REGISTRY", str(tmp_path / "nothing.json"))
    found = fleet.machines()
    assert len(found) == 1 and found[0].is_primary
    assert fleet.here() == found[0].id != ""


def test_a_torn_read_falls_back_rather_than_raising(registry):
    """Atlas writes its caches temp+rename, but this file is hand-editable and git-tracked —
    a half-saved or conflicted registry must not take the daemon's session listing down."""
    registry("{not json at all")
    assert len(fleet.machines()) == 1


def test_a_registry_with_no_primary_is_not_usable(registry):
    """Every host reachable only over ssh describes a network this daemon is not on. Listing
    them would stamp this Mac's own sessions with somebody else's machine."""
    registry({"hosts": [{"id": "ubuntu", "ssh": "ubuntu"}, {"id": "fractal", "ssh": "fractal"}]})
    found = fleet.machines()
    assert len(found) == 1 and found[0].is_primary
