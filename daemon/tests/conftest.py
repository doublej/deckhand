import json
import logging
import time

import pytest

from deckhand_daemon import config, sessions


@pytest.fixture(autouse=True)
def keep_the_real_log_clean(tmp_path, monkeypatch):
    """A test run must never appear in the log file the user watches in Console.app."""
    from deckhand_daemon import log as log_module

    directory = tmp_path / "logs"
    directory.mkdir()
    monkeypatch.setattr(log_module, "LOG_DIR", directory)
    monkeypatch.setattr(log_module, "LOG_FILE", directory / "deckhand.log")
    handler = logging.FileHandler(directory / "deckhand.log")
    handler.setFormatter(logging.Formatter(log_module.FORMAT))
    monkeypatch.setattr(log_module.log, "handlers", [handler])


@pytest.fixture
def no_hands(monkeypatch):
    """No other machine answers. Every route that merges the fleet asks all of them at once, and
    a test that did not say this would try to open a real ssh link to whatever atlas's registry
    happens to hold on the machine running the suite."""
    from deckhand_daemon.fleet import proxy

    async def nobody(method, path, **kwargs):
        return {}

    monkeypatch.setattr(proxy, "every", nobody)


@pytest.fixture
def claude_home(tmp_path, monkeypatch):
    """A fake ~/.claude with one live session (pid 4242) and one stale record."""
    home = tmp_path / "claude"
    (home / "sessions").mkdir(parents=True)
    (home / "projects" / "-Users-jj-dev").mkdir(parents=True)
    now = time.time() * 1000
    for pid, sid, name, status, updated in [
        (4242, "aaaa1111-2222-3333-4444-555566667777", "warm-okapi", "busy", now),
        (4243, "bbbb1111-2222-3333-4444-555566667777", "cold-otter", "idle", now - 60_000),
        (9999, "cccc1111-2222-3333-4444-555566667777", "dead-mole", "idle", now - 10),
    ]:
        (home / "sessions" / f"{pid}.json").write_text(
            json.dumps(
                {
                    "pid": pid,
                    "sessionId": sid,
                    "cwd": "/Users/jj/dev/web/shop",
                    "kind": "interactive",
                    "name": name,
                    "status": status,
                    "updatedAt": updated,
                    "messagingSocketPath": f"/tmp/cc-socks/{pid}.sock",
                }
            )
        )
    monkeypatch.setattr(sessions.panes, "_pane_cache", (0.0, {}))
    # The listing is cached for a couple of seconds in the daemon, which every test that moves
    # a record and looks again would have to sleep through. Off here; `test_sessions` turns it
    # back on for the two tests that are about the cache itself.
    monkeypatch.setattr(sessions.live, "LISTING_TTL", 0.0)
    monkeypatch.setattr(sessions.live, "_listing", (0.0, [], False))
    # Which conversation is running under which pid outlives a single listing, so it outlives a
    # single test too unless it is blanked here.
    monkeypatch.setattr(sessions.live, "_current", {})
    monkeypatch.setattr(sessions.live, "_retired", {})
    monkeypatch.setenv("DECKHAND_CLAUDE_HOME", str(home))
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setattr(
        sessions.live, "_processes", lambda pids: {4242: "ttys014", 4243: "ttys015"}
    )
    monkeypatch.setattr(
        sessions.panes,
        "lookup",
        lambda: {
            "ttys014": sessions.Pane("ITERM-A", "win-1", "180", "◐ warm-okapi"),
            "ttys015": sessions.Pane("ITERM-B", "win-1", "181", "✳ cold-otter"),
        },
    )
    return home


@pytest.fixture
def token(claude_home):
    return config.token()


@pytest.fixture(autouse=True)
def keep_utts_plugin_folder_clean(tmp_path, monkeypatch):
    """A test run must not install a plugin page into the utt a person is using."""
    monkeypatch.setenv("DECKHAND_PLUGIN_DIR", str(tmp_path / "plugins"))
