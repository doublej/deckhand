"""A phone with a key, a session with a decision waiting, and every delivery caught.

The key is a software P-256 key made here, the same curve and encoding the Secure Enclave key
uses: the daemon sees a 65-byte point and DER signatures either way.
"""

import json

import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from decision_kit import AID, SID, page_html, public_key
from fastapi.testclient import TestClient

from deckhand_daemon import config, deliver, sessions
from deckhand_daemon.app import app
from deckhand_daemon.pairing import devices


@pytest.fixture
def project(claude_home, tmp_path):
    """The session's folder, moved somewhere a test may write."""
    cwd = tmp_path / "project"
    cwd.mkdir()
    record = claude_home / "sessions" / "4242.json"
    record.write_text(json.dumps(json.loads(record.read_text()) | {"cwd": str(cwd)}))
    return cwd


@pytest.fixture
def session(project):
    return next(s for s in sessions.live_sessions() if s.session_id == SID)


@pytest.fixture
def decision(project):
    """A confirm decision in the session's own folder. Rewrite it to change its hash."""
    spot = project / ".deckhand" / "artifacts" / SID
    spot.mkdir(parents=True)
    page = spot / f"{AID}.html"
    page.write_text(page_html())
    return page


@pytest.fixture
def key():
    return ec.generate_private_key(ec.SECP256R1())


@pytest.fixture
def phone(claude_home, key):
    """A phone paired by code that has filed its key: `(token, device row)`."""
    token, _ = devices.mint("JJ's iPhone", "phone")
    answered = TestClient(app).put("/devices/key", json={"publicKey": public_key(key)},
                                   headers={config.TOKEN_HEADER: token})
    assert answered.status_code == 200, answered.text
    return token, devices.known(token)


@pytest.fixture
def typed(monkeypatch):
    """Every delivery: (session id, text, route, person). Nothing reaches a real pane."""
    seen = []

    def fake(session, text, route="auto", person=False):
        seen.append((session.session_id, text, route, person))
        return route, None

    monkeypatch.setattr(deliver, "deliver", fake)
    return seen
