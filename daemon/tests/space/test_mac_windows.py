"""`/windows`: what `deckhand-windows` answers, passed through — or a 503 when nothing listens."""

from __future__ import annotations

import json
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import ClassVar

import pytest

from deckhand_daemon.space import windows

LISTED = [{"id": 7, "app": "Safari", "title": "Docs", "w": 800, "h": 600}]
JPEG = b"\xff\xd8\xff\xe0fake\xff\xd9"
HEVC = b"\x00\x00\x00\x01\x40\x01fake-vps"
BOUNDARY = "frame"
STREAM = b"".join(
    f"--{BOUNDARY}\r\nContent-Type: image/jpeg\r\n\r\n".encode() + JPEG + b"\r\n" for _ in range(3)
)


class Helper(BaseHTTPRequestHandler):
    """A stand-in for `deckhand-windows`: one window, one frame, a stream of three."""

    asked: ClassVar[list[str]] = []

    def do_GET(self):
        Helper.asked.append(self.path)
        if self.path == "/windows":
            self._send(200, "application/json", json.dumps(LISTED).encode())
        elif self.path == "/windows/7/frame":
            self._send(200, "image/jpeg", JPEG)
        elif self.path.startswith("/windows/7/hevc"):
            self._send(200, "application/octet-stream", HEVC)
        elif self.path.startswith("/windows/7/stream"):
            self._send(200, f"multipart/x-mixed-replace; boundary={BOUNDARY}", STREAM)
        else:
            # The real helper's shape, which the relay must not wrap a second time.
            self._send(404, "application/json", json.dumps({"detail": "no window 9"}).encode())

    def do_POST(self):
        sent = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        Helper.asked.append((self.path, sent))
        if self.path == "/windows/7/input":
            self.send_response(204)
            self.end_headers()
        else:
            self._send(404, "application/json", json.dumps({"detail": "no window 9"}).encode())

    def _send(self, code, kind, body):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


@pytest.fixture
def helper(monkeypatch):
    served = ThreadingHTTPServer(("127.0.0.1", 0), Helper)
    threading.Thread(target=served.serve_forever, daemon=True).start()
    monkeypatch.setattr(windows, "HELPER", f"http://127.0.0.1:{served.server_port}")
    Helper.asked = []
    yield served
    served.shutdown()
    served.server_close()


@pytest.fixture
def nobody(monkeypatch):
    """A loopback port nothing listens on — not 4181 itself, which a real helper may hold."""
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    monkeypatch.setattr(windows, "HELPER", f"http://127.0.0.1:{port}")


@pytest.mark.parametrize("path", ["/windows", "/windows/7/frame", "/windows/7/stream?fps=5"])
def test_no_helper_is_a_503_that_says_why(client, head, nobody, path):
    answered = client.get(path, headers=head)
    assert answered.status_code == 503
    assert "deckhand-windows" in answered.json()["detail"]


def test_a_window_plane_needs_the_helper_too(client, head, nobody):
    sent = {"kind": "window", "window": 7}
    assert client.post("/space/planes", json=sent, headers=head).status_code == 503


def test_the_list_and_a_frame_pass_straight_through(client, head, helper):
    assert client.get("/windows", headers=head).json() == LISTED
    frame = client.get("/windows/7/frame", headers=head)
    assert frame.content == JPEG and frame.headers["content-type"] == "image/jpeg"
    missing = client.get("/windows/9/frame", headers=head)
    assert missing.status_code == 404 and missing.json()["detail"] == "no window 9"


def test_the_stream_is_relayed_as_it_came_with_its_fps(client, head, helper):
    with client.stream("GET", "/windows/7/stream", params={"fps": 5}, headers=head) as streamed:
        assert streamed.headers["content-type"].startswith("multipart/x-mixed-replace")
        assert b"".join(streamed.iter_raw()) == STREAM
    assert Helper.asked == ["/windows/7/stream?fps=5"]


def test_input_reaches_the_helper_and_the_headset_touches_last(client, head, helper, monkeypatch):
    from deckhand_daemon import presence

    monkeypatch.setattr(presence, "_headset_beat", None)
    click = {"type": "down", "x": 0.5, "y": 0.25, "button": "left"}
    assert client.post("/windows/7/input", json=click, headers=head).status_code == 204
    assert Helper.asked == [("/windows/7/input", click)]
    assert presence._headset_beat is not None
    missing = client.post("/windows/9/input", json=click, headers=head)
    assert missing.status_code == 404 and missing.json()["detail"] == "no window 9"


def test_input_without_the_helper_is_a_503(client, head, nobody):
    sent = {"type": "up", "x": 0, "y": 0}
    assert client.post("/windows/7/input", json=sent, headers=head).status_code == 503


def test_the_whole_query_goes_through_and_hevc_is_relayed_too(client, head, helper):
    asked = {"fps": 20, "max": 2880, "q": 0.9}
    with client.stream("GET", "/windows/7/stream", params=asked, headers=head) as streamed:
        assert b"".join(streamed.iter_raw()) == STREAM
    with client.stream("GET", "/windows/7/hevc", params=asked, headers=head) as streamed:
        assert streamed.headers["content-type"] == "application/octet-stream"
        assert b"".join(streamed.iter_raw()) == HEVC
    assert Helper.asked == [
        "/windows/7/stream?fps=20&max=2880&q=0.9",
        "/windows/7/hevc?fps=20&max=2880&q=0.9",
    ]
    assert client.get("/windows/7/gif", headers=head).status_code == 422
