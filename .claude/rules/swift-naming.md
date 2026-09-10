---
paths:
  - "**/*.swift"
---

# Swift naming traps in this repo

Two names have cost time here more than once. Both are lint- or compiler-level, and neither
error message points at the real cause.

- **A two-letter name fails the lint, and `at` is the one everybody reaches for.** SwiftLint's
  `identifier_name` wants three characters, and a point on a picture wants to be called `at` — it
  has now been written and renamed three times (`Pin.at` → `Pin.spot`, and twice in `Marking`).
  The two spaces need two words anyway: `spot` is a place in the picture's own pixels, `onScreen`
  is where that place currently is in a view. Never the same word for both.
- **Never call a public type `Context` in DeckhandKit.** Inside a `UIViewRepresentable`, `Context`
  is already a typealias for `UIViewRepresentableContext<Self>`, so a module-level `Context`
  imported beside SwiftUI silently breaks the conformance of anything spelling
  `makeUIView(context:)` the documented way — and the error names the representable, not the
  clash. It is `ContextWindow`.

Verb-based names for functions (`calculateTax`). `just lint` is SwiftLint; it runs inside
`just check`.
