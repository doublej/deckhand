"""The OpenCode service stand-in, as a fixture for every OpenCode test here."""

import pytest
from opencode_fake import FakeOpenCode

from deckhand_daemon.sessions import opencode


@pytest.fixture
def opencode_service(claude_home, tmp_path, monkeypatch):
    """A registered, answering OpenCode service, with nothing in it yet."""
    registration = tmp_path / "opencode" / "service.json"
    registration.parent.mkdir(parents=True, exist_ok=True)
    registration.write_text('{"url": "http://127.0.0.1:49374", "password": "pw"}')
    fake = FakeOpenCode()
    monkeypatch.setattr(opencode, "request", fake.request)
    return fake
