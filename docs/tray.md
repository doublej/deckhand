# The tray

The manager panel's first half: every session that needs the person, on every machine, with its
slips answerable in place — and what happened lately to the ones that did. The manager's
conversation is the second half, one tap away, and saying anything to the manager turns to it.

**Tray, not inbox.** *Inbox* is a session's own message queue (`GLOSSARY.md`), and the dashboard's
"Clear inbox" square means exactly that. The tray is the person's in-tray.

## The wire

`GET /tray?since=` answers three things:

- `open` — one row per session with a slip nobody answered or a line it called for you with:
  `session`, `name`, `machine`, `status`, `provider`, `waiting`, and `slips`, each with its `ask`.
  Never stored: read off every machine's disk on each request (`GET /tray/open` on a hand), so it
  cannot disagree with the slips tab or a Lock Screen card.
- `updates` — what happened, after the cursor: `answered` (with the answer in the words on the
  button), `called`, `blocked`, `done` (one ask finished) and `finished` (the list went clear).
- `newest` — the cursor to ask with next.

The updates are `tray.json` in the data dir, 200 kept, ids never restarting. `push/`'s sweep
writes them as it notices each moment, **before** any notification switch: a folder set quiet is
not to be interrupted, which says nothing about the tray saying what happened in it. Updates are
this Mac's sessions only — a hand runs no sweep — while `open` covers every machine.

## A slip asked without its page

`tray/shapes.py` reads a waiting slip's own markup into one of five shapes, and the phone draws it:

| Shape | Read from | Drawn as | Answer sent |
|---|---|---|---|
| `confirm` | `<button id="yes">` + `<button id="no">`, no input but `#note` | No / Yes | `{"answer": bool}` |
| `pick` | radio rows, no input but `#other` | one row per option | `{"answer": "option"}` |
| `text` | exactly one input, `#name` | a field and Send | `{"answer": "words"}` |
| `aloud` | `id="deckhand-aloud"` | "Answer aloud" → the page | — |
| `page` | anything else | "Open the slip" → the page | — |

Each kind is held to the *only* inputs its template has: `demos/form.html` has radio rows too,
and answering it as a pick would send half a form. Unknown is never guessed at.

An answer goes the route the page's own buttons use (`POST …/artifacts/{id}/answer`), as the
person. For a session on another machine that request is forwarded with its body — it was
forwarded empty once, which made every remote slip a 422.

## On the phone

`Views/Manager/TrayView.swift` — NEEDS YOU, a card per session (`TrayCards.swift`), then LATELY,
one card of rows (`TrayHistory.swift`). A session's `done` updates gather into one row until its
`finished` closes it (`TrayItem.items`, in DeckhandKit where `just test` reaches it). A row newer
than the last time the tray was open draws its word in colour; nothing else marks it.
