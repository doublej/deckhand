---
name: deckhand
description: Ask the person a question on their phone and read the answer, or reach them when they are away from the Mac. Use when a decision needs the person and they are not at the keyboard, when a choice has more than two options, when a long job finishes with nobody watching, or when the session is stuck, or about to guess at something only they can answer.
license: MIT
metadata:
  version: "1.0"
---

# Deckhand

There is a phone in the person's pocket that can see this session, and it can be asked a question.
Most of what follows is a file in this folder, not a call.

**Say slip to the person, write artifact in code, paths and endpoints.** Same thing, two audiences:
"I have put a slip on your phone", never "an artifact".

<presentation>
Reference skill: no banner, no report. Slips and logbooks stay free of any signature. When invoked
directly and the answer is the main output, end with: — deckhand · github.com/doublej
</presentation>

## Where the person is

`deckhand presence` answers `laptop` or `phone` (the `presence` tool says the same). At the
laptop they are reading this conversation: ask here, in a sentence, and stop. On the phone, a
sentence here is unread — use a slip or a card. Ask again before each question; it moves the
moment they sit down or walk off.

## When a slip beats a sentence

Say it in a sentence when the answer is prose and you can wait for the person to come back to the
keyboard. Write a slip when the answer has **structure** — one of these four, these six fields,
yes or no to this exact thing — or when the person is away, and a sentence in a terminal nobody
is looking at is the same as saying nothing. Then do both: a phone in a pocket announces nothing
itself, so say in one line that the slip is there.

## The same things as tools, and as one command

Where the `deckhand` MCP server is installed, eleven tools arrive with it and are the shorter path.
`presence` says where the person is; `ask_on_phone` and `read_answer` write and read exactly the
file the scripts below do; `call_for_attention` puts a card on the Lock Screen; `whoami` says
which session this is; and `sessions` and `say_to_session` reach the other sessions on this Mac.
`open_plane` puts a web page or a Mac window beside this session in the person's headset, and
`close_plane`, `space` and `mac_windows` go with it — a URL there must be reachable from the
headset, so prefer `https://<slug>.atlas.local.jurrejan.com` over localhost.
They work from any directory, because they take this session's folder out of its own record
rather than out of `cwd`.

Every one of them is also a `deckhand` shell command (`just install-cli` puts it on PATH):
`presence`, `whoami`, `sessions`, `ask`, `answer`, `notify`, `say`, `open`, `space`, `close`,
`windows`. JSON when piped, a structured
error on stderr, and an exit status to branch on — 4 means "no": not said, not pushed, not
answered yet. `deckhand prime` prints the whole contract.

`say_to_session` goes down the peer socket and takes no route. There is no tool for the keyboard,
for `/clear`, for a session's settings or its filters, or for starting one — those belong to the
person, and an agent choosing them is an agent claiming to be the person. `curl` still performs
what a tool declines, so treat that as a boundary rather than a fence.

Nothing below needs the tools. With none present it all still works.

## Writing one

A slip is one HTML page in this session's own folder, and there is a script for the common shapes:

```bash
python3 ~/.claude/skills/deckhand/scripts/slip.py --kind pick \
  --title "Which branch should this land on?" --note "Three worktrees are waiting." \
  --option develop --option main
```

It prints the path it wrote. Tell the person, then read the answer:

```bash
python3 ~/.claude/skills/deckhand/scripts/answer.py which-branch --wait 300
```

`--kind` is `confirm`, `pick`, `text` or `aloud`. `answer.py` prints the answered JSON, or exits 1
while nothing has answered; `--wait` blocks, bounded by the tool call's own timeout — though the
daemon also messages this session when an answer lands, so a stopped session is woken rather than
polling. Run both from the session's own folder: nothing walks upward, so a slip written from a
subdirectory is one the phone never lists.

## Whose slip it is

A slip goes in **this session's own folder**, `.deckhand/artifacts/$CLAUDE_CODE_SESSION_ID/`, and
both scripts do that without being told — that variable is in every Bash call and is the id the
daemon knows this session by. Only the session that asked lists it, and the answer comes back to
the session that asked; two sessions in one repo no longer read each other's questions or take
each other's answers.

A slip written **flat** in `.deckhand/artifacts/` belongs to the folder instead, and every session
working there lists it and can answer it. Write one there for a question about the project rather
than about the work in hand — pass `--session ""` to either script. The phone marks those rows
`project`, because answering one sends the answer into whichever session is open.

## Writing one by hand

For a wizard, sliders, or anything those four miss, copy a template out of
`~/.claude/skills/deckhand/templates/` — all four plus `form` and `tweak`, as working pages
(`logbook` is in there as well, but a script writes that one):

```bash
mkdir -p .deckhand/artifacts/$CLAUDE_CODE_SESSION_ID
cp ~/.claude/skills/deckhand/templates/form.html \
   .deckhand/artifacts/$CLAUDE_CODE_SESSION_ID/release-check.html
```

The `<title>` is the slip's name, the filename before `.html` its id:
`[A-Za-z0-9][A-Za-z0-9_-]{0,63}`.

Inline HTML, CSS and JS **only**. The app injects `default-src 'none'` with inline style and
script, `img-src data:`, no form action and no navigation — so a CDN, a font, a `fetch` or a
remote image fails **silently**. Pictures are `data:` URIs or SVG, and Deckhand's own design
tokens are injected, so use the custom properties. The page answers through four things:

