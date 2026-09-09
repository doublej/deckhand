# deckhand

> iOS remote for live Claude Code sessions in iTerm — list, read, and speak to them

## What this is

An iOS SwiftUI application built with SwiftPM. Deployment target: `26.0`. SwiftLint is the lint bar; tests are SwiftPM-driven.

## Mental model

```
deckhand/
└── ...             # SwiftUI app source (views, models, services)
Package.swift       # SwiftPM manifest — executable target + tests
Justfile            # task runner
.swiftlint.yml      # strict ruleset
```

The runtime path is `App entry (`@main struct ... : App`) → root `Scene` → `View` hierarchy`. New surfaces are SwiftUI `View` types composed from the root scene; persistence / network work belongs in `@Observable` services owned at the app or scene level.

## Invariants

- SwiftPM is the build system — no Xcode project files committed. `just xcode` opens the package in Xcode for editing.
- SwiftUI for the UI layer (UIKit only where SwiftUI cannot reach).
- `async` / `await` for concurrency; avoid completion handlers and explicit `DispatchQueue` work in new code.
- SwiftLint `--strict` must pass — no warnings.
- Functions stay small (5–10 lines target, 20 max).
- Errors surface at the boundary; throw, propagate with `try`, handle at the SwiftUI layer.

## Common change patterns

- **Add a view** → new `struct ...: View` in a dedicated file.
- **Add a model** → `struct` (value-typed) or `@Observable` class for state that survives across views.
- **Add a service** → class with `async` methods, injected via environment or initializer.
- **Add a dependency** → declare in `Package.swift` `dependencies:` and the executable target's `dependencies:`.

## Verification

Run `just check` after every change. It composes:

`just-fmt-check` + `loc-check` + `dir-check` + `lint` + `build` + `test`

Recipe reference:

- `just install` — resolve SwiftPM dependencies (warns if SwiftLint missing)
- `just lint` — `swiftlint --strict`
- `just lint-fix` — `swiftlint --fix` then relint
- `just build` / `just build-release` — debug / release build
- `just test` — SwiftPM test
- `just xcode` — open in Xcode (required for running on a simulator / device)
- `just loc-check` / `just dir-check` — file-size and per-directory thresholds from `.quality.json`
- `just just-fmt-check` — verify Justfile formatting
- `just clean` — remove `.build/` artifacts
- `just update-scaffold` — pull updates from the cookiecutter template

## Related context

- [agent.md](agent.md) — verify loop, auto-fix commands, common tasks, boundaries
- `.claude/` — Claude Code settings, scaffold-update hook, library-freshness hook, diagnostic logging
- `.quality.json` — loc / dir thresholds (single source of truth)
- `.swiftlint.yml` — strict lint ruleset
- As this project grows, add nested `CLAUDE.md` files in high-value subfolders (Views, Services, Models, integrations) following the `claude-md-tree` skill's context-packet pattern.

<!-- agent-log:policy -->
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
