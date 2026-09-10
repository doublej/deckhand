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


def fake_utt(jobs, answer: dict, deadline: float = 30.0):
    """Answers the first finished clip, exactly as the guide describes: pick up the audio,
    write the answer beside it, delete the audio and the hints.

    The deadline only stops a leaked thread outliving the run — it is not what the test is
    measuring, and it must stay well clear of `transcribe.TIMEOUT` (180s) or the fake is the one
    that gives up. At five seconds it did exactly that, once, on a Mac busy writing briefings.
    """

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
    heard = transcribe.transcribe(_clip(jobs))
    assert (heard.text, heard.error) == ("put the kettle on", None)
    # The stages are the point of the object: one span for the handoff, one for utt, one for
    # reading the answer, in the order they ran.
    assert list(heard.stages) == ["handoff", "utt", "answer"]


def test_the_answer_is_cleaned_up_afterwards(jobs):
    """The audio is utt's to delete; the answer file is ours, and a folder that only grows is
    a second copy of everything ever said."""
    utt = fake_utt(jobs, {"text": "hello"})
    transcribe.transcribe(_clip(jobs))
    # utt deletes the audio just after writing the answer, so the real utt may still be at it
    # when we return. Waiting for it is the test being honest about who deletes what, rather
    # than a sleep hiding a race.
    utt.join(timeout=5)
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
    heard = transcribe.transcribe(_clip(jobs))
    assert (heard.text, heard.error) == (None, "Could not transcribe that clip.")


def test_an_empty_answer_is_reported_as_nothing_heard(jobs):
    """utt answers with an empty string for silence. A blank line is not a transcript."""
    fake_utt(jobs, {"text": "   "})
    heard = transcribe.transcribe(_clip(jobs))
    assert (heard.text, heard.error) == (None, "nothing recognisable in that clip")


def test_a_closed_utt_is_named_as_the_cause(tmp_path, monkeypatch):
    """No jobs folder means utt has never run here — the app is shut, not broken."""
    monkeypatch.setenv("DECKHAND_PLUGIN_DIR", str(tmp_path))
    clip = tmp_path / "clip.wav"
    clip.write_bytes(b"RIFF")
    assert transcribe.transcribe(clip).error == "utt is not running on the Mac — open utt and try again"


def test_a_format_utt_cannot_open_is_refused_before_the_wait(jobs):
    """The extension is how AVFoundation picks its reader, so an unopenable one is a 3 minute
    wait for an answer that will never come."""
    clip = jobs.parent / "clip.webm"
    clip.write_bytes(b"x")
    assert transcribe.transcribe(clip).error == "utt cannot open .webm files"


def test_silence_from_utt_gives_up_rather_than_hanging(jobs, monkeypatch):
    monkeypatch.setattr(transcribe, "TIMEOUT", 0.05)
    heard = transcribe.transcribe(_clip(jobs))
    assert heard.text is None
    assert "did not answer" in heard.error


def test_the_hints_are_what_this_session_is_working_on(jobs):
    hints = transcribe.hints_for("warm-okapi", "/Users/jj/dev/web/shop")
    assert {"deckhand", "warm", "okapi", "shop", "web"} <= set(hints)


def _clip(jobs):
    clip = jobs.parent / "clip.wav"
    clip.write_bytes(b"RIFF....WAVE")
    return clip


def test_a_switched_off_extension_says_so_rather_than_waiting(tmp_path, monkeypatch):
    """utt stops servicing the jobs folder the moment Deckhand is disabled on its page, and the
    folder stays where it was. Without noticing the marker the clip is written, nothing ever
    reads it, and hold-to-talk blocks for the full three minutes to say utt did not answer."""
    jobs = tmp_path / "deckhand.jobs"
    jobs.mkdir()
    (tmp_path / "deckhand.disabled").touch()
    monkeypatch.setenv("DECKHAND_PLUGIN_DIR", str(tmp_path))
    clip = tmp_path / "said.wav"
    clip.write_bytes(b"pretend audio")
    heard = transcribe.transcribe(clip)
    assert heard.text is None
    assert "switched off" in heard.error
    # And nothing was handed over: a folder utt is not reading must not be filled up.
    assert not list(jobs.iterdir())


def test_a_key_utt_gains_reaches_the_phone_without_a_change_here(jobs):
    """The forward-compatible half, and the reason `_read` does not decode into fixed fields.

    utt's jobs lane answers with `text`, `error` and `finishedAt` today; `raw`, `stages` and
    `cleanupSkipped` are in scope in its own `ProcessedTranscript` and dropped at that boundary.
    The day it stops dropping them they must arrive, so anything unrecognised rides through.
    """
    fake_utt(jobs, {
        "text": "ship it",
        "finishedAt": "2026-09-10T12:00:00Z",
        "raw": "ship it,",
        "stages": ["cleanup"],
        "cleanupSkipped": None,
    })
    heard = transcribe.transcribe(_clip(jobs))
    assert heard.text == "ship it"
    # finishedAt is known and therefore not extra; the three utt has yet to send are.
    assert heard.extra == {"raw": "ship it,", "stages": ["cleanup"], "cleanupSkipped": None}


def test_utts_span_is_measured_finer_than_utt_answers():
    """`POLL` is what our observation of the answer is quantised to, and utt's span is the
    largest stage in the whole path — at the old 0.2 s it was measured with a fifth of a second
    of noise on it, which is not measurement."""
    assert transcribe.POLL <= 0.05
