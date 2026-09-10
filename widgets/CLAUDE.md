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
- **This is read at arm's length, so it does not take the rail's sizes.** The design layer is
  utt's, and utt is a Mac app you sit a forearm away from: `railRowSelected` is 13 and `hint` is
  11. Both surfaces here were built out of those two and read as a grey smudge in the corner of a
  black card. `pageTitle` and `prose` are the tokens for this distance and were already there.
  Port the *values* from utt, never the *choice of token* — the distance is not the same.
- **The state word says what is true of you, not of the sessions.** It was `IDLE` when something
  was waiting, which is true of the session and useless on a card about whether to pick the phone
  up — and `RunState.idle` is grey, so the card's one moment of purpose was its one moment with
  no colour on it. `wait` is yellow and is the state's own word for waiting on a person.
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
