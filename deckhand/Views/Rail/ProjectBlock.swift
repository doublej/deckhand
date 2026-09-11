import DeckhandKit
import SwiftUI

/// The folder a block of sessions is working in, and where that folder sits. Said once above
/// the block rather than on every row — the path is the thing they have in common, and
/// repeating it on each row is what would make the rail busier instead of clearer.
///
/// Two lines rather than one long path: the folder is the name you know the project by and it
/// has to survive at the front of the line, so the rest of the path is a quieter second line
/// truncated from the head. `~/dev/multi-stack` loses its middle before `deckhand` loses a
/// letter, which is the right way round.
///
/// **Where the machine is said.** Here, in front of the path, and nowhere else on the rail. A
/// project is on exactly one machine, so every session in the block is accounted for by saying
/// it once — the same argument that put the path here rather than on every row. It is blank on
/// a one-machine network, which is what keeps this rail looking as it always did.
struct ProjectHeader: View {
    let project: ProjectGroup
    /// What to call the machine, already resolved. Empty says nothing at all.
    var machine: String = ""

    private var second: String {
        machine.isEmpty ? project.parent : "\(machine) · \(project.parent)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(project.name.uppercased())
                .font(Typography.groupLabel)
                .tracking(0.6)
                .foregroundStyle(Palette.textSecondary)
            Text(second)
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.small)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            machine.isEmpty
                ? "\(project.name), in \(project.parent)"
                : "\(project.name), in \(project.parent) on \(machine)"
        )
    }
}
