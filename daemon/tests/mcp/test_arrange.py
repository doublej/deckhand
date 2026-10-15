"""`tmux_tree` and `tmux_arrange` against a tmux server of their own, never the person's.

`-L` with `TMUX` dropped from the environment: inside tmux, `$TMUX` beats `TMUX_TMPDIR`, and a
probe that trusted the latter once killed the person's real server.
"""

import asyncio
import shutil
import subprocess
import uuid
from pathlib import Path

import pytest

from deckhand_daemon.mcp import tmux

pytestmark = pytest.mark.skipif(shutil.which("tmux") is None, reason="no tmux on this machine")
run = asyncio.run


@pytest.fixture
def box(monkeypatch):
    """Two windows in tmux session `work`, `utt` and `deckhand` in them, and one in `side`."""
    monkeypatch.delenv("TMUX", raising=False)
    monkeypatch.setenv("TMUX_PANE", "%0")
    sock = ("tmux", "-L", f"dh-test-{uuid.uuid4().hex[:8]}")
    monkeypatch.setattr(tmux, "TMUX", sock)

    def sh(*args: str) -> str:
        return subprocess.run([*sock, *args], capture_output=True, text=True,
                              check=True).stdout.strip()

    sh("-f", "/dev/null", "new-session", "-d", "-s", "work", "-n", "one", "-x", "200", "-y", "50",
       "sleep 600")
    sh("new-window", "-d", "-t", "work:", "-n", "two", "sleep 600")
    sh("new-session", "-d", "-s", "side", "-n", "three", "sleep 600")
    panes = {name: sh("display", "-p", "-t", f"work:{name}", "#{pane_id}") for name in ("one", "two")}
    listing = {"sessions": [
        {"session_id": "s-utt", "name": "utt", "status": "idle",
         "pane": {"iterm_session_id": panes["one"]}},
        {"session_id": "s-deck", "name": "deckhand", "status": "busy",
         "pane": {"iterm_session_id": panes["two"]}},
    ]}

    async def reach(method, path, **kw):
        return listing

    monkeypatch.setattr(tmux.here, "reach", reach)
    left = Path(sh("display", "-p", "#{socket_path}"))
    yield sh
    subprocess.run([*sock, "kill-server"], capture_output=True, check=False)
    left.unlink(missing_ok=True)  # a killed server leaves its socket file behind


def test_the_tree_names_the_session_in_each_pane(box):
    seen = run(tmux.tmux_tree())
    assert seen["you"] == "%0"
    work = next(s for s in seen["sessions"] if s["name"] == "work")
    assert [w["name"] for w in work["windows"]] == ["one", "two"]
    assert work["windows"][1]["panes"][0]["session"] == "deckhand"
    assert work["windows"][1]["panes"][0]["status"] == "busy"


def test_a_group_is_set_on_the_window_and_dropped_again(box):
    assert run(tmux.tmux_arrange("group", "utt", name="review"))["done"] == "group"
    assert box("show-options", "-wv", "-t", "work:one", "@group") == "review"
    run(tmux.tmux_arrange("ungroup", "utt"))
    assert box("show-options", "-wqv", "-t", "work:one", "@group") == ""


def test_two_sessions_join_side_by_side_and_break_out_keeping_their_group(box):
    run(tmux.tmux_arrange("group", "utt", name="pair"))
    run(tmux.tmux_arrange("join", "deckhand", to="utt"))
    assert box("display", "-p", "-t", "work:one", "#{window_panes}") == "2"
    assert run(tmux.tmux_arrange("layout", "work:one", layout="even-horizontal"))["done"]
    broke = run(tmux.tmux_arrange("break", "deckhand", name="alone"))
    assert box("display", "-p", "-t", broke["window"], "#{window_name}") == "alone"
    assert box("show-options", "-wv", "-t", broke["window"], "@group") == "pair"


def test_windows_move_rename_and_swap(box):
    run(tmux.tmux_arrange("move", "three", to="work"))
    assert box("list-windows", "-t", "work", "-F", "#{window_name}").split() == ["one", "two",
                                                                                 "three"]
    run(tmux.tmux_arrange("move", "three", to="utt"))
    run(tmux.tmux_arrange("rename", "three", name="logs"))
    run(tmux.tmux_arrange("swap", "logs", to="deckhand"))
    assert box("list-windows", "-t", "work", "-F", "#{window_name}").split() == ["one", "two",
                                                                                 "logs"]


def test_a_wrong_name_or_a_missing_argument_moves_nothing(box):
    assert run(tmux.tmux_arrange("join", "nobody", to="utt"))["code"] == "NO_SUCH_TARGET"
    assert run(tmux.tmux_arrange("rename", "utt"))["code"] == "BAD_ARRANGE"
    assert run(tmux.tmux_arrange("layout", "utt", layout="spiral"))["code"] == "BAD_ARRANGE"
    assert run(tmux.tmux_arrange("move", "utt", to="nowhere"))["code"] == "NO_SUCH_TARGET"


def test_a_bare_word_is_an_exact_window_before_a_session_it_is_part_of():
    rows = [{"pane_id": "%1", "window_id": "@1", "window_name": "deckhand-x", "pane_active": "1",
             "session_name": "w", "window_index": "0"},
            {"pane_id": "%2", "window_id": "@2", "window_name": "logs", "pane_active": "1",
             "session_name": "w", "window_index": "1"}]
    labels = {"%1": {"session_id": "s1", "name": "catalogs", "pane": {"iterm_session_id": "%1"}}}
    assert tmux.find("logs", rows, labels)["pane_id"] == "%2"
    assert tmux.find("catalogs", rows, labels)["pane_id"] == "%1"
    assert tmux.find("w:1", rows, labels)["pane_id"] == "%2"
    assert tmux.find("cat", rows, labels)["pane_id"] == "%1"
