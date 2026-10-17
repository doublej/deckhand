from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon import artifacts, config, push, sessions
from deckhand_daemon.app import app
from deckhand_daemon.tray import feed, routes, shapes

DEMOS = Path(__file__).parents[3] / "demos"


@pytest.fixture(autouse=True)
def data(monkeypatch, tmp_path):
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))
    (tmp_path / "data").mkdir()
    for held in ("_slips", "_open", "_done", "_said", "_blocked"):
        monkeypatch.setattr(push, held, {})
    monkeypatch.setattr(push, "show", lambda card, mac, loud=True: None)
    monkeypatch.setattr(push, "end", lambda sid: None)


def one(tmp_path, monkeypatch):
    session = sessions.Session(session_id="one", pid=0, name="one", cwd=str(tmp_path), status="idle",
                               updated_at=0.0, tty="", pane=None, machine="m2")
    monkeypatch.setattr(sessions, "live_sessions", lambda paned_only=True: [session])
    return session


def slip(session, name: str, page: str) -> None:
    folder = artifacts.folder(session)
    (folder / f"{name}.html").write_text(page)


# --- a slip's shape, read off the pages slip.py writes ----------------------------------------

def test_every_demo_page_reads_as_its_own_kind():
    read = {name: shapes.ask((DEMOS / f"{name}.html").read_text())
            for name in ("confirm", "pick", "text", "aloud", "form")}
    assert read["confirm"] == {"kind": "confirm", "accept": "Tag and push", "decline": "Not yet"}
    assert read["pick"] == {"kind": "pick", "options": ["develop", "main", "feature/artifacts"],
                            "other": True}
    assert read["text"]["kind"] == "text"
    assert read["aloud"] == {"kind": "aloud"}
    assert read["form"]["kind"] == "page", "a form is never guessed at"


def test_an_answer_is_said_in_the_words_on_the_button():
    shape = {"kind": "confirm", "accept": "Tag and push", "decline": "Not yet"}
    assert shapes.said({"answer": True}, shape) == "Tag and push"
    assert shapes.said({"answer": False}, {"kind": "page"}) == "No"
    assert shapes.said({"answer": "main"}, {"kind": "pick"}) == "main"
    assert shapes.said({"answer": {"scope": "all of it"}}, {"kind": "aloud"}) == "all of it"


# --- the feed, written by the sweep ------------------------------------------------------------

def test_answering_a_slip_is_an_update_and_withdrawing_one_is_not(tmp_path, monkeypatch):
    session = one(tmp_path, monkeypatch)
    page = (DEMOS / "confirm.html").read_text()
    slip(session, "ship", page)
    slip(session, "gone", page)
    push.sweep()
    artifacts.answer(session, "ship", {"answer": True})
    (artifacts.folder(session) / "gone.html").unlink()
    push.sweep()
    updates = feed.after(0)
    assert [(u["kind"], u["slip"], u["answer"]) for u in updates] == [
        ("answered", "ship", "Tag and push")]


def test_each_ask_done_is_an_update_and_the_list_clearing_is_one_more(tmp_path, monkeypatch):
    one(tmp_path, monkeypatch)
    book = {"tasks": [{"id": "a", "text": "fix it", "state": "todo"},
                      {"id": "b", "text": "test it", "state": "done"}]}
    monkeypatch.setattr(push.tasks, "load", lambda sid: book["tasks"])
    push.sweep()
    book["tasks"] = [{**book["tasks"][0], "state": "done"}, book["tasks"][1]]
    push.sweep()
    assert [(u["kind"], u.get("ask"), u.get("asks")) for u in feed.after(0)] == [
        ("done", "fix it", None), ("finished", None, ["fix it", "test it"])]


def test_a_call_is_an_update_and_a_line_still_waiting(tmp_path, monkeypatch):
    session = one(tmp_path, monkeypatch)
    push.called(session, "need a  decision on the schema")
    assert feed.after(0)[0]["line"] == "need a decision on the schema"
    assert push.waiting_lines() == {"one": "need a decision on the schema"}


def test_the_feed_is_read_by_cursor_and_kept_short(tmp_path, monkeypatch):
    session = one(tmp_path, monkeypatch)
    monkeypatch.setattr(feed, "KEPT", 3)
    for n in range(5):
        feed.add("called", session, line=str(n))
    assert [u["line"] for u in feed.after(0)] == ["2", "3", "4"]
    assert [u["line"] for u in feed.after(4)] == ["4"]
    assert feed.newest() == 5


# --- the route ---------------------------------------------------------------------------------

def test_the_tray_is_every_open_slip_with_its_shape_and_the_feed(tmp_path, monkeypatch):
    session = one(tmp_path, monkeypatch)
    slip(session, "which", (DEMOS / "pick.html").read_text())
    push.called(session, "look at this")

    async def nobody(method, path, **kwargs):
        return {}

    monkeypatch.setattr(routes.proxy, "every", nobody)
    client = TestClient(app)
    body = client.get("/tray", headers={config.TOKEN_HEADER: config.token()}).json()
    (row,) = body["open"]
    assert row["waiting"] == "look at this" and row["machine"] == "m2"
    assert row["slips"][0]["ask"]["kind"] == "pick"
    assert [u["kind"] for u in body["updates"]] == ["called"]
    assert body["newest"] == 1
    assert client.get("/tray?since=1", headers={config.TOKEN_HEADER: config.token()}
                      ).json()["updates"] == []
