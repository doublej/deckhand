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
            StateWord(state.waiting > 0 ? .idle : .busy)
        }
        DynamicIslandExpandedRegion(.bottom) {
            Waiting(state: state)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The card on the Lock Screen. utt's rail, because that is the surface this language uses
/// whenever the phone is not showing a page: warm ground, dot mark, four-letter pill.
private struct LockScreen: View {
    let state: Deck.ContentState
    let mac: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.extraSmall) {
            DotMark(DotGlyph.anchor, size: 34, hotCore: 0.3)
            Waiting(state: state)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                StateWord(state.waiting > 0 ? .idle : .busy)
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
private struct Waiting: View {
    let state: Deck.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(headline)
                    .font(Typography.railRowSelected)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(state.moment, style: .relative)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    // Never the one that gives way, the same call `Statusline` makes: a clipped
                    // age is a wrong number, where a clipped session name is only an ugly one.
                    .fixedSize()
            }
            if !state.line.isEmpty {
                Text(state.line)
                    .font(Typography.hint)
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

    /// "3 waiting · utt" rather than "3": the number alone makes you open the app to learn
    /// which one, which is the thing this is meant to save you.
    private var headline: String {
        switch state.waiting {
        case 0: "Nothing waiting"
        case 1: state.name
        default: "\(state.waiting) waiting · \(state.name)"
        }
    }
}
