"""The three endpoints, and what reaches the session when the person answers.

A separate file from `test_store.py` because these go through the app: the token, the 404s, and
the relay are the daemon's behaviour rather than the store's.
"""

import json

import pytest
from fastapi.testclient import TestClient

from deckhand_daemon import deliver as deliver_module
from deckhand_daemon import plugin
from deckhand_daemon.app import app

SID = "aaaa1111-2222-3333-4444-555566667777"


def client(token):
    c = TestClient(app)
    c.headers["x-deckhand-token"] = token
    return c


@pytest.fixture
def taken(monkeypatch):
    """Every delivery, as `deliver.deliver` was asked to make it. Nothing reaches a real session."""
    seen = []
    monkeypatch.setattr(
        deliver_module, "deliver",
        lambda session, text, route: (seen.append((text, route)), ("keyboard", None))[1],
    )
    return seen


def test_the_phone_is_told_what_the_project_is_asking(token, asking):
    answer = client(token).get(f"/sessions/{SID}/artifacts").json()

    assert [(a["id"], a["title"], a["answered"]) for a in answer["artifacts"]] == [
        ("which-branch", "Which branch?", False)
    ]


def test_a_project_with_nothing_to_ask_answers_with_an_empty_list(token, project):
    assert client(token).get(f"/sessions/{SID}/artifacts").json() == {"artifacts": []}


def test_the_page_is_served_as_html(token, asking):
    answer = client(token).get(f"/sessions/{SID}/artifacts/which-branch")

    assert answer.status_code == 200
    assert answer.headers["content-type"].startswith("text/html")
    assert answer.text == asking.read_text()


def test_a_page_that_is_not_there_is_a_404(token, asking):
    assert client(token).get(f"/sessions/{SID}/artifacts/never-written").status_code == 404


def test_an_id_that_is_a_path_never_serves_a_file(token, asking):
    """Over HTTP as well as in the store: percent-encoded, dotted, or with a separator in it."""
    c = client(token)
    for climbing in ["..%2F..%2F..%2Fetc%2Fpasswd", "..", "%2Fetc%2Fpasswd", "which-branch%2F.."]:
        assert c.get(f"/sessions/{SID}/artifacts/{climbing}").status_code == 404, climbing
        assert c.post(
            f"/sessions/{SID}/artifacts/{climbing}/answer", json={"value": "yes"}
        ).status_code == 404, climbing


def test_artifacts_need_the_token_like_everything_else(asking):
    anon = TestClient(app)
    assert anon.get(f"/sessions/{SID}/artifacts").status_code == 401
    assert anon.get(f"/sessions/{SID}/artifacts/which-branch").status_code == 401
    assert anon.post(
        f"/sessions/{SID}/artifacts/which-branch/answer", json={"value": "develop"}
    ).status_code == 401


def test_an_answer_is_written_down_and_the_session_is_told(token, asking, taken):
    answer = client(token).post(
        f"/sessions/{SID}/artifacts/which-branch/answer",
        json={"value": {"branch": "develop", "tag": True}},
    ).json()

    beside = asking.parent / "which-branch.answer.json"
    assert json.loads(beside.read_text())["value"] == {"branch": "develop", "tag": True}
    assert answer["answer"]["file"] == str(beside)
    assert answer["delivered"] is True
    assert answer["delivered_by"] == "keyboard"
    said, _ = taken[0]
    # Names the page, carries the answer, and says where the whole of it is.
    assert "which-branch" in said
    assert '{"branch": "develop", "tag": true}' in said
    assert str(beside) in said


def test_a_long_answer_travels_short_and_whole_in_the_file(token, asking, taken):
    essay = "because " * 100
    client(token).post(
        f"/sessions/{SID}/artifacts/which-branch/answer", json={"value": essay}
    )

    said, _ = taken[0]
    assert "…" in said
    assert len(said) < len(essay)
    assert json.loads((asking.parent / "which-branch.answer.json").read_text())["value"] == essay


def test_the_answer_goes_by_the_route_the_person_chose(token, asking, taken, monkeypatch):
    """The answer is theirs, so it travels as theirs: the socket would stamp it as an agent's."""
    monkeypatch.setattr(plugin, "route", lambda: "keyboard")
    c = client(token)

    c.post(f"/sessions/{SID}/artifacts/which-branch/answer", json={"value": "develop"})
    c.post(f"/sessions/{SID}/artifacts/which-branch/answer?route=socket", json={"value": "main"})

    assert [route for _, route in taken] == ["keyboard", "socket"]


def test_a_delivery_that_fails_does_not_lose_the_answer(token, asking, monkeypatch):
    """The file is written first on purpose: a session with no pane left is not a lost answer."""
    monkeypatch.setattr(
        deliver_module, "deliver", lambda session, text, route: (None, "warm-okapi has no pane"))

    answer = client(token).post(
        f"/sessions/{SID}/artifacts/which-branch/answer", json={"value": "develop"}).json()

    assert answer["delivered"] is False
    assert answer["delivery_error"] == "warm-okapi has no pane"
    written = json.loads((asking.parent / "which-branch.answer.json").read_text())
    assert written["value"] == "develop"


def test_an_answer_to_a_page_that_is_not_there_is_a_404(token, asking, taken):
    answer = client(token).post(
        f"/sessions/{SID}/artifacts/never-written/answer", json={"value": "yes"})

    assert answer.status_code == 404
    assert taken == []


def test_any_json_value_is_an_answer_including_a_falsy_one(token, asking, taken):
    """A confirm returns a bool, a pick a string, a form an object, sliders an array of numbers.

    `false`, `0` and `""` are answers like any other, which is why nothing here tests the value
    for truth. A body with no `value` in it is not an answer and is refused: FastAPI cannot tell
    a missing field from an explicit `null`, so an empty body and `{"value": null}` are the same
    request to it, and accepting either would write an answer nobody gave.
    """
    c = client(token)
    for value in [True, False, 0, "", "develop", 3, ["a", "b"], {"q1": "yes", "q2": [1, 2]}]:
        c.post(f"/sessions/{SID}/artifacts/which-branch/answer", json={"value": value})
        kept = json.loads((asking.parent / "which-branch.answer.json").read_text())
        assert kept["value"] == value, value

    assert c.post(f"/sessions/{SID}/artifacts/which-branch/answer", json={}).status_code == 422