```js
window.deckhand.respond(value)  // any JSON value. May be called more than once.
window.deckhand.close()         // dismiss the viewer
window.deckhand.artifact        // { id, title }
window.deckhand.answer          // what was answered last time, or null
```

**A reopened page must prefill from `window.deckhand.answer`.** The row that opened it says
"answered"; an empty form under that is the page lying about its own state.

## Asking several things at once, out loud

A phone dictates better than it types, so a page can **declare** its questions rather than only
draw them — the app then renders one card per question with its own talk mark:

```html
<script type="application/json" id="deckhand-aloud">
{ "questions": [
  { "id": "scope", "ask": "How far should this go?", "hint": "Reads first, writes later." },
  { "id": "deadline", "ask": "Is there a date this has to be done by?" }
] }
</script>
```

That block is the whole of what you edit — `aloud.html` renders itself from it, so the questions
exist once. The answer arrives as `{"answer": {id: words}, "completedCount": n}`, an unanswered
question left out rather than sent empty; every way the block can be wrong renders as plain HTML.

## Saying where a long job has got to

Some work is too long to report in a sentence and too slow to be worth interrupting for: a
migration, a port, a release, anything that crosses a compaction. A **logbook** is a slip that
asks nothing — one page the person can look at whenever they wonder how it is going, so they
never have to ask.

```bash
LOG=~/.claude/skills/deckhand/scripts/logbook.py
python3 $LOG start "Moving the reader onto the new store" --standing "Porting first, cutover last."
python3 $LOG add done "Read every caller" "Nine, and two of them are in the manager."
python3 $LOG add blocked "Export needs an Apple account" "There is no token on this Mac."
python3 $LOG standing "Everything but the cutover is done."
python3 $LOG finish "Cut over at 16:40, no session lost its place."
```

`add` takes a state — `done`, `doing`, `blocked` or `note` — a heading of at most 80 characters,
and one line of at most 300 saying what happened. Flags go **after** the verb. Each command
rewrites the whole page, so an entry costs one command and no thought; that cheapness is the
design, because a logbook that costs a page rewrite per entry stops getting entries by the third
one. A longer line is refused rather than cut, so nothing you thought you recorded is missing.

**Reach for one** when the job has more than a handful of steps, when it will outlive this
session, or when it has a part the person will want to see coming — a cutover, a deletion, the
thing that will need them. Start it as you start the job: a logbook written at the end is a
report, and they already get those. **Do not** write one for work you will finish in a few
minutes, or to narrate what you are about to say in the session anyway.

**A logbook belongs to the folder, not to this session**, which is the one place it differs from
every other slip. It is written flat, so another session working here appends to the same book
with the same command and a compaction, a `/clear` or a handover loses none of it. Its state is
`.deckhand/artifacts/<slug>.log.json`, beside the page; `--slug` gives a second job its own book
and `--session "$CLAUDE_CODE_SESSION_ID"` pins one to this session if you really want that.

Say once that it is there; after that it is theirs to open. The page carries a single field as
well — a note back, so someone reading "blocked on X" on a train can say what to do instead. It
arrives like any other answer, so `answer.py logbook` reads it, and rewriting the page does not
take it away.

## Asking for the person outright

When what is needed is not an answer but attention — `deckhand notify "The migration is done,
tests green."`, or by hand:

```bash
curl -s -X POST "http://127.0.0.1:4180/sessions/$CLAUDE_CODE_SESSION_ID/notify" \
  -H "x-deckhand-token: $(cat ~/Library/Application\ Support/Deckhand/token)" \
  -H 'content-type: application/json' -d '{"line":"The migration is done, tests green."}'
```

`{"pushed": true}`, or `{"pushed": false, "why": …}` — the one Lock Screen card a session raises
for itself, so the one a folder may refuse outright. A refusal means the person does **not** know,
and you are expected to say so rather than assume otherwise.

## Mermaid, both halves

A ` ```mermaid ` fence in what you **say** renders as a picture on the phone — transcript,
briefing and report alike. It does **not** render inside a slip: that CSP sandboxes the page, and
the renderer is injected into the transcript view rather than carried. Draw in a slip with SVG.

## What this never does

The route is an authority choice, not a transport choice: the keyboard arrives as the person at
the machine, the socket as another Claude session carrying none of their authority — and this
surface is exactly what that wrapper exists to constrain.

- **Never pass `route`.** It is the person's own setting, never your parameter.
- **Never `POST /sessions/{id}/control`** — those are keystrokes the person presses, and `clear`
  is the only irreversible thing in the app.
- **Never `PUT /settings` or `PUT /sessions/{id}/filters`** — an agent that can rewrite a filter
  chain can remove the filter that would have stopped it, quietly.
- **Never `POST /projects/session`** — a process on a launch line nobody approved, in a folder
  whose trust dialog was answered for a person.

**None of this is enforced today.** One shared token means the daemon cannot tell an agent from a
phone, and anything refused here `curl` still performs. These are rules kept, not rules held to.

## More

- `reference/wire.md` — every endpoint, its shape, and the trap in it
- `reference/traps.md` — prefilling, `delivered` vs said, the inbox, `null`, the CSP, the session id
