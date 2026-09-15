"""A client with no token on it, and a project list naming two folders, one on another machine."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon.app import app
from deckhand_daemon.projects import sources


@pytest.fixture
def client(claude_home, monkeypatch):
    listed = [sources.Project("shop", "/Users/jj/dev/web/shop"),
              sources.Project("docs", "/home/jj/dev/web/docs", machine="ubuntu")]
    monkeypatch.setattr(sources, "catalog", lambda: (listed, "atlas"))
    return TestClient(app)


@pytest.fixture
def head(token):
    return {"x-deckhand-token": token}
