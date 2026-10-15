# deckhand

> iOS remote for the Claude Code sessions running on every machine on the home network

## What this is

Two halves in one repo. A Python daemon on the Mac lists every live Claude Code session, serves
the last rounds of its conversation, and stores voice clips the phone sends. A SwiftUI iOS app is
the remote: pick a session, read what it just said, hold to talk.

What is shipped, end to end: the phone lists sessions, reads the last rounds, and holds to talk;
the Mac stores the clip, transcribes it with utt, and writes the text straight into that session's
own inbox socket, the way one Claude session messages another. The daemon is controlled from its
own page inside utt.

One swipe left of the sessions list is **the manager** — a Claude Agent SDK conversation living
inside the daemon that reads every session, speaks into them, starts new ones, changes this Mac's
switches and moves the phone's own screen. What it may not do is one sentence and it is
load-bearing: it never types into a pane. See [docs/manager.md](docs/manager.md).

## Stack

- **Daemon** — Python 3.13, FastAPI, uv. Port **4180**, binds `0.0.0.0`, launchd agent
  `com.jurrejan.deckhand`. Logs to `~/Library/Logs/Deckhand/deckhand.log` (`just logs`). State in
  `~/Library/Application Support/Deckhand/`. Says where it is on the LAN as `_deckhand._tcp`,
  so the phone's pairing screen finds the address; the token is still typed.
- **Transcription** — utt, on-device, over its plugin file lane. No listener, no token, nothing on
  the network.
- **Summaries** — the Claude Agent SDK, Haiku 4.5, thinking off, three task tools and nothing else.
  The daemon owns the schedule; the phone only ever reads.
- **The manager** — the Claude Agent SDK again, Sonnet 5, thinking off, twelve in-process tools
  over this daemon's own modules. One `query()` per thing said, carrying `resume=`; the
  conversation is a file with a cursor, never a stream.
- **App** — Swift 6.2, SwiftUI, iOS 18. `DeckhandKit` (SwiftPM) holds the models, the HTTP client
  and the design layer so they are testable on the Mac; the app target comes from XcodeGen.
- **Lock Screen** — a Live Activity, driven from the Mac over APNs. Bundle id
  `dev.jurrejan.deckhand`, explicit because push cannot be enabled on a wildcard App ID.
- **Mac-side UI** — Deckhand's page inside utt (`plugin.py`), plus utt's menu bar, for running
  the daemon. A first menu bar app did only that and was deleted. The Mac app (`mac/`) is the
  manager and the Lock Screen's cards, for the person at the Mac.

## Architecture map

| Folder | Its job |
|---|---|
| `daemon/` | The Mac half: sessions, projects, transcripts, delivery, briefings, utt, APNs. |
| `daemon/…/fleet/` | The rest of the network: atlas's registry, the ssh links, the hands, the merge. |
| `daemon/…/manager/` | The manager: its conversation, its facade of tools, its run, its routes. |
| `daemon/…/space/` | The headset's space, and the pass-through to deckhand-windows. |
| `daemon/…/mcp/` | The twelve tools an agent *inside* a session gets: over stdio (`just install-mcp`) and as the `deckhand` command (`just install-cli`). |
| `skills/deckhand/` | The same surface as prose and two scripts, for a session with no tools. |
| `Sources/DeckhandKit/` | Models, HTTP client, pure logic, design layer — everything `just test` can reach. |
| `Sources/IconMaker/` | Draws the app icon from the same grid as the in-app mark (`just icon`). |
| `deckhand/` | The iOS app target: `Model`, the recorders, and `Views/`. |
| `mac/` | The Mac app: the manager in the menu bar and a window, the cards as notifications. |
| `widgets/` | `DeckhandWidgets` — the Live Activity. |
| `Tests/`, `UITests/` | Swift tests on the Mac; UI tests drive the simulator against a live daemon. |
| `launchd/` | The agent plist's template, rendered into `~/Library/LaunchAgents` by `just install-agent`. |
| `docs/`, `demos/` | Deep docs, and the artifact demo pages `just demo-check` validates. |

## Context boundaries

Before editing in one of these, read its CLAUDE.md — the invariants there were expensive to learn
and none of them is visible in the code.

