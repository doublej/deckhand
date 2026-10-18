"""The manager's `look`: what the phone can see, read whole, and nothing that is not a read.

Here rather than under `tests/manager/` because the OpenCode fake is the cheapest session that has
files: a session whose history named a file is one `fake.add` away.
"""

import anyio
from opencode_fake import NOW, info

from deckhand_daemon.manager.looking import look

SID = "ses_eba59923effeLookAtMeZ28SzabW"


def text_of(answer):
    return answer["content"][0]["text"]


def wrote(path):
    state = {"status": "completed", "input": {"path": str(path)}, "content": [{"type": "text", "text": "ok"}]}
    return {"id": "a1", "type": "assistant", "time": {"created": NOW + 1}, "agent": "build",
            "model": {"id": "claude-opus-5-5", "providerID": "anthropic"},
            "content": [{"type": "tool", "id": "call-write", "name": "write", "time": {"created": NOW},
                         "state": state}]}


def test_a_file_the_session_wrote_comes_back_whole_and_unchanged(opencode_service, tmp_path):
    spec = tmp_path / "gta-vreeswijk-SPEC.md"
    body = "# Spec\n" + "every line of it, unchanged\n" * 2000  # far past any preview
    spec.write_text(body)
    opencode_service.add(info(SID, "nimble-dunlin"), messages=[wrote(spec)])
    listed = anyio.run(look, "/files", "nimble-dunlin")
    assert str(spec) in text_of(listed)
    assert text_of(anyio.run(look, f"/file?path={spec}", SID)) == body


def test_a_picture_comes_back_as_a_picture(opencode_service, tmp_path):
    shot = tmp_path / "shot.png"
    shot.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 16)
    opencode_service.add(info(SID, "nimble-dunlin"), messages=[wrote(shot)])
    seen = anyio.run(look, f"/file?path={shot}", SID)["content"][0]
    assert (seen["type"], seen["mimeType"]) == ("image", "image/png")


def test_what_the_session_never_named_stays_unreadable(opencode_service, tmp_path):
    opencode_service.add(info(SID, "nimble-dunlin"), messages=[])
    secret = tmp_path / "elsewhere.md"
    secret.write_text("not this session's")
    assert text_of(anyio.run(look, f"/file?path={secret}", SID)).startswith("404")


def test_reads_that_are_not_only_reads_and_reads_with_no_end_are_refused(claude_home):
    assert "silence the phone" in text_of(anyio.run(look, "/manager?since=0"))
    assert "no end" in text_of(anyio.run(look, "/windows/12/stream"))
    assert "goes nowhere up" in text_of(anyio.run(look, "/sessions/../../etc"))
    assert "no live session" in text_of(anyio.run(look, "/files", "nobody-by-this-name"))


def test_any_page_the_phone_reads_reads_here_too(claude_home):
    assert '"where"' in text_of(anyio.run(look, "/presence"))
