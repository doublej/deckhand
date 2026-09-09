# deckhand

> iOS remote for the Claude Code sessions running in iTerm on the Mac

## What this is

Two halves in one repo. A Python daemon on the Mac lists every live Claude Code session,
serves the last rounds of its conversation, and stores voice clips the phone sends. A SwiftUI
iOS app is the remote: pick a session, read what it just said, hold to talk.

Phase 1 (shipped) carries audio to the Mac and stops there — `transcript` in the upload
receipt is always `null`. Phase 2 transcribes on the Mac and types the result into the pane.

## Stack

- Daemon: Python 3.13, FastAPI, uv. Port **4180**, binds `0.0.0.0`, launchd agent
  `com.jurrejan.deckhand`.
- App: Swift 6.2, SwiftUI, iOS 26. `DeckhandKit` (SwiftPM library) holds the models and the
  HTTP client so they are testable on the Mac; the app target comes from XcodeGen.
- State on the Mac: `~/Library/Application Support/Deckhand/` — `token` and `audio/<sessionId>/`.

## Mental model

```
daemon/src/deckhand_daemon/
  sessions.py     # which Claude sessions are alive, and their iTerm pane
  transcripts.py  # the last rounds, read from the tail of the session's JSONL
  app.py          # the five endpoints
  config.py       # data dir, token, port
Sources/DeckhandKit/
  Models.swift, DeckhandClient.swift, ServerSettings.swift
deckhand/         # the app: App, Model, Recorder, Views/
UITests/          # drives the simulator against a running daemon
launchd/          # the agent plist, symlinked into ~/Library/LaunchAgents
```

`GET /sessions` → tap a row → `GET /sessions/{id}/turns` → hold to talk →
`POST /sessions/{id}/audio`. `POST /sessions/{id}/focus` brings that pane forward on the Mac.
`/health` is the only unauthenticated route; everything else needs the `x-deckhand-token`
header.

## Quirks worth knowing

- **The join that makes this work**: Claude Code writes `~/.claude/sessions/<pid>.json` for
  every running session — sessionId, cwd, name, and a live busy/idle status. Those files
  outlive the process, so a record only counts when `ps` still shows that pid. `ps` gives the
  tty, `it2 session list --json` maps tty → iTerm pane. No hooks, no polling of iTerm's title.
- Transcript folder names are lossy (`/` and `_` both become `-`), so the JSONL is found by
  globbing `~/.claude/projects/*/<sessionId>.jsonl`, never by rebuilding the path.
- Transcripts run to megabytes: only the last 512 KB is read, and the first line of that
  chunk is dropped as a fragment.
- Sessions with no iTerm pane are hidden — unless iTerm answers nothing at all, in which case
  every live session is listed so the app still works without the iTerm Python API.
- ATS: the app talks plain HTTP to a `.local` name, which needs `NSAllowsLocalNetworking`
  plus `NSLocalNetworkUsageDescription` (both in `project.yml`, not a checked-in plist).
- **Device installs are blocked**: Xcode is signed out on this Mac, so `just device` fails at
  provisioning. Sign in as `jurrejan@gmail.com` (team KA6433FU8U) first. The simulator path
  (`just sim`, `just ui-test`) needs nothing.
- Phase 2 has two ready threads: `messagingSocketPath` in the session record is Claude Code's
  own peer socket (better than typing into the pane), and `python/parakeet-server` is the
  local ASR service, currently disabled for memory.

## Verification

`just check` — Justfile format, file sizes, directory sizes, SwiftLint, both builds, Swift
tests, ruff, pytest. The app build needs the simulator named in the Justfile's `sim`.

`just ui-test` additionally drives the simulator against a daemon started with `just daemon`.

- `just daemon` — run the daemon, prints its address and pairing token
- `just token` — print the token again
- `just sim` — build, install and launch in the simulator, already paired
- `just install-agent` / `just uninstall-agent` — run it at login, or stop doing that

## Related context

- [agent.md](agent.md) — verify loop, auto-fix commands, boundaries
- `.quality.json` — loc / dir thresholds
- `launchd/com.jurrejan.deckhand.plist` — registered in `multi-stack/project-atlas/shared/daemons.json`

### Shared agent journal

Use `./agent-log` (a shim for `atlas agent-log` — both are identical) for short-lived
operational awareness between concurrent agents. It is not chat and not a task tracker: the
issue tracker remains the source of truth for ownership, blockers, and durable findings.

- Run `./agent-log recent` before interpreting shared state.
- Before an action that can change another agent's observations, write an intent with every
  affected scope. This includes shared-worktree edits, generated artifacts, git/index
  mutations, and shared ports, processes, or services.
- Run builds, tests, and deployments through the wrapper so start, commit, dirty state,
  duration, exit code, and outcome are recorded even on failure:
  `./agent-log run build|test|deploy --scope <resource> [--bead <id>] -- <command...>`.
- For manual operations, use `./agent-log begin <operation> --scope <resource> [--bead <id>]
  -- <summary>` and always close the returned id with `./agent-log end <id> --outcome
  ok|failed|cancelled -- <result>`. `<operation>` is one of build, commit, deploy, edit, implement, investigate, merge, push, review, sync, test — what
  makes this particular run specific goes in the summary, never in an invented operation name.
- Record a temporary result-affecting discovery with `./agent-log finding --scope <resource>
  --evidence <fact> [--bead <id>] -- <summary>`. This is the entry that saves another agent a
  wasted run, and the one most often skipped — write one whenever you learn something that
  would change what a concurrent agent does next, especially a dead end. Promote lasting
  knowledge to the issue tracker or the relevant doc.
- At session end, write `./agent-log handoff -- <stopping point + next step>` — the durable
  baton the next session's briefing picks up. Handoffs never expire; the latest one is
  always shown by `recent`.
- Intents expire after 20 minutes and findings after 4 hours unless `--ttl` overrides them.
  Renew by closing and reopening an intent; never treat an expired entry as current.
- Keep summaries factual and short. Do not reply, ask questions, mention agents, narrate
  routine progress, or log isolated reads/edits/tests that cannot affect anyone else.

Canonical scopes are `path:<repo-relative-path>`, `artifact:<name>`, `service:<name>`,
`host:<name>`, `port:<number>`, and `git:<worktree-or-ref>`; a repo may define additional
canonical scopes of its own. Add multiple `--scope` flags when needed. The journal SQLite db
lives in the git common directory, so linked worktrees share it without dirtying the repo.