- `daemon/CLAUDE.md` — the daemon as a whole, delivery routes, utt, the plugin page, APNs
- `mac/CLAUDE.md` — the Mac app, what its polls tell the daemon, and the session links
- `daemon/src/deckhand_daemon/reading/CLAUDE.md` — transcripts, the inbox lane, context fullness
- `daemon/src/deckhand_daemon/filters/CLAUDE.md` — the prompt chain
- `daemon/src/deckhand_daemon/prompts/CLAUDE.md` — every prompt sent a model
- `Sources/DeckhandKit/CLAUDE.md` — the wire, decoding traps, slips
- `Sources/DeckhandKit/Design/CLAUDE.md` — the design language, ported from utt
- `deckhand/CLAUDE.md` — the screens, the gestures, running on hardware
- `docs/manager.md` — the manager, its facade, and what it refuses
- `deckhand/Views/Annotation/CLAUDE.md` — marking up a picture
- `widgets/CLAUDE.md` — the Live Activity and its wire contract

<vocabulary>
Canonical terms are defined in GLOSSARY.md — this project's ubiquitous language. Use them exactly.
Top concepts: session, pane, turn, inbox, briefing, ask, route, filter, slip, rail, mark, surface,
manager, panel, entry.
Say **slip** to the person holding the phone; write **artifact** in code, paths and endpoints.
Full glossary: ./GLOSSARY.md
</vocabulary>

## Global invariants

- **The join that makes this work.** Claude Code writes `~/.claude/sessions/<pid>.json` for every
  running session — sessionId, cwd, name, live busy/idle status. Those files outlive the process,
  so a record only counts when `ps` still shows that pid. `ps` gives the tty, `tmux list-panes
  -a` maps tty → tmux pane. No hooks, no polling of a terminal's title. Everything else in this
  repo hangs off that.
- **The route is an authority choice, not a transport choice.** The keyboard route arrives as the
  person at the machine; the peer socket arrives labelled as another Claude session carrying none
  of the person's authority. That wrapper is a genuine control against one agent laundering
  permissions through another — it is not something to defeat. `keyboard` therefore never silently
  falls back.
- **One session messaging another is visible only in the receiver's transcript**, as a
  `queue-operation`/`enqueue` whose `content` opens `<cross-session-message from="uds:…">`. That
  header is written by the *sender's* Claude Code, which the daemon is not — so its own socket
  deliveries structurally cannot appear in that lane and no "is this really an agent?" filter is
  needed or wanted. Four ways to parse it wrong, each measured rather than assumed, are written
  out at the top of `daemon/src/deckhand_daemon/links/edges.py`. Read them before touching it.
- **`delivered: true` is not the same as "it was said".** A filter can stop a prompt the daemon
  accepted. Ask `Delivery.went`, never `delivered` alone.
