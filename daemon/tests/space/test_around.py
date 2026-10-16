"""A session's own view of the space, telling it what the person gave it, and starting one beside it."""

from __future__ import annotations

import pytest

from deckhand_daemon.space import around, routes, stored

LIVE = "aaaa1111-2222-3333-4444-555566667777"
OTHER = "bbbb1111-2222-3333-4444-555566667777"


def _row(sid: str, group: str, name: str = "s") -> dict:
    return {"session_id": sid, "name": name, "cwd": "/x", "project": {"group": group}}


def _plane(pid: str, near: str | None = None, by: str | None = None) -> dict:
    return {"id": pid, "kind": "web", "url": "https://a.com", "window": None, "title": "a.com",
            "near": near, "by": by}


def test_only_a_kept_pose_puts_a_terminal_in_a_group():
    rows = [_row("a", "proj-1"), _row("b", "proj-1"), _row("c", "proj-2")]
    kept = {"planes": [], "poses": {}}
    assert around.around(kept, rows, "a")["group"] is None  # one project is not a group
    assert around.around(kept, rows, "a")["beside"] == []
    for sid in ("a", "c"):
        kept["poses"][f"session:{sid}"] = {"x": 0, "y": 0, "z": 0, "yaw": 0, "group": "g1"}
    seen = around.around(kept, rows, "a")
    assert seen["group"] == "g1" and [b["session"] for b in seen["beside"]] == ["c"]


def test_a_page_is_beside_you_when_near_you_or_in_your_group():
    rows = [_row("a", "proj-1"), _row("b", "proj-1")]
    pose = {"x": 0, "y": 0, "z": 0, "yaw": 0, "group": "g1"}
    kept = {"planes": [_plane("p1", near="a"), _plane("p2", near="b"), _plane("p3")],
            "poses": {"session:a": pose, "session:b": pose, "plane:p3": pose}}
    beside = {b.get("plane") for b in around.around(kept, rows, "a")["beside"]} - {None}
    assert beside == {"p1", "p2", "p3"}


@pytest.fixture
def told(monkeypatch):
    heard: list[tuple[str, str]] = []
    monkeypatch.setattr(around, "tell", lambda session, plane: heard.append((session.session_id,
                                                                              plane["id"])))
    return heard


def test_a_page_the_person_opens_near_a_session_is_told_to_it(client, head, told):
    mine = client.post("/space/planes", json={"kind": "web", "url": "https://a.com", "near": LIVE},
                       headers=head).json()
    assert told == [(LIVE, mine["id"])]
    client.post("/space/planes", json={"kind": "web", "url": "https://b.com", "near": LIVE,
                                       "by": "warm-okapi"}, headers=head)
    assert len(told) == 1  # an agent's own page is not news to it


@pytest.fixture
def lost(monkeypatch):
    heard: list[tuple] = []
    monkeypatch.setattr(around, "taken", lambda session, plane, how, to="": heard.append(
        (session.session_id, plane["id"], how, to)))
    return heard


def test_handing_a_page_to_another_session_tells_that_one_once(client, head, told, lost):
    plane = client.post("/space/planes", json={"kind": "web", "url": "https://a.com"},
                        headers=head).json()
    given = f"/space/planes/{plane['id']}/near"
    assert client.put(given, json={"near": OTHER}, headers=head).status_code == 204
    assert client.put(given, json={"near": OTHER}, headers=head).status_code == 204
    assert told == [(OTHER, plane["id"])]
    assert lost == []  # it stood beside nobody before
    assert client.get("/space", headers=head).json()["planes"][0]["near"] == OTHER
    assert client.put(given, json={"near": None}, headers=head).status_code == 204
    assert client.put("/space/planes/nope/near", json={}, headers=head).status_code == 404


def test_the_session_a_page_leaves_is_told_where_it_went(client, head, told, lost):
    plane = client.post("/space/planes", json={"kind": "web", "url": "https://a.com", "near": LIVE},
                        headers=head).json()
    given = f"/space/planes/{plane['id']}/near"
    client.put(given, json={"near": OTHER}, headers=head)
    assert lost == [(LIVE, plane["id"], "handed", "cold-otter")]
    client.put(given, json={"near": None}, headers=head)
    client.put(given, json={"near": None}, headers=head)  # nowhere to nowhere: nothing to tell
    assert lost[1:] == [(OTHER, plane["id"], "loose", "")]


def test_closing_a_page_tells_its_session_unless_an_agent_closed_it(client, head, told, lost):
    def opened(url: str, near: str | None = LIVE) -> str:
        return client.post("/space/planes", json={"kind": "web", "url": url, "near": near},
                           headers=head).json()["id"]

    mine, its, nobodys = opened("https://a.com"), opened("https://b.com"), opened("https://c", None)
    assert client.delete(f"/space/planes/{mine}", headers=head).status_code == 204
    assert lost == [(LIVE, mine, "closed", "")]
    closed = client.delete(f"/space/planes/{its}", params={"by": "warm-okapi"}, headers=head)
    assert closed.status_code == 204
    assert client.delete(f"/space/planes/{nobodys}", headers=head).status_code == 204
    assert len(lost) == 1
    assert client.delete(f"/space/planes/{mine}", headers=head).status_code == 404


def test_a_page_beside_a_session_that_has_gone_is_closed_without_telling_anyone(client, head,
                                                                                lost):
    plane, _ = stored.add(_plane("p1", near="gone-1111"))
    assert client.delete(f"/space/planes/{plane['id']}", headers=head).status_code == 204
    assert lost == [] and stored.space()["planes"] == []


