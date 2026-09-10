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

## When a slip beats a sentence

Say it in a sentence when the answer is prose and you can wait for the person to come back to the
keyboard. Write a slip when the answer has **structure** — one of these four, these six fields,
yes or no to this exact thing — or when the person is away, and a sentence in a terminal nobody
is looking at is the same as saying nothing. Then do both: a phone in a pocket announces nothing
itself, so say in one line that the slip is there.

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

## Writing one by hand

For a wizard, sliders, or anything those four miss, copy a template out of
`~/.claude/skills/deckhand/templates/` — all four plus `form` and `tweak`, as working pages. The
`<title>` is the slip's name, the filename before `.html` its id: `[A-Za-z0-9][A-Za-z0-9_-]{0,63}`.

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

## Asking for the person outright

When what is needed is not an answer but attention:

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
