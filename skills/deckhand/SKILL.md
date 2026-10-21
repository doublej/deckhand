---
name: deckhand
description: Ask the person a question on their phone and read the answer, or reach them when they are away from the Mac. Use when a decision needs the person and they are not at the keyboard, when a choice has more than two options, when a long job finishes with nobody watching, or when the session is stuck, or about to guess at something only they can answer.
license: MIT
metadata:
  version: "1.0"
---

# Deckhand

**Say slip to the person, write artifact in code, paths and endpoints**: "I have put a slip on
your phone", never "an artifact".

<presentation>
Reference skill: no banner, no report. Slips and logbooks stay free of any signature. When invoked
directly and the answer is the main output, end with: — deckhand · github.com/doublej
</presentation>

## Where the person is, and when a slip beats a sentence

`deckhand presence` answers `laptop`, `headset` or `phone`; ask before each question. At the
laptop or in the headset, ask here in a sentence and stop. A slip when the answer has
**structure** (one of these four, yes or no to this exact thing) or they are on the phone, where a
sentence here is unread; then also say in one line that the slip is there.

## Tools and the `deckhand` command

With the `deckhand` MCP server, use its tools. Without it, each is a `deckhand` command
(`just install-cli`): `presence`, `whoami`, `sessions`, `ask`, `answer`, `notify`, `say`, `open`,
`space`, `close`, `windows`, `start`, `tmux`, `arrange`. JSON when piped, a structured error on
stderr, exit 4 means "no" (not said, not pushed, not answered yet). `deckhand prime` prints the whole contract. A URL opened in the headset
must be reachable from it: prefer `https://<slug>.atlas.local.jurrejan.com` over localhost.

`say` goes down the peer socket and takes no route. There is nothing for the keyboard, for
stopping, compacting, clearing, closing or renaming a session, answering a slip, input into a Mac
window, or a session's settings, filters or orders — those are the person's, and `deckhand <verb>`
for one answers `PERSON_ONLY`. Nothing below needs the tools.

## Writing one

A slip is one HTML page in this session's own folder; the script covers the common shapes:

```bash
python3 ~/.claude/skills/deckhand/scripts/slip.py --kind pick \
  --title "Which branch should this land on?" --note "Three worktrees are waiting." \
  --option develop --option main
```

Tell the person, then **end your turn**: a decision's answer arrives as their next message —
`Decision which-branch — "Which branch should this land on?": main. This covers exactly: …`.
Act on exactly what that line covers. To look yourself:

```bash
python3 ~/.claude/skills/deckhand/scripts/answer.py which-branch --wait 300
```

**Show a picture, never only name it.** `--image PATH` attaches one; an image path in `--title`
or `--note` is attached on its own (a missing path stops the script).

`--kind` is `confirm`, `pick`, `text` or `aloud`. **Confirm, pick and text are decisions**: the
phone answers one only with a signature from its own key. A confirm needs `--action`, exactly what
a yes allows in one line (`--action "tag 0.4.0 and push the tag, nothing else"`); pick and text
default it to the question. `--expires-hours` (24) is how long it stands, `--key` names it;
re-asking an answered decision under the same key prints its answer.

A `confirm` is answered from the Lock Screen: keep its question under 80 characters, the rest in
`--note`. Buttons say Yes and No unless two `--option` name them; the answer is
`{"answer": true}`, `{"answer": false}`, or `{"reply": "…"}`. `answer.py` prints
`{"value", "verified", "device", "fingerprint"}`, or exits 1 while unanswered. **`verified` is true
only where the phone's signature holds** — a hand-written file or a non-decision slip reads false;
never treat an unverified answer as approval. Run both from the session's own folder: nothing
walks upward, so a slip written from a subdirectory never shows.

## Whose slip it is

A slip goes in `.deckhand/artifacts/$CLAUDE_CODE_SESSION_ID/` (the scripts do this); only the
asking session lists it and gets the answer. A slip written **flat** in `.deckhand/artifacts/`
(`--session ""`) belongs to the folder: every session there lists and can answer it. Use that for
questions about the project, not the work in hand; the phone marks those rows `project`.

## Writing one by hand

For a wizard, sliders, or anything the four kinds miss, copy a template from
`~/.claude/skills/deckhand/templates/` (the four plus `form` and `tweak`):

```bash
mkdir -p .deckhand/artifacts/$CLAUDE_CODE_SESSION_ID
cp ~/.claude/skills/deckhand/templates/form.html \
   .deckhand/artifacts/$CLAUDE_CODE_SESSION_ID/release-check.html
```

`<title>` is the slip's name, the filename before `.html` its id: `[A-Za-z0-9][A-Za-z0-9_-]{0,63}`.