- **A screen is one of two surfaces**: the rail (dark, `Palette.lcdGround`) or a page (the
  system's light ground). The app forces no colour scheme — it did once, and lost the distinction
  the whole design language rests on.
- **The manager never types into a pane.** It is a Claude session, so its words reach another
  session down that session's inbox socket carrying none of the person's authority — and from
  that one rule follow every refusal on its surface: no stop, compact or clear, no rename, no
  answering a slip, no editing a filter chain. They are enforced by absence: there is no tool.
- **The design layer is a port of utt's** (`swift/utt/Utt/Design/`). Values are copied from there,
  never re-picked, so a change in utt is a diff here and not a redesign.
- **Everything the daemon says to a model is a file** in `daemon/src/deckhand_daemon/prompts/`,
  never a Python string.
- **`.quality.json` caps a source file at 400 lines and a directory at 16 files** (`.swift` and
  `.py` only). It is why several files exist as `+Feature` splits.
- **This local history is the project; the public repo is behind it.** `github.com/doublej/deckhand`
  holds one orphan snapshot from 2026-09-09 that shares no ancestor with `develop`. Until JJ has
  it re-pushed from the real history, the remote is named `public` and is push-only, so nothing
  can fetch that snapshot into a branch. Agent worktrees branch from `HEAD` (`worktree.baseRef`
  in `.claude/settings.json`) because three branched from the snapshot in one day and none could
  merge. `just roots` proves every branch still shares the one root.

## The wire

`GET /sessions` → tap a row → `GET /sessions/{id}/turns` and `GET /sessions/{id}/summary` → hold
to talk → `POST /sessions/{id}/audio`, which answers with the transcript and whether it reached
the session. `?deliver=false` transcribes without sending, for the review card, and
`POST /sessions/{id}/say` sends the text once the person has read it. That answer also carries
`timings` — milliseconds per stage in the order they ran — and every stage is written to
`timings.jsonl` beside the daemon's other state, one line per clip.

- `GET /projects` — every folder on this Mac a session could be started in, and which source
  said so; `POST /projects/session` opens a terminal there and answers with the session itself
- `GET|POST|DELETE /bindings`, `GET /bindings/match?url=` — web pages pinned to a listed project
  folder, as an origin plus optional path prefix; a match answers best first, longest prefix then
  most recently used. `POST /feedback`, `GET /feedback?path=` — what was said about one spot on
  such a page, kept per folder, oldest first (`bindings/`)
- `GET|PUT /settings` — what this Mac has been set to do, globally and per folder; `GET
  /settings/project?path=` is the resolved answer for one of them
- `GET|PUT /aliases` — the words this Mac always mishears and what they were meant to be, as rows
  of two. Swapped into every clip the moment utt answers, so the card, the session and the
  manager all read the one sentence; the right-hand side also goes into the next clip's hints
- `GET|PUT /sessions/{id}/orders` — what this session is to keep in mind, carried in front of
  every prompt it is sent. Empty adds nothing at all
- `POST /sessions/{id}/notify` — an agent asking for the person outright, in its own words
- `GET /sessions/links?within=` — which sessions have been messaging each other lately, as
  directed edges whose two ends are both on the listing. The rail draws them as light running
  from sender to receiver, decaying over the same window the phone asked for
- `GET /briefings` — every live session's last briefing at once, off disk, for a cold start
- `GET /presence` — `where`: `laptop`, `phone` or `headset`, which a session should reach the
  person on — `headset` while the Quest app's `POST /presence/headset` beat is under 30 s old,
  else whichever was touched last, or `phone` after two minutes untouched. `POST
  /presence/phone` is the app saying it was touched. `/health` carries it too, beside `cover`,
  the sign utt draws over the screens while the Mac is driven from the phone
- `GET /sessions/{id}/commands` — the slash commands and skills that session could be handed
- `GET /sessions/{id}/context` — every CLAUDE.md a session in that folder is loaded with, as a
  tree with the connectors already drawn, and what it costs
- `GET /sessions/{id}/agents` — the subagents it has started, each with its own step count and
  whether it is still going; `GET /sessions/{id}/agents/{aid}/turns` is one of their conversations.
  A subagent is not a tool call: Claude Code writes its transcript beside the session's, under
  `<sessionId>/subagents/`, and the phone draws it as a row you can open rather than a dot
- `GET /sessions/{id}/raw` — the transcript as readable lines, for when the app's reading looks wrong
- `POST /sessions/{id}/queue/clear` — draw a line under an inbox holding prompts nothing will read
- `GET /filters` — every filter this Mac has; `GET|PUT /sessions/{id}/filters` — the chain one
  session is actually running
- `GET /sessions/{id}/files`, `GET /sessions/{id}/file?path=` — what the session touched
- `GET /sessions/{id}/artifacts`, `GET|POST /sessions/{id}/artifacts/{aid}/answer` — slips.
  A session writes one as a file in its own `.deckhand/artifacts/`, never over HTTP
- `POST /sessions/{id}/image`, `POST /sessions/{id}/focus`, `POST /sessions/{id}/control`
- `POST /sessions/{id}/name` — rename, by typing Claude Code's own `/rename` into the pane
- `GET /projects`, `POST /projects/session` — the folders on this Mac, and starting a session in one
- `POST /live/token` — the phone hands over its Live Activity push tokens; the Mac does the sending
- `GET /manager?since=` — the manager's conversation after the last entry id this phone saw, plus
  whether a run is still in flight. `POST /manager/say` and `POST /manager/audio` speak to it and
  answer with the entry rather than the reply; `POST /manager/clear` drops the conversation and
  the SDK thread behind it, both together
- `GET /alerts?since=` — every card the Mac raised for a session, by cursor, for the Mac app,
  which APNs cannot reach. `GET /manager?watching=false` is a poll with no panel on screen, and
  leaves the phone's pushes on
- `GET /space`, `POST /space/planes`, `DELETE /space/planes/{id}?by=`, `PUT /space/poses/{key}` —
  the headset's space: open web and window planes, near which session, and every plane's pose;
  `rev` rises on each change. A session is told when the person puts a plane beside it or takes
  one away; no `by` is the person. `GET /windows`, `/windows/{id}/frame|stream` pass through to
  deckhand-windows on :4181, 503 when it is down ([docs/space.md](docs/space.md))
- `POST /camera/frames`, `GET /camera/stream`, `GET /camera` — the headset's camera: one JPEG
  per POST in, MJPEG out to whoever watches, and whether it is live

`/health` is the only unauthenticated route; everything else needs the `x-deckhand-token` header.
Off the home network that surface is `https://deckhand.jurrejan.com` — the NAS Caddy, checking
the same header in front of the Mac so `/health` is not open to the internet either. See
[daemon/CLAUDE.md](daemon/CLAUDE.md) under *Off the home network*.
Both `/health` and `/sessions` carry an `iterm` field saying whether pane data is trustworthy —
named for iTerm, which tmux replaced on 2026-10-15; the key, like `pane.iterm_session_id`, stays
because the installed apps decode it.
Every row carries `provider`, `claude` or `codex` (a Codex app-server thread: `pid` 0, no `tty`, no
pane); `/health` carries `codex`, whether the app server answered the last listing; and
`POST /projects/session` takes `provider` as well. See `daemon/CLAUDE.md` under *Codex threads*.

## Commands

`just` lists them all. The ones worth knowing:

- `just check` — the whole gate: Justfile format, file and directory sizes, SwiftLint, both
  builds, Swift tests, ruff, pytest, demo artifacts
- `just ui-test` — additionally drives the simulator against a daemon started with `just daemon`
- `just daemon` — run the daemon in the foreground; prints its address and pairing token
- `just token` — print the token again
- `just mac` — build the Mac app into `~/Applications` and start it
- `just sim` / `just device` — build, install and launch, already paired
- `just install-agent` / `just uninstall-agent` — run it at login, or stop doing that
- `just sync-apns` — materialise the APNs key out of 1Password for launchd

## Related context

- [GLOSSARY.md](GLOSSARY.md) — the project's vocabulary
- [agent.md](agent.md) — verify loop, auto-fix commands, boundaries
- [docs/commands.md](docs/commands.md) — every HTTP route, MCP tool and `deckhand` command,
  generated from the code (`just commands-doc`)
- [docs/install-and-pairing.md](docs/install-and-pairing.md) — `just setup`, `just teardown`, being
  found after the Mac's address moves, and pairing by code
- [docs/artifacts.md](docs/artifacts.md) — what a slip is, what it may contain, and the bridge
- `just install-cli` — put `deckhand` on PATH; `deckhand prime` is its whole contract
- [docs/prompt-review.md](docs/prompt-review.md) — the standing prompt audit and its rollout order
- [docs/agent-surface.md](docs/agent-surface.md) — what an agent *inside* a session needs to know
  about Deckhand, why that is a skill rather than an MCP server, and the token that would make its
  refusals real
- [docs/control-surface.md](docs/control-surface.md) — what it would take to drive the whole app from a command interface, and what such a surface must refuse
- [docs/audio-speedup.md](docs/audio-speedup.md) — why clips are not re-encoded faster before
  utt hears them: the saving is 0.27 s on a typical clip, and utt costs `1.38 s + 0.068 × seconds`
- `.claude/rules/` — Swift naming traps, and the shared agent journal protocol
- `launchd/com.jurrejan.deckhand.plist` — registered in `multi-stack/project-atlas/shared/daemons.json`
- `python/parakeet-server` is the other local ASR service, currently disabled for memory; utt is
  what deckhand uses.
