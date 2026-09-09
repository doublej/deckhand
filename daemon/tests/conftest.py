import json
import time

import pytest

from deckhand_daemon import config, sessions


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
                }
            )
        )
    monkeypatch.setattr(sessions, "_pane_cache", (0.0, {}))
    monkeypatch.setenv("DECKHAND_CLAUDE_HOME", str(home))
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setattr(sessions, "_processes", lambda: {4242: "ttys014", 4243: "ttys015"})
    monkeypatch.setattr(
        sessions,
        "_panes",
        lambda: {
            "ttys014": sessions.Pane("ITERM-A", "win-1", "180", "◐ warm-okapi"),
            "ttys015": sessions.Pane("ITERM-B", "win-1", "181", "✳ cold-otter"),
        },
    )
    return home


@pytest.fixture
def token(claude_home):
    return config.token()
