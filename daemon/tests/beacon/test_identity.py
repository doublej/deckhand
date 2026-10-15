"""What a client learns from the Mac it found, rather than from a constant compiled into it."""

from __future__ import annotations

from fastapi.testclient import TestClient

from deckhand_daemon import config
from deckhand_daemon.app import app


def test_health_says_which_mac_and_where_its_halves_are(claude_home) -> None:
    """Open like the rest of /health: an id names a Mac and grants nothing, and both addresses
    are null until `just setup` was told them, never a guess."""
    first = TestClient(app).get("/health").json()
    assert first["id"] == config.machine_id()
    assert first["web"] is None and first["remote"] is None

    (config.data_dir() / "web-url").write_text("https://web.example\n")
    (config.data_dir() / "remote-url").write_text("https://far.example\n")
    again = TestClient(app).get("/health").json()
    assert again["id"] == first["id"]
    assert (again["web"], again["remote"]) == ("https://web.example", "https://far.example")


def test_an_empty_address_file_is_no_address(claude_home) -> None:
    (config.data_dir() / "web-url").write_text("\n")
    assert config.web_url() is None
