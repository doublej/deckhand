import ActivityKit
import AppIntents
import DeckhandKit
import SwiftUI
import WidgetKit

/// One session's face on the Lock Screen and in the Dynamic Island: which session, what it asked
/// or finished, and how long ago.
///
/// **One card is one session, not the Mac.** There was a count here — "5 waiting" — and a count
/// is the one thing a person cannot act on. With the count gone the leading side of every
/// presentation is free for the session's own identity, and `kind` is what colour carries:
/// `asking` is yellow because something wants you, `finished` is grey because nothing does.
///
/// A widget is drawn from a snapshot, not run, so nothing here animates on its own — the fixed
/// `DotMark` rather than the living one, and a relative date that iOS re-renders for us instead
/// of a clock we would have to keep.
@main
struct DeckhandWidgets: WidgetBundle {
    var body: some Widget { DeckWidget() }
}

struct DeckWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Deck.self) { context in
            LockScreen(deck: context.attributes, state: context.state)
        } dynamicIsland: { context in
            island(context.attributes, context.state)
        }
    }

    /// The compact pair says two things and no more: **which session** on the leading side and
    /// **what it wants** on the trailing, read across the camera as one sentence — `▚▚ — WAIT`.
    ///
    /// Both compact presentations used to draw the same 16pt anchor, which is a logo twice over:
    /// the person knows this is Deckhand, it is the only Live Activity the app raises, and at 16pt
    /// a 6×6 grid has 0.91pt lit dots and is a texture rather than a shape. The teal is not lost —
    /// `keylineTint` draws it around the whole island, which is where an identity belongs once the
    /// inside is needed for news.
    private func island(_ deck: Deck, _ state: Deck.ContentState) -> DynamicIsland {
        DynamicIsland {
            expanded(deck, state)
        } compactLeading: {
            Face(deck: deck, kind: state.kind, size: 20)
        } compactTrailing: {
            StateWord(state.kind.run, size: 12)
        } minimal: {
            Face(deck: deck, kind: state.kind, size: 20)
        }
        .widgetURL(deck.cardLink)
        .keylineTint(Palette.tint)
    }

    /// Three regions around the camera: who, what state and how stale, and then the sentence
    /// across the full width.
    ///
    /// Three measured things are why it looks like this. Each region carries its own inset, so
    /// nothing here is padded — `contentMargins(_:_:)` is the lever if the mark ever needs
    /// nudging into line with the words below it, never `.padding`. The top row cannot go below
    /// the camera's own height, so a mark bigger than 22 buys nothing and only makes the mark the
    /// loudest thing in a panel that exists to show a sentence. And a `Text` clips rather than
    /// grows unless it asks for its ideal height, which is what `Panel`'s `fixedSize` is for.
    @DynamicIslandExpandedContentBuilder
    private func expanded(_ deck: Deck, _ state: Deck.ContentState) -> DynamicIslandExpandedContent<some View> {
        DynamicIslandExpandedRegion(.leading) {
            Face(deck: deck, kind: state.kind, size: 22)
        }
        DynamicIslandExpandedRegion(.trailing) {
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                StateWord(state.kind.run, size: 12)
                Age(state.moment)
            }
        }
        // The sentence wins the height when the panel has to choose: it is the reason somebody
        // held a thumb on the island rather than glanced at it.
        DynamicIslandExpandedRegion(.bottom, priority: 1) {
            Panel(deck: deck, state: state)
        }
    }
}

