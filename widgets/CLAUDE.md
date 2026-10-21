# The Lock Screen widget

## What this is

`DeckhandWidgets`, a Live Activity about **one session**: which one, what it asked or finished,
and how long ago. The **Mac** drives it over APNs — a backgrounded app has no promise of running
again — so the phone only hands over push tokens and the daemon does the sending
(`daemon/src/deckhand_daemon/push.py`).

It counted once — "5 waiting" — and a count is the one thing a person cannot act on: five
finished turns and five blocked questions drew the identical card. With one card per session the
number on the Lock Screen is drawn by iOS for free, and the card's own space goes to the sentence.

## Invariants

- **The card is push-to-start, never started by the app.** Asking for one at launch would park
  "Nothing waiting" on the Lock Screen for hours, which teaches you to ignore it. The app hands
  over a `start` token and the daemon raises the card.
- **A turn ending raises nothing, and the measurement is why.** It used to be the only trigger:
  294 cards in 28 hours, every one loud, 21 in the worst hour. A slip fired 9 times in the same
  window. Both drew the same card, so the surface taught you to ignore the 9. `asking` — a slip
  nobody has answered, or an agent calling for you in its own words — is the only kind that may
  raise a card or make a noise. `finished` may only ever *update* one already on screen, and it
  means a session cleared its whole list of asks, not one box ticked: single check-offs measured
  12.3/h, worse than the turns they replaced. A list going empty is 4/h across the Mac.
- **A confirm slip is answered from the card.** The daemon sends `slip`, `accept` and `decline` only for a
  slip whose page has `<button id="yes">` and `<button id="no">` (`artifacts.yes_no`), and then
  the line is that slip's question — a Yes under any other sentence answers something unread.
  `AnswerSlip` posts `{"answer": bool}` and redraws the card at once; answering one of several
  moves the card to the next with a quiet update, never one that raises a swiped-away card.
- **A confirm decision's card also carries `hash`** (the page's sha256), which `AnswerSlip` signs
  over; a decision moves the card silently, its one alert is a notification — `docs/artifacts.md`.
- **`Kind` decodes unknown as `finished`, the quiet one.** The Mac is upgraded by a git pull and
  the phone by a rebuild, so they are routinely a version apart. A daemon that learns a louder
  kind must never be able to make an older phone louder than it was built to be — the same
  argument `ManagerRole` is written for, one packet over.
- **One token per card, keyed by session.** The daemon kept one `activity` slot while the app
  posts a token per live card, so the last one won and every other card was unreachable — then
  each announce retried the dead token, got `410`, and started another. That is what four stacked
  cards on one Lock Screen looked like. Tokens live under `cards[<session id>]`, and `end` is a
  real push (`event: "end"`) rather than a card left to rot.
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
  black card. `lead` and `prose` are the tokens for this distance and were already there.
  Port the *values* from utt, never the *choice of token* — the distance is not the same.
  The pill was the half of that lesson nobody applied, and the widget grew a near-copy of
  `StateWord` to say so. It is `StateWord(_:size:)` now: one place a state is drawn, and the
  distance is the only thing that varies. A second view drawing a state is how a design language
  stops being one.
- **`Palette.textTertiary` is unreadable on `lcdGround`** — 3.69:1, where the scale asks 4.5 at
  this size. It is why the hostname and the state pill were invisible rather than merely dim in
  the card this replaced. `textSecondary` is 5.86:1. Nothing a person must read goes in tertiary
  on this ground, and the HIG asks specifically that a custom Lock Screen background be checked
  on an Always-On display, which takes luminance back out of whatever passes here.
- **The Lock Screen presentation has a height *range*, not a height** — 371 × 84–160 on a 393pt
  phone, and 84 is a floor the system pads up to. The old card measured 65pt, so a fifth of it
  was guaranteed nothing before any decision was made. Height has to be earned by content.
- **The state word is read off `kind`, and both words are now true of the session.** It was
  computed from the count — `IDLE` while something was waiting, which was true of the *session*
  and useless on a card about whether to pick the phone up, and grey, so the card's one moment of
  purpose was its one moment with no colour on it. Now that a card *is* a session the mapping is
  honest in both directions: `asking → wait`, yellow, the state's own word for waiting on a
  person; `finished → idle`, grey, and `RunState.idle`'s own doc — "alive and doing nothing" — is
  exactly what `Kind.finished` means. No word outside `RunState`'s vocabulary, ever.
- **`StateWord` is the only place a state is drawn**, at whatever distance. It takes a `size:`
  because this surface is read at arm's length; it does not take anything else, and a second view
  that draws a state is the thing to delete rather than the thing to extend.
- **Never `.fixedSize()` a date-style `Text` (`.relative`, `.timer`) in the Live Activity.** It
  blanks the *whole card*: the tinted rectangle draws, nothing inside it does, for `asking` and
  `finished` alike, and the extension logs a successful render — so it looks like a colour or a
  launch problem and is neither. A date-style `Text` takes every point of width it is offered;
  that is what the `fixedSize` was for. Put it last in its row instead, where it is the spacer.
  Found by bisecting the card one view at a time in the simulator, which is the way to find the
  next one: `Activity<Deck>.request` from the app under a launch flag, lock, screenshot.
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
