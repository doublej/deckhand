import json
from pathlib import Path

from fastapi.testclient import TestClient

from deckhand_daemon import config, sessions
from deckhand_daemon import deliver as deliver_module
from deckhand_daemon import transcribe as transcribe_module
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
    assert turns == [
        {"role": "user", "text": "ping", "written_by": "", "timestamp": "t", "tools": [], "thoughts": []}
    ]


def test_a_subagents_notice_is_not_labelled_as_the_person(token, claude_home):
    """It arrives as a `user` entry, so only `by` keeps it out of JJ's mouth."""
    notice = ('<task-notification><summary>Agent "recon" finished</summary>'
              "<result>found it</result></task-notification>")
    (claude_home / "projects" / "-Users-jj-dev" / f"{SID}.jsonl").write_text(
        json.dumps({"type": "user", "message": {"content": notice}, "timestamp": "t"}) + "\n"
    )
    turns = client(token).get(f"/sessions/{SID}/turns?limit=4").json()["turns"]
    assert turns[0]["written_by"] == "recon" and "found it" in turns[0]["text"]


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
    monkeypatch.setattr(transcribe_module, "transcribe",
                        lambda clip, hints: transcribe_module.Heard(text="Testing, one, two."))
    r = client(token).post(
        f"/sessions/{SID}/audio", files={"file": ("clip.m4a", b"audio bytes", "audio/m4a")}
    )
    assert r.json()["transcript"] == "Testing, one, two."
    assert r.json()["transcript_error"] is None


def test_a_clip_is_kept_even_when_utt_is_off(token, monkeypatch):
    monkeypatch.setattr(transcribe_module, "transcribe",
                        lambda clip, hints: transcribe_module.Heard(error="utt is off"))
    body = client(token).post(
        f"/sessions/{SID}/audio", files={"file": ("clip.m4a", b"audio bytes", "audio/m4a")}
    ).json()
    assert body["transcript"] is None
    assert body["transcript_error"] == "utt is off"
    assert Path(body["path"]).read_bytes() == b"audio bytes"


def test_a_clip_can_be_transcribed_without_being_delivered(token, monkeypatch):
    """Reading it first is the whole point: nothing reaches the session until the person says."""
    monkeypatch.setattr(transcribe_module, "transcribe",
                        lambda _clip, _hints: transcribe_module.Heard(text="read me first"))
    delivered = []
    monkeypatch.setattr(deliver_module, "deliver", lambda *a, **k: delivered.append(a))
    answer = client(token).post(
        f"/sessions/{SID}/audio?deliver=false",
        files={"file": ("clip.m4a", b"x" * 64, "audio/mp4")},
    )
    assert answer.status_code == 201
    body = answer.json()
    assert body["transcript"] == "read me first"
    assert body["delivered"] is False
    assert delivered == []


def test_a_clip_answers_with_what_each_stage_cost_and_records_it(token, monkeypatch):
    """Every stage of the path, in the order it ran, plus a line on disk to compare runs with.

    A list rather than an object: the phone decodes with `convertFromSnakeCase`, which rewrites
    dictionary keys as happily as struct ones, and a stage name is data.
    """
    monkeypatch.setattr(transcribe_module, "transcribe",
                        lambda clip, hints: transcribe_module.Heard(
                            text="how long did that take",
                            stages={"handoff": 1.0, "utt": 900.0, "answer": 0.2}))
    monkeypatch.setattr(deliver_module, "deliver", lambda *a, **k: ("keyboard", None))

    body = client(token).post(
        f"/sessions/{SID}/audio?seconds=4.25",
        files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")},
    ).json()

    named = [stage["name"] for stage in body["timings"]]
    assert named == ["session", "read", "write", "hints", "handoff", "utt", "answer",
                     "filters", "deliver", "total"]
    assert dict(zip(named, [s["ms"] for s in body["timings"]]))["utt"] == 900.0
    # And the same numbers again on disk, keyed rather than ordered, one line per clip.
    line = json.loads((config.data_dir() / "timings.jsonl").read_text().splitlines()[-1])
    assert line["bytes"] == 64
    assert line["seconds"] == 4.25
    assert line["chars"] == len("how long did that take")
    assert line["delivered"] is True
    assert line["ms"]["utt"] == 900.0


