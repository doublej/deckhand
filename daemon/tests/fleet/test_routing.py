"""Which paths go to another machine, and — the half that matters — which never do.

The allow-list is the safety property. A route the daemon keeps must stay kept even when nobody
remembers this file exists, so the interesting assertions here are the negative ones.
"""

from __future__ import annotations

import pytest

from deckhand_daemon.fleet import routing

REMOTE = "ubuntu"
SID = "f1ddae0a-7aaf-4bb0-9f42-9a26753f3b03"


@pytest.fixture
def elsewhere(monkeypatch):
    """Pretend the session lives on another machine, and that this one is the Mac."""
    monkeypatch.setattr(routing.merge, "owner", lambda sid: REMOTE if sid == SID else "")
    monkeypatch.setattr(routing.registry, "here", lambda: "m2")


@pytest.mark.parametrize(
    "suffix",
    ["turns", "raw", "context", "commands", "files", "file", "artifacts", "queue/clear"],
)
def test_a_read_of_the_sessions_own_files_goes_to_its_machine(elsewhere, suffix):
    assert routing.owner_of(f"/sessions/{SID}/{suffix}") == (REMOTE, SID)


def test_a_nested_artifact_path_goes_too(elsewhere):
    """A slip's answer is under `/artifacts/<id>/answer`, and it is still that machine's file."""
    assert routing.owner_of(f"/sessions/{SID}/artifacts/abc/answer") == (REMOTE, SID)


@pytest.mark.parametrize(
    "suffix",
    [
        # The daemon decides these, and deciding happens in one place.
        "summary", "orders", "filters", "notify", "say", "audio", "image",
        # Pane work. A hand has none.
        "focus", "control", "name",
    ],
)
def test_what_the_daemon_keeps_is_never_forwarded(elsewhere, suffix):
    assert routing.owner_of(f"/sessions/{SID}/{suffix}") is None


def test_a_prefix_of_an_allowed_suffix_is_not_allowed(elsewhere):
    """`files` is forwarded; `filesystem` would be a different route entirely, and matching on
    `startswith` alone would have sent it away."""
    assert routing.owner_of(f"/sessions/{SID}/filesystem") is None
    assert routing.owner_of(f"/sessions/{SID}/turnsomething") is None


def test_a_session_on_this_mac_is_never_forwarded(monkeypatch):
    monkeypatch.setattr(routing.merge, "owner", lambda sid: "m2")
    monkeypatch.setattr(routing.registry, "here", lambda: "m2")
    assert routing.owner_of(f"/sessions/{SID}/turns") is None


def test_an_unknown_session_is_handled_here_and_404s_here(monkeypatch):
    """Before the first listing, and for an id nothing recognises. Handling it locally makes it
    one 404; guessing would make it three requests at three machines."""
    monkeypatch.setattr(routing.merge, "owner", lambda sid: "")
    monkeypatch.setattr(routing.registry, "here", lambda: "m2")
    assert routing.owner_of(f"/sessions/{SID}/turns") is None


@pytest.mark.parametrize(
    "path",
    ["/sessions", "/sessions/all", "/sessions/links", "/machines", "/health", "/briefings",
     "/settings", "/filters", "/projects", "/manager", f"/sessions/{SID}"],
)
def test_paths_that_are_not_a_sessions_own_file(elsewhere, path):
    """`/sessions/links` is the sharp one: it looks like a session id followed by a suffix, and
    it is a route of its own that the daemon answers by merging every machine."""
    assert routing.owner_of(path) is None
