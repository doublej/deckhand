# deckhand

> iOS remote for the Claude Code sessions running in iTerm on the Mac

## What this is

Two halves in one repo. A Python daemon on the Mac lists every live Claude Code session, serves
the last rounds of its conversation, and stores voice clips the phone sends. A SwiftUI iOS app is
the remote: pick a session, read what it just said, hold to talk.

What is shipped, end to end: the phone lists sessions, reads the last rounds, and holds to talk;
the Mac stores the clip, transcribes it with utt, and writes the text straight into that session's
own inbox socket, the way one Claude session messages another. The daemon is controlled from its
own page inside utt.

## Stack

- **Daemon** — Python 3.13, FastAPI, uv. Port **4180**, binds `0.0.0.0`, launchd agent
  `com.jurrejan.deckhand`. Logs to `~/Library/Logs/Deckhand/deckhand.log` (`just logs`). State in
  `~/Library/Application Support/Deckhand/`.
- **Transcription** — utt, on-device, over its plugin file lane. No listener, no token, nothing on
  the network.
- **Summaries** — the Claude Agent SDK, Haiku 4.5, thinking off, three task tools and nothing else.
  The daemon owns the schedule; the phone only ever reads.
- **App** — Swift 6.2, SwiftUI, iOS 18. `DeckhandKit` (SwiftPM) holds the models, the HTTP client
  and the design layer so they are testable on the Mac; the app target comes from XcodeGen.
- **Lock Screen** — a Live Activity, driven from the Mac over APNs. Bundle id
  `dev.jurrejan.deckhand`, explicit because push cannot be enabled on a wildcard App ID.
- **Mac-side UI** — Deckhand's page inside utt (`plugin.py`), plus utt's menu bar. There was a
  menu bar app; the plugin page replaced every reason it existed.

## Architecture map

| Folder | Its job |
|---|---|
| `daemon/` | The Mac half: sessions, projects, transcripts, delivery, briefings, utt, APNs. |
| `Sources/DeckhandKit/` | Models, HTTP client, pure logic, design layer — everything `just test` can reach. |
| `Sources/IconMaker/` | Draws the app icon from the same grid as the in-app mark (`just icon`). |
| `deckhand/` | The iOS app target: `Model`, the recorders, and `Views/`. |
| `widgets/` | `DeckhandWidgets` — the Live Activity. |
| `Tests/`, `UITests/` | Swift tests on the Mac; UI tests drive the simulator against a live daemon. |
| `launchd/` | The agent plist, symlinked into `~/Library/LaunchAgents`. |
| `docs/`, `demos/` | Deep docs, and the artifact demo pages `just demo-check` validates. |

## Context boundaries

Before editing in one of these, read its CLAUDE.md — the invariants there were expensive to learn
and none of them is visible in the code.

- `daemon/CLAUDE.md` — the daemon as a whole, delivery routes, utt, the plugin page, APNs
- `daemon/src/deckhand_daemon/reading/CLAUDE.md` — transcripts, the inbox lane, context fullness
- `daemon/src/deckhand_daemon/filters/CLAUDE.md` — the prompt chain
- `daemon/src/deckhand_daemon/prompts/CLAUDE.md` — every prompt sent a model
- `Sources/DeckhandKit/CLAUDE.md` — the wire, decoding traps, slips
- `Sources/DeckhandKit/Design/CLAUDE.md` — the design language, ported from utt
- `deckhand/CLAUDE.md` — the screens, the gestures, running on hardware
- `deckhand/Views/Annotation/CLAUDE.md` — marking up a picture
- `widgets/CLAUDE.md` — the Live Activity and its wire contract

<vocabulary>
Canonical terms are defined in GLOSSARY.md — this project's ubiquitous language. Use them exactly.
Top concepts: session, pane, turn, inbox, briefing, ask, route, filter, slip, rail, mark, surface.
Say **slip** to the person holding the phone; write **artifact** in code, paths and endpoints.
Full glossary: ./GLOSSARY.md
</vocabulary>

## Global invariants

- **The join that makes this work.** Claude Code writes `~/.claude/sessions/<pid>.json` for every
  running session — sessionId, cwd, name, live busy/idle status. Those files outlive the process,
  so a record only counts when `ps` still shows that pid. `ps` gives the tty, `it2 session list
  --json` maps tty → iTerm pane. No hooks, no polling of iTerm's title. Everything else in this
  repo hangs off that.
