import DeckhandKit
import SwiftUI

/// One turn on a screen of its own, so a sentence can be taken out of it.
///
/// Holding a turn in the transcript used to select the whole card and offer Copy, which is the
/// only thing `.textSelection(.enabled)` does on iOS. This is the surface that gives the press
/// somewhere useful to land: the turn, alone, in a `UITextView` — handles, loupe, Select All,
/// and the phone's own menu.
///
/// **The source, not the rendering.** The transcript draws a turn as the document it is, through
/// ``Markdown``; this draws the characters underneath it. Two reasons and both are about copying.
/// A fenced command is the thing most worth taking out of a turn and it only exists in the
/// source. And a selection lifted out of a rendered view arrives as words with the markdown
/// stripped — paste it back into a session and the fence, the list and the emphasis are gone.
/// Nothing is lost the other way: a dictated turn has no markdown in it and reads identically.
///
/// A sheet rather than a push. Every other full screen in this app is one (`RawView`,
/// `AssetView`, `SessionFilters`), the session's page hides its navigation bar and catches its
/// own swipe-back on an overlaid strip, and a pushed screen inside a `TabView(.page)` pane would
/// have to be arbitrated against the paging. A sheet takes none of that on.
struct TurnReader: View {
    let turn: Turn
    /// What the other speaker is called, so this says what the card you held said. See
    /// ``TurnCard/theirWord``.
    var theirWord = "CLAUDE"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                when
                SelectableText(text: turn.text, font: .systemFont(ofSize: 15))
                    .accessibilityIdentifier("turn-reader")
            }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.surfaceGround)
                .navigationTitle(turn.speaker(theirs: theirWord))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Teal rather than the page's accent: a sheet is its own surface and the
                        // talk mark is behind it. The same rule `RawView` and `AssetView` follow.
                        Button("Close") { dismiss() }.tint(Palette.tint)
                    }
                }
        }
    }

    /// When it was said, over the words it said.
    ///
    /// ``Turn/clock`` rather than a format of this screen's own, and that is the whole decision:
    /// it already answers the clock alone while the turn is from today and puts the day in front
    /// of it once it is not, which is exactly what a reader opened from a long scroll back needs.
    /// A second spelling here would be a second place that rule could drift, and the card and the
    /// reader disagreeing about the same turn is the confusing kind of wrong.
    ///
    /// Formatted to a `String` by the model, never a `Text(date, style:)` — a date-style `Text`
    /// is what `widgets/CLAUDE.md` records as drawing an empty container when it meets
    /// `.fixedSize()`, and the cheapest way never to meet that again is not to build one.
    @ViewBuilder private var when: some View {
        if !turn.clock.isEmpty {
            Text(turn.clock)
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .monospacedDigit()
                .accessibilityIdentifier("reader-time")
        }
    }
}
