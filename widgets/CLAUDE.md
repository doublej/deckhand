# The Lock Screen widget

## What this is

`DeckhandWidgets`, a Live Activity saying how many sessions have stopped and are waiting. The
**Mac** drives it over APNs — a backgrounded app has no promise of running again — so the phone
only hands over push tokens and the daemon does the sending (`daemon/src/deckhand_daemon/push.py`).

## Invariants

- **The card is push-to-start, never started by the app.** Asking for one at launch would park
  "Nothing waiting" on the Lock Screen for hours, which teaches you to ignore it. The app hands
  over a `start` token and the daemon raises a card the moment a session goes busy → idle; that
  transition is the only event here. A session already idle when the daemon starts is not one, or
  every restart would announce old news.
- **`attributes-type` in the push payload is the Swift type's bare name** (`Deck`). Nothing checks
  that the two still agree, so renaming the type in `../Sources/DeckhandKit/LiveActivity.swift`
  silently breaks push-to-start until `push.py` moves with it. The `ContentState` field names are
  the wire format for the same reason — there is no Swift on the sending side.
- **The APNs host must match the entitlement.** The app signs `aps-environment: development`, so
  the daemon talks to `api.sandbox.push.apple.com`; a token minted for one host is refused by the
  other. A TestFlight or App Store build flips both.
- **A `Text` in a Dynamic Island region clips rather than grows.** The expanded island's second
  line of the session's own words was sliced through the middle: a `Text` draws into whatever
  height it is offered and clips the rest, and the island offers a stack one line's worth unless
  something in it asks for its own ideal height. `.fixedSize(horizontal: false, vertical: true)` is
  that ask. Two more: each region carries its own inset already, so padding the leading one puts
  the mark out of line with the words underneath it; and the top row cannot go below the camera's
  own height whatever is in it, so a bigger mark up there buys nothing and only makes the mark the
  loudest thing in the panel.

## Related context

- `../Sources/DeckhandKit/LiveActivity.swift` — the attributes and the content state
- `../daemon/CLAUDE.md` — the sending half, and `just sync-apns`
