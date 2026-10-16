"""Which OpenCode sessions a TUI on this Mac has open: the TUI tab file, the running TUIs, and
the `in_client` every OpenCode row carries."""

import json
import os

import pytest
from fastapi.testclient import TestClient
from opencode_fake import NOW, SHOP, info

from deckhand_daemon import config
from deckhand_daemon.app import app
from deckhand_daemon.sessions import opencode_tabs

HOUR = 3_600_000
ELSEWHERE = "/Users/jj/dev/web/blog"
#: The real probe, taken before the autouse fixture stubs it out of every test.
REAL_CLIENTS = opencode_tabs.clients


def tabs(tmp_path, folders, everywhere=()):
    """The TUI's tab file, beside the service registration as OpenCode keeps it."""
    path = tmp_path / "opencode" / "latest" / "tui" / "tabs.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    listed = lambda ids: {"tabs": [{"sessionID": sid, "title": sid} for sid in ids], "unread": {}}
    path.write_text(json.dumps({"global": listed(everywhere),
                                "cwd": {folder: listed(ids) for folder, ids in folders.items()}}))
    return path


def rows(client):
    return {r["session_id"]: r for r in client.get("/sessions").json()["sessions"]
            if r["provider"] == "opencode"}


@pytest.fixture
def client(opencode_service):
    found = TestClient(app)
    found.headers["x-deckhand-token"] = config.token()
    return found


def test_a_tui_tab_is_open_only_in_a_folder_a_tui_runs_in(
        opencode_service, client, tmp_path, monkeypatch):
    fake = opencode_service
    fake.add(info("ses_open0001", "Open here"))
    fake.add(info("ses_aged0002", "Open since this morning", updated=NOW - 5 * HOUR))
    fake.add(info("ses_glob0003", "Open in every TUI", updated=NOW - 9 * HOUR))
    fake.add(info("ses_else0004", "A tab where no TUI runs", folder=ELSEWHERE))
    fake.add(info("ses_shut0005", "Closed, but recent"))
    fake.add(info("ses_busy0006", "Running with no window"), busy=True)
    fake.add(info("ses_cold0007", "Closed and old", updated=NOW - 5 * HOUR))
    tabs(tmp_path, {SHOP: ["ses_open0001", "ses_aged0002"], ELSEWHERE: ["ses_else0004"]},
         everywhere=["ses_glob0003"])
    monkeypatch.setattr(opencode_tabs, "clients", lambda: {SHOP})
    listed = rows(client)
    # A TUI tab keeps a session on the phone past the two hours; nothing else old does.
    assert set(listed) == {"ses_open0001", "ses_aged0002", "ses_glob0003", "ses_else0004",
                           "ses_shut0005", "ses_busy0006"}
    assert {sid for sid, r in listed.items() if r["in_client"]} == {
        "ses_open0001", "ses_aged0002", "ses_glob0003"}
    assert listed["ses_busy0006"]["status"] == "busy"


def test_with_no_tui_running_nothing_is_open_and_old_tabs_are_not_kept(
        opencode_service, client, tmp_path, monkeypatch):
    opencode_service.add(info("ses_open0001", "Was open"))
    opencode_service.add(info("ses_aged0002", "Was open long ago", updated=NOW - 5 * HOUR))
    tabs(tmp_path, {SHOP: ["ses_open0001", "ses_aged0002"]})
    monkeypatch.setattr(opencode_tabs, "clients", set)
    assert {sid: r["in_client"] for sid, r in rows(client).items()} == {"ses_open0001": False}


def test_a_mac_that_cannot_tell_says_nothing(opencode_service, client, tmp_path):
    opencode_service.add(info("ses_open0001", "Open, as far as anyone knows"))
    tabs(tmp_path, {SHOP: ["ses_open0001"]})
    assert rows(client)["ses_open0001"]["in_client"] is None


@pytest.mark.parametrize(("words", "folder"), [
    ([], ""),
    (["-c"], ""),
    (["--session", "ses_x"], ""),
    (["-s", "ses_x", "../shop"], "../shop"),
    (["--log-level", "debug", "~/dev"], "~/dev"),
    (["run", "say hi"], None),
    (["serve", "--service"], None),
    (["--print-logs", "mini"], None),
])
def test_the_folder_argument_and_what_is_no_tui(words, folder):
    assert opencode_tabs.folder_argument(words) == folder


def test_the_running_tuis_are_asked_once_each_and_forgotten_when_they_go(monkeypatch):
    monkeypatch.setattr(opencode_tabs.shutil, "which", lambda name: f"/usr/bin/{name}")
    pids = ["11\n12\n13\n14\n"]
    asked = []

    def probe(argv):
        asked.append(argv[0])
        if argv[0] == "pgrep":
            return pids[0]
        if argv[0] == "ps":
            return ("   11 ttys030  opencode\n"
                    "   12 ??       /Users/jj/.opencode/bin/opencode serve --service\n"
                    "   13 ttys031  opencode run hello\n"
                    "   14 ttys032  opencode -c ../blog\n")
        assert argv[-1] == "11,14"  # only the two TUIs need a folder
        return f"p11\nfcwd\nn{SHOP}\np14\nfcwd\nn{SHOP}\n"

    monkeypatch.setattr(opencode_tabs, "_run", probe)
    assert REAL_CLIENTS() == {SHOP, ELSEWHERE}
    assert asked == ["pgrep", "ps", "lsof"]
    asked.clear()
    pids[0] = "11\n12\n13\n"
    assert REAL_CLIENTS() == {SHOP}
    assert asked == ["pgrep"]  # nothing new to describe
    assert set(opencode_tabs._folders) == {11, 12, 13}


def test_a_machine_without_the_probes_cannot_tell(monkeypatch):
    monkeypatch.setattr(opencode_tabs.shutil, "which", lambda name: None)
    assert REAL_CLIENTS() is None


def test_a_tab_file_caught_mid_write_is_read_again(tmp_path, monkeypatch):
    path = tabs(tmp_path, {SHOP: ["ses_open0001"]})
    monkeypatch.setattr(opencode_tabs, "clients", lambda: {SHOP})
    state = tmp_path / "opencode"
    assert opencode_tabs.open_sessions(state) == {"ses_open0001"}
    path.write_text('{"cwd": {')
    os.utime(path, (path.stat().st_atime, path.stat().st_mtime + 5))
    assert opencode_tabs.open_sessions(state) == set()
    assert opencode_tabs._read[1] == {SHOP: {"ses_open0001"}}  # the broken read was not kept