/// The card on the Lock Screen: three rows, each spanning the whole width.
///
/// Apple gives this presentation a height *range* and not a height — 371 × 84–160 on a 393pt
/// phone — and 84 is a floor the system pads up to. The card this replaces measured 65pt with a
/// 34pt mark beside two short lines, so a fifth of it was guaranteed nothing before any decision
/// was made, and across the width a `Spacer` parked the state and the Mac's name at the right
/// edge in `Palette.textTertiary`, which measures 3.69:1 on this ground where the scale asks 4.5.
/// Here the floor case is ~103pt and the three-line case ~144pt: every point is content-driven.
///
/// **The sentence is the biggest thing.** This is read in the second before you decide whether to
/// pick the phone up. "Does it want me" is already answered by one yellow word; what it *said* is
/// the part that decides you, and `lead` is the token for the one line that has to survive being
/// read at arm's length.
private struct LockScreen: View {
    let deck: Deck
    let state: Deck.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            identity
            Text(hero)
                .font(Typography.lead)
                .foregroundStyle(Palette.textPrimary)
                // The button costs a line of what the session said, and that is the trade rather
                // than an accident: 16 + 22 + 8 + hero + 8 + 44 + 16 puts a three-line asking
                // card at ~166 against a 160 ceiling, where two lines is ~155. A finished card
                // has no button and keeps the third line. Arithmetic, not seen on a device.
                .lineLimit(showsStop ? 2 : 3)
                // A `Text` draws into whatever height it is offered and clips the rest. This is
                // the ask for its own ideal height, and the reason later lines survive.
                .fixedSize(horizontal: false, vertical: true)
            footnote
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .activityBackgroundTint(Palette.lcdGround)
        .activitySystemActionForegroundColor(Palette.tint)
        .environment(\.colorScheme, .dark)
        // The card and the island link to the same screen, which is what the HIG asks for. On the
        // card this is the *background* tap: the Stop button below takes its own hits first.
        .widgetURL(deck.cardLink)
    }

    /// Face, name, and the one word for what this session wants — left edge to right edge, so
    /// there is no gap in the middle for the eye to read as absence.
    ///
    /// The mark is 22 and drops `hotCore`, which `DotMark` documents as "0 below 44pt, where the
    /// gradient is invisible anyway" — 0.3 at 34pt was paying for a gradient nobody can see.
    private var identity: some View {
        HStack(spacing: Spacing.extraSmall) {
            Face(deck: deck, kind: state.kind, size: 22)
            Text(deck.name)
                .font(Typography.prose)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                // Not `minimumScaleFactor` at this size: 0.7 of 14 is 9.8pt, under the floor for
                // this distance. These names are hyphenated pairs, so keeping both ends —
                // `umber…tuatara` — says which session better than keeping one end whole.
                .truncationMode(.middle)
            Spacer(minLength: Spacing.small)
            StateWord(state.kind.run, size: 12)
        }
    }

    /// How stale, and which Mac. `Palette.textSecondary`, never `textTertiary`: 5.86:1 against
    /// 3.69:1 on this ground, and the HIG asks specifically that a custom Lock Screen background
    /// be checked on an Always-On display, which takes luminance back out of whatever passes here.
    private var footnote: some View {
        HStack(spacing: Spacing.xxs) {
            Age(state.moment)
            Text("·")
            Text(deck.mac)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Spacing.small)
            if showsStop { stop }
        }
        .font(Typography.hint)
        .foregroundStyle(Palette.textSecondary)
    }

    /// The one thing a card may do to a session, below the sentence rather than beside the name:
    /// the card's job is to be read, and a control beside the identity would be the first thing
    /// the eye lands on.
    ///
    /// **Only on `asking`.** A `finished` card is a session that has cleared your list — there is
    /// nothing running for Escape to take away, and because a card is *updated* rather than
    /// re-raised, a finished card can still be on screen after the session has been given
    /// something new. A button that acts on state the card no longer describes is worse than no
    /// button. This is the sentence to change if that reading is wrong; nothing else moves.
    ///
    /// Not mono and not tracked, which is deliberate. `WAIT` two rows up is the state vocabulary,
    /// and the design layer's rule is that a state is never a thing you press — so the one thing
    /// you actually can press must not borrow the state's voice. `Radius.small` and not a capsule,
    /// for the same reason a filled control inside a card is: corners get tighter inwards.
    private var stop: some View {
        Button(intent: StopRun(session: deck.session)) {
            Label("Stop", systemImage: Control.cancel.symbol)
                .font(Typography.primaryRow)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, Spacing.extraSmall)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Palette.tileIdle)
                )
                // The pill draws at ~31pt; Apple's floor for anything you tap is 44. The extra
                // points are hit area and nothing else, which is why they are inside the label
                // and why `contentShape` is what makes them count.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Whether this card has anything to stop. See `stop`.
    private var showsStop: Bool { state.kind == .asking }

    /// `line` is documented as never empty, and this is the one place that would be a blank card
    /// rather than a wrong one — the payload is JSON composed in Python, so the guard stays.
    private var hero: String { state.line.isEmpty ? deck.name : state.line }
}

/// The expanded panel's bottom region: which session, and what it said.
///
/// The same two things the Lock Screen's first two rows say, in the same voice, because they are
/// the same card at two distances. The island only splits the rest differently: the face is its
/// own region here and the state and the age are a column of their own.
private struct Panel: View {
    let deck: Deck
    let state: Deck.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(deck.name)
                .font(Typography.prose)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(state.line)
                .font(Typography.lead)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                // The same ask as the card's, and the reason the second line was sliced through
                // the middle before it was here.
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Which session, as the face it already wears on the rail.
///
/// `DotGlyph.forName` is FNV-1a over the name and `Deck.name` is documented byte-identical to the
/// rail's, so the shape here and the shape in the list are the same shape. 20 is not a new size:
/// `GlyphTile(size: 32)` draws its mark at 32 × 0.62 = 19.8, which is where this face is learned.
///
/// The tint is the state's rather than Deckhand's teal, because colour is what actually resolves
/// at this size: a 6×6 grid at 20pt has 1.13pt lit dots and the shape may well be marginal, where
/// yellow and grey are told apart across a room. If the seven shapes prove untellable on
/// hardware, this view is where to change it and nothing else moves.
private struct Face: View {
    let deck: Deck
    let kind: Deck.Kind
    let size: CGFloat

    var body: some View {
        DotMark(DotGlyph.forName(deck.name), size: size, tint: kind.run.tint)
            // `DotMark` hides itself from accessibility, so a label laid on top of it is never
            // read — the element has to be made here for the name to reach VoiceOver at all. It
            // is the only thing saying which session in the two compact presentations.
            .accessibilityElement()
            .accessibilityLabel(deck.name)
    }
}

/// How stale this is. It ticks on its own, so the card proves it is alive without costing the
/// daemon a push — and it never gives way, the same call `Statusline` makes: a clipped age is a
/// wrong number, where a clipped name is only an ugly one. Not in the compact trailing region,
/// where it would be the best free fact on the surface: `.relative` renders the two largest
/// units, so "2 hr, 15 min" is eleven characters into 52.33 points.
private struct Age: View {
    private let moment: Date

    init(_ moment: Date) { self.moment = moment }

    var body: some View {
        Text(moment, style: .relative)
            .font(Typography.hint)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .fixedSize()
    }
}

extension Deck.Kind {
    /// What a card's reason for existing looks like in the design layer's own vocabulary.
    ///
    /// `asking` is the state that wants something and `RunState.wait` is the word and the colour
    /// for waiting on a person — yellow, which is the one moment this card has a purpose and so
    /// the one moment it must not be grey. `finished` is `idle`, "alive and doing nothing": true
    /// of a session that has cleared your list, and quiet, which is the whole of the policy.
    var run: RunState {
        switch self {
        case .asking: .wait
        case .finished: .idle
        }
    }
}
