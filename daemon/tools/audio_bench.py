"""How far a clip can be sped up and silence-trimmed before utt stops hearing it.

An experiment, not a feature. It re-encodes real clips out of `~/Library/Application
Support/Deckhand/audio/` at a sweep of tempos, with and without silence removal, pushes every
one through the same jobs-folder lane the daemon uses, and scores the text against the clip's
own as-shipped transcript.

    uv run --directory daemon python tools/audio_bench.py            # run the sweep
    uv run --directory daemon python tools/audio_bench.py --report   # re-read the results
    uv run --directory daemon python tools/audio_bench.py --self-check

Two things to know before reading a number off it. Every job carries up to utt's 300 ms folder
scan plus this lane's 200 ms poll, so nothing here resolves finer than half a second — medians,
never means. And the reference is the clip's own transcript, not ground truth: this measures
how far a condition moves the words, not whether they were right to begin with.

Jobs queue behind the live daemon's, so a sweep makes real dictation slower while it runs.
"""

from __future__ import annotations

import argparse
import json
import random
import statistics
import subprocess
import time
from pathlib import Path

from deckhand_daemon import transcribe

FFMPEG = "/opt/homebrew/bin/ffmpeg"
FFPROBE = "/opt/homebrew/bin/ffprobe"
AUDIO = Path.home() / "Library/Application Support/Deckhand/audio"
RESULTS = Path(__file__).with_name("audio-bench.jsonl")
SEED = 20260910

# Trim first, then speed. The other order measures the pauses after they have already been
# shortened, so a 0.6 s breath falls under the threshold and survives — which is the opposite
# of what the filter is for. Thresholds are RMS: leading silence goes but 0.10 s is left so the
# clip does not open mid-syllable, and any pause past 0.50 s is cut back to 0.20 s, which keeps
# the boundary a listener uses to tell one sentence from the next.
TRIM = ("silenceremove=start_periods=1:start_duration=0:start_silence=0.10:"
        "start_threshold=-40dB:stop_periods=-1:stop_duration=0.50:stop_silence=0.20:"
        "stop_threshold=-40dB:detection=rms")
# atempo, not a resample: it preserves pitch, so formants stay where a speech model expects
# them and the result is a tempo measurement rather than a chipmunk measurement.
SPEEDS = (1.0, 1.25, 1.5, 1.75, 2.0)
# What the phone records: AAC-LC, 16 kHz, mono. Matching it keeps the byte column honest.
ENCODE = ("-c:a", "aac", "-b:a", "24k", "-ar", "16000", "-ac", "1")
# Long enough that utt has words to work with, short enough to bound the sweep.
BANDS = ((1.0, 3.0), (3.0, 8.0), (8.0, 15.0), (15.0, 25.0), (25.0, 60.0))


def probe(clip: Path) -> float:
    """Seconds of audio, straight from the container."""
    done = subprocess.run([FFPROBE, "-v", "quiet", "-show_entries", "format=duration",
                           "-of", "default=nw=1:nk=1", str(clip)],
                          capture_output=True, text=True, check=False)
    try:
        return float(done.stdout.strip())
    except ValueError:
        return 0.0