def test_taken_goes_down_the_socket_and_says_what_became_of_it(monkeypatch):
    sent: list[tuple[str, str]] = []
    monkeypatch.setattr(around.deliver, "deliver",
                        lambda session, text, route: sent.append((text, route)) or (None, "gone"))
    session = type("S", (), {"name": "warm-okapi"})()
    around.taken(session, _plane("p1"), "handed", "cold-otter")  # a failure is logged, not raised
    around.taken(session, _plane("p2"), "closed")
    (handed, route), (closed, _) = sent
    assert route == "socket" and "a.com (https://a.com)" in handed and "p1" in handed
    assert "handed it to the session cold-otter" in handed and "he closed it" in closed
    assert "{" not in handed + closed


def test_a_session_sees_its_group_over_the_wire(client, head):
    assert client.get(f"/sessions/{LIVE}/space", headers=head).json()["group"] is None
    pose = {"x": 0, "y": 0, "z": 0, "yaw": 0, "group": "g1"}
    for sid in (LIVE, OTHER):
        client.put(f"/space/poses/session:{sid}", json=pose, headers=head)
    seen = client.get(f"/sessions/{LIVE}/space", headers=head).json()
    assert seen["group"] == "g1" and [b["session"] for b in seen["beside"]] == [OTHER]


def test_a_session_started_beside_another_stands_beside_it(client, head, monkeypatch, tmp_path):
    asked: list[str] = []

    async def start(path, provider="claude"):
        asked.append(path)
        return {"session": {"session_id": "new-one", "cwd": path}}

    monkeypatch.setattr(routes.projects, "start_project_session", start)
    monkeypatch.setattr(routes, "catalog", lambda: ([], {}))
    monkeypatch.setattr(routes.project, "root", lambda path: "/Users/jj/dev/web/shop")
    made = client.post("/space/sessions", json={"near": LIVE, "path": "/Users/jj/dev/web/shop/src"},
                       headers=head)
    assert made.status_code == 201 and made.json()["session_id"] == "new-one"
    assert asked == ["/Users/jj/dev/web/shop"]  # a subfolder is taken as its repo
    assert stored.space()["beside"] == {"new-one": LIVE}
    assert client.post("/space/sessions", json={"path": "/x"}, headers=head).status_code == 400
    relative = client.post("/space/sessions", json={"near": LIVE, "path": "shop"}, headers=head)
    assert relative.status_code == 400
    gone = client.post("/space/sessions", json={"near": "no-such", "path": "/x"}, headers=head)
    assert gone.status_code == 404


def test_telling_goes_down_the_socket_and_names_the_page(monkeypatch):
    sent: list[tuple[str, str]] = []
    monkeypatch.setattr(around.deliver, "deliver",
                        lambda session, text, route: sent.append((text, route)) or (route, None))
    session = type("S", (), {"name": "warm-okapi"})()
    around.tell(session, _plane("p1"))
    text, route = sent[0]
    assert route == "socket" and "a.com (https://a.com)" in text and "p1" in text


def test_opening_what_is_already_beside_a_session_hands_back_that_plane(client, head, told):
    sent = {"kind": "web", "url": "https://a.com", "near": LIVE, "by": "warm-okapi"}
    first = client.post("/space/planes", json=sent, headers=head)
    again = client.post("/space/planes", json=sent, headers=head)
    assert first.status_code == 201 and again.status_code == 200
    assert again.json() == first.json() | {"reused": True}
    assert len(client.get("/space", headers=head).json()["planes"]) == 1
    elsewhere = client.post("/space/planes", json=sent | {"near": OTHER}, headers=head)
    assert elsewhere.status_code == 201  # the same page beside another session is another plane


def test_a_pose_keeps_minimized_only_while_it_is(client, head):
    pose = {"x": 0, "y": 1, "z": 1, "yaw": 0}
    assert client.put("/space/poses/manager", json=pose | {"minimized": True},
                      headers=head).status_code == 204
    assert client.get("/space", headers=head).json()["poses"]["manager"]["minimized"] is True
    client.put("/space/poses/manager", json=pose | {"minimized": False}, headers=head)
    assert "minimized" not in client.get("/space", headers=head).json()["poses"]["manager"]
    client.put("/space/poses/manager", json=pose | {"minimized": "group"}, headers=head)
    assert client.get("/space", headers=head).json()["poses"]["manager"]["minimized"] == "group"
    for bad in ("yes", 1):
        refused = client.put("/space/poses/manager", json=pose | {"minimized": bad}, headers=head)
        assert refused.status_code == 400


def test_a_pose_keeps_its_pin_and_a_pose_without_one_is_free(client, head):
    pose = {"x": 0, "y": 1, "z": 1, "yaw": 0}
    for pin in ("fixed", "slide"):
        assert client.put("/space/poses/manager", json=pose | {"pin": pin}, headers=head).status_code == 204
        assert client.get("/space", headers=head).json()["poses"]["manager"]["pin"] == pin
    client.put("/space/poses/manager", json=pose, headers=head)  # a PUT is the whole pose: no pin is free
    assert "pin" not in client.get("/space", headers=head).json()["poses"]["manager"]
    for bad in ("yes", True, 1):
        assert client.put("/space/poses/manager", json=pose | {"pin": bad}, headers=head).status_code == 400
