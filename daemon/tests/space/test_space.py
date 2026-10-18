"""The space over the wire: opening a plane, closing it, and placing things."""

from __future__ import annotations

import json

import pytest

from deckhand_daemon import config
from deckhand_daemon.space import routes, stored, windows

LIVE = "aaaa1111-2222-3333-4444-555566667777"
LAN = "192.168.178.180"


def _open(client, head, **sent):
    return client.post("/space/planes", json=sent, headers=head)


def test_every_route_needs_the_token(client):
    assert client.get("/space").status_code == 401
    assert client.post("/space/planes", json={"kind": "web"}).status_code == 401
    assert client.delete("/space/planes/x").status_code == 401
    assert client.put("/space/poses/manager", json={}).status_code == 401
    assert client.get("/windows").status_code == 401
    assert client.get("/windows/1/frame").status_code == 401
    assert client.get("/windows/1/stream").status_code == 401


def test_an_empty_space_is_rev_zero(client, head):
    assert client.get("/space", headers=head).json() == {"rev": 0, "planes": [], "poses": {}}


def test_a_web_plane_is_kept_named_after_its_host(client, head):
    made = _open(
        client,
        head,
        kind="web",
        url="https://shop.atlas.local.jurrejan.com/cart",
        near=LIVE,
        by="warm-okapi",
        stray=1,
    )
    assert made.status_code == 201
    plane = made.json()
    assert set(plane) == {"id", "kind", "url", "window", "title", "near", "by", "at"}
    assert plane["title"] == "shop.atlas.local.jurrejan.com" and plane["window"] is None
    assert (plane["near"], plane["by"]) == (LIVE, "warm-okapi") and plane["at"].endswith("Z")
    space = client.get("/space", headers=head).json()
    assert space["rev"] == 1 and space["planes"] == [plane]


@pytest.mark.parametrize(
    "given,reached",
    [
        ("http://localhost:5173/a?b=1#c", f"http://{LAN}:5173/a?b=1#c"),
        ("http://LOCALHOST/", f"http://{LAN}/"),
        ("http://127.0.0.1:8000", f"http://{LAN}:8000"),
        ("http://0.0.0.0:3000/x", f"http://{LAN}:3000/x"),
        ("http://[::1]:4000/", f"http://{LAN}:4000/"),
        ("https://shop.atlas.local.jurrejan.com/", "https://shop.atlas.local.jurrejan.com/"),
        ("http://127.0.0.2/", "http://127.0.0.2/"),
    ],
)
def test_a_loopback_host_becomes_the_lan_address(given, reached):
    assert routes.reachable(given, LAN) == reached


def test_no_lan_address_leaves_the_url_alone():
    assert routes.reachable("http://localhost:5173/", "") == "http://localhost:5173/"


def test_localhost_is_rewritten_on_the_way_in(client, head):
    plane = _open(client, head, kind="web", url="http://localhost:5173/", title="Shop").json()
    assert plane["url"] == f"http://{LAN}:5173/" and plane["title"] == "Shop"
    assert plane["near"] is None and plane["by"] is None


@pytest.mark.parametrize(
    "sent",
    [
        {"kind": "session", "url": "https://a.com"},
        {"url": "https://a.com"},
        {"kind": "web"},
        {"kind": "web", "url": "ftp://a.com/"},
        {"kind": "web", "url": "https://"},
        {"kind": "web", "url": "http://localhost:port/"},
        {"kind": "web", "url": "https://a.com", "title": 3},
        {"kind": "window"},
        {"kind": "window", "window": "7"},
        {"kind": "window", "window": True},
        {"kind": "window", "window": 7.0},
    ],
)
def test_a_bad_plane_is_a_400_and_keeps_nothing(client, head, sent):
    answered = client.post("/space/planes", json=sent, headers=head)
    assert answered.status_code == 400 and answered.json()["detail"]
    assert client.get("/space", headers=head).json()["rev"] == 0


def test_near_must_be_a_live_session(client, head):
    gone = _open(client, head, kind="web", url="https://a.com", near="no-such-session")
    assert gone.status_code == 404
    assert client.get("/space", headers=head).json()["planes"] == []


def test_a_window_plane_takes_the_windows_title(client, head, monkeypatch):
    async def listed():
        return [
            {"id": 7, "app": "Safari", "title": "Docs", "w": 800, "h": 600},
            {"id": 8, "app": "Finder", "title": "", "w": 400, "h": 300},
        ]

    monkeypatch.setattr(windows, "listed", listed)
    plane = _open(client, head, kind="window", window=7, near=LIVE).json()
    assert (plane["kind"], plane["window"], plane["url"], plane["title"]) == (
        "window",
        7,
        None,
        "Docs",
    )
    assert _open(client, head, kind="window", window=8).json()["title"] == "Finder"
    assert _open(client, head, kind="window", window=9).status_code == 404