def pick(count: int) -> list[tuple[Path, float]]:
    """An even spread across the length bands, taken by index so the same clips come back."""
    everything = [(path, probe(path)) for path in sorted(AUDIO.rglob("*.m4a"))]
    per = max(1, count // len(BANDS))
    chosen: list[tuple[Path, float]] = []
    for low, high in BANDS:
        inside = sorted((row for row in everything if low <= row[1] < high), key=lambda r: r[1])
        if not inside:
            continue
        step = max(1, len(inside) // per)
        chosen.extend(inside[::step][:per])
    return chosen


def encode(source: Path, destination: Path, speed: float, trim: bool) -> None:
    """One condition, written as m4a because AVFoundation reads the extension, not the bytes."""
    stages = ([TRIM] if trim else []) + ([f"atempo={speed}"] if speed != 1.0 else [])
    filters = ",".join(stages) or "anull"
    subprocess.run([FFMPEG, "-v", "error", "-y", "-i", str(source), "-af", filters,
                    *ENCODE, str(destination)], check=True, capture_output=True)


def normalise(text: str) -> list[str]:
    """Case, punctuation and whitespace only. Apostrophes stay, because "don't" and "dont" are
    the same mistake twice and counting it would flatter every condition equally."""
    kept = [character.lower() if character.isalnum() or character == "'" else " "
            for character in text.replace("’", "'")]
    return "".join(kept).split()


def distance(one: list, two: list) -> int:
    """Levenshtein, two rows. Works on tokens or on characters."""
    previous = list(range(len(two) + 1))
    for index, left in enumerate(one, 1):
        row = [index]
        for column, right in enumerate(two, 1):
            row.append(min(previous[column] + 1, row[column - 1] + 1,
                           previous[column - 1] + (left != right)))
        previous = row
    return previous[-1]


def error_rates(reference: str, heard: str) -> tuple[float, float]:
    """WER then CER, both against the reference's own length."""
    words, said = normalise(reference), normalise(heard)
    letters, spoken = " ".join(words), " ".join(said)
    wer = distance(words, said) / len(words) if words else float(len(said) > 0)
    cer = distance(list(letters), list(spoken)) / len(letters) if letters else 0.0
    return wer, cer


def conditions() -> list[tuple[str, float | None, bool]]:
    """The as-shipped clip first — it is the reference every other row is scored against."""
    rows: list[tuple[str, float | None, bool]] = [("original", None, False)]
    rows += [(f"{speed:.2f}x{'+trim' if trim else ''}", speed, trim)
             for speed in SPEEDS for trim in (False, True)]
    return rows


def listen(clip: Path) -> tuple[str | None, str | None, float]:
    """One trip through the lane, wall-clock included. Hints are constant so they cannot be
    what moved a number; they are the daemon's own list, so the run stays production-shaped."""
    started = time.monotonic()
    text, error = transcribe.transcribe(clip, list(transcribe.VOCABULARY))
    return text, error, time.monotonic() - started


def run(count: int, scratch: Path) -> None:
    clips = pick(count)
    print(f"{len(clips)} clips, {len(conditions())} conditions, "
          f"{len(clips) * len(conditions())} jobs")
    done = {(row["clip"], row["condition"]) for row in read()}
    jobs = [(clip, seconds, name, speed, trim)
            for clip, seconds in clips for name, speed, trim in conditions()
            if (clip.name, name) not in done]
    random.Random(SEED).shuffle(jobs)  # so a condition cannot correlate with when it ran
    if not jobs:
        print("nothing left to run")
        return
    if not done:
        print("warming utt (the first clip after launch loads the model)...")
        listen(clips[0][0])
    scratch.mkdir(parents=True, exist_ok=True)
    with RESULTS.open("a") as sink:
        for index, (clip, seconds, name, speed, trim) in enumerate(jobs, 1):
            row = measure(clip, seconds, name, speed, trim, scratch)
            sink.write(json.dumps(row) + "\n")
            sink.flush()
            print(f"[{index}/{len(jobs)}] {clip.name} {name:<12} "
                  f"{row['utt_seconds']:5.2f}s {row['error'] or ''}")


def measure(clip: Path, seconds: float, name: str, speed: float | None, trim: bool,
            scratch: Path) -> dict:
    """Encode if the condition asks for it, then time one trip through utt."""
    if speed is None:
        target, duration = clip, seconds
    else:
        target = scratch / f"{clip.stem}-{name.replace('.', '')}.m4a"
        encode(clip, target, speed, trim)
        duration = probe(target)
    text, error, elapsed = listen(target)
    return {"clip": clip.name, "condition": name, "speed": speed, "trim": trim,
            "source_seconds": round(seconds, 3), "seconds": round(duration, 3),
            "bytes": target.stat().st_size, "utt_seconds": round(elapsed, 3),
            "text": text, "error": error}


def read() -> list[dict]:
    if not RESULTS.exists():
        return []
    return [json.loads(line) for line in RESULTS.read_text().splitlines() if line.strip()]


def band_of(seconds: float) -> str:
    for low, high in BANDS:
        if low <= seconds < high:
            return f"{low:g}-{high:g}s"
    return "other"


def scored(rows: list[dict]) -> list[dict]:
    """Every row joined to its clip's as-shipped transcript and scored against it."""
    reference = {row["clip"]: row["text"] for row in rows
                 if row["condition"] == "original" and row["text"]}
    out = []
    for row in rows:
        truth = reference.get(row["clip"])
        if not truth:
            continue
        wer, cer = (0.0, 0.0) if row["condition"] == "original" else \
            error_rates(truth, row["text"] or "")
        out.append({**row, "wer": wer, "cer": cer, "band": band_of(row["source_seconds"]),
                    "cost": row["utt_seconds"] / row["source_seconds"]})
    return out


def quantile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(fraction * len(ordered)))]


