import DeckhandKit
import SwiftUI

/// The things said to the manager most, one tap each, above the field while it is empty.
///
/// The manager is meant to be where the whole network is driven from, and the first move of
/// almost every visit is one of these three questions. Typing or holding to say them every time
/// is the cost that sends a person back to scrolling the rail instead.
struct ManagerStarters: View {
    let ask: (String) -> Void

    private static let lines = [
        ("What needs me?", "What needs me right now? Open asks, waiting slips, anything stuck."),
        ("What's running?", "What is every session doing right now, on every machine?"),
        ("What finished?", "Which sessions finished something since I last asked, and what?")
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.extraSmall) {
                ForEach(Self.lines, id: \.0) { label, words in
                    Button(label) { ask(words) }
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.extraSmall)
                        .padding(.vertical, Spacing.xxs)
                        .background(Capsule().fill(Palette.textPrimary.opacity(0.06)))
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("manager-starters")
    }
}
