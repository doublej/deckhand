"""The two filter endpoints, and what the delivering endpoints do with a chain.

Beside the filter tests rather than in `test_api.py`, which is at its size target.
"""

from fastapi.testclient import TestClient

from deckhand_daemon import app as app_module
from deckhand_daemon import filters
from deckhand_daemon.app import app

SID = "aaaa1111-2222-3333-4444-555566667777"


def client(token):
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    return c


def test_the_phone_is_told_what_filters_exist_and_what_it_saved(token):
    c = client(token)
    offered = c.get("/filters").json()
    assert "words" in [f["name"] for f in offered["known"]]
    assert offered["steps"] == []

    chain = [{"filter": "words", "settings": {"pairs": [["deck hand", "deckhand"]]}}]
    saved = c.put("/filters", json={"steps": chain}).json()["steps"]

    assert saved == [{"filter": "words", "on": True, "settings": {"pairs": [["deck hand", "deckhand"]]}}]
    assert c.get("/filters").json()["steps"] == saved


def test_a_chain_naming_a_filter_that_does_not_exist_is_refused(token):
    answer = client(token).put("/filters", json={"steps": [{"filter": "translate"}]})

    assert answer.status_code == 400
    assert "translate" in answer.json()["detail"]
    # Nothing was written: a chain is saved whole or not at all.
    assert client(token).get("/filters").json()["steps"] == []


def test_filters_need_the_token_like_everything_else(claude_home):
    anon = TestClient(app)
    assert anon.get("/filters").status_code == 401
    assert anon.put("/filters", json={"steps": []}).status_code == 401


def test_the_words_that_reach_a_session_are_the_filtered_ones(token, monkeypatch):
    seen = {}
    monkeypatch.setattr(
        app_module.deliver, "deliver",
        lambda session, text, route: (seen.update(text=text), ("keyboard", None))[1],
    )
    c = client(token)
    c.put("/filters", json={"steps": [
        {"filter": "words", "settings": {"pairs": [["deck hand", "deckhand"]]}}]})

    answer = c.post(f"/sessions/{SID}/say", json={"text": "the deck hand is broken"}).json()

    assert seen["text"] == "the deckhand is broken"
    assert answer["notes"] == ['swapped "deck hand" for "deckhand"']
    assert answer["stopped_by"] is None


def test_a_stopped_prompt_never_reaches_the_session(token, monkeypatch):
    """It is refused, and the phone is told by whom and why — not left to guess."""
    delivered = []
    monkeypatch.setattr(app_module.deliver, "deliver", lambda *a: delivered.append(a))
    monkeypatch.setitem(
        filters.registry._known, "gate",
        filters.Filter(name="gate", title="gate", summary="gate",
                       apply=lambda p, s: filters.Verdict(note="already logged as #12", stop=True)),
    )
    c = client(token)
    c.put("/filters", json={"steps": [{"filter": "gate"}]})

    answer = c.post(f"/sessions/{SID}/say", json={"text": "log the crash"}).json()

    assert delivered == []
    assert answer["delivered"] is False
    assert answer["stopped_by"] == "gate"
    assert answer["delivery_error"] == "already logged as #12"


def test_a_filter_is_told_which_session_and_how_the_words_arrived(token, monkeypatch):
    """A slip of the tongue and a slip of the finger are not the same mistake, so `source` says."""
    monkeypatch.setattr(app_module.transcribe, "transcribe", lambda clip, hints: ("spoken", None))
    monkeypatch.setattr(app_module.deliver, "deliver", lambda *a: ("socket", None))
    seen = []
    monkeypatch.setitem(
        filters.registry._known, "probe",
        filters.Filter(name="probe", title="probe", summary="probe",
                       apply=lambda p, s: seen.append(p) or filters.Verdict()),
    )
    c = client(token)
    c.put("/filters", json={"steps": [{"filter": "probe"}]})

    c.post(f"/sessions/{SID}/audio", files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")})
    c.post(f"/sessions/{SID}/say?route=socket", json={"text": "typed"})

    assert [(p.text, p.source, p.route) for p in seen] == [
        ("spoken", "spoken", "auto"), ("typed", "typed", "socket")]
    assert (seen[0].session_id, seen[0].session_name) == (SID, "warm-okapi")


def test_a_clip_is_filtered_too_and_the_transcript_still_says_what_was_heard(token, monkeypatch):
    monkeypatch.setattr(
        app_module.transcribe, "transcribe", lambda clip, hints: ("the deck hand", None))
    seen = {}
    monkeypatch.setattr(
        app_module.deliver, "deliver",
        lambda session, text, route: (seen.update(text=text), ("socket", None))[1],
    )
    c = client(token)
    c.put("/filters", json={"steps": [
        {"filter": "words", "settings": {"pairs": [["deck hand", "deckhand"]]}}]})

    body = c.post(
        f"/sessions/{SID}/audio", files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")}
    ).json()

    assert seen["text"] == "the deckhand"
    assert body["transcript"] == "the deck hand"
    assert body["notes"] == ['swapped "deck hand" for "deckhand"']
