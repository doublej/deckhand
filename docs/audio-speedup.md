# Speeding a clip up before utt hears it

> An experiment with a negative result. The prize was inference time; the prize is
> **0.27 seconds** on a typical clip, and the failures it buys are fluent sentences with the
> meaning changed.

## The recommendation

**Do not re-encode clips faster, and do not trim silence on the phone.** Ship neither.

utt's cost is almost entirely fixed. Measured across twelve clean points spanning 1.7 s to
42.2 s of audio:

```
utt wall clock = 1.38 s + 0.068 x audio_seconds        R² = 0.925
```

Deckhand's median clip is 12.2 s. Halving it saves **0.41 s of 2.20 s**. On the ~8 s clip this
started from, 2.0× saves **0.27 s of 1.92 s**. On a 3.4 s clip it saves nothing measurable —
1.65 s becomes 1.64 s. The saving only becomes interesting above ~40 s of audio, where 2.0×
takes 3.95 s down to 2.90 s, and clips that long are 22% of the corpus.

Against that, the sample that was scored before the run was stopped shows 1.5× already moving
words, and moving them in the worst possible way — see [the failures](#what-going-faster-breaks).
A quarter of a second is not worth a prompt that says the opposite of what was said.

**One thing here is worth shipping, and it has nothing to do with speed.** Every clip the phone
records carries an `mp4` `free` atom — padding, not audio. All 326 clips have one, 18–32 KB
each, median 23 KB, **36.8% of the median file**; 7.5 MB of the corpus's 24 MB is nothing.
Stripping it is lossless, costs no accuracy risk of any kind, and is a bigger byte win than
2.0× is. Bytes were never the prize, but this one is free.

## What was measured, and what was not

**Measured, and trustworthy:** utt's inference cost against audio length, on a serialized,
repeated, minimum-of-N instrument. Twelve points, stable to under 1% run to run.

**Measured, and thin:** accuracy. 43 jobs landed before the sweep was stopped, of which only
**10 are scoreable across 3 clips** — a row can only be scored once that clip's own reference
row exists, and the run order is shuffled. Every accuracy statement below is a direction with
n = 1 or 2 behind each cell. It is not a cliff measurement and must not be quoted as one.

**Not measured at all:** where the accuracy limit actually sits. That was JJ's question and it
is still open. It was left open deliberately: the timing result caps the prize at ~0.27 s for a
typical clip, and no accuracy risk is worth 0.27 s, so spending another ~90 minutes of contended
utt — during which JJ's own dictation gets slower — to locate a cliff nobody should walk toward
was not worth it. If the answer is wanted anyway, [the re-run](#running-it-again) is cheap now.

## utt's cost is fixed, not per-second

The first attempt at this measured `rename → answer` wall clock inside a 275-job sweep and
produced nonsense: a 42.2 s clip in 7.83 s and a 1.8 s clip in 21.99 s, non-monotonic in both
directions, regression slope 0.085 s/s at r = 0.113. Halving one clip's audio appeared to make
it ten times slower.

**That was not utt and it was not concurrency in the bench.** The bench calls `transcribe()`
strictly one at a time; nothing in it overlaps. The contention was external:
`mediaanalysisd` was running at 79% CPU doing Photos analysis on the Neural Engine — the same
accelerator utt's speech model uses — alongside `VTEncoderXPCService` and `VTDecoderXPCService`.
A wall-clock number taken while that runs measures the queue, not the model.

The fix needed no new instrument. **Queue wait only ever adds**, so the minimum over repeated
interleaved measurements estimates the inference cost cleanly. Min-of-4 on one clip gave 1.65,
1.64, 1.66, 1.66 s. The contaminated readings are still visible in the raw data as isolated
20 s spikes, and they are what the minimum discards.

This is not one investigation's odd luck. `transcribe.inside()` records the same thing from the
other side, independently: *"The clip sits in the jobs folder until `ExtensionJobs.interval`
comes round, and behind whatever else is already queued — measured here at **2.1 s and 10.1 s
for the same clip**, minutes apart."* A five-fold spread on identical bytes is the normal
condition of this lane, not an anomaly, and **any single-shot utt timing on this Mac should be
treated as an upper bound rather than a measurement.**

| Clip | Audio | 1.0× | 1.5× | 2.0× | 2.0× vs 1.0× |
|---|---|---|---|---|---|
| `3d5c3ed8` | 3.39 s | 1.65 s | — | 1.64 s | 99% |
| `0e854a4e` | 8.00 s | 1.84 s | 1.44 s | 1.46 s | 79% |
| `67861a22` | 13.70 s | 2.28 s | — | 1.64 s | 72% |
| `4c0abebd` | 25.09 s | 3.32 s | 2.88 s | 2.49 s | 75% |
| `42dbb9cc` | 42.18 s | 3.95 s | — | 2.90 s | 73% |

What 2.0× buys, from the fit:

| Clip length | 1.0× | 2.0× | Saved |
|---|---|---|---|
| 4 s | 1.65 s | 1.52 s | 0.14 s (8%) |
| 8 s | 1.92 s | 1.65 s | 0.27 s (14%) |
| 12 s | 2.20 s | 1.79 s | 0.41 s (19%) |
| 20 s | 2.74 s | 2.06 s | 0.68 s (25%) |
| 40 s | 4.10 s | 2.74 s | 1.36 s (33%) |

**A correction worth recording:** the 3.30 s figure this investigation started from, for a
62 KB / ~8 s clip, is itself a contended single measurement. The true warm cost of that clip is
**1.84 s**. utt is roughly 1.8× faster than it was believed to be, which shrinks the prize
again — there is less to win than the premise assumed, before any of this is attempted.

## What going faster breaks

The scored sample is too thin to place a cliff, but it is not too thin to show the *shape* of
the failure, and the shape is the argument. These are the real transcripts.

**`67861a22`, 13.7 s.** As shipped:

> I want to control it globally and percession, and it should be about delivery of slips or
> finishing off tasks or the agent wanting to push notification.

At 1.25× it is word-for-word identical. At 1.5× (WER 0.222):

> **want control** globally and percession, … the agent wanting to **push in a fishing**

At 2.0× (WER 0.259):

> **One control** globally **in protection** and it should be … wanting to **push information**.

**`5e10ceda`, 31.0 s** — the dangerous one. As shipped:

> …the transcript page should always auto scroll to the newest message **to the first** new
> message or the latest message.

At 1.5×:

> …should always auto scroll to the newest message, **not to the first** new message…

At 2.0× + trim:

> …at the bottom of the transcript page. **But actually, I think I've** already received it…

The second one is not garbled. It is a fluent, well-punctuated sentence that inserted a
**negation that was never spoken**, and the third changed the subject of the sentence from the
agent to the speaker. Nothing downstream can catch this: it goes through `deliver.py` and is
typed into a live coding session as if JJ had said it. A visibly broken transcript is a
non-event — the person re-records. A plausible transcript with the meaning inverted is the
failure mode this feature would be adding, and it is strictly worse than the 0.27 s it buys.

Directionally, across the 10 scoreable rows: **1.25× is clean** (WER 0.000 on the one clip that
got both rows), **1.5× is where words start moving** (WER 0.174 median, 0.222 worst), and
**2.0× is worse** (0.259). If a limit does exist it is a slope beginning between 1.25× and 1.5×
rather than a cliff — but with n = 1–2 per cell, treat that sentence as a hypothesis.

## Silence trimming pays, and can eat the clip

Across the 25 sampled clips the filter removed a **median of 11.0%** of a clip's duration
(min 1.8%, max 100%). That is real, but it is 11% of a term that is only 0.068 s per second to
begin with — on a 12 s clip it is worth **0.09 s**. It is the smallest effect in this document.

It also has a failure mode that a naive implementation would ship. A **1.088 s clip was deleted
outright**: `silenceremove` at −40 dB RMS produced a 0.0-second, 258-byte file, and utt answered
`Could not transcribe that clip.` A second clip lost 55.6% of itself, 1.66 s down to 0.74 s.
Both are in the 1–3 s band, where the median removal is only 4.4% — so this is not a filter that
is slightly too aggressive everywhere, it is one that occasionally takes everything. Any
on-device trim needs a guard that keeps the original whenever the trimmed result is empty or far
shorter than expected. Short clips are 16% of the corpus, so this is a common case rather than
an edge one.

## The five questions

1. **Does speed-up reduce utt's time roughly linearly?** No. It is `1.38 s + 0.068 × seconds`,
   R² = 0.925 — dominated by a fixed cost at every length deckhand actually sees. 2.0× returns
   14% on an 8 s clip and nothing on a 3.4 s one.
2. **Where is the accuracy cliff?** Unresolved. The thin sample suggests a slope starting
   between 1.25× and 1.5×, not a cliff, and 1.25× looked clean. Not enough data to ship against.
3. **Does silence trimming pay, and does it interact with speed?** It removes a median 11.0% of
   duration, worth ~0.09 s on a median clip — the smallest effect measured here. The interaction
   with speed was not measured; too few paired rows survived. That it can delete a short clip
   entirely is the more important finding.
4. **Does the answer differ by clip length?** Yes, and this is the one real nuance. Below ~10 s
   the fixed cost swamps everything and speed-up is pointless. Above ~40 s it returns a third of
   the span. If any version of this ships it should apply only to long clips — where, note, the
   person is also least likely to be waiting on the result.
5. **What would you ship?** Only the `free`-atom strip. Not speed, not trim.

## Running it again

`just audio-bench` runs the sweep; `just audio-bench --report` re-reads
`daemon/tools/audio-bench.jsonl` without making a single job. The 43 rows from this run are
committed, so the table above can be reproduced without touching utt.

**The script's timing column should not be trusted as it stands**, and three things would fix
it:

- **Take a minimum over repeats, not a single reading.** This is the whole difference between
  r = 0.113 and R² = 0.925, and it needs no cooperation from utt.
- **Record queue wait separately from work.** The daemon half of this has since landed:
  `transcribe.inside()` splits utt's span into the stages utt measured plus a derived `waiting`
  lead, and `saying.py` writes one line per clip to `timings.jsonl`. It returns empty today,
  because no shipped utt sends a `timings` key yet — so it is the right instrument and it is not
  usable until utt's side ships. **When it does, note that it derives the queue wait rather than
  removing it**, so a single reading is still a reading taken through a queue. Minimum-over-
  repeats stays the honest estimator; the two are complements, not alternatives.
- **Refuse to run while the daemon is serving**, and check the machine is otherwise quiet. A
  sweep makes JJ's own dictation slower for its whole duration, and a sweep run against a busy
  Neural Engine produces numbers that look like data and are not.

The accuracy question, if it is still wanted, is now cheap: 12 clips × {1.0, 1.25, 1.5, 2.0} ×
{trim, no trim} ≈ 96 jobs, and the existing rows already cover some of them.

## Exactly what was run

**Corpus.** `~/Library/Application Support/Deckhand/audio/` — 326 real clips of JJ dictating at
Claude Code sessions, 0.19 s to 84.4 s, median 12.2 s, 5197 s in total. 25 were chosen by even
spread across five length bands (1–3 s, 3–8 s, 8–15 s, 15–25 s, 25–60 s), taken by index within
each band so the same clips come back on a re-run.

**The lane.** `deckhand_daemon.transcribe.transcribe()`, imported and used read-only — the same
jobs-folder lane the daemon uses, with the daemon's own `VOCABULARY` passed as hints on every
job so hints are constant and cannot be what moved a number.

**Re-encode.** AAC-LC, 16 kHz, mono, 24 kbps — matched to what the phone records:

```
-c:a aac -b:a 24k -ar 16000 -ac 1
```

**Tempo.** `atempo=<speed>`, which preserves pitch. A naive resample would shift formants and
would measure the wrong thing.

**Silence.** Applied *before* the tempo change — the other order measures pauses after they have
already been shortened, so a 0.6 s breath falls under the threshold and survives:

```
silenceremove=start_periods=1:start_duration=0:start_silence=0.10:start_threshold=-40dB:
stop_periods=-1:stop_duration=0.50:stop_silence=0.20:stop_threshold=-40dB:detection=rms
```

Leading silence goes but 0.10 s is left so the clip does not open mid-syllable; any pause past
0.50 s is cut back to 0.20 s, which keeps the boundary a listener uses to separate sentences.

**Normalisation before scoring.** `’` → `'`; every character that is not a letter, a digit or an
apostrophe becomes a space; the result is lowercased and split on whitespace. So case,
punctuation and whitespace are ignored and `don't` ≠ `dont`. WER is Levenshtein over those
tokens divided by the reference's token count; CER is Levenshtein over the characters of the
space-joined result. Both are stdlib, in `audio_bench.py`, checked by `--self-check`.

**Reference.** Each clip's own as-shipped transcript through the same lane — **not ground
truth.** These numbers measure how far a condition moves the words from what deckhand produces
today, which is the question that was asked. The reference itself contains errors: `percession`
for *per session* and `harness harmonize` are both in the reference rows above.

**Timing caveat.** Every job carries up to utt's 300 ms folder scan plus this lane's 200 ms
poll, so nothing resolves finer than about half a second. Nothing was subtracted. The min-of-N
figures include that overhead and are therefore an upper bound on utt's own cost — which makes
the fixed-cost conclusion stronger, not weaker.

## Related context

- `daemon/tools/audio_bench.py` — the bench, and `audio-bench.jsonl` beside it
- `daemon/src/deckhand_daemon/transcribe.py` — the lane this borrows, unchanged
- `daemon/CLAUDE.md` — utt, the plugin file lane, and why hints are the cheapest accuracy here