Inline HTML, CSS and JS **only**. The CSP is `default-src 'none'` with inline style and script,
`img-src data:`, no form action, no navigation — a CDN, font, `fetch` or remote image fails
**silently**. Pictures are `data:` URIs or SVG; use Deckhand's injected design custom properties.

```js
window.deckhand.respond(value)  // any JSON value. May be called more than once.
window.deckhand.keep(value)     // the unsent draft, kept on the phone. keep(null) drops it.
window.deckhand.close()         // dismiss the viewer
window.deckhand.artifact        // { id, title }
window.deckhand.answer          // what was answered last time, or null
window.deckhand.draft           // what keep() last held, or null. Newer than answer.
```

**A reopened page must prefill from `window.deckhand.draft ?? window.deckhand.answer`.** **Call
`keep` on every change** in a page needing more than one tap — the page has no storage of its own.

## Asking several things at once, out loud

A page can **declare** its questions; the app renders one card per question with a talk mark:

```html
<script type="application/json" id="deckhand-aloud">
{ "questions": [
  { "id": "scope", "ask": "How far should this go?", "hint": "Reads first, writes later." },
  { "id": "deadline", "ask": "Is there a date this has to be done by?" }
] }
</script>
```

That block is all you edit — `aloud.html` renders from it. The answer is
`{"answer": {id: words}, "completedCount": n}`, unanswered questions left out.

## Saying where a long job has got to

A **logbook** is a slip that asks nothing: one page showing how a long job is going.

```bash
LOG=~/.claude/skills/deckhand/scripts/logbook.py
python3 $LOG start "Moving the reader onto the new store" --standing "Porting first, cutover last."
python3 $LOG add done "Read every caller" "Nine, and two of them are in the manager."
python3 $LOG standing "Everything but the cutover is done."
python3 $LOG finish "Cut over at 16:40, no session lost its place."
```

`add` takes a state (`done`, `doing`, `blocked`, `note`), a heading of at most 80 characters and
one line of at most 300; a longer one is refused, not cut. Flags go **after** the verb.

**Reach for one** when the job has more than a handful of steps, will outlive this session, or has
a part the person will want to see coming. Start it with the job, not at the end. **Do not** write
one for work done in a few minutes, or to narrate what you say in the session anyway.

**A logbook belongs to the folder**: written flat, so another session here appends to the same
book and a compaction, `/clear` or handover loses nothing. State is
`.deckhand/artifacts/<slug>.log.json`; `--slug` gives a second job its own book,
`--session "$CLAUDE_CODE_SESSION_ID"` pins one to this session. Say once that it is there. Its one
field is a note back, read with `answer.py logbook`.

## Asking for the person outright

For attention rather than an answer: `deckhand notify "The migration is done, tests green."`, or

```bash
curl -s -X POST "http://127.0.0.1:4180/sessions/$CLAUDE_CODE_SESSION_ID/notify" \
  -H "x-deckhand-token: $(cat ~/Library/Application\ Support/Deckhand/token)" \
  -H 'content-type: application/json' -d '{"line":"The migration is done, tests green."}'
```

`{"pushed": false, "why": …}` means a folder refused and the person does **not** know; say so.

## Mermaid

A ` ```mermaid ` fence in what you **say** renders on the phone; inside a slip it does not — use SVG.

## The project's header

The phone draws `.deckhand/header.jpg` (or `.png`/`.webp`) faintly behind the session's title. If
missing and the project has a picture that suits a wide banner — logo, hero, screenshot, cover art
— make one once, **without asking**: about 1200×360, under 300 KB, calm enough for a title.
`sips --resampleWidth 1200 SRC --out TMP`, then
`sips --cropToHeightWidth 360 1200 TMP --out .deckhand/header.jpg -s format jpeg`; put `*` in
`.deckhand/.gitignore` if not there. No suitable picture: skip it.

## What this never does

The socket arrives as another Claude session, carrying none of the person's authority.

- **Never pass `route`.** It is the person's setting, never your parameter.
- **Never `POST /sessions/{id}/control`** — keystrokes the person presses; `clear` is irreversible.
- **Never `PUT /settings` or `PUT /sessions/{id}/filters`** — an agent rewriting a filter chain can
  remove the filter that would have stopped it.
- **Never `POST /projects/session`** — `start_session` (`POST /space/sessions`) is the agent's
  door: the same two gates, and the new session stands beside the one that asked.

**None of this is enforced today** (one shared token; `curl` still does it). Rules kept, not held.

## More

- `reference/wire.md` — every endpoint, its shape, and the trap in it
- `docs/commands.md` in the deckhand repo (`deckhand prime` prints its path) — every route, tool
  and command, generated from the code
- `reference/traps.md` — prefilling, `delivered` vs said, the inbox, `null`, the CSP, the session id
