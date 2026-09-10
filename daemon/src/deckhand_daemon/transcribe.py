"""Speech to text through utt, over the file lane utt gives its plugins.

No socket, no token, nothing on the network: the clip is written into
`<plugins>/deckhand.jobs/`, utt transcribes it on-device and writes the text beside it. This
works whether or not utt's HTTP API is switched on, which is the point — the API being off was
the single most common reason a clip came back with nothing.

The name matters twice. A clip is written as `<name>.wav.part` and only renamed to `<name>.wav`
once it is whole, because utt picks up finished audio extensions and would otherwise read a
half-written file. And the extension has to match the bytes: AVFoundation chooses its reader
from the extension, so a wav named `.m4a` fails to open however correct it is.
"""

from __future__ import annotations

import json
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from . import plugin
from .log import log, took

# utt loads its model on the first clip after launch, and that one is slow.
TIMEOUT = 180
# What our own observation of utt's answer is quantised to. It was 0.2, which put a fifth of a
# second of noise on the largest stage in the whole path — measuring the one number that matters
# at a resolution coarser than the thing being measured is not measurement. 20 ms of `stat` on a
# worker thread is free by comparison, and still an order of magnitude finer than utt's own
# 300 ms pickup interval.
POLL = 0.02
AUDIO_SUFFIXES = {".wav", ".m4a", ".mp3", ".aiff", ".flac", ".caf"}
# What this daemon knows how to read out of utt's answer file. Everything else rides through.
KNOWN = ("text", "error", "finishedAt")


@dataclass
class Heard:
    """What utt made of one clip, what each part of the handoff cost, and anything utt said
    that this daemon has no name for.

    `extra` is the forward-compatible half and it is deliberately not a fixed list of fields.
    utt's jobs lane answers with `text`, `error` and `finishedAt` today; its own pipeline holds
    `raw`, `stages` and `cleanupSkipped` in a `ProcessedTranscript` and drops them at that
    boundary. When utt stops dropping them they appear on the phone with no change here.
    """

    text: str | None = None
    error: str | None = None
    #: Milliseconds per stage, in the order they ran.
    stages: dict[str, float] = field(default_factory=dict)
    #: Every key utt wrote that is not in `KNOWN`, verbatim — camel case and all.
    extra: dict = field(default_factory=dict)


def transcribe(clip: Path, hints: list[str] | None = None) -> Heard:
    """Never raises: a clip that cannot be transcribed is still stored."""
    if clip.suffix.lower() not in AUDIO_SUFFIXES:
        return Heard(error=f"utt cannot open {clip.suffix} files")
    jobs = plugin.jobs_dir()
    if not jobs.is_dir():
        return Heard(error="utt is not running on the Mac — open utt and try again")
    # utt services a jobs folder only while the extension is enabled, and switching Deckhand off
    # on its own page leaves the folder sitting there. Without this the clip is written, nothing
    # ever reads it, and hold-to-talk blocks for the full three minutes before saying utt did not
    # answer — which is true and useless. The marker is an empty file beside the folder, and its
    # presence is the whole state.
    if plugin.turned_off():
        return Heard(error="Deckhand is switched off in utt — turn it back on on its page there")
    job = jobs / f"{time.strftime('%Y%m%dT%H%M%S')}-{uuid.uuid4().hex[:8]}{clip.suffix.lower()}"
    stages: dict[str, float] = {}
    try:
        heard = _run(job, clip, hints, stages)
    except OSError as error:
        heard = Heard(error=f"could not hand the clip to utt: {error}")
    finally:
        _clean(job)
    heard.stages = stages
    return heard


def _run(job: Path, clip: Path, hints: list[str] | None, stages: dict[str, float]) -> Heard:
    """The handoff itself: hints first, then the audio, then wait for the answer beside it."""
    with took(stages, "handoff"):
        if hints:
            job.with_suffix(".hints.json").write_text(json.dumps(hints))
        part = job.with_name(job.name + ".part")
        part.write_bytes(clip.read_bytes())
        part.rename(job)  # only now is it audio, and only now will utt read it
    answer = job.with_suffix(".json")
    with took(stages, "utt"):
        answered = _wait(answer)
    if not answered:
        return Heard(error=f"utt did not answer within {TIMEOUT}s")
    with took(stages, "answer"):
        return _read(answer)


def _wait(answer: Path) -> bool:
    """utt's span, and it is one span on purpose.

    From the rename that makes the clip visible to utt, to an answer file appearing beside it.
    It cannot honestly be split: `ExtensionJobResult` carries no timings, utt announces its
    pickup only to in-process listeners, and it deletes the audio *after* writing the answer —
    so the disappearance of the clip marks the end of this span, never the start of utt's work.

    Up to 300 ms of whatever this reports is utt not having looked yet (`ExtensionJobs.interval`),
    which is the difference between "utt is slow" and "utt has not noticed". The app says so
    under the number.
    """
    deadline = time.monotonic() + TIMEOUT
    while time.monotonic() < deadline:
        if answer.exists():
            return True
        time.sleep(POLL)
    return False


def _read(answer: Path) -> Heard:
    try:
        written = json.loads(answer.read_text())
    except (OSError, json.JSONDecodeError):
        return Heard(error="utt wrote an answer that could not be read")
    # Anything utt writes beside the three keys this daemon knows rides through untouched, so a
    # field utt gains reaches the phone without a change here. Dropping unknown keys is what
    # would make that a release rather than a restart.
    extra = {key: value for key, value in written.items() if key not in KNOWN}
    if error := written.get("error"):
        return Heard(error=str(error), extra=extra)
    text = (written.get("text") or "").strip()
    # utt answers with an empty string for a clip it could make no words out of. Saying so
    # beats showing a blank line and calling it a transcript.
    if not text:
        return Heard(error="nothing recognisable in that clip", extra=extra)
    return Heard(text=text, extra=extra)


def _clean(job: Path) -> None:
    """The answer file is ours to remove; utt deletes the audio and the hints itself."""
    for leftover in (job.with_suffix(".json"), job.with_name(job.name + ".part")):
        try:
            leftover.unlink(missing_ok=True)
        except OSError as error:
            log.warning("could not tidy %s: %s", leftover.name, error)


# Words utt hears wrong because it has never heard them: the product's own name, the tools
# this repo is built with, terms of art. A term only displaces text that is already nearly it
# and starts with the same letter, so this list cannot rewrite a sentence — it can only catch
# "cockwheel", "Tu Y", "deck hand". It cannot fix an ordinary word misheard as another.
VOCABULARY = (
    "deckhand", "utt", "launchd", "onenv", "XcodeGen", "SwiftLint", "SwiftUI", "FastAPI",
    "iTerm", "TUI", "cogwheel", "JSONL", "daemon", "transcript", "socket", "Claude",
)


def hints_for(name: str, cwd: str) -> list[str]:
    """Every clip was dictated at a named session working in a known folder. Those are the
    words most likely to be in it and most likely to come back wrong, and we have them before
    the clip is even recorded."""
    words = {*VOCABULARY, *name.replace("-", " ").split()}
    words.update(part for part in Path(cwd).parts[-2:] if part not in ("/", "Users"))
    return sorted(word for word in words if len(word) > 2)