def summarise(rows: list[dict]) -> dict:
    median = statistics.median
    return {"n": len(rows),
            "seconds": median([r["seconds"] for r in rows]),
            "bytes": median([r["bytes"] for r in rows]),
            "utt": median([r["utt_seconds"] for r in rows]),
            "cost": median([r["cost"] for r in rows]),
            "wer": median([r["wer"] for r in rows]),
            "wer90": quantile([r["wer"] for r in rows], 0.9),
            "wermax": max(r["wer"] for r in rows),
            "cer": median([r["cer"] for r in rows]),
            "clean": sum(1 for r in rows if r["wer"] == 0.0),
            "failed": sum(1 for r in rows if r["error"])}


def report() -> None:
    rows = scored(read())
    if not rows:
        print(f"no results in {RESULTS}")
        return
    order = [name for name, _, _ in conditions()]
    base = summarise([r for r in rows if r["condition"] == "original"])["utt"]
    print(f"\n{len(rows)} scored jobs over {len({r['clip'] for r in rows})} clips. "
          f"Medians unless named. Reference: each clip's own as-shipped transcript.\n")
    head = ("condition", "n", "dur s", "KB", "utt s", "vs base", "s/orig s",
            "WER", "WER p90", "WER max", "CER", "clean")
    print("  ".join(f"{column:>8}" for column in head))
    for name in order:
        inside = [r for r in rows if r["condition"] == name]
        if not inside:
            continue
        it = summarise(inside)
        print("  ".join(f"{value:>8}" for value in (
            f"{name:<8}", it["n"], f"{it['seconds']:.1f}", f"{it['bytes'] / 1024:.1f}",
            f"{it['utt']:.2f}", f"{it['utt'] / base:.2f}", f"{it['cost']:.2f}",
            f"{it['wer']:.3f}", f"{it['wer90']:.3f}", f"{it['wermax']:.3f}",
            f"{it['cer']:.3f}", f"{it['clean']}/{it['n']}")))
    print("\nmedian WER by clip length")
    bands = [f"{low:g}-{high:g}s" for low, high in BANDS]
    print("  ".join(f"{column:>10}" for column in ["condition", *bands]))
    for name in order:
        cells = [f"{name:<10}"]
        for band in bands:
            inside = [r for r in rows if r["condition"] == name and r["band"] == band]
            cells.append(f"{statistics.median([r['wer'] for r in inside]):.3f}"
                         if inside else "-")
        print("  ".join(f"{cell:>10}" for cell in cells))


def self_check() -> None:
    assert normalise("Don't  — STOP, it's 3.") == ["don't", "stop", "it's", "3"]
    assert distance(list("kitten"), list("sitting")) == 3
    assert distance([], ["a", "b"]) == 2
    assert error_rates("one two three", "one two three") == (0.0, 0.0)
    wer, cer = error_rates("one two three four", "one two three")
    assert wer == 0.25 and 0 < cer < 0.5
    assert error_rates("one two", "")[0] == 1.0
    assert error_rates("", "anything")[0] == 1.0
    assert band_of(2.0) == "1-3s" and band_of(90.0) == "other"
    assert [name for name, _, _ in conditions()][:3] == ["original", "1.00x", "1.00x+trim"]
    print("ok")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clips", type=int, default=25)
    parser.add_argument("--scratch", type=Path, default=Path("/tmp/deckhand-audio-bench"))
    parser.add_argument("--report", action="store_true", help="re-read the results and stop")
    parser.add_argument("--self-check", action="store_true", help="check the scoring and stop")
    options = parser.parse_args()
    if options.self_check:
        return self_check()
    if not options.report:
        run(options.clips, options.scratch)
    report()


if __name__ == "__main__":
    main()
