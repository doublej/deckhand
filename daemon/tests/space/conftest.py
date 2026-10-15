"""A client with no token on it, over `claude_home`'s live sessions, on a known LAN address."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon import config
from deckhand_daemon.app import app


@pytest.fixture
def client(claude_home, monkeypatch):
    monkeypatch.setattr(config, "lan_address", lambda: "192.168.178.180")
    return TestClient(app)


@pytest.fixture
def head(token):
    return {"x-deckhand-token": token}
