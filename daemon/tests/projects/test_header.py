"""The project header: found where the agent puts it, and nothing at all when it is not there."""

from types import SimpleNamespace

from deckhand_daemon.projects import header


def test_no_header_is_nothing(tmp_path):
    assert header.found(SimpleNamespace(cwd=str(tmp_path))) is None


def test_header_is_found_and_jpg_wins(tmp_path):
    folder = tmp_path / ".deckhand"
    folder.mkdir()
    (folder / "header.png").write_bytes(b"png")
    (folder / "header.jpg").write_bytes(b"jpg")
    assert header.found(SimpleNamespace(cwd=str(tmp_path))) == folder / "header.jpg"


def test_an_oversized_header_is_not_served(tmp_path):
    folder = tmp_path / ".deckhand"
    folder.mkdir()
    (folder / "header.jpg").write_bytes(b"x" * (header.MAX_BYTES + 1))
    assert header.found(SimpleNamespace(cwd=str(tmp_path))) is None
