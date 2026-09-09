"""The two filter endpoints, and what the delivering endpoints do with a chain.

Beside the filter tests rather than in `test_api.py`, which is at its size target.
"""

from fastapi.testclient import TestClient

from deckhand_daemon import deliver as deliver_module
from deckhand_daemon import filters
from deckhand_daemon import transcribe as transcribe_module
from deckhand_daemon.app import app

SID = "aaaa1111-2222-3333-4444-555566667777"


def client(token):
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    return c


OTHER = "bbbb1111-2222-3333-4444-555566667777"


def test_what_this_mac_can_do_is_global_and_carries_no_chain(token):
    """A filter is what the Mac has; a chain is what one terminal does with it."""
    offered = client(token).get("/filters").json()

    assert "words" in [f["name"] for f in offered["known"]]
    assert "steps" not in offered


def test_one_terminals_chain_round_trips(token):
    c = client(token)
    assert c.get(f"/sessions/{SID}/filters").json() == {
        "session": "warm-okapi", "known": c.get("/filters").json()["known"], "steps": []}

    chain = [{"filter": "words", "settings": {"pairs": [["deck hand", "deckhand"]]}}]
    saved = c.put(f"/sessions/{SID}/filters", json={"steps": chain}).json()

    assert saved == {"session": "warm-okapi", "steps": [
        {"filter": "words", "on": True, "settings": {"pairs": [["deck hand", "deckhand"]]}}]}
    assert c.get(f"/sessions/{SID}/filters").json()["steps"] == saved["steps"]
    # And it is that terminal's alone.
    assert c.get(f"/sessions/{OTHER}/filters").json()["steps"] == []


def test_a_chain_naming_a_filter_that_does_not_exist_is_refused(token):
    c = client(token)
    answer = c.put(f"/sessions/{SID}/filters", json={"steps": [{"filter": "translate"}]})

    assert answer.status_code == 400
    assert "translate" in answer.json()["detail"]
    # Nothing was written: a chain is saved whole or not at all.
    assert c.get(f"/sessions/{SID}/filters").json()["steps"] == []


def test_a_terminal_that_is_not_running_has_no_chain_to_read_or_set(token):
    """Per-session like every other per-session route, and the id is the only handle there is."""
    dead = "cccc1111-2222-3333-4444-555566667777"
    c = client(token)

    assert c.get(f"/sessions/{dead}/filters").status_code == 404
    assert c.put(f"/sessions/{dead}/filters", json={"steps": []}).status_code == 404


def test_filters_need_the_token_like_everything_else(claude_home):
    anon = TestClient(app)
    assert anon.get("/filters").status_code == 401
    assert anon.get(f"/sessions/{SID}/filters").status_code == 401
    assert anon.put(f"/sessions/{SID}/filters", json={"steps": []}).status_code == 401


def test_a_rename_carries_the_chain_onto_the_new_name(token, monkeypatch):
    """A chain that vanished on /rename would be the same bug as a star that did."""
    monkeypatch.setattr(deliver_module, "rename", lambda session, name: None)
    c = client(token)
    c.put(f"/sessions/{SID}/filters", json={"steps": [{"filter": "words"}]})

    answer = c.post(f"/sessions/{SID}/name", json={"name": "bright-heron"}).json()

    assert answer == {"renamed": "bright-heron", "was": "warm-okapi", "carried_filters": True}
    assert filters.load("bright-heron") == [{"filter": "words", "on": True, "settings": {}}]
    assert filters.load("warm-okapi") == []


def test_the_words_that_reach_a_session_are_the_filtered_ones(token, monkeypatch):
    seen = {}
    monkeypatch.setattr(
        deliver_module, "deliver",
        lambda session, text, route: (seen.update(text=text), ("keyboard", None))[1],
    )
    c = client(token)
    c.put(f"/sessions/{SID}/filters", json={"steps": [
        {"filter": "words", "settings": {"pairs": [["deck hand", "deckhand"]]}}]})

    answer = c.post(f"/sessions/{SID}/say", json={"text": "the deck hand is broken"}).json()

    assert seen["text"] == "the deckhand is broken"
    assert answer["notes"] == ['swapped "deck hand" for "deckhand"']
    assert answer["stopped_by"] is None


def test_a_stopped_prompt_never_reaches_the_session(token, monkeypatch):
    """It is refused, and the phone is told by whom and why — not left to guess."""
    delivered = []
    monkeypatch.setattr(deliver_module, "deliver", lambda *a: delivered.append(a))
    monkeypatch.setitem(
        filters.registry._known, "gate",
        filters.Filter(name="gate", title="gate", summary="gate",
                       apply=lambda p, s: filters.Verdict(note="already logged as #12", stop=True)),
    )
    c = client(token)
    c.put(f"/sessions/{SID}/filters", json={"steps": [{"filter": "gate"}]})

    answer = c.post(f"/sessions/{SID}/say", json={"text": "log the crash"}).json()

    assert delivered == []
    assert answer["delivered"] is False
    assert answer["stopped_by"] == "gate"
    assert answer["delivery_error"] == "already logged as #12"


