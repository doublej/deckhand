# Demo artifacts

Six working pages: one per thing `consult-user-mcp` can ask, plus the one shape that has no
`consult-user` equivalent because it only makes sense on a phone — a slip answered out loud.
They are artifacts, not mockups: copy one into a project's `.deckhand/artifacts/` and it is live
on the phone, where its `<title>` becomes its name and the part of the filename before `.html`
becomes its id.

```
cp demos/pick.html ~/dev/multi-stack/deckhand/.deckhand/artifacts/which-branch.html
```

Each one answers through `window.deckhand.respond(value)` with the **same shape** the matching
`ask` comes back with, so an agent that can already read a consult-user answer can read this one
without learning anything new.

| Page | The dialog it stands in for | What comes back |
| --- | --- | --- |
| `confirm.html` | `ask` `type: "confirm"` | `{ answer: true }`, plus `feedbackText` if a note was typed |
| `pick.html` | `ask` `type: "pick"` | `{ answer: "develop" }` — a typed "somewhere else" is the answer, never the word "Other" |
| `text.html` | `ask` `type: "text"` | `{ answer: "artifacts" }` |
| `form.html` | `ask` `type: "form"` — the wizard | `{ answer: { branch, gates, message, token }, completedCount }`, where `gates` is an array (`multi`) and `token` was masked (`hidden`) |
| `aloud.html` | nothing — a phone-only shape | `{ answer: { scope, deadline, … }, completedCount }`, one card per question with the app's own talk mark on it |
| `tweak.html` | `tweak` | `{ answer: { "fade-floor": 0.5, … }, action: "agent" }`, or `{ cancelled: true }` |

Two things they do not copy. A `tweak` can come back `action: "file"` because the pane writes to
disk while you drag; a page on a phone has no file lane, so the action is always `agent` and the
agent applies what it is handed. And a snooze has no meaning here — an artifact is already
asynchronous, so a page nobody answers just sits there.

`aloud.html` is also the template for that shape: everything on it is rendered from the one
`id="deckhand-aloud"` JSON block, so an agent writing one edits the block and nothing else. See
"A slip answered by talking" in `../docs/artifacts.md`.

`python3 demos/check.py` (or `just demo-check`) is the gate: every page parses, names itself,
calls `window.deckhand.respond`, and contains nothing the viewer's CSP would block. Opened in a
plain browser a page still renders, says `OFF`, and prints the JSON it would have sent — which is
how you review one without a phone. It will not be wearing the app's clothes there: the token
stylesheet (`ArtifactStyle.css`) is injected by the viewer, not carried by the page.
