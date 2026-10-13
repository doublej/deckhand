"""Codex threads on the listing: which ones, in what shape, and what a dead app server costs."""

import json
import shutil
import tempfile
import threading
import time
from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient
from websockets.sync.server import unix_serve

from deckhand_daemon import sessions
from deckhand_daemon.app import app
from deckhand_daemon.sessions import codex

SHOP = "/Users/jj/dev/web/shop"


def thread(thread_id, status="idle", parent=None, name=None, updated=1789316385):
    kind = {"type": status, "activeFlags": []} if status == "active" else {"type": status}
    return {"id": thread_id, "name": name, "cwd": SHOP, "status": kind, "updatedAt": updated,
            "parentThreadId": parent, "ephemeral": False, "source": "vscode"}


def app_server(monkeypatch, *threads):
    """The app server behind the seam, answering only what a listing may ask. Returns the calls."""
    calls = []
    by_id = {t["id"]: t for t in threads}

    def request(method, params=None, timeout=None):
        calls.append((method, params))
        if method == "thread/loaded/list":
            return {"data": list(by_id)}
        if method == "thread/read":
            return {"thread": by_id[params["threadId"]]}
        raise AssertionError(f"a listing has no business calling {method}")

    monkeypatch.setattr(codex, "request", request)
    return calls


def test_a_thread_is_a_row_with_no_process_no_tty_and_no_pane():
    assert codex.record(thread("t-1", status="active")) == {
        "session_id": "t-1", "pid": 0, "name": "shop-codex-t-1", "cwd": SHOP, "status": "busy",
        "updated_at": 1789316385.0, "tty": "", "pane": None, "provider": "codex"}
    assert codex.record(thread("t-1", name="Plan the provider"))["name"] == "Plan the provider"
    assert codex.record(thread("t-1"))["status"] == "idle"


def test_only_loaded_top_level_threads_that_can_take_input_are_listed(monkeypatch):
    calls = app_server(monkeypatch, thread("idle"), thread("busy", status="active"),
                       thread("child", parent="idle"), thread("broken", status="systemError"),
                       thread("gone", status="notLoaded"))
    assert [row["session_id"] for row in codex.records()] == ["idle", "busy"]
    calls.clear()
    codex.records()
    # A child is a child for good, so the next listing does not pay to read it again.
    assert [p["threadId"] for m, p in calls if m == "thread/read"] == [
        "idle", "busy", "broken", "gone"]


def test_codex_rows_join_the_listing_and_are_not_hidden_for_having_no_pane(
    claude_home, monkeypatch
):
    app_server(monkeypatch, thread("t-1", status="active", updated=time.time() + 60))
    listed = sessions.live_sessions()
    assert [(s.name, s.provider) for s in listed] == [
        ("shop-codex-t-1", "codex"), ("warm-okapi", "claude"), ("cold-otter", "claude")]
    row = listed[0].to_json()
    assert (row["pid"], row["tty"], row["pane"], row["status"]) == (0, "", None, "busy")
    assert TestClient(app).get("/health").json()["codex"] is True


def test_a_dead_app_server_costs_one_attempt_and_never_the_claude_rows(claude_home, monkeypatch):
    attempts = []
    real = codex.unix_connect

    def connect(path, **kwargs):
        attempts.append(path)
        return real(path, **kwargs)

    monkeypatch.setattr(codex, "unix_connect", connect)
    assert [s.name for s in sessions.live_sessions()] == ["warm-okapi", "cold-otter"]
    sessions.live_sessions()  # the listing's own cache is off in tests, so this rebuilds it
    assert len(attempts) == 1
    assert TestClient(app).get("/health").json()["codex"] is False
    monkeypatch.setattr(codex, "_asked", (time.monotonic() - codex.RETRY_AFTER - 1, False))
    sessions.live_sessions()
    assert len(attempts) == 2


def test_a_python_without_unix_sockets_still_lists_its_claude_rows(claude_home, monkeypatch):
    # Windows' socket module has no AF_UNIX: Fractal's hand answered every listing 500 over it.
    monkeypatch.setattr(codex, "socket", SimpleNamespace())
    assert [s.name for s in sessions.live_sessions()] == ["warm-okapi", "cold-otter"]
    assert TestClient(app).get("/health").json()["codex"] is False


def test_the_link_speaks_websocket_says_initialized_without_an_id_and_skips_the_chatter(
    monkeypatch,
):
    home = Path(tempfile.mkdtemp(dir="/tmp"))  # AF_UNIX caps a socket path at 104 bytes
    sock = home / "app-server-control" / "app-server-control.sock"
    sock.parent.mkdir()
    monkeypatch.setenv("DECKHAND_CODEX_HOME", str(home))
    heard = []

    def serve(connection):
        for frame in connection:
            message = json.loads(frame)
            heard.append(message)
            if "id" in message:
                # Notifications arrive interleaved with answers, and are not the answer.
                connection.send(json.dumps({"method": "remoteControl/status/changed"}))
                connection.send(json.dumps({"id": message["id"], "result": {"data": ["t-1"]}}))

    with unix_serve(serve, str(sock)) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        assert codex.request("thread/loaded/list") == {"data": ["t-1"]}
        codex._drop()
        server.shutdown()
    shutil.rmtree(home, ignore_errors=True)
    assert [m["method"] for m in heard] == ["initialize", "initialized", "thread/loaded/list"]
    assert heard[0]["params"] == codex.HELLO and "id" not in heard[1]
