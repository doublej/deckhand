import DeckhandKit
import SwiftUI

/// One word per row, a way to add one and a way to take one away — `Pairs` with one side.
struct HintWords: View {
    let label: String
    let hint: String
    @Binding var words: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label).font(Typography.primaryRow)
            Text(hint).font(Typography.hint).foregroundStyle(Palette.textTertiary)
            // By index, for `Pairs`' reason: keyed by content, a row loses the keyboard mid-word.
            ForEach(words.indices, id: \.self) { spot in
                HStack(spacing: Spacing.extraSmall) {
                    TextField("word", text: word(spot))
                    Button { words.remove(at: spot) } label: {
                        Image(systemName: "minus.circle").font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityLabel("Stop listening for this word")
                }
                .font(Typography.mono)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
            Button("Add a word") { words.append("") }
                .buttonStyle(.plain)
                .font(Typography.hint)
                .foregroundStyle(Palette.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Guarded, for `Pairs`' reason: a removal and the redraw after it are not one step.
    private func word(_ spot: Int) -> Binding<String> {
        Binding(get: { words.indices.contains(spot) ? words[spot] : "" },
                set: { typed in
                    guard words.indices.contains(spot) else { return }
                    words[spot] = typed
                })
    }
}
