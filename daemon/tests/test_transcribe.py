import subprocess

from deckhand_daemon import transcribe


def test_the_environment_wins_over_a_1password_read(monkeypatch):
    monkeypatch.setattr(transcribe, "_token", None)
    monkeypatch.setenv("UTT_SECRET", "from-env")
    assert transcribe.token() == "from-env"


def test_the_token_comes_from_onenv_when_the_environment_is_bare(monkeypatch, tmp_path):
    monkeypatch.setattr(transcribe, "_token", None)
    monkeypatch.delenv("UTT_SECRET", raising=False)
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "empty"))
    seen = {}

    def fake_run(cmd, **kwargs):
        seen["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0, stdout="from-1password\n", stderr="")

    monkeypatch.setattr(transcribe.subprocess, "run", fake_run)
    assert transcribe.token() == "from-1password"
    assert seen["cmd"] == ["onenv", "get", "deckhand", "UTT_SECRET"]


def test_no_token_means_a_message_not_a_crash(monkeypatch, tmp_path):
    monkeypatch.setattr(transcribe, "_token", None)
    monkeypatch.delenv("UTT_SECRET", raising=False)
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "empty"))
    monkeypatch.setattr(
        transcribe.subprocess,
        "run",
        lambda cmd, **kw: subprocess.CompletedProcess(cmd, 1, stdout="", stderr="no such item"),
    )
    assert transcribe.transcribe(tmp_path / "clip.m4a") == (
        None,
        "no utt token on this Mac — run `just sync-secrets`",
    )


def test_onenv_hanging_under_launchd_is_survivable(monkeypatch, tmp_path):
    """1Password cannot ask for a fingerprint from a launchd agent, so the read times out."""
    monkeypatch.setattr(transcribe, "_token", None)
    monkeypatch.delenv("UTT_SECRET", raising=False)
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(tmp_path / "empty"))

    def hang(cmd, **kwargs):
        raise subprocess.TimeoutExpired(cmd, 10)

    monkeypatch.setattr(transcribe.subprocess, "run", hang)
    assert transcribe.token() is None


def test_the_materialised_file_is_used_before_1password(monkeypatch, tmp_path):
    monkeypatch.setattr(transcribe, "_token", None)
    monkeypatch.delenv("UTT_SECRET", raising=False)
    data = tmp_path / "data"
    data.mkdir()
    (data / "utt-token").write_text("from-file\n")
    monkeypatch.setenv("DECKHAND_DATA_DIR", str(data))
    monkeypatch.setattr(transcribe.subprocess, "run", lambda *a, **k: 1 / 0)
    assert transcribe.token() == "from-file"


def test_every_recorded_format_maps_to_a_decoder():
    assert transcribe.CONTENT_TYPES[".m4a"] == "audio/mp4"
    assert transcribe.CONTENT_TYPES[".wav"] == "audio/wav"


def test_an_empty_answer_is_reported_as_nothing_heard(monkeypatch, tmp_path):
    """utt answers 200 with an empty string when the clip is silence."""
    import urllib.request

    monkeypatch.setattr(transcribe, "_token", "t")
    clip = tmp_path / "clip.m4a"
    clip.write_bytes(b"x")
    monkeypatch.setattr(
        urllib.request, "urlopen", lambda *a, **k: _Response(b'{"text": "   "}')
    )
    assert transcribe.transcribe(clip) == (None, "nothing recognisable in that clip")


class _Response:
    def __init__(self, body: bytes):
        self._body = body

    def read(self) -> bytes:
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False