- **The route is an authority choice, not a transport choice.** The keyboard route arrives as the
  person at the machine; the peer socket arrives labelled as another Claude session carrying none
  of the person's authority. That wrapper is a genuine control against one agent laundering
  permissions through another — it is not something to defeat. `keyboard` therefore never silently
  falls back.
- **`delivered: true` is not the same as "it was said".** A filter can stop a prompt the daemon
  accepted. Ask `Delivery.went`, never `delivered` alone.
- **A screen is one of two surfaces**: the rail (dark, `Palette.lcdGround`) or a page (the
  system's light ground). The app forces no colour scheme — it did once, and lost the distinction
  the whole design language rests on.
- **The design layer is a port of utt's** (`swift/utt/Utt/Design/`). Values are copied from there,
  never re-picked, so a change in utt is a diff here and not a redesign.
- **Everything the daemon says to a model is a file** in `daemon/src/deckhand_daemon/prompts/`,
  never a Python string.
- **`.quality.json` caps a source file at 400 lines and a directory at 16 files** (`.swift` and
  `.py` only). It is why several files exist as `+Feature` splits.

## The wire

`GET /sessions` → tap a row → `GET /sessions/{id}/turns` and `GET /sessions/{id}/summary` → hold
to talk → `POST /sessions/{id}/audio`, which answers with the transcript and whether it reached
the session. `?deliver=false` transcribes without sending, for the review card, and
`POST /sessions/{id}/say` sends the text once the person has read it.

- `GET /projects` — every folder on this Mac a session could be started in, and which source
  said so; `POST /projects/session` opens a terminal there and answers with the session itself
- `GET|PUT /settings` — what this Mac has been set to do, globally and per folder; `GET
  /settings/project?path=` is the resolved answer for one of them
- `POST /sessions/{id}/notify` — an agent asking for the person outright, in its own words
- `GET /briefings` — every live session's last briefing at once, off disk, for a cold start
- `GET /sessions/{id}/commands` — the slash commands and skills that session could be handed
- `GET /sessions/{id}/context` — every CLAUDE.md a session in that folder is loaded with, as a
  tree with the connectors already drawn, and what it costs
- `GET /sessions/{id}/raw` — the transcript as readable lines, for when the app's reading looks wrong
- `POST /sessions/{id}/queue/clear` — draw a line under an inbox holding prompts nothing will read
- `GET /filters` — every filter this Mac has; `GET|PUT /sessions/{id}/filters` — the chain one
  session is actually running
- `GET /sessions/{id}/files`, `GET /sessions/{id}/file?path=` — what the session touched
- `GET|POST /sessions/{id}/artifacts` — slips
- `POST /sessions/{id}/image`, `POST /sessions/{id}/focus`, `POST /sessions/{id}/control`
- `POST /sessions/{id}/name` — rename, by typing Claude Code's own `/rename` into the pane
- `GET /projects`, `POST /projects/session` — the folders on this Mac, and starting a session in one
- `POST /live/token` — the phone hands over its Live Activity push tokens; the Mac does the sending

`/health` is the only unauthenticated route; everything else needs the `x-deckhand-token` header.
Both `/health` and `/sessions` carry an `iterm` field saying whether pane data is trustworthy.

## Commands

`just` lists them all. The ones worth knowing:

- `just check` — the whole gate: Justfile format, file and directory sizes, SwiftLint, both
  builds, Swift tests, ruff, pytest, demo artifacts
- `just ui-test` — additionally drives the simulator against a daemon started with `just daemon`
- `just daemon` — run the daemon in the foreground; prints its address and pairing token
- `just token` — print the token again
- `just sim` / `just device` — build, install and launch, already paired
- `just install-agent` / `just uninstall-agent` — run it at login, or stop doing that
- `just sync-apns` — materialise the APNs key out of 1Password for launchd

## Related context

- [GLOSSARY.md](GLOSSARY.md) — the project's vocabulary
- [agent.md](agent.md) — verify loop, auto-fix commands, boundaries
- [docs/artifacts.md](docs/artifacts.md) — what a slip is, what it may contain, and the bridge
- [docs/prompt-review.md](docs/prompt-review.md) — the standing prompt audit and its rollout order
- [docs/control-surface.md](docs/control-surface.md) — what it would take to drive the whole app from a command interface, and what such a surface must refuse
- `.claude/rules/` — Swift naming traps, and the shared agent journal protocol
- `launchd/com.jurrejan.deckhand.plist` — registered in `multi-stack/project-atlas/shared/daemons.json`
- `python/parakeet-server` is the other local ASR service, currently disabled for memory; utt is
  what deckhand uses.
