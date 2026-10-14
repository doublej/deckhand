"""A client with no token on it, over `claude_home`'s live sessions, on a known LAN address — and
iTerm's API as a fake behind the daemon's real gate and thread."""

from __future__ import annotations

import json
import os
from types import SimpleNamespace

import iterm2
import pytest
from fastapi.testclient import TestClient
from iterm2 import api_pb2, rpc

from deckhand_daemon import config
from deckhand_daemon.app import app
from deckhand_daemon.space import iterm, screen, theme


@pytest.fixture
def client(claude_home, monkeypatch):
    monkeypatch.setattr(config, "lan_address", lambda: "192.168.178.180")
    return TestClient(app)


@pytest.fixture
def head(token):
    return {"x-deckhand-token": token}


@pytest.fixture
def approved(claude_home):
    """The marker `just iterm-styles` writes once iTerm has let `deckhand` in."""
    (config.data_dir() / iterm.MARKER).write_text(f"{iterm.NAME}\n")


@pytest.fixture
def iterm_api(monkeypatch):
    """`connects` counts every attempt to reach iTerm, authenticating included, so a test can
    assert there were none. `rows` is the screen it answers and `profile` the pane's profile;
    `broken` makes the screen read fail."""
    api = SimpleNamespace(
        connects=0, reads=0, rows=[], profile={"Normal Font": "Menlo-Regular 12"}, broken=False
    )

    async def closed():
        return None

    async def connect():
        api.connects += 1
        # The library leaves the spent cookie in the environment; the daemon must not.
        os.environ["ITERM2_COOKIE"] = "spent"
        return SimpleNamespace(websocket=SimpleNamespace(close=closed))

    def authenticate(*args, **kwargs):
        api.connects += 1
        return False

    async def screen_contents(connection, session, *rest):
        api.reads += 1
        if api.broken:
            raise rpc.RPCException("broken")
        answer = api_pb2.GetBufferResponse(contents=api.rows)
        return api_pb2.ServerOriginatedMessage(get_buffer_response=answer)

    async def get_profile(connection, session, keys=None):
        found = [
            api_pb2.ProfileProperty(key=key, json_value=json.dumps(value))
            for key, value in api.profile.items()
        ]
        answer = api_pb2.GetProfilePropertyResponse(properties=found)
        return api_pb2.ServerOriginatedMessage(get_profile_property_response=answer)

    monkeypatch.delenv("ITERM2_COOKIE", raising=False)
    monkeypatch.setattr(iterm2.Connection, "async_create", staticmethod(connect))
    monkeypatch.setattr(iterm2.auth, "authenticate", authenticate)
    monkeypatch.setattr(iterm2.connection, "_auth_authenticate", authenticate)
    # `_connect` renames the client for the whole library; put the names back afterwards.
    monkeypatch.setattr(iterm2.auth, "get_script_name", iterm2.auth.get_script_name)
    monkeypatch.setattr(iterm2.connection, "get_script_name", iterm2.connection.get_script_name)
    monkeypatch.setattr(rpc, "async_get_screen_contents", screen_contents)
    monkeypatch.setattr(rpc, "async_get_profile", get_profile)
    monkeypatch.setattr(iterm, "_connection", None)
    monkeypatch.setattr(iterm, "_failed_at", float("-inf"))
    monkeypatch.setattr(screen, "_read", {})
    monkeypatch.setattr(theme, "_kept", {})
    monkeypatch.setattr(theme, "dark", lambda: False)
    return api
