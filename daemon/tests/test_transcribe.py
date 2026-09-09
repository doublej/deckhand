import json
import threading
import time
from pathlib import Path

import pytest

from deckhand_daemon import plugin, transcribe


@pytest.fixture
def jobs(tmp_path, monkeypatch):
    """utt's side of the lane: the folder it watches, made the way utt makes it."""
    monkeypatch.setenv("DECKHAND_PLUGIN_DIR", str(tmp_path))
    directory = plugin.jobs_dir()
    directory.mkdir()
    monkeypatch.setattr(transcribe, "POLL", 0.01)
    return directory


def fake_utt(jobs, answer: dict, deadline: float = 5.0):
    """Answers the first finished clip, exactly as the guide describes: pick up the audio,
    write the answer beside it, delete the audio and the hints."""

    def work():
        stop = time.monotonic() + deadline
        while time.monotonic() < stop:
            for clip in jobs.glob("*.wav"):
                clip.with_suffix(".json").write_text(json.dumps(answer))
                clip.unlink()
                return
            time.sleep(0.01)

    thread = threading.Thread(target=work, daemon=True)
    thread.start()
    return thread


def test_a_clip_becomes_text(jobs):
    fake_utt(jobs, {"text": "  put the kettle on  "})
    assert transcribe.transcribe(_clip(jobs)) == ("put the kettle on", None)


def test_the_answer_is_cleaned_up_afterwards(jobs):
    """The audio is utt's to delete; the answer file is ours, and a folder that only grows is
    a second copy of everything ever said."""
    fake_utt(jobs, {"text": "hello"})
    transcribe.transcribe(_clip(jobs))
    assert list(jobs.iterdir()) == []


def test_nothing_is_visible_to_utt_until_it_is_complete(jobs, monkeypatch):
    """The rename is the whole contract. utt picks up finished audio extensions, so the clip
    must be whole before it wears one — and the hints must already be there, because a hints
    file written afterwards is one utt has run past. Watching the folder would race; this
    asks the rename itself what the world looked like when it happened."""
    at_rename: dict = {}
    real = Path.rename

    def record(self, target):
        at_rename["name"] = self.name
        at_rename["bytes"] = self.stat().st_size
        at_rename["hints"] = [p.name for p in self.parent.glob("*.hints.json")]
        return real(self, target)

    monkeypatch.setattr(Path, "rename", record)
    fake_utt(jobs, {"text": "done"})
    transcribe.transcribe(_clip(jobs), ["deckhand", "TUI"])
    assert at_rename["name"].endswith(".wav.part")
    assert at_rename["bytes"] == len(b"RIFF....WAVE")
    assert at_rename["hints"], "the hints were written after the audio became visible"


def test_an_error_from_utt_is_passed_on_as_it_is(jobs):
    fake_utt(jobs, {"error": "Could not transcribe that clip."})
    assert transcribe.transcribe(_clip(jobs)) == (None, "Could not transcribe that clip.")


def test_an_empty_answer_is_reported_as_nothing_heard(jobs):
    """utt answers with an empty string for silence. A blank line is not a transcript."""
    fake_utt(jobs, {"text": "   "})
    assert transcribe.transcribe(_clip(jobs)) == (None, "nothing recognisable in that clip")


def test_a_closed_utt_is_named_as_the_cause(tmp_path, monkeypatch):
    """No jobs folder means utt has never run here — the app is shut, not broken."""
    monkeypatch.setenv("DECKHAND_PLUGIN_DIR", str(tmp_path))
    clip = tmp_path / "clip.wav"
    clip.write_bytes(b"RIFF")
    assert transcribe.transcribe(clip) == (
        None,
        "utt is not running on the Mac — open utt and try again",
    )


def test_a_format_utt_cannot_open_is_refused_before_the_wait(jobs):
    """The extension is how AVFoundation picks its reader, so an unopenable one is a 3 minute
    wait for an answer that will never come."""
    clip = jobs.parent / "clip.webm"
    clip.write_bytes(b"x")
    assert transcribe.transcribe(clip) == (None, "utt cannot open .webm files")


def test_silence_from_utt_gives_up_rather_than_hanging(jobs, monkeypatch):
    monkeypatch.setattr(transcribe, "TIMEOUT", 0.05)
    text, error = transcribe.transcribe(_clip(jobs))
    assert text is None
    assert "did not answer" in error


def test_the_hints_are_what_this_session_is_working_on(jobs):
    hints = transcribe.hints_for("warm-okapi", "/Users/jj/dev/web/shop")
    assert {"deckhand", "warm", "okapi", "shop", "web"} <= set(hints)


def _clip(jobs):
    clip = jobs.parent / "clip.wav"
    clip.write_bytes(b"RIFF....WAVE")
    return clip
