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

    @DynamicIslandExpandedContentBuilder
    private func expanded(_ state: Deck.ContentState) -> DynamicIslandExpandedContent<some View> {
        DynamicIslandExpandedRegion(.leading) {
            DotMark(DotGlyph.anchor, size: 26)
                .padding(.leading, Spacing.extraSmall)
        }
        DynamicIslandExpandedRegion(.trailing) {
            StateWord(state.waiting > 0 ? .idle : .busy)
                .padding(.trailing, Spacing.extraSmall)
        }
        DynamicIslandExpandedRegion(.bottom) {
            Waiting(state: state, compact: false)
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
            Waiting(state: state, compact: false)
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
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xxs) {
                Text(headline)
                    .font(Typography.railRowSelected)
                    .foregroundStyle(Palette.textPrimary)
                Text(state.moment, style: .relative)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
            if !state.line.isEmpty {
                Text(state.line)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(compact ? 1 : 2)
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
