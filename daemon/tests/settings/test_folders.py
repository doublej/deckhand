"""Folders connected to a project: kept per folder, listed with the session's files, and the only
thing besides the transcript that `/file` will serve — with nothing outside them reachable."""

from __future__ import annotations

import json
from pathlib import Path

from deckhand_daemon import files
from deckhand_daemon.settings import folders

SID = "aaaa1111-2222-3333-4444-555566667777"
SHOP = "/Users/jj/dev/web/shop"


def made(tmp_path):
    """A render folder with one frame, one file nothing should list, and a secret beside it."""
    renders = (tmp_path / "renders").resolve()
    (renders / "pass2").mkdir(parents=True)
    (renders / "pass2" / "frame.png").write_bytes(b"\x89PNG fake")
    (renders / "node_modules").mkdir()
    (renders / "node_modules" / "junk.png").write_bytes(b"junk")
    (tmp_path / "secret.md").write_text("not yours")
    (tmp_path / "renders-evil").mkdir()
    (tmp_path / "renders-evil" / "x.png").write_bytes(b"evil")
    return renders


def test_kept_per_project_absolute_and_resolved(claude_home, tmp_path):
    renders = made(tmp_path)
    kept = folders.save(SHOP, [str(tmp_path / "renders" / "pass2" / ".."), "relative/dir", "/",
                               str(Path.home()), "  ", str(renders)])
    assert kept == [str(renders)]
    assert folders.load(SHOP) == [str(renders)]
    assert folders.load("/somewhere/else") == []
    folders.save(SHOP, [])
    assert json.loads(folders.path().read_text()) == {"projects": {}}


def test_a_connected_folder_s_files_are_listed_without_the_transcript(claude_home, tmp_path):
    renders = made(tmp_path)
    folders.save(SHOP, [str(renders)])
    found = files.readable_files(SID, SHOP)
    assert [(a.name, a.connected) for a in found] == [("frame.png", str(renders))]


def test_serving_stops_at_the_folder_s_edge(client, token, tmp_path):
    renders = made(tmp_path)
    (renders / "out.png").symlink_to(tmp_path / "secret.md")
    head = {"x-deckhand-token": token}
    assert client.put(f"/sessions/{SID}/folders", json={"folders": [str(renders)]},
                      headers=head).status_code == 200

    def status(wanted):
        return client.get(f"/sessions/{SID}/file", params={"path": wanted}, headers=head).status_code

    assert status(str(renders / "pass2" / "frame.png")) == 200
    # Climbing out, by `..`, by a symlink, or by a folder that only shares the name's prefix.
    assert status(f"{renders}/../secret.md") == 404
    assert status(f"{renders}/pass2/../../secret.md") == 404
    assert status(str(renders / "out.png")) == 404
    assert status(str(tmp_path / "renders-evil" / "x.png")) == 404
    assert status(str(renders / "node_modules" / "junk.png")) == 404
    assert status("renders/pass2/frame.png") == 404


def test_a_folder_the_session_wrote_into_is_suggested(client, token, claude_home, tmp_path):
    renders = made(tmp_path)
    transcript = claude_home / "projects" / "-Users-jj-dev" / f"{SID}.jsonl"
    transcript.write_text(json.dumps({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": "t1", "name": "Bash",
         "input": {"command": f"open {renders}/pass2/frame.png"}}]}}) + "\n")
    head = {"x-deckhand-token": token}
    before = client.get(f"/sessions/{SID}/folders", headers=head).json()
    assert before == {"path": SHOP, "folders": [], "suggested": [str(renders / "pass2")]}
    after = client.put(f"/sessions/{SID}/folders", json={"folders": [str(renders)]},
                       headers=head).json()
    # Connected now, and everything under it is no longer worth suggesting.
    assert after == {"path": SHOP, "folders": [str(renders)], "suggested": []}


def test_folders_need_the_token(client):
    assert client.get(f"/sessions/{SID}/folders").status_code == 401
