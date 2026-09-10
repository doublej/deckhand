import ActivityKit
import DeckhandKit
import SwiftUI
import WidgetKit

/// The Lock Screen and Dynamic Island face of the Mac: how many sessions have stopped and are
/// waiting for you, and which one stopped last.
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
            LockScreen(state: context.state, mac: context.attributes.mac)
        } dynamicIsland: { context in
            island(context.state)
        }
    }

    private func island(_ state: Deck.ContentState) -> DynamicIsland {
        DynamicIsland {
            expanded(state)
        } compactLeading: {
            DotMark(DotGlyph.anchor, size: 16)
        } compactTrailing: {
            Text("\(state.waiting)")
                .font(Typography.eyebrow)
                .foregroundStyle(Palette.tint)
        } minimal: {
            DotMark(DotGlyph.anchor, size: 16)
        }
        .widgetURL(URL(string: "deckhand://waiting"))
        .keylineTint(Palette.tint)
    }

    /// The expanded island is three regions stacked around the camera, and the height they are
    /// given between them is not generous. Two things that were wrong here:
    ///
    /// The regions each carry their own inset already, so the extra eight points on the leading
    /// one put the mark eight points to the right of the words below it — every horizontal edge
    /// in the panel lined up except the one at the top left, which is the one you look at first.
    ///
    /// And the mark was 26. The top row cannot go below the camera's own height whatever is in
    /// it, so those points bought nothing and only made the mark the loudest thing in a panel
    /// that exists to show a sentence.
    @DynamicIslandExpandedContentBuilder
    private func expanded(_ state: Deck.ContentState) -> DynamicIslandExpandedContent<some View> {
        DynamicIslandExpandedRegion(.leading) {
            DotMark(DotGlyph.anchor, size: 22)
        }
        DynamicIslandExpandedRegion(.trailing) {
            StateWord(state.waiting > 0 ? .wait : .idle)
        }
        DynamicIslandExpandedRegion(.bottom) {
            Waiting(state: state)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The card on the Lock Screen. utt's rail, because that is the surface this language uses
/// whenever the phone is not showing a page: warm ground, dot mark, four-letter pill.
///
/// The word was `IDLE` when something was waiting and `BUSY` when nothing was — true of the
/// *sessions*, and the wrong sentence for a card about you: `RunState.idle` is grey, so the one
/// moment this card exists for was the one moment it had no colour on it at all. `wait` is the
/// state's own word for "waiting on a person", and it is yellow.
private struct LockScreen: View {
    let state: Deck.ContentState
    let mac: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.extraSmall) {
            DotMark(DotGlyph.anchor, size: 34, hotCore: 0.3)
            Waiting(state: state)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                StateWord(state.waiting > 0 ? .wait : .idle)
                Text(mac)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(Spacing.small)
        .activityBackgroundTint(Palette.lcdGround)
        .activitySystemActionForegroundColor(Palette.tint)
        .environment(\.colorScheme, .dark)
    }
}

/// The words, in both places they are needed. The count leads because it is the whole question
/// — "is anything waiting for me" — and the name and line answer the follow-up.
///
/// The sizes are the point of this view. It was built out of `railRowSelected` and `hint` — 13
/// and 11 — which are the sizes utt uses in a rail you are sitting a forearm away from. On a
/// Lock Screen a foot and a half away, read in the second before you decide whether to pick the
/// phone up, they are a grey smudge in the corner of a black card. `lead` and `prose` exist for
/// exactly this distance and were already in the design layer, unused here.
private struct Waiting: View {
    let state: Deck.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(headline)
                .font(Typography.pageTitle)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                // A long name shrinks rather than truncates: the name is how you tell which
                // session this is, so half of it is worth more than an ellipsis.
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                if state.waiting > 1 {
                    Text(state.name)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Text(state.moment, style: .relative)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    // Never the one that gives way, the same call `Statusline` makes: a clipped
                    // age is a wrong number, where a clipped session name is only an ugly one.
                    .fixedSize()
            }
            if !state.line.isEmpty {
                Text(state.line)
                    .font(Typography.prose)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    // Why the second line was sliced through the middle in the island. A `Text`
                    // draws whatever height it is offered and clips the rest; the island offers
                    // the stack one line's worth unless something in it asks for its own ideal
                    // height. This is that ask, and it is what makes the region grow instead.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The one line you read first, so it holds one fact and stays short enough to be set large.
    /// The name moves under it when there are several waiting — "3 waiting · umber-tuatara" at
    /// this size is a truncated name, which answers "which one" worse than not asking it to.
    private var headline: String {
        switch state.waiting {
        case 0: "Nothing waiting"
        case 1: state.name
        default: "\(state.waiting) waiting"
        }
    }
}
