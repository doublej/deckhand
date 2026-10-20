"""A growing transcript is read once and then only where it grew."""

from deckhand_daemon.reading.increments import LONGEST, Increments


def _lines(path, *lines):
    with path.open("ab") as out:
        out.write(b"".join(line + b"\n" for line in lines))


def test_growth_only_and_long_lines_unread(tmp_path):
    seen = []
    reader = Increments(lambda line, _: seen.append(line) or [line], window=1 << 20, keep=100)
    path = tmp_path / "t.jsonl"
    _lines(path, b"one", b"x" * (LONGEST + 1), b"two")
    assert reader.read(path) == [b"one", b"two"]
    _lines(path, b"three")
    assert reader.read(path) == [b"one", b"two", b"three"]
    assert seen == [b"one", b"two", b"three"]  # the long line was never handed over


def test_a_window_starts_mid_file_and_a_shrunk_file_starts_again(tmp_path):
    reader = Increments(lambda line, _: [line], window=10, keep=2)
    path = tmp_path / "t.jsonl"
    _lines(path, b"aaaaaaaa", b"bbbb", b"cc")
    assert reader.read(path) == [b"bbbb", b"cc"]  # the line the window cut into is dropped
    path.write_bytes(b"dd\n")
    assert reader.read(path) == [b"dd"]
