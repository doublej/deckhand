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
import shutil
import subprocess
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from . import plugin
from .log import log, took
from .settings import aliases, hints

# utt loads its model on the first clip after launch, and that one is slow.
TIMEOUT = 180
# What our own observation of utt's answer is quantised to. It was 0.2, which put a fifth of a
# second of noise on the largest stage in the whole path — measuring the one number that matters
# at a resolution coarser than the thing being measured is not measurement. 20 ms of `stat` on a
# worker thread is free by comparison, and still an order of magnitude finer than utt's own
# 300 ms pickup interval.
POLL = 0.02
AUDIO_SUFFIXES = {".wav", ".m4a", ".mp3", ".aiff", ".flac", ".caf"}
# What a browser's MediaRecorder hands over and AVFoundation cannot open: Chrome and Firefox record
# Opus in webm or ogg, Safari AAC in mp4. ffmpeg turns each into a wav before utt sees it.
CONVERTED = {".webm", ".ogg", ".mp4", ".aac"}
# What this daemon knows how to read out of utt's answer file. Everything else rides through.
KNOWN = ("text", "error", "finishedAt")
# The order utt's own stages run in. Its `timings` is a dict and a dict has no order, so this is
# where the reading order comes from; anything utt adds later lands after these rather than
# being dropped. Read off `TranscriptStage` on utt's own branch, not guessed.
STAGE_ORDER = ("decode", "hints", "replacements", "cleanup", "formatting", "filter")


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


def ready() -> bool:
    """Whether a browser's clip could be heard right now: utt servicing its jobs folder, and
    ffmpeg there to read what a browser records. Two stats and a PATH walk, cheap enough for
    `/health`, which is polled."""
    return plugin.jobs_dir().is_dir() and not plugin.turned_off() and converter() is not None


def converter() -> str | None:
    """ffmpeg, which the launchd plist's PATH finds under Homebrew."""
    return shutil.which("ffmpeg")


def transcribe(clip: Path, hints: list[str] | None = None) -> Heard:
    """Never raises: a clip that cannot be transcribed is still stored."""
    if clip.suffix.lower() in CONVERTED:
        return _converted(clip, hints)
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


def _converted(clip: Path, hints: list[str] | None) -> Heard:
    """The clip as a 16 kHz mono wav beside it, heard, and the wav gone again. The clip itself
    stays, exactly as one utt can open does."""
    ffmpeg = converter()
    if ffmpeg is None:
        return Heard(error=f"ffmpeg is needed to read {clip.suffix} files (brew install ffmpeg)")
    wav = clip.with_name(f"{clip.stem}.converted.wav")
    stages: dict[str, float] = {}
    try:
        with took(stages, "convert"):
            done = subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(clip), "-ac", "1",
                                   "-ar", "16000", str(wav)], capture_output=True, timeout=60,
                                  check=False)
        if done.returncode != 0:
            log.warning("ffmpeg could not read %s: %s", clip.name, done.stderr.decode()[-200:])
            return Heard(error=f"could not read that {clip.suffix} clip", stages=stages)
        heard = transcribe(wav, hints)
    except (OSError, subprocess.TimeoutExpired) as error:
        return Heard(error=f"could not convert the clip: {error}", stages=stages)
    finally:
        wav.unlink(missing_ok=True)
    heard.stages = stages | heard.stages
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
def hints_for(name: str, cwd: str) -> list[str]:
    """Every clip was dictated at a named session working in a known folder. Those are the
    words most likely to be in it and most likely to come back wrong, and we have them before
    the clip is even recorded.

    The aliases go in too, and only their right-hand side. An alias is a word this Mac has been
    told it gets wrong, and what it should have been — so the second half is exactly the word to
    bias the recogniser towards. The two halves of the fix are not the same fix: a hint makes the
    word less likely to come back wrong at all, and the swap in `settings/aliases.py` catches it
    when it does anyway. Only the swap can be relied on; a hint only displaces text already
    nearly it.
    """
    words = {*hints.load(), *aliases.spoken(), *name.replace("-", " ").split()}
    words.update(part for part in Path(cwd).parts[-2:] if part not in ("/", "Users"))
    return sorted(word for word in words if len(word) > 2)


def inside(span: float, heard: Heard) -> list[dict]:
    """utt's span, broken into the stretches utt measured, plus the wait in front of them.

    utt answers with a `timings` of its own — milliseconds keyed by stage name, `decode` for the
    recogniser and one entry per text stage that actually ran. It is deliberately **not** a
    subset of `stages`: a stage that ran and left the words alone is timed all the same, which is
    the whole point of having both.

    What utt cannot tell us is the part of our span that was over before utt looked. The clip
    sits in the jobs folder until `ExtensionJobs.interval` comes round, and behind whatever else
    is already queued — measured here at 2.1 s and 10.1 s for the same clip, minutes apart. That
    wait is our span minus everything utt accounted for, so it is derived rather than asked for,
    and clamped: the two measurements have different ends and a negative sliver is noise.

    Empty for a utt that sends no timings, which is every utt shipped today. The span then stays
    the single opaque number it has always been.
    """
    measured = heard.extra.get("timings")
    if not isinstance(measured, dict) or not measured:
        return []
    order = {name: spot for spot, name in enumerate(STAGE_ORDER)}
    parts = sorted(measured.items(), key=lambda pair: (order.get(pair[0], len(order)), pair[0]))
    waited = round(span - sum(value for _, value in parts), 1)
    lead = [{"name": "waiting", "ms": waited}] if waited > 0 else []
    return lead + [{"name": name, "ms": value} for name, value in parts]
