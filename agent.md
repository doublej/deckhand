# deckhand

> iOS remote for live Claude Code sessions in iTerm — list, read, and speak to them

## Stack

- Swift, SwiftPM, SwiftUI
- iOS deployment target: 26.0

## Commands

Use `just` as the task runner:

- `just check` — run all checks (just-fmt-check + loc-check + dir-check + lint + build + test)
- `just install` — resolve package dependencies (warns if SwiftLint missing)
- `just lint` / `just lint-fix` — SwiftLint strict / autocorrect + relint
- `just build` — debug build
- `just build-release` — release build
- `just test` — run tests
- `just loc-check` — check file lengths (thresholds in `.quality.json`)
- `just dir-check` — check files per directory (thresholds in `.quality.json`)
- `just just-fmt-check` — verify Justfile formatting
- `just clean` — remove `.build/` artifacts
- `just xcode` — open in Xcode
- `just update-scaffold` — pull updates from the cookiecutter template

## Project Structure

```
deckhand/
└── ...             # SwiftUI app source
Package.swift       # SwiftPM manifest
Justfile            # task runner
```

## Conventions

- SwiftPM for dependency management
- SwiftUI for UI layer
- async/await for concurrency
- Keep functions small (5–10 lines target, 20 max)
- Prefer explicit, readable code over cleverness
- Handle errors at boundaries; let unexpected errors surface

## Agent

### Verify Loop

Run after every change: `just check`

Runs: just-fmt-check + loc-check + dir-check + lint + build + test.

Step-by-step alternative:

1. `just lint-fix`
2. `just build`
3. `just test`

### Delegating verification

Don't block on `just check` while a feature is still in progress — hand it to the
`verify-runner` subagent and keep building. It applies safe auto-fixes itself and writes
anything it can't safely resolve to `.claude/tickets/` instead of stopping you. Read
`.claude/tickets/` before treating a feature as done, and delete a ticket once you've
confirmed its issue is fixed.

### Auto-fixable

- `swiftlint --fix` — autocorrect SwiftLint violations (or `just lint-fix`)

### Common Tasks

- Add a SwiftUI view: create a new `.swift` file with a `View` struct
- Add a model: create a `Codable` + `Identifiable` struct
- Add a service: create a class/struct with `async`/`await` methods
- Add a dependency: add the package URL to `Package.swift` dependencies

### Testing

- Test files: `Tests/*Tests.swift`
- Framework: XCTest
- Run a single test: `swift test --filter FooTests/testBar`

### Boundaries

- Do not run `just xcode` — never open Xcode
- Do not deploy, archive, or push
- Do not modify the deployment target without asking