def test_a_filter_is_told_which_session_and_how_the_words_arrived(token, monkeypatch):
    """A slip of the tongue and a slip of the finger are not the same mistake, so `source` says."""
    monkeypatch.setattr(transcribe_module, "transcribe", lambda clip, hints: ("spoken", None))
    monkeypatch.setattr(deliver_module, "deliver", lambda *a: ("socket", None))
    seen = []
    monkeypatch.setitem(
        filters.registry._known, "probe",
        filters.Filter(name="probe", title="probe", summary="probe",
                       apply=lambda p, s: seen.append(p) or filters.Verdict()),
    )
    c = client(token)
    c.put(f"/sessions/{SID}/filters", json={"steps": [{"filter": "probe"}]})

    c.post(f"/sessions/{SID}/audio", files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")})
    c.post(f"/sessions/{SID}/say?route=socket", json={"text": "typed"})

    assert [(p.text, p.source, p.route) for p in seen] == [
        ("spoken", "spoken", "auto"), ("typed", "typed", "socket")]
    assert (seen[0].session_id, seen[0].session_name) == (SID, "warm-okapi")


def test_a_clip_read_first_shows_what_will_be_sent(token, monkeypatch):
    """The card has an Edit button, so it has to show the words that are actually going in."""
    monkeypatch.setattr(
        transcribe_module, "transcribe", lambda clip, hints: ("the deck hand is broken", None))
    delivered = []
    monkeypatch.setattr(deliver_module, "deliver", lambda *a: delivered.append(a))
    c = client(token)
    c.put(f"/sessions/{SID}/filters", json={"steps": [
        {"filter": "words", "settings": {"pairs": [["deck hand", "deckhand"]]}}]})

    body = c.post(
        f"/sessions/{SID}/audio?deliver=false", files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")}
    ).json()

    assert body["transcript"] == "the deck hand is broken"
    assert body["prepared"] == "the deckhand is broken"
    assert body["notes"] == ['swapped "deck hand" for "deckhand"']
    # Read first means read first: the preview is not a delivery.
    assert delivered == []
    assert body["delivered"] is False


def test_a_chain_that_changed_nothing_prepares_nothing(token, monkeypatch):
    """Null rather than a copy, so the card shows the transcript it already has."""
    monkeypatch.setattr(transcribe_module, "transcribe", lambda clip, hints: ("nothing to fix", None))
    body = client(token).post(
        f"/sessions/{SID}/audio?deliver=false", files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")}
    ).json()

    assert body["transcript"] == "nothing to fix"
    assert body["prepared"] is None


def test_a_clip_utt_could_not_hear_prepares_nothing(token, monkeypatch):
    monkeypatch.setattr(transcribe_module, "transcribe", lambda clip, hints: (None, "utt is off"))
    body = client(token).post(
        f"/sessions/{SID}/audio?deliver=false", files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")}
    ).json()

    assert (body["transcript"], body["prepared"]) == (None, None)


def test_a_clip_the_chain_will_refuse_says_so_before_it_is_sent(token, monkeypatch):
    """Better on the card than after pressing Send, and it costs nothing to say it here."""
    monkeypatch.setattr(transcribe_module, "transcribe", lambda clip, hints: ("log the crash", None))
    monkeypatch.setitem(
        filters.registry._known, "gate",
        filters.Filter(name="gate", title="gate", summary="gate",
                       apply=lambda p, s: filters.Verdict(note="already logged as #12", stop=True)),
    )
    c = client(token)
    c.put(f"/sessions/{SID}/filters", json={"steps": [{"filter": "gate"}]})

    body = c.post(
        f"/sessions/{SID}/audio?deliver=false", files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")}
    ).json()

    assert body["stopped_by"] == "gate"
    assert body["prepared"] is None


def test_a_clip_is_filtered_too_and_the_transcript_still_says_what_was_heard(token, monkeypatch):
    monkeypatch.setattr(
        transcribe_module, "transcribe", lambda clip, hints: ("the deck hand", None))
    seen = {}
    monkeypatch.setattr(
        deliver_module, "deliver",
        lambda session, text, route: (seen.update(text=text), ("socket", None))[1],
    )
    c = client(token)
    c.put(f"/sessions/{SID}/filters", json={"steps": [
        {"filter": "words", "settings": {"pairs": [["deck hand", "deckhand"]]}}]})

    body = c.post(
        f"/sessions/{SID}/audio", files={"file": ("clip.m4a", b"x" * 64, "audio/m4a")}
    ).json()

    assert seen["text"] == "the deckhand"
    assert body["transcript"] == "the deck hand"
    assert body["notes"] == ['swapped "deck hand" for "deckhand"']


def test_words_the_person_has_already_read_are_not_filtered_again(token, monkeypatch):
    """`prepared=true` is what the phone sends after the card has shown the prepared words.

    Not an optimisation. Prompt crafting rewrites rather than swaps, so running it on its own
    output rewrites a prompt twice — and changing anything after somebody has approved it on the
    card contradicts the card. Proved with the word filter because it is the one that is easy to
    see: the swap happens without the flag and does not happen with it.
    """
    seen = {}
    monkeypatch.setattr(
        deliver_module, "deliver",
        lambda session, text, route: (seen.update(text=text), ("keyboard", None))[1],
    )
    c = client(token)
    c.put(f"/sessions/{SID}/filters", json={"steps": [
        {"filter": "words", "settings": {"pairs": [["deck hand", "deckhand"]]}}]})

    c.post(f"/sessions/{SID}/say", json={"text": "the deck hand is here"})
    assert seen["text"] == "the deckhand is here"

    c.post(f"/sessions/{SID}/say?prepared=true", json={"text": "the deck hand is here"})
    assert seen["text"] == "the deck hand is here"
