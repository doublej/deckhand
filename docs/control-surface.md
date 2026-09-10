# Driving the app from a command interface

> A plan, not a build. JJ: "at some point I want to build it, but for now plan it."

The question was whether Deckhand could be driven entirely by a command interface — MCP or CLI —
with a real-time agent inside the app controlling every state it holds, and whether today's code
is kind to that idea.

## The honest answer

**The data is addressable. The interaction is not.** About a third of the app's state already
lives on an `@Observable` model and could be read or written by an agent this afternoon. The
other two thirds is `@State` inside individual views, and that is where the work is.

| Where it lives | Roughly | What it means |
|---|---|---|
| `AppModel` + `ProjectPicker` + `Switchboard` | ~35 pieces | Already addressable |
| `@State` in 23 view files | ~68 pieces | Not reachable without moving it |
| Derived | ~20 | Free, follows the above |

Of the view-local two thirds, **22 pieces gate presentation** — `showSettings`, `showProjects`,
`chosen`, `showing`, `confirming`, `renaming`, `filtering`, `open`, `marking`, `picking` — and
every one is `private` to the view that owns it. Another ~15 hold *content* an agent would need
to read and write, and one of those matters more than the rest: `ReviewCard.draft`, the edited
prompt. It is the single most important string in the app and it never touches the model.

**The biggest structural obstacle is navigation.** There is no router. `RootView` picks rail
versus deck from a `GeometryReader` size — orientation, not state — and everything below it is a
private boolean in whichever view happens to own it. "Go to session X, open its slips, scroll to
Y" reaches nothing today.

One encouraging detail: `AppModel.current` already exists and is documented as "the session whose
page is open". It is written *after* the fact and read only to highlight a rail row — a mirror,
not a source. Making it the source is a small diff and buys the most valuable verb there is.

## Transport

**Recommended: an in-process `Command`/`Reply` façade on `AppModel`, fed by a daemon-side
long-poll.** The app already polls the Mac every four seconds, so the channel is about thirty
lines on a loop that exists. The façade is the real work and it is worth doing on its own merits —
it is also what an agent embedded in the app would call directly, with no transport at all.

Why not the others:

- **An HTTP server on the phone** — ~150 lines on `NWListener`, and it is foreground-only anyway.
  The phone's address moves. It solves a problem the existing poll does not have.
- **A URL scheme** — ~20 lines, navigation only, and it cannot read state back. Half a surface.
- **App Intents** — genuinely tempting, because it buys Siri and Shortcuts for nothing. But it
  wants one type per verb against a directory capped at 16 files, and it is a bolt-on to a
  façade rather than a substitute for one. Worth adding *after* Phase 0, aimed at the same verbs.
- **APNs is not a channel.** The app declares `push-type: liveactivity` only and has no
  background modes; there is nothing there to receive a command on.

The app declares **no** App Intents and **no** URL scheme today.

## The bill

About a week and a half, and the first day is worth more than the rest put together.

| Phase | Size | What it buys |
|---|---|---|
| **0 — the façade** | 1 day | `Command`/`Reply` over the ~25 model methods that already exist; make `AppModel.current` the source rather than a mirror. Pick a session, speak, control, rename, star, hide, filters, projects, slips. **Best control per unit of work by a wide margin.** |
| 1 — navigation | 2 days | The 22 presentation gates onto one `Route` on the model. Tabs, sheets, covers, dialogs. |
| 2 — the read side | 1 day | A `Snapshot` an agent can ask "what is on screen". Fills the raw-transcript and slip-HTML holes. |
| 3 — drafts | 2 days | Lift `ReviewCard.draft`, the editor, slip answers, renaming and markups onto the model. Prompt editing and answering. |
| 4 — the recorder | 1–2 days | One model-owned recorder; `TalkControl` drives it instead of owning one of seven. |
| 5 — transport | 1 day | The long-poll, a second token, and the refusals. |

**Stop after Phase 0 and reassess.** It is a day, it breaks nothing, and it is useful on its own.

## What it must refuse

A surface that can drive the app is a surface that can speak as the person. That is the same
authority question the delivery routes already answer, and the answer has to be the same one.

- **Its own token, not the pairing token.** The pairing token is what the phone holds; a command
  channel that shares it means anything that can read a screenshot of Settings can drive the app.
- **It may never manufacture the keyboard route.** The keyboard route arrives as the person at
  the machine. An agent driving the app is not that, and `deliver` already refuses to pretend
  otherwise — the command surface must not become the way around it.
- **The irreversible ones stay behind a person.** `/clear` is the only thing in the app that
  cannot be undone. It should not be a verb on this surface at all.
- **No new reach.** The file endpoint is permissioned by the transcript that named the file, and
  the project endpoint by the Mac's own project list. A command surface inherits both limits or
  it has quietly widened them.

## Sources

Measured against the current tree, not recalled: `deckhand/Model.swift`, `deckhand/Starting.swift`,
`deckhand/App.swift:33-39`, `deckhand/Views/SessionListView.swift`, `deckhand/Views/SessionView.swift`,
`deckhand/Views/ReviewCard.swift`, `deckhand/Views/TalkControl.swift`, `daemon/src/deckhand_daemon/push.py`.
