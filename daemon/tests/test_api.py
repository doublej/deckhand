import json
from pathlib import Path

from fastapi.testclient import TestClient

from deckhand_daemon import app as app_module
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
    assert turns == [{"role": "user", "text": "ping", "timestamp": "t", "tools": []}]


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


def test_upload_answers_with_what_utt_heard(token, monkeypatch):
    monkeypatch.setattr(app_module.transcribe, "transcribe", lambda clip, hints: ("Testing, one, two.", None))
    r = client(token).post(
        f"/sessions/{SID}/audio", files={"file": ("clip.m4a", b"audio bytes", "audio/m4a")}
    )
    assert r.json()["transcript"] == "Testing, one, two."
    assert r.json()["transcript_error"] is None


def test_a_clip_is_kept_even_when_utt_is_off(token, monkeypatch):
    monkeypatch.setattr(app_module.transcribe, "transcribe", lambda clip, hints: (None, "utt is off"))
    body = client(token).post(
        f"/sessions/{SID}/audio", files={"file": ("clip.m4a", b"audio bytes", "audio/m4a")}
    ).json()
    assert body["transcript"] is None
    assert body["transcript_error"] == "utt is off"
    assert Path(body["path"]).read_bytes() == b"audio bytes"


def test_a_clip_can_be_transcribed_without_being_delivered(token, monkeypatch):
    """Reading it first is the whole point: nothing reaches the session until the person says."""
    monkeypatch.setattr(app_module.transcribe, "transcribe", lambda _clip, _hints: ("read me first", None))
    delivered = []
    monkeypatch.setattr(app_module.deliver, "deliver", lambda *a, **k: delivered.append(a))
    answer = client(token).post(
        f"/sessions/{SID}/audio?deliver=false",
        files={"file": ("clip.m4a", b"x" * 64, "audio/mp4")},
    )
    assert answer.status_code == 201
    body = answer.json()
    assert body["transcript"] == "read me first"
    assert body["delivered"] is False
    assert delivered == []


def test_say_puts_the_words_in_and_names_the_route(token, monkeypatch):
    seen = {}

    def deliver(session, text, route):
        seen.update(text=text, route=route)
        return "keyboard", None

    monkeypatch.setattr(app_module.deliver, "deliver", deliver)
    answer = client(token).post(f"/sessions/{SID}/say?route=keyboard", json={"text": "run the tests"})
    assert answer.status_code == 200
    assert answer.json() == {
        "delivered": True, "delivered_by": "keyboard", "delivery_error": None,
        "notes": [], "stopped_by": None,
    }
    assert seen == {"text": "run the tests", "route": "keyboard"}


def test_a_picture_is_kept_and_the_message_names_it(token, monkeypatch):
    """An image reaches a session as a path: the session's own Read is what can see a file."""
    seen = {}
    monkeypatch.setattr(
        app_module.deliver, "deliver",
        lambda session, text, route: (seen.update(text=text), ("keyboard", None))[1],
    )
    kept = client(token).post(
        f"/sessions/{SID}/image", files={"file": ("shot.png", b"\x89PNG" + b"x" * 40, "image/png")}
    )
    assert kept.status_code == 200
    path = Path(kept.json()["path"])
    assert path.is_file() and path.parent == config.image_dir(SID)

    said = client(token).post(f"/sessions/{SID}/say", json={"text": "look", "images": [str(path)]})

    assert said.json()["delivered"] is True
    assert seen["text"] == f"look\n\nattached image: {path}"


def test_only_this_sessions_own_pictures_can_be_named(token, monkeypatch):
    """Otherwise "say this and read that file" would point a session at anything on the Mac."""
    seen = {}
    monkeypatch.setattr(
        app_module.deliver, "deliver",
        lambda session, text, route: (seen.update(text=text), ("keyboard", None))[1],
    )
    elsewhere = config.data_dir() / "escape.png"
    elsewhere.write_bytes(b"x")

    client(token).post(
        f"/sessions/{SID}/say",
        json={"text": "look", "images": [str(elsewhere), "/etc/passwd"]},
    )

    assert seen["text"] == "look"


def test_a_file_that_is_not_an_image_is_refused(token):
    answer = client(token).post(
        f"/sessions/{SID}/image", files={"file": ("notes.txt", b"hello", "text/plain")}
    )
    assert answer.status_code == 415


def test_every_briefing_comes_back_in_one_call_without_a_model(token):
    """The cold start: a reinstalled app is handed what the Mac already knew, for one request.

    Nothing here can reach a model — the SDK is never touched — which is the guarantee that
    matters. A blank rail after a reinstall used to be bought back one model run at a time.
    """
    from deckhand_daemon import briefings

    briefings.save(SID, {"summary": "Built it", "headline": "Built it", "written_at": 1.0})

    written = client(token).get("/briefings").json()["briefings"]

    assert written[SID]["headline"] == "Built it"
    assert written[SID]["writtenAt"] == 1.0
    # Every live session is listed, written about or not, so the phone can tell the two apart.
    assert set(written) == {s.session_id for s in sessions.live_sessions()}


def test_reading_one_summary_moves_that_session_to_the_front_of_the_queue(token):
    from deckhand_daemon import briefings

    briefings._bumped.clear()
    assert client(token).get(f"/sessions/{SID}/summary").status_code == 200
    assert briefings._bumped == [SID]
