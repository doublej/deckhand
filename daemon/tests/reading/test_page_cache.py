"""`page_turns` keeps a page per file state, and hands out copies of it."""

import json

from deckhand_daemon.reading import transcripts


def test_a_kept_page_is_reread_when_the_file_grows_and_cannot_be_changed_by_a_caller(
        tmp_path, monkeypatch):
    path = tmp_path / "s.jsonl"
    said = {"type": "assistant", "timestamp": "t", "message": {"content": [{"type": "text"}]}}
    path.write_text(json.dumps(said | {"message": {"content": [{"type": "text", "text": "one"}]}})
                    + "\n")
    monkeypatch.setattr(transcripts, "transcript_path", lambda _: path)

    turns, _ = transcripts.page_turns("s", 4)
    turns[0].text = "scribbled on"
    turns.clear()
    assert [t.text for t in transcripts.page_turns("s", 4)[0]] == ["one"]

    with path.open("a") as grown:
        grown.write(json.dumps(said | {"message": {"content": [{"type": "text", "text": "two"}]}})
                    + "\n")
    assert [t.text for t in transcripts.page_turns("s", 4)[0]] == ["one", "two"]