def test_a_key_utt_gains_rides_through_to_the_phone(token, monkeypatch):
    """`raw`, `stages` and `cleanupSkipped` do not exist on utt's jobs lane today. Nothing here
    fabricates them; the day utt sends them they arrive with no change on this side."""
    monkeypatch.setattr(transcribe_module, "transcribe",
                        lambda clip, hints: transcribe_module.Heard(
                            text="ship it",
                            extra={"raw": "ship it,", "stages": ["cleanup"]}))
    body = client(token).post(
        f"/sessions/{SID}/audio?deliver=false",
        files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")},
    ).json()

    assert body["raw"] == "ship it,"
    assert body["stages"] == ["cleanup"]
    # And never over the top of a key of ours: `timings` is the daemon's, whatever utt calls its.
    assert [stage["name"] for stage in body["timings"]][-1] == "total"


def test_utts_own_stages_nest_inside_the_span_they_belong_to(token, monkeypatch):
    """utt calls its per-stage breakdown `timings`, and so do we.

    Ours is the whole path and utt's is the inside of one stage of it, so utt's is nested rather
    than merged — the old pass-through would have dropped it in silence, which is the one
    failure nobody would ever have noticed.
    """
    monkeypatch.setattr(transcribe_module, "transcribe",
                        lambda clip, hints: transcribe_module.Heard(
                            text="ship it",
                            stages={"handoff": 1.0, "utt": 3000.0, "answer": 0.2},
                            extra={"raw": "ship it", "stages": ["hints"], "duration": 2.4,
                                   "timings": {"cleanup": 900.0, "decode": 1300.0}}))

    body = client(token).post(
        f"/sessions/{SID}/audio?deliver=false",
        files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")},
    ).json()

    span = next(s for s in body["timings"] if s["name"] == "utt")
    # Pipeline order, not the dict's: decode first, then the text stages. And the wait in front
    # of them is what the span cost minus everything utt accounted for.
    assert [part["name"] for part in span["inside"]] == ["waiting", "decode", "cleanup"]
    assert span["inside"][0]["ms"] == 800.0
    # utt's own `timings` never appears at the top level, where it would be read as ours.
    assert all(isinstance(stage["ms"], float) for stage in body["timings"])
    assert body["raw"] == "ship it"
    assert body["duration"] == 2.4


def test_a_utt_that_measures_nothing_leaves_the_span_whole(token, monkeypatch):
    """Every utt shipped today. The span stays the single number it has always been."""
    monkeypatch.setattr(transcribe_module, "transcribe",
                        lambda clip, hints: transcribe_module.Heard(
                            text="ship it", stages={"utt": 3000.0}))

    body = client(token).post(
        f"/sessions/{SID}/audio?deliver=false",
        files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")},
    ).json()

    assert "inside" not in next(s for s in body["timings"] if s["name"] == "utt")


def test_say_puts_the_words_in_and_names_the_route(token, monkeypatch):
    seen = {}

    def deliver(session, text, route):
        seen.update(text=text, route=route)
        return "keyboard", None

    monkeypatch.setattr(deliver_module, "deliver", deliver)
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
        deliver_module, "deliver",
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
        deliver_module, "deliver",
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


def test_a_prompt_still_lands_on_a_session_that_was_cleared(token, claude_home, monkeypatch):
    """The symptom this fixes: hold to talk on a page opened before a `/clear` and the words go
    nowhere, with nothing on the phone changed to explain why — same name, same pane, same row."""
    sent = []
    monkeypatch.setattr(deliver_module, "deliver",
                        lambda session, *a, **k: sent.append(session.session_id) or ("socket", None))
    c = client(token)
    assert c.post(f"/sessions/{SID}/say", json={"text": "before"}).status_code == 200

    record = claude_home / "sessions" / "4242.json"
    rec = json.loads(record.read_text())
    rec["sessionId"] = "dddd1111-2222-3333-4444-555566667777"
    record.write_text(json.dumps(rec))

    answer = c.post(f"/sessions/{SID}/say", json={"text": "after"})
    assert answer.status_code == 200, "the id the phone is holding is the one it opened the page with"
    assert sent == [SID, "dddd1111-2222-3333-4444-555566667777"]
