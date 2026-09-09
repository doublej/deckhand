import json

from fastapi.testclient import TestClient

from deckhand_daemon import config, sessions
from deckhand_daemon.app import app

SID = "aaaa1111-2222-3333-4444-555566667777"


def client(token):
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    return c


def test_health_is_open_but_the_rest_is_not(claude_home):
    anon = TestClient(app)
    assert anon.get("/health").json()["name"] == "deckhand"
    assert anon.get("/sessions").status_code == 401
    assert anon.headers.get("x-deckhand-token") is None


def test_wrong_token_is_rejected(token):
    c = TestClient(app)
    c.headers["x-deckhand-token"] = "not-the-token"
    assert c.get("/sessions").status_code == 401


def test_sessions_are_served_with_their_pane(token):
    body = client(token).get("/sessions").json()
    first = body["sessions"][0]
    assert first["session_id"] == SID
    assert first["name"] == "warm-okapi"
    assert first["status"] == "busy"
    assert first["pane"]["iterm_session_id"] == "ITERM-A"


def test_turns_come_from_the_transcript(token, claude_home):
    (claude_home / "projects" / "-Users-jj-dev" / f"{SID}.jsonl").write_text(
        json.dumps({"type": "user", "message": {"content": "ping"}, "timestamp": "t"}) + "\n"
    )
    turns = client(token).get(f"/sessions/{SID}/turns?limit=4").json()["turns"]
    assert turns == [{"role": "user", "text": "ping", "timestamp": "t"}]


def test_audio_upload_lands_on_the_mac(token):
    clip = b"ftypM4A " + b"\x00" * 2048
    r = client(token).post(
        f"/sessions/{SID}/audio", files={"file": ("clip.m4a", clip, "audio/m4a")}
    )
    assert r.status_code == 201
    body = r.json()
    assert body["bytes"] == len(clip)
    assert body["transcript"] is None
    saved = config.data_dir() / "audio" / SID
    written = list(saved.glob("*.m4a"))
    assert len(written) == 1
    assert written[0].read_bytes() == clip


def test_upload_rejects_junk(token):
    c = client(token)
    assert c.post(f"/sessions/{SID}/audio", files={"file": ("x.txt", b"hi", "text/plain")}).status_code == 415
    assert c.post(f"/sessions/{SID}/audio", files={"file": ("x.m4a", b"", "audio/m4a")}).status_code == 400
    dead = "cccc1111-2222-3333-4444-555566667777"
    assert c.post(f"/sessions/{dead}/audio", files={"file": ("x.m4a", b"ok", "audio/m4a")}).status_code == 404


def test_focus_asks_iterm_for_that_pane(token, monkeypatch):
    seen = {}
    monkeypatch.setattr(sessions, "focus", lambda s: seen.setdefault("id", s.pane.iterm_session_id) or True)
    assert client(token).post(f"/sessions/{SID}/focus").json() == {"focused": True}
    assert seen["id"] == "ITERM-A"
