"""What a page on another origin may do: CORS on two routes only, and a token that can do one thing.

The negative assertions are the point, as in `test_pairing.py`: a scoped token reaches nothing
but `/transcribe`, and no other route grows CORS headers because these two did.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon import transcribe
from deckhand_daemon.app import app

PAGE = "https://wallgen.birdsonpaper.com"


def as_(token: str) -> TestClient:
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    return c


def scoped(mac_token: str) -> str:
    answer = as_(mac_token).post("/pair/transcribe?name=wallgen")
    assert answer.status_code == 200, answer.text
    assert answer.json()["device"]["scope"] == "transcribe"
    return answer.json()["token"]


@pytest.fixture
def heard(monkeypatch):
    """utt, answering with whatever the test puts in `said`, and noting the clip it was given."""
    said = {"text": "drie rollen graag", "error": None, "seen": []}

    def fake(clip, hints=None):
        said["seen"].append((clip, clip.exists(), clip.read_bytes()))
        return transcribe.Heard(text=said["text"], error=said["error"])

    monkeypatch.setattr(transcribe, "transcribe", fake)
    return said


def test_a_scoped_token_transcribes_and_nothing_else(token, heard):
    key = scoped(token)
    answer = as_(key).post("/transcribe", files={"file": ("clip.webm", b"opus", "audio/webm")})
    assert answer.json() == {"text": "drie rollen graag"}
    for refused in (as_(key).get("/sessions"), as_(key).get("/pair/check"),
                    as_(key).post("/pair/open"), as_(key).post("/pair/transcribe")):
        assert refused.status_code == 401


def test_only_this_macs_token_mints_one(token):
    key = scoped(token)
    assert TestClient(app).post("/pair/transcribe").status_code == 401
    assert as_(key).post("/pair/transcribe").status_code == 401


def test_the_clip_is_kept_only_while_it_is_heard(token, heard):
    answer = as_(token).post("/transcribe", files={"file": ("clip.mp4", b"aac", "audio/mp4")})
    assert answer.status_code == 200
    ((clip, existed, body),) = heard["seen"]
    assert existed and body == b"aac" and clip.suffix == ".mp4"
    assert not clip.exists() and not clip.parent.exists()


def test_what_cannot_be_heard_is_refused(token, heard):
    assert TestClient(app).post("/transcribe", files={"file": ("a.webm", b"x")}).status_code == 401
    mac = as_(token)
    assert mac.post("/transcribe", files={"file": ("a.exe", b"x")}).status_code == 415
    assert mac.post("/transcribe", files={"file": ("a.webm", b"")}).status_code == 400
    heard["text"], heard["error"] = None, "utt is not running on the Mac"
    answer = mac.post("/transcribe", files={"file": ("a.webm", b"x")})
    assert (answer.status_code, answer.json()["detail"]) == (422, "utt is not running on the Mac")


def test_a_preflight_is_answered_for_the_page_with_private_network_access(claude_home):
    answer = TestClient(app).options("/transcribe", headers={
        "Origin": PAGE, "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "x-deckhand-token",
        "Access-Control-Request-Private-Network": "true"})
    assert answer.status_code == 204
    assert answer.headers["access-control-allow-origin"] == PAGE
    assert answer.headers["access-control-allow-headers"] == "x-deckhand-token"
    assert answer.headers["access-control-allow-private-network"] == "true"


def test_no_other_origin_and_no_other_route_gets_cors(claude_home):
    def preflight(path: str, origin: str):
        return TestClient(app).options(path, headers={
            "Origin": origin, "Access-Control-Request-Method": "POST"})

    for answer in (preflight("/transcribe", "https://evil.example"),
                   preflight("/sessions/x/say", PAGE),
                   TestClient(app).get("/sessions", headers={"Origin": PAGE})):
        assert "access-control-allow-origin" not in answer.headers


def test_health_says_whether_it_can_hear_and_lets_the_page_read_that(claude_home, monkeypatch):
    monkeypatch.setattr(transcribe, "ready", lambda: True)
    answer = TestClient(app).get("/health", headers={"Origin": "http://127.0.0.1:4131"})
    assert answer.json()["transcribe"] is True
    assert answer.headers["access-control-allow-origin"] == "http://127.0.0.1:4131"
