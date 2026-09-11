# Reading a transcript

## What this is

Everything that reads a Claude Code transcript and nothing that writes one.

```
transcripts.py  # the last rounds, the activity blob a summary is written from, context fullness
entries.py      # one entry: the words inside its envelope, and who put them there
machinery.py    # the wrappers a message travels in, and how much of one is worth keeping
asked.py        # what the person asked for, and what is still in the session's inbox
commands.py     # the slash commands and skills a session could be handed by name
readable.py     # the whole transcript as lines, for when the app's reading looks wrong
context.py      # the CLAUDE.md tree a session in a folder is loaded with, before it says anything
```

## Where the file is, and how much of it is read

- Transcript folder names are lossy (`/` and `_` both become `-`), so the JSONL is found by
  globbing `~/.claude/projects/*/<sessionId>.jsonl`, never by rebuilding the path.
- Transcripts run to megabytes: only the last 512 KB is read, and the first line of that chunk
  is dropped as a fragment. Context fullness reads a 256 KB tail, because it is asked for every
  session on every listing.

## Invariants

- **`role` does not say who wrote a turn.** A subagent's notice, another session's message and a
  teammate's report all arrive as an ordinary `user` entry, so a reader going by `role` alone
  labels every one of them YOU on the phone — the app putting words in JJ's mouth. `Turn.written_by`
  carries the name `machinery.wrote` finds in the envelope and is empty only for the person
  themselves; the phone's `Turn.isUser` asks for both.
- **The name is in the envelope and nowhere else**, so it has to be read before the envelope comes
  off — which is why `entries.blocks_of` exists apart from `text_of`. A subagent is named in the
  notice's own `<summary>` as `Agent "…" finished`, and a third of those are written with the
  quotes escaped: a pattern without `\?"` silently drops 247 of the 1112 on this Mac.
- **A wrapper is caught by name, never by shape.** `machinery.py` knows six noise tags, two peer
  envelopes and `task-notification`, and everything else it sees is content: `Array<String>` in a
  prompt, `a < b`, an HTML snippet two sessions are discussing. This once swept every `<...>` out
  of a queued message, which is a tidier screen bought with somebody's actual words. The two
  answers differ because the wrappers do — a `<system-reminder>` hides nothing and goes whole, a
  `<teammate-message>` is another session's entire report and its `summary=` was written for a
  person, so the tag becomes a `**From <who>:** <summary>` line and the body stays. Under it the
  boilerplate paragraphs the harness writes around a peer message go too, and only when a peer
  envelope was actually seen outside a fence.
- **Fenced and backticked text is quoted, whatever it says.** The transcripts here are full of
  sessions showing each other these exact tags. A fence is sacred to everything in `machinery`;
  a backticked span is sacred only to the tag stripping, because a peer's report is markdown and
  says `just check` in it — one pattern covering both cuts the wrapper in half before anything
  can read it. An unterminated fence takes the rest of the message with it, and an unclosed tag
  loses the tag and keeps the words: neither can lose a message.
- **Structure survives the daemon.** What comes off is machinery; markdown is not machinery. The
  bold, the bullets and the fences reach the phone intact, because the thing that draws them is
  `Markdown` in the app and the daemon cannot draw anything.

- **A message absorbed mid-turn is a `queued_command` attachment, not a `user` entry.** No
  `user` entry is ever written for one — but it is written down, as
  `{"type":"attachment","attachment":{"type":"queued_command","prompt":…}}` at the moment it
  arrived, which is the entry Claude Code renders as "The user sent a new message while you were
  working". Measured on a live transcript: 149 of them, and **not one** also present as a user
  entry, so `transcripts.absorbed` can read them as turns with no risk of showing anything twice.
  Missing that is what made those messages look lost: `asked.queued` kept its own copy marked
  `taken` and the phone drew them after the last turn, so answered prompts sat at the foot of the
  conversation looking like prompts nobody had got to. They are ordinary turns now, in the place
  they arrived, and `asked.queued` returns only what is still in the inbox.
- **The session's inbox is a lane of its own.** Claude Code writes a `queue-operation` line
  (`enqueue` / `dequeue` / `remove` / `popAll`) every time something joins or leaves a session's
  message queue, and `asked.queued` replays it. This is the only honest answer to "has it seen
  what I said yet": a message sent mid-turn is **not a turn** — it appears nowhere in the
  transcript until the session absorbs it, which is why speaking to a busy session and seeing
  nothing happen used to read as having sent nothing. `dequeue` carries no content, so the replay
  pops the oldest; a `remove` naming something outside the tail window does the same, which is
  what lets a replay that began mid-queue still empty in the right order.
