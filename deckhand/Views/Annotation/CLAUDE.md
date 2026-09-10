# Marking up a picture

## What this is

The pane that shows a picture, lets a pin be dropped on it, and hands the session both the marked
copy and the words. The maths lives in `DeckhandKit` (`Fitting`, `Markup`) because it is the part
with no UIKit in it and the part that goes wrong; this folder is the UIKit and SwiftUI around it.

## Invariants

- **SwiftUI state must not be set from inside `updateUIView`.** It runs inside the update pass and
  the change is dropped — silently, with no warning in the console. `PictureScroll` reports a
  marker's position to the surface above it, and the first report always worked while every later
  one vanished: dropping a pin also mutates a binding, which buys a second update pass that picks
  the change up, so only a path that happened to mutate something else appeared to work. Report
  from a gesture or a delegate callback, or defer to the next tick — and where a pushed value
  identifies *what* it describes, the reader can ignore a stale one rather than draw it.
- **A marker drawn on a picture wears no Deckhand colour.** Everywhere else a mark is teal because
  teal is what says Deckhand; a marker is drawn over somebody else's picture, and that picture is
  very often a screenshot of this app, where a teal disc on a teal button is a marker you have to
  hunt for. So it is achromatic and double-ringed: black figure, white face, black ring, white
  ring — the white one holds it off a dark picture and the black one off a light one, and there is
  no colour a photograph can be that it disappears into. `Marker.bands` draws it into the flattened
  copy and `Marker.label()` builds the same thing as a view; on screen the outer ring is a shadow
  with no blur, because one label carries one border.
- **Two spaces, two words, never the same one.** `spot` is a place in the picture's own pixels,
  `onScreen` is where that place currently is in a view. See `../../../.claude/rules/swift-naming.md`
  for why it is not `at`.
- **A marker's id is the picture's letter and then its number: `A1`, `B2`.** The number alone
  restarted at 1 for every picture, so two marked pictures pinned to one prompt arrived as two
  markers called 1 and two items called 1 — and nothing in the words could say which was which,
  because there is no filename to name (a picture is bytes on the phone until Send, and the Mac
  renames what arrives). The letter is the only id a session can *see*, since it is burnt into the
  pixels, which is also the constraint that rules out anything longer: it has to fit a small disc
  and read identically in the prose. `Pin.lettering(round:)` makes it, `AppModel.lettering(for:)`
  says which round this card is on, and `Marking` is handed it so the disc on screen is character
  for character the disc that gets burnt in. Marking a copy that already carries markers is the
  next round, so its new marks are `B1` beside the `A1` already on it — never a second `A1`.
- **The unmarked original travels with the marked copy**, so the session can see what was there
  before somebody drew on it.
