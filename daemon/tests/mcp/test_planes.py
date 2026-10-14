"""The four space tools, and the `deckhand` commands that are them."""

import asyncio
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from deckhand_daemon import config
from deckhand_daemon.mcp import cli, here, server

run = asyncio.run


@pytest.fixture
def daemon(monkeypatch):
    """Every `reach` recorded and answered with whatever the test set in `answers`."""
    seen, answers = [], {}

    async def reach(method, path, **kw):
        seen.append((method, path, kw.get("json")))
        return answers.get(path, {})

    monkeypatch.setattr(server.here, "reach", reach)
    return seen, answers


def test_a_plane_opened_from_a_session_is_near_it(monkeypatch, daemon):
    seen, _ = daemon
    monkeypatch.setattr(server.here, "mine", lambda: {"sessionId": "s1", "name": "deckhand"})
    run(server.open_plane(url="http://localhost:5173/", title="Shop"))
    run(server.open_plane(window=7))
    assert seen == [
        ("POST", "/space/planes", {"kind": "web", "url": "http://localhost:5173/",
                                   "title": "Shop", "near": "s1", "by": "deckhand"}),
        ("POST", "/space/planes", {"kind": "window", "window": 7, "near": "s1",
                                   "by": "deckhand"}),
    ]


def test_with_no_session_above_a_plane_is_near_nothing(monkeypatch, daemon):
    seen, _ = daemon
    monkeypatch.setattr(server.here, "mine", lambda: None)
    run(server.open_plane(url="https://a.com"))
    assert seen == [("POST", "/space/planes", {"kind": "web", "url": "https://a.com"})]


@pytest.mark.parametrize("given", [{}, {"url": "https://a.com", "window": 7}])
def test_one_of_url_or_window_and_never_both(daemon, given):
    seen, _ = daemon
    assert run(server.open_plane(**given))["code"] == "BAD_PLANE"
    assert seen == []


def test_closing_takes_a_plane_id_and_only_that(daemon):
    seen, _ = daemon
    assert run(server.close_plane("ab12")) == {"closed": "ab12"}
    run(server.close_plane("../../sessions/x"))
    assert [path for _, path, _ in seen] == [
        "/space/planes/ab12", "/space/planes/..%2F..%2Fsessions%2Fx"]
    assert {method for method, _, _ in seen} == {"DELETE"}


def test_mac_windows_wraps_the_list_and_passes_a_refusal_through(daemon):
    _, answers = daemon
    answers["/windows"] = [{"id": 7, "app": "Safari", "title": "Docs", "w": 1, "h": 1}]
    assert run(server.mac_windows())["windows"][0]["id"] == 7
    answers["/windows"] = {"error": "the daemon refused that (503): no helper", "code": "REFUSED"}
    assert run(server.mac_windows())["code"] == "REFUSED"


def test_a_204_from_the_daemon_is_an_empty_answer(tmp_path, monkeypatch):
    class NoContent(BaseHTTPRequestHandler):
        def do_DELETE(self):
            self.send_response(204)
            self.end_headers()

        def log_message(self, *args):
            pass

    served = ThreadingHTTPServer(("127.0.0.1", 0), NoContent)
    threading.Thread(target=served.serve_forever, daemon=True).start()
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path))
    monkeypatch.setattr(config, "PORT", served.server_port)
    try:
        assert run(here.reach("DELETE", "/space/planes/ab12")) == {}
    finally:
        served.shutdown()
        served.server_close()


def test_open_with_nothing_to_open_is_a_user_error(capsys):
    with pytest.raises(SystemExit) as ended:
        cli.main(["open"])
    assert ended.value.code == 1
    assert json.loads(capsys.readouterr().err)["error"]["code"] == "BAD_PLANE"


def test_the_commands_reach_the_same_tools(daemon, capsys):
    seen, answers = daemon
    answers["/space"] = {"rev": 2, "planes": [], "poses": {}}
    cli.main(["space"])
    assert json.loads(capsys.readouterr().out)["rev"] == 2
    cli.main(["close", "ab12"])
    assert json.loads(capsys.readouterr().out) == {"closed": "ab12"}
    assert seen[-1][:2] == ("DELETE", "/space/planes/ab12")
