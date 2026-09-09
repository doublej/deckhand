import DeckhandKit
import SwiftUI

/// A replacement list: rows of two, a way to add one and a way to take one away.
///
/// Its own control for one reason — a pair does not fit in a text box, which is the whole reason
/// the `pairs` kind exists. Full width rather than in a row's control slot: two fields and an
/// arrow squeezed into the right-hand third of a row is not something anyone can type into.
struct Pairs: View {
    let label: String
    let hint: String
    @Binding var rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label).font(Typography.primaryRow)
            if !hint.isEmpty {
                Text(hint).font(Typography.hint).foregroundStyle(Palette.textTertiary)
            }
            // By index, because the rows are what is being edited: keyed by content, a row would
            // change identity on every letter typed into it and lose the keyboard mid-word.
            ForEach(rows.indices, id: \.self) { spot in
                row(spot)
            }
            Button("Add a replacement") { rows.append(["", ""]) }
                .buttonStyle(.plain)
                .font(Typography.hint)
                .foregroundStyle(Palette.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ spot: Int) -> some View {
        HStack(spacing: Spacing.extraSmall) {
            TextField("from", text: side(spot, 0))
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
            TextField("to", text: side(spot, 1))
            Button { rows.remove(at: spot) } label: {
                Image(systemName: "minus.circle").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textTertiary)
            .accessibilityLabel("Remove this replacement")
        }
        .font(Typography.mono)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    /// Guarded on both sides: a removal and the redraw that follows it are not one step, and an
    /// index into a row that has just gone is the crash this kind of editor is known for.
    private func side(_ spot: Int, _ half: Int) -> Binding<String> {
        Binding(get: { rows.indices.contains(spot) ? rows[spot][half] : "" },
                set: { typed in
                    guard rows.indices.contains(spot) else { return }
                    rows[spot][half] = typed
                })
    }
}
