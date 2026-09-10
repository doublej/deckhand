# The design layer

## What this is

utt's design language, ported. Deckhand is a plugin of utt's and a guest borrows its host's
identity whole, so this folder is a port of `swift/utt/Utt/Design/`: **the values are copied from
there, never re-picked**, so a change in utt is a diff here and not a redesign.

The one thing that is Deckhand's own is `Palette.tint` (#3EAFB4) and its mark, an anchor on the
same 6×6 dot grid utt's own mark lives on.

```
Palette, Typography, Spacing   # utt's tokens, copied
DotMatrix / DotPatterns   # the 6x6 geometry and the level curves; DotGlyph holds the shapes
DotMatrixDriver # utt's shared clock, so a mark is never still
DotMark         # a shape on the grid, and the wordmark
StateWord       # the four-letter state vocabulary, and a glyph on its tile
Accent          # the accent read out of the environment
Fade            # how present a rail row is, given how long its session has been quiet
Links           # addresses in what a session wrote
Chrome          # Card, SettingsGroup, SettingRow, PageHeader
Markdown / MarkdownBlocks / Prose  # how a session's words are drawn
```

## Invariants

- **A screen is one of two surfaces.** The sessions list and the landscape deck are the rail:
  `Palette.lcdGround` with `.environment(\.colorScheme, .dark)`, whatever the phone is set to.
  Everything else is a page on the system's own light ground. The app therefore forces no colour
  scheme — it did once, which made both surfaces the same and lost the distinction the whole
  language rests on.
- **No badges.** A state is the word alone — 9pt mono, tracked, in the state's colour, nothing
  around it. It was a dot and a label inside a bordered capsule, ported from utt, and that shape
  is not to appear in this app again: it reads as something you press, and each one sits beside
  something you actually can. `StateWord` is the only place a state is drawn.
- **Recording is the one exception to teal: it goes utt orange**, because recording is utt's job
  in every plugin — and that exception is the whole screen's, not one mark's. The accent is read
  out of the environment (`\.accent`) and a screen that can record sets it once at its top from
  its own recorder, so the rail, the session page and the deck all turn orange together and a view
  written later follows without knowing what a microphone is.
- **The fade is one opacity over the whole row**, applied last so the tile and border travel with
  the words: log curve from a two-minute grace to a 0.5 floor at eight hours. It reads
  `updated_at`, which is the age of an *idle* session only — a busy row is never faded whatever
  its timestamp says, or the hardest-working row on the rail would be the faintest one. Portrait
  only; `SessionRow` has no other caller.
- **Session glyphs are derived from the session's name with FNV-1a, not `hashValue`**: Swift seeds
  its hashing per process, so a session's face would change on every cold start.
- **The app icon is drawn from `DotMatrix.rect` itself** by `Sources/IconMaker` (`just icon`), so
  the home screen and the in-app mark cannot drift apart. It sits at 0.74 of the canvas rather
  than the 0.62 a tile uses, because iOS masks the icon to a squircle.
- **`ArtifactStyle` and `ArtifactTokens` are the same values as CSS.** They mirror this folder for
  a web view; copied, never re-picked, same as the port itself.

## Related context

- `../CLAUDE.md` — DeckhandKit as a whole
- `../../../deckhand/CLAUDE.md` — the screens that use all of this
