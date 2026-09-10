# The wire

Every route the daemon serves, what it answers with, and the trap in it. Read against the
daemon's own source on 2026-09-10.

Nothing here is needed to write a slip — that is a file, and `SKILL.md` covers it. This is for
the three things a slip cannot do: ask for the person outright, read another session's state, and
speak into one.

## Reaching it at all

```bash
DECK=http://127.0.0.1:4180
TOKEN=$(cat ~/Library/Application\ Support/Deckhand/token)
curl -s "$DECK/sessions" -H "x-deckhand-token: $TOKEN"
```

- The daemon binds `0.0.0.0` on port **4180** so the phone can reach it; from a session on this
  Mac, `127.0.0.1` is always right. `GET /health` answers `host` (the `.local` name the phone
  pairs with) and `lan` (this Mac's address).
- The token is a 12-character file, mode 600, owned by the person — and the agent runs as the
  person, so it is readable. Written as `$(cat …)` the shell expands it after the command is
  recorded, so the secret stays out of the transcript.
- `$DECKHAND_DATA_DIR` overrides the state folder if it is set.
- **`GET /health` is the only route without the token header.** Everything else answers 401.
- **This session's own id is already in the environment**: `CLAUDE_CODE_SESSION_ID`, injected
  into every Bash tool call, is the `{id}` these routes take. `CLAUDE_PID` is beside it. There is
  no discovery step.

## What a session is

`GET /sessions` → `{sessions: [row], iterm, week}`. One row per **live** session:

`session_id`, `pid`, `name`, `cwd`, `folder`, `status` (busy/idle), `updated_at`, `tty`, `pane`
(null when iTerm cannot be reached), `context: {used, limit}`, `model`, `effort`,
`artifacts_waiting`, `artifacts_answered`.

- **A session with no pane is hidden — unless iTerm answers nothing at all**, in which case every
  live session is listed. `iterm` says which of those two worlds you are in; anything but `"ok"`
  means pane data is not trustworthy and rows may be missing or stale.
- **`updated_at` is when the status last changed, not a heartbeat.** A busy session can report a
  stamp half an hour old while it is mid-turn, so it is only the age of an *idle* session.
- **`context.limit` is this Mac's auto-compact window, not the model's ceiling** — it says when
  *this* Mac folds a session into a summary. It lags by a turn on a busy session.
- The name is a key, not a label: stars, hidden rows and filter chains are all filed under it,
  so two sessions sharing a name silently share all three.

## Reading

| Route | Answers | The trap |
|---|---|---|
| `GET /sessions/{id}/turns?limit=8&before=0` | `{turns, queued, more}` | `limit` 1–200, `before` walks backwards in pages. **`queued` is the inbox, not the transcript** — and it is `[]` on any page but the newest, because nothing is queued behind history. |
| `GET /sessions/{id}/summary` | the last briefing, off disk | Never waits for a model. Reading it **bumps** that session to the front of the daemon's write queue. |
| `GET /briefings` | `{briefings: {id: briefing}}` | Every live session at once, off disk. What makes a cold start whole without buying a model run. |
| `GET /sessions/{id}/raw?limit=1500` | `{lines: [str]}` | 1–4000. The transcript as readable lines, for when the app's reading looks wrong. |
| `GET /sessions/{id}/commands` | `{commands: [{name, description, hint, kind, scope}]}` | Re-read from disk per request. The session's own `.claude/commands` shadow the user's on a name collision; nested folders become `/git:amend`. |
| `GET /sessions/{id}/context` | `{documents, tokens}` | Every CLAUDE.md a session in that folder **starts** with — not what it read. The tree is also a permission: those documents are readable through `/file` whether or not the run opened them. |
| `GET /sessions/{id}/files` | `{files}` | Source files and `node_modules`/`.build`/`.git` are left out on purpose. |
| `GET /sessions/{id}/file?path=` | the bytes | **The listing is the permission**, re-derived per request: a path the transcript never named is a 404. 413 over 512 MB. You have `Read`; you do not need this. |

## Slips

The listing and the answer, for when you want them from the Mac rather than off disk.

| Route | Answers | The trap |
|---|---|---|
| `GET /sessions/{id}/artifacts` | `{artifacts: [{id, title, modified, answered}]}` | Newest first. `answered` is the whole state: a page with no `.answer.json` beside it is open. |
| `GET /sessions/{id}/artifacts/{aid}` | `text/html` | 404 if there is no such id, no `.deckhand/artifacts/` folder, or the page is over 4 MB. |
| `GET /sessions/{id}/artifacts/{aid}/answer` | `{value}` | **`{"value": null}` means nobody has answered** — it is not an error. A missing page is still a 404. |
| `POST /sessions/{id}/artifacts/{aid}/answer` | `{answer, delivered, delivered_by, delivery_error}` | The phone's route in. `value` is required JSON and **cannot be `null`** (FastAPI cannot tell an omitted field from an explicit null); `false`, `0`, `""` and `[]` all arrive intact. Do not answer your own slip. |

## Speaking, and asking for the person

| Route | Answers | The trap |
|---|---|---|
| `POST /sessions/{id}/notify` `{line}` | `{pushed: true}` or `{pushed: false, why}` | The one Lock Screen card a session raises **for itself**, in its own words. Empty text is a 400, not a blank card. Gated by the `called` setting, which a folder may refuse outright — and the refusal comes back rather than being swallowed. Say so when it does. |
| `POST /sessions/{id}/say` `{text, images?}` | `{delivered, delivered_by, delivery_error, notes, stopped_by}` | **Never pass `route`.** See "What this refuses". `delivered: true` is not "it was said" — check `delivered && stopped_by == null`. A leading `/` is refused on the socket route and where there is no pane. |
| `POST /sessions/{id}/audio?deliver=` | `{path, bytes, received_at, transcript, transcript_error, prepared, delivered, delivered_by, delivery_error, notes, stopped_by}` | 201. The phone's lane, not yours. `deliver=false` transcribes only but still runs the chain once, so `prepared` shows what would really be sent; sending those words on with `/say` needs `prepared=true` or a non-idempotent filter runs on its own output. |
| `POST /sessions/{id}/image` | `{path}` | Multipart, image suffixes only, 32 MB. The path only works while it stays in that session's own `images/<id>/` folder; anything else is dropped silently from `/say`. |
| `POST /sessions/{id}/focus` | `{focused: true}` | 409 when there is no iTerm pane. |
| `POST /sessions/{id}/name` `{name}` | `{renamed, was, carried_filters}` | Types Claude Code's own `/rename` into the pane, so a busy session only runs it when its turn ends and the listing catches up late. The filter chain is carried across because it is filed by name. |
| `POST /sessions/{id}/queue/clear` | `{cleared: n}` | Draws a line under an inbox holding prompts nothing will read. It never touches the transcript. |
| `POST /live/token` `{token, kind}` | `{registered: kind}` | The phone's own push tokens. Nothing an agent has. |

## Filters and settings, read-only

- `GET /filters` → `{known}` — what this Mac can do to a prompt. Global; changes only on daemon
  update.
- `GET /sessions/{id}/filters` → `{session, known, steps}` — the chain one session runs. **Array
  order is run order**, and a filter may appear twice with different settings, so it is a list of
  positions and not a table.
- `GET /settings` → the whole document: global answers, a `projects` override map keyed by
  **folder path**, and `offers` (the model lists a write would be checked against).
- `GET /settings/project?path=` → `{path, wants}` — the resolved answer for one folder, already
  merged. Per key, not per object: `null` on the wire means "no opinion, follow global".
- `GET /projects` → `{projects, source}` — every folder on this Mac a session could start in,
  each with `live` (session count) and `trusted` inline.

## What this refuses, and why it is a default rather than a fence

The route is an authority choice, not a transport choice. The keyboard route arrives as the
person at the machine; the peer socket arrives labelled as another Claude session carrying none
of the person's authority. An agent-facing surface is exactly the thing that wrapper exists to
constrain.

- **No `route` argument, ever.** `route` is the person's setting, in their own Settings screen —
  never a parameter you pass. Choosing `keyboard` is claiming to be the person.
- **No `POST /control`.** Cancel, compact, clear and exit are keystrokes the person presses.
  `clear` is the only irreversible thing in the app.
- **No `PUT /settings`, no `PUT /sessions/{id}/filters`.** An agent that can rewrite a session's
  filter chain can remove the filter that would have stopped it. That is quiet, which makes it
  worse.
- **No `POST /projects/session`.** Starting a session is starting a process on a launch line
  nobody approved, in a folder whose trust dialog was answered for a person.
- **No `/file`.** You have `Read`. A second path to the disk is not worth having.

**None of this is enforced today.** There is one shared pairing token, so the daemon cannot tell
an agent from a phone, and anything declined here `curl` still performs. What these refusals
defend against is drifting into speaking as the person because that route was the convenient one
— not an attack on a Mac you are already running on. An agent token distinct from the pairing
token is the change that would make them real; until it lands, treat every line above as a rule
you keep rather than one you are held to.
