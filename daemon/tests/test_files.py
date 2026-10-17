import json

from deckhand_daemon import files

SID = "aaaa1111-2222-3333-4444-555566667777"


def write_transcript(home, entries, session_id=SID):
    path = home / "projects" / "-Users-jj-dev" / f"{session_id}.jsonl"
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n")
    return path


def ran(tool, **supplied):
    return {
        "type": "assistant",
        "message": {"content": [{"type": "tool_use", "id": "t1", "name": tool, "input": supplied}]},
    }


def test_finds_what_the_session_read_and_wrote(claude_home, tmp_path):
    shot = tmp_path / "shot.png"
    shot.write_bytes(b"\x89PNG fake")
    note = tmp_path / "report.md"
    note.write_text("# what happened\n")
    write_transcript(claude_home, [ran("Read", file_path=str(shot)), ran("Write", file_path=str(note))])

    found = files.readable_files(SID, str(tmp_path))

    assert {(a.name, a.kind) for a in found} == {("shot.png", "image"), ("report.md", "text")}


def test_a_relative_path_is_read_against_the_session_s_folder(claude_home, tmp_path):
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "plan.md").write_text("the plan")
    write_transcript(claude_home, [ran("Read", file_path="docs/plan.md")])

    found = files.readable_files(SID, str(tmp_path))

    assert [a.path for a in found] == [str((tmp_path / "docs" / "plan.md").resolve())]


def test_source_and_machinery_are_left_out(claude_home, tmp_path):
    (tmp_path / "node_modules").mkdir()
    junk = tmp_path / "node_modules" / "readme.md"
    junk.write_text("not yours")
    code = tmp_path / "app.swift"
    code.write_text("struct App {}")
    write_transcript(claude_home, [ran("Read", file_path=str(junk)), ran("Read", file_path=str(code))])

    assert files.readable_files(SID, str(tmp_path)) == []


def test_a_path_the_transcript_never_named_cannot_be_read(claude_home, tmp_path):
    seen = tmp_path / "seen.md"
    seen.write_text("fine")
    secret = tmp_path / "secret.md"
    secret.write_text("not fine")
    write_transcript(claude_home, [ran("Read", file_path=str(seen))])

    assert files.allowed(SID, str(tmp_path), str(seen.resolve())) == seen.resolve()
    assert files.allowed(SID, str(tmp_path), str(secret.resolve())) is None


def test_one_file_named_two_ways_is_one_row(claude_home, tmp_path):
    note = tmp_path / "notes.md"
    note.write_text("once")
    write_transcript(
        claude_home,
        [ran("Read", file_path=str(note)), ran("Read", file_path="notes.md")],
    )

    assert len(files.readable_files(SID, str(tmp_path))) == 1


def test_a_clip_the_session_talked_about_is_listed_as_audio(claude_home, tmp_path):
    # Named in a command rather than handed to a tool as a path, which is how most audio a
    # session makes gets mentioned: it renders one and then plays or converts it.
    clip = tmp_path / "take.m4a"
    clip.write_bytes(b"\x00\x00\x00\x20ftypM4A ")
    write_transcript(claude_home, [ran("Bash", command=f"afplay {clip}")])

    assert [(a.name, a.kind) for a in files.readable_files(SID, str(tmp_path))] == [
        ("take.m4a", "audio")
    ]


def test_the_names_are_kept_until_the_transcript_moves(claude_home, tmp_path, monkeypatch):
    """The scan is kept per transcript size and mtime; a file named after it must still show."""
    first = tmp_path / "first.md"
    first.write_text("one")
    later = tmp_path / "later.md"
    later.write_text("two")
    path = write_transcript(claude_home, [ran("Read", file_path=str(first))])
    assert [a.name for a in files.readable_files(SID, str(tmp_path))] == ["first.md"]

    scans = []
    scan = files._distinct
    monkeypatch.setattr(files, "_distinct", lambda lines, cwd: scans.append(1) or scan(lines, cwd))
    files.readable_files(SID, str(tmp_path))
    assert scans == []  # unchanged transcript, no second scan

    with path.open("a") as grown:
        grown.write(json.dumps(ran("Read", file_path=str(later))) + "\n")
    assert {a.name for a in files.readable_files(SID, str(tmp_path))} == {"first.md", "later.md"}
    assert scans == [1]