- **An inbox can hold prompts nothing will ever remove**: a session killed mid-queue leaves
  enqueues with no matching removal, and a replay cannot tell that from a message still waiting.
  `POST /sessions/{id}/queue/clear` writes a timestamp to `queue/<sessionId>.json` and the replay
  starts after it. Claude Code's transcript is never touched — it is not this daemon's file.
  There is no way to make a session read its inbox early; the queue drains when a turn ends.
- **The keyboard route's ctrl-U travels with the message.** Queued content written by Deckhand
  starts with `\x15`, so `asked._unwrap` strips control characters as well as the envelope tags.
- **How full a session's context is comes off its own transcript.** Every assistant entry carries
  the usage of the request that produced it, and the window is what was billed as input —
  `input_tokens` + `cache_creation_input_tokens` + `cache_read_input_tokens`. Output is not in it.
  The limit is `autoCompactWindow` from `~/.claude/settings.json` (450k here), not the model's own
  ceiling: what matters is when *this* Mac folds a session into a summary. It lags by a turn on a
  busy session — the usage of a request in flight is not written until the assistant entry it
  produced lands — and it will not match a statusline counting against the model's full window.
- **`updated_at` is the moment a session's status last changed, not a heartbeat.** Measured here:
  a session reporting `busy` with a 1553 s old stamp while it was mid-turn. So it is only the age
  of an *idle* session.
- **And Claude Code sometimes stops writing that record at all**, which is a `busy` that outlives
  its turn by however long the session then sits there. Measured: a record froze at the prompt
  that started background agents, and four whole turns began and ended after it without one
  rewrite — the phone read WORKING for half an hour at a session waiting to be spoken to. The
  **age of the claim cannot be the test**, because the record is written twice a turn and never
  in between: over six minutes one session turning over rewrote it five times and one mid-turn
  rewrote it not at all in 26. Two sessions proved it in the same minute — stale by 1546 s and
  working, stale by 2036 s and finished. `transcripts.turn_ended` answers off the transcript
  instead, which is a log and not a claim: `stop_reason` is `tool_use` while the model is still
  going. `sessions._reading` uses it to lower a `busy` nothing is maintaining, never to raise
  one, and moves `updated_at` to the turn's own end when it does — the rail fades a row by that.
- **Thinking rides with the turn it produced.** The transcript carries `thinking` blocks in the
  same content list as `text` and `tool_use`, and they were dropped outright — 326 of them in one
  session here. They are collected exactly as tool calls are and handed to the next message with
  words, because that is what they are: how the session got to what it says next. They travel
  with the turns rather than behind a second route, which is affordable (measured: median 548
  characters, p90 1718, and a 25-turn page comes to 18 KB against tool results already capped at
  4000 each) and is the whole of how thinking arrives **live** — a run still in flight is a turn
  with thoughts and no words, and the phone re-reads the page every few seconds anyway.
  `redacted_thinking` is deliberately skipped: it is an encrypted blob with no words in it, so
  surfacing it would be a heading over nothing.
- **The context tree is the other half of "why did it do that".** `context.py` answers what a
  session *starts* with, where everything else here answers what it has said — a rule three
  folders up never appears in a transcript and is shaping every answer all the same. It is
  `atlas tree` reimplemented rather than shelled out to: atlas prints ascii and has no
  machine-readable mode, so parsing it would be reading a picture. The one thing copied rather
  than re-picked is the token estimate, `length / 2.5` from `atlas-cli/src/commands/prime.ts`, so
  the two tools never disagree about the same file. The walk is pruned as it goes and capped at
  `MAX_DEPTH`/`MAX_DOCS` — it once called `_walk` once per descendant and a folder with a dozen
  of them timed the route out. And the tree is a *permission*: `context.allowed` is a second door
  onto `GET /sessions/{id}/file`, so a CLAUDE.md this run never opened is still readable, because
  it is running either way.
- **Command names come from two places, project shadowing user.** `commands.py` reads `~/.claude`
  and the project's own `.claude` at every request; nested folders keep their `dir:name` namespace.

## Verification

`daemon/tests/reading/` — pytest, inside `just daemon-test`.