def test_closing_a_plane_drops_it_and_its_pose(client, head):
    plane = _open(client, head, kind="web", url="https://a.com").json()
    key = f"plane:{plane['id']}"
    pose = {"x": 1.0, "y": 1.5, "z": -2.0, "yaw": 0.3}
    assert client.put(f"/space/poses/{key}", json=pose, headers=head).status_code == 204
    assert client.get("/space", headers=head).json()["poses"][key] == pose
    assert client.delete(f"/space/planes/{plane['id']}", headers=head).status_code == 204
    space = client.get("/space", headers=head).json()
    assert space == {"rev": 3, "planes": [], "poses": {}}
    assert client.delete(f"/space/planes/{plane['id']}", headers=head).status_code == 404


@pytest.mark.parametrize(
    "key", [f"session:{LIVE}", "manager", "projects", "launcher", "monitor", "camera", "why"]
)
def test_every_kind_of_key_can_be_placed(client, head, key):
    pose = {"x": 0, "y": 1.2, "z": -1, "yaw": -3.1, "stray": True}
    assert client.put(f"/space/poses/{key}", json=pose, headers=head).status_code == 204
    kept = client.get("/space", headers=head).json()["poses"][key]
    assert kept == {"x": 0.0, "y": 1.2, "z": -1.0, "yaw": -3.1}


@pytest.mark.parametrize(
    "key,code",
    [
        ("session:", 400),
        ("plane:", 400),
        ("hud", 400),
        ("window:7", 400),
        ("plane:nope", 404),
    ],
)
def test_a_key_that_names_nothing_is_refused(client, head, key, code):
    pose = {"x": 0, "y": 0, "z": 0, "yaw": 0}
    assert client.put(f"/space/poses/{key}", json=pose, headers=head).status_code == code


@pytest.mark.parametrize(
    "body",
    [
        '{"x": NaN, "y": 0, "z": 0, "yaw": 0}',
        '{"x": 0, "y": Infinity, "z": 0, "yaw": 0}',
        '{"x": 0, "y": 0, "z": 0, "yaw": -Infinity}',
        '{"x": 0, "y": 0, "z": 0}',
        '{"x": true, "y": 0, "z": 0, "yaw": 0}',
        '{"x": "1", "y": 0, "z": 0, "yaw": 0}',
        '{"x": 20.5, "y": 0, "z": 0, "yaw": 0}',
        '{"x": 15, "y": 0, "z": -15, "yaw": 0}',
    ],
)
def test_a_pose_that_is_not_a_place_in_the_room_is_refused(client, head, body):
    sent = head | {"content-type": "application/json"}
    assert client.put("/space/poses/manager", content=body, headers=sent).status_code == 400
    assert client.get("/space", headers=head).json()["rev"] == 0


def test_the_store_is_one_file_written_whole(claude_home):
    plane, _ = stored.add({"id": "p1", "kind": "web"})
    stored.place("plane:p1", {"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0})
    stored.place("manager", {"x": 1.0, "y": 0.0, "z": 0.0, "yaw": 0.0})
    assert stored.drop("p1") and not stored.drop("p1")
    on_disk = json.loads((config.data_dir() / stored.SPACE).read_text())
    assert (
        on_disk
        == stored.space()
        == {
            "rev": 4,
            "planes": [],
            "poses": {"manager": {"x": 1.0, "y": 0.0, "z": 0.0, "yaw": 0.0}},
        }
    )
    assert plane["id"] == "p1"
    assert not list(config.data_dir().glob("*.part"))


def test_a_pose_keeps_its_group_and_refuses_a_bad_one(client, head):
    pose = {"x": 1, "y": 1.5, "z": 1, "yaw": 0.5}
    grouped = client.put("/space/poses/manager", json={**pose, "group": "proj-1"}, headers=head)
    assert grouped.status_code == 204
    assert client.get("/space", headers=head).json()["poses"]["manager"]["group"] == "proj-1"
    assert client.put("/space/poses/projects", json=pose, headers=head).status_code == 204
    assert "group" not in client.get("/space", headers=head).json()["poses"]["projects"]
    for bad in ("", "a b", "x" * 65, 3):
        sent = {**pose, "group": bad}
        assert client.put("/space/poses/launcher", json=sent, headers=head).status_code == 400


def test_a_pose_keeps_tilt_roll_and_scale_within_bounds(client, head):
    pose = {"x": 1, "y": 1.5, "z": 1, "yaw": 0.5, "pitch": -0.3, "roll": 0.1, "scale": 1.5}
    assert client.put("/space/poses/manager", json=pose, headers=head).status_code == 204
    kept = client.get("/space", headers=head).json()["poses"]["manager"]
    assert (kept["pitch"], kept["roll"], kept["scale"]) == (-0.3, 0.1, 1.5)
    for bad in ({"pitch": 4}, {"roll": -4}, {"scale": 0.1}, {"scale": 5}, {"scale": "big"}):
        sent = {**pose, **bad}
        assert client.put("/space/poses/manager", json=sent, headers=head).status_code == 400
