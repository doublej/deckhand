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
from pathlib import Path

from . import plugin
from .log import log

# utt loads its model on the first clip after launch, and that one is slow.
TIMEOUT = 180
POLL = 0.2
AUDIO_SUFFIXES = {".wav", ".m4a", ".mp3", ".aiff", ".flac", ".caf"}


def transcribe(clip: Path, hints: list[str] | None = None) -> tuple[str | None, str | None]:
    """Returns (text, error). Never raises: a clip that cannot be transcribed is still stored."""
    if clip.suffix.lower() not in AUDIO_SUFFIXES:
        return None, f"utt cannot open {clip.suffix} files"
    jobs = plugin.jobs_dir()
    if not jobs.is_dir():
        return None, "utt is not running on the Mac — open utt and try again"
    # utt services a jobs folder only while the extension is enabled, and switching Deckhand off
    # on its own page leaves the folder sitting there. Without this the clip is written, nothing
    # ever reads it, and hold-to-talk blocks for the full three minutes before saying utt did not
    # answer — which is true and useless. The marker is an empty file beside the folder, and its
    # presence is the whole state.
    if plugin.turned_off():
        return None, "Deckhand is switched off in utt — turn it back on on its page there"
    job = jobs / f"{time.strftime('%Y%m%dT%H%M%S')}-{uuid.uuid4().hex[:8]}{clip.suffix.lower()}"
    try:
        return _run(job, clip, hints)
    except OSError as error:
        return None, f"could not hand the clip to utt: {error}"
    finally:
        _clean(job)


def _run(job: Path, clip: Path, hints: list[str] | None) -> tuple[str | None, str | None]:
    """The handoff itself: hints first, then the audio, then wait for the answer beside it."""
    if hints:
        job.with_suffix(".hints.json").write_text(json.dumps(hints))
    part = job.with_name(job.name + ".part")
    part.write_bytes(clip.read_bytes())
    part.rename(job)  # only now is it audio, and only now will utt read it
    answer = job.with_suffix(".json")
    deadline = time.monotonic() + TIMEOUT
    while time.monotonic() < deadline:
        if answer.exists():
            return _read(answer)
        time.sleep(POLL)
    return None, f"utt did not answer within {TIMEOUT}s"


def _read(answer: Path) -> tuple[str | None, str | None]:
    try:
        written = json.loads(answer.read_text())
    except (OSError, json.JSONDecodeError):
        return None, "utt wrote an answer that could not be read"
    if error := written.get("error"):
        return None, str(error)
    text = (written.get("text") or "").strip()
    # utt answers with an empty string for a clip it could make no words out of. Saying so
    # beats showing a blank line and calling it a transcript.
    return (text, None) if text else (None, "nothing recognisable in that clip")


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
