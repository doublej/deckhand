"""A client with no token on it, because half of what is tested here is who may ask."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon.app import app


@pytest.fixture
def client(claude_home):
    return TestClient(app)
