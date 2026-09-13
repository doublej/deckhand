import DeckhandKit
import SwiftUI

/// Which machine's folders the picker is showing, as one row of chips above it.
///
/// **Derived from the projects, not from `/machines`.** The question this answers is "which of
/// these rows do I want", and a machine with nothing catalogued on it is not an answer to that —
/// it would be a chip that empties the list. The machine list is consulted for one thing only:
/// what to call each one, because `Ubuntu` is what a person says and `ubuntu` is what atlas
/// writes. A machine nothing knows a label for keeps its id, which is still a true answer.
///
/// The row draws nothing at all when every folder is on one machine. On a Mac with no fleet that
/// is the whole of the old behaviour, restored by absence rather than by a flag.
struct MachineChips: View {
    let projects: [Project]
    let machines: [Machine]
    /// The machine id being shown alone, or nil for all of them.
    @Binding var only: String?

    /// Every machine that actually has folders, most first — the order is stable across keystrokes
    /// because it is a property of the catalogue rather than of what has been typed.
    private var tallies: [(id: String, count: Int)] {
        var counted: [String: Int] = [:]
        for project in projects { counted[project.machine, default: 0] += 1 }
        return counted.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { (id: $0.key, count: $0.value) }
    }

    private func label(_ id: String) -> String {
        if id.isEmpty { return machines.first(where: \.isPrimary)?.title ?? "This Mac" }
        return machines.first { $0.id == id }?.title ?? id
    }

    var body: some View {
        let rows = tallies
        if rows.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.extraSmall) {
                    chip("All", count: projects.count, picked: only == nil) { only = nil }
                    ForEach(rows, id: \.id) { row in
                        chip(label(row.id), count: row.count, picked: only == row.id) {
                            // Tapping the one already showing goes back to all of them: the row
                            // is a filter, and a filter you cannot take off is a mode.
                            only = only == row.id ? nil : row.id
                        }
                    }
                }
                .padding(.horizontal, Spacing.medium)
            }
            .accessibilityIdentifier("machine-chips")
        }
    }

    private func chip(_ text: String, count: Int, picked: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                Text(text)
                Text("\(count)")
                    .foregroundStyle(picked ? Palette.surfaceGround : Palette.textTertiary)
            }
            .font(Typography.hint)
            .foregroundStyle(picked ? Palette.surfaceGround : Palette.textSecondary)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(picked ? Palette.tint : Palette.surfacePrimary)
            )
        }
        .buttonStyle(.plain)
    }
}
