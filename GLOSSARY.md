# Vocabulary

The words this project uses, and the ones it has decided against. One concept, one word — in
code, in the UI, in commits, and in what a session is told.

Two audiences, and they differ in exactly one place: **say slip to a person, write artifact in
the wire.** Everywhere else the word is the same on both sides.

## The session and the Mac

| Word | Means | Not |
|---|---|---|
| **session** | One live Claude Code process on the Mac, keyed by its `sessionId`. | conversation, agent, instance |
| **pane** | The iTerm split a session is running in. Absent when iTerm cannot be reached. | window, tab, terminal |
| **record** | `~/.claude/sessions/<pid>.json` — what Claude Code writes about a live session. | session file |
| **transcript** | The session's own JSONL under `~/.claude/projects/`. Never written by Deckhand. | log, history |
| **listing** | What `/sessions` answers: every live session plus what is true of the Mac as a whole. | index, list of sessions |
| **pairing token** | The `x-deckhand-token` secret. `/health` is the only route without it. | api key, password |

## The conversation

| Word | Means | Not |
|---|---|---|
| **turn** | One round of the conversation as the phone draws it. A message absorbed mid-turn is a turn. | message, exchange, round |
| **inbox** | The session's own message queue, replayed from `queue-operation` lines. | queue (in prose), buffer |
| **briefing** | What the small model writes about a session since you last spoke. A file on disk. | summary (in prose), digest |
| **ask** | One item on the person's list, kept by the Mac, changed only by the three SDK tools. | todo, task (in the UI), item |
| **task** | The same thing, in code and on the wire (`tasks.py`, `add_task`). | — |
| **nudge / idle check** | The daemon asking a quiet session about the asks still open. | ping, poke, reminder |

## Speaking into a session

| Word | Means | Not |
|---|---|---|
| **clip** | The recorded audio the phone sends. | recording, voice note |
| **hint** | A word handed to utt to bias transcription (`transcribe.hints_for`). | prompt, vocabulary |
| **route** | Keyboard or socket — whose authority the words carry. `auto`, `keyboard`, `socket`. | channel, transport |
| **keyboard route** | `it2 session send` typing into the pane, as the person at the machine. | type route, direct |
| **socket route** | The session's own peer socket, labelled as another agent. | fallback (in code), IPC |
| **delivered** | The daemon accepted and wrote it. Never on its own — ask `Delivery.went`. | sent, said |
| **orders** | What the person has told one session to keep in mind, carried in front of every prompt it is sent. "Standing orders" in prose — a ship's hold for every watch, and so do these. They are the person's; the **context** (`/context`) is the project's CLAUDE.md and is a different thing. | rules, memory, context, system prompt |
| **control** | Stop, compact, clear: a keystroke, not a message (`Control`, `deliver.control`). | command, action |
| **filter** | One step that may change or stop a prompt on its way in. | rule, middleware, hook |
| **chain** | The ordered list of steps. Order is run order; a step is a position, not a key. | pipeline, config |
| **verdict** | What a filter returns: carry on, or stop. | result, decision |

## What a session leaves behind

| Word | Means | Not |
|---|---|---|
| **slip** | An artifact, spoken to the person: "1 of 3 slips waiting", "Answered the slip …". | card, note, artifact (in the UI) |
| **artifact** | The same thing in code, on the wire, and in `.deckhand/artifacts/`. | slip (in code) |
| **page** | The HTML inside an artifact. | document, view |
| **file** | Something the session touched that a phone can open. The listing is the permission. | attachment, asset |
| **snap / picture** | An image the person sends *to* a session, delivered as a path. | photo, screenshot, image (in prose) |
| **markup** | What was marked on a picture, and what the session is told about it. | annotation (in code), drawing |
| **lettering** | What a picture's markers wear in front of their numbers — `A1`, `B2`. One letter per marked picture, so one prompt holds no two ids alike. | prefix, group, index |
| **spot** | A place in a picture's own pixels. | at, point, position |
| **onScreen** | Where that place currently is in a view. | at, frame |

## The look

| Word | Means | Not |
|---|---|---|
| **surface** | One of two: the rail, or a page. Nothing is a third. | theme, mode |
| **rail** | The dark LCD surface — the sessions list and the landscape deck. | list, sidebar |
| **deck** | The landscape rail. | grid, board |
| **mark** | A shape on the 6×6 dot grid (`DotMark`). | logo, icon (in code), badge |
| **glyph** | A session's own face on its tile, from FNV-1a of its name. | avatar, icon |
| **state word** | The four-letter state, drawn as the word alone. | badge, pill, chip, status |
| **tint** | Deckhand's own #3EAFB4. | teal (in code), brand colour |
| **accent** | What a screen is currently in — tint, or utt orange while recording. | highlight |

**Never: badge.** A dot and a label inside a bordered capsule is not to appear in this app
again — it reads as something you press. `StateWord` is the only place a state is drawn.
