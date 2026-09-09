"""The folder, what it lists, and the two ways an id must not be allowed to leave it."""

import json
import os

from deckhand_daemon import artifacts


def test_a_page_lists_under_its_own_title(session, asking):
    listed = artifacts.listing(session)

    assert [(row["id"], row["title"], row["answered"]) for row in listed] == [
        ("which-branch", "Which branch?", False)
    ]
    assert listed[0]["modified"] == asking.stat().st_mtime


def test_the_newest_page_is_first(session, asking):
    later = asking.parent / "palette-pick.html"
    later.write_text("<title>Pick a palette</title>")
    os.utime(asking, (1_700_000_000, 1_700_000_000))

    assert [row["id"] for row in artifacts.listing(session)] == ["palette-pick", "which-branch"]


def test_a_page_with_no_title_or_no_sense_still_lists(session, asking):
    """An agent interrupted mid-`Write` must not be able to empty the phone's listing."""
    (asking.parent / "half-written.html").write_text("<!doctype html><head><tit")
    (asking.parent / "not-text.html").write_bytes(b"\xff\xfe\x00\x00 not html at all")

    listed = {row["id"]: row["title"] for row in artifacts.listing(session)}

    assert listed == {
        "which-branch": "Which branch?",
        "half-written": "half-written",
        "not-text": "not-text",
    }


def test_an_escape_in_the_title_is_shown_as_the_character_it_is(session, asking):
    asking.write_text("<title>Ship &amp; tag?</title>")

    assert artifacts.listing(session)[0]["title"] == "Ship & tag?"


def test_a_project_with_no_folder_has_no_artifacts_and_gains_no_folder(session, project):
    """A session working in `/` or in `$HOME` must not turn the daemon into a file server."""
    assert artifacts.kept(session) is None
    assert artifacts.listing(session) == []
    assert artifacts.page(session, "which-branch") is None
    assert artifacts.answer(session, "which-branch", "develop") is None
    assert not (project / ".deckhand").exists()


def test_the_folder_ignores_itself(session, project):
    spot = artifacts.folder(session)

    assert spot == project / ".deckhand" / "artifacts"
    assert (project / ".deckhand" / ".gitignore").read_text() == "*\n"


def test_a_folder_an_agent_made_with_write_gets_the_gitignore_too(session, asking):
    """`Write` creates the folder and nothing else, so the daemon tops it up on the first read."""
    ignore = asking.parent.parent / ".gitignore"
    assert not ignore.exists()

    artifacts.listing(session)

    assert ignore.read_text() == "*\n"


def test_an_id_that_climbs_out_of_the_folder_is_refused(session, asking, tmp_path):
    """The id is one slug or it is nothing. A path is not an id, whichever way it is spelled."""
    secret = tmp_path / "passwd"
    secret.write_text("root:x:0:0")

    for climbing in ["../../../etc/passwd", "../../passwd", "..", ".", "a/b", "/etc/passwd",
                     "which-branch/../../../passwd", f"{secret}", "which branch", ""]:
        assert artifacts.page(session, climbing) is None, climbing
        assert artifacts.answer(session, climbing, "yes") is None, climbing

    # Nothing was created anywhere on the way past the guard.
    assert sorted(p.name for p in asking.parent.iterdir()) == ["which-branch.html"]
    assert secret.read_text() == "root:x:0:0"


def test_a_page_that_is_really_a_symlink_out_of_the_folder_is_refused(session, asking, tmp_path):
    """A valid id pointing at someone else's file: the slug check cannot see this one, the
    resolved parent can. Both halves of the guard are needed."""
    elsewhere = tmp_path / "secrets.html"
    elsewhere.write_text("<title>Private</title>the keys")
    (asking.parent / "leak.html").symlink_to(elsewhere)

    assert artifacts.page(session, "leak") is None
    assert artifacts.answer(session, "leak", "taken") is None
    assert [row["id"] for row in artifacts.listing(session)] == ["which-branch"]


def test_an_answer_file_that_is_a_symlink_out_of_the_folder_is_not_written_through(
    session, asking, tmp_path
):
    """The answer file does not exist yet, so the same check has to hold for a path being made."""
    target = tmp_path / "elsewhere.json"
    target.write_text("untouched")
    (asking.parent / "which-branch.answer.json").symlink_to(target)

    assert artifacts.answer(session, "which-branch", "develop") is None
    assert target.read_text() == "untouched"


def test_an_answer_lands_beside_the_page_and_the_listing_says_so(session, asking):
    written = artifacts.answer(session, "which-branch", {"branch": "develop", "tag": True})

    beside = asking.parent / "which-branch.answer.json"
    assert json.loads(beside.read_text()) == {
        "id": "which-branch",
        "answeredAt": written["answeredAt"],
        "value": {"branch": "develop", "tag": True},
    }
    assert written["file"] == str(beside)
    assert artifacts.listing(session)[0]["answered"] is True


def test_answering_twice_replaces_the_first_answer(session, asking):
    artifacts.answer(session, "which-branch", "main")
    artifacts.answer(session, "which-branch", "develop")

    beside = json.loads((asking.parent / "which-branch.answer.json").read_text())
    assert beside["value"] == "develop"


def test_an_answer_to_a_page_that_is_not_there_is_refused(session, asking):
    """Otherwise the phone could create files in a project by naming ids that do not exist."""
    assert artifacts.answer(session, "never-asked", "yes") is None
    assert not (asking.parent / "never-asked.answer.json").exists()


def test_the_page_comes_back_as_it_was_written(session, asking):
    assert artifacts.page(session, "which-branch") == asking.read_text()


def test_a_page_too_big_to_be_a_page_is_not_served(session, asking, monkeypatch):
    monkeypatch.setattr(artifacts, "MAX_PAGE_BYTES", 8)

    assert artifacts.page(session, "which-branch") is None
    # It still lists: the phone saying "cannot open that" beats the row vanishing.
    assert [row["id"] for row in artifacts.listing(session)] == ["which-branch"]
