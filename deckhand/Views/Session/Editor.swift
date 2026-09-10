import DeckhandKit
import SwiftUI

/// The whole screen above the keyboard, as one field holding what was heard.
///
/// A phone dictates better than it types, but not perfectly: utt hears a name wrong, or the
/// sentence ran on, and the fix is two words. The card is far too small a place to make that
/// fix — so the edit is a page of its own, opened focused with the keyboard already up, which
/// is the only arrangement where correcting one word is faster than saying the whole thing again.
///
/// And the mark is here too, under the field, because this is the page you reach *because* a word
/// came back wrong: half of what happens here is a correction typed, and the other half is another
/// sentence that is easier said. It lands under what is in the box and never over it.
struct Editor: View {
    let words: String
    let target: String
    var say: Dictation?
    let keep: (String) -> Void
    @State private var edited: String = ""
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $edited)
                .font(Typography.mono)
                .focused($typing)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surfaceGround)
                // Above the keyboard rather than in the toolbar: a 44pt capsule does not fit in a
                // navigation bar beside Cancel and Done, and this is the one control here your
                // thumb is already resting on. A blank line between the halves, because two things
                // said one after the other are two paragraphs and not one long sentence.
                .safeAreaInset(edge: .bottom) {
                    if let say {
                        SayInto(say: say, text: $edited, gap: "\n\n")
                            .padding(.horizontal, Spacing.medium)
                            .padding(.bottom, Spacing.extraSmall)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .navigationTitle("→ \(target)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }.tint(Palette.textSecondary)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { keep(edited) }.tint(Palette.tint).fontWeight(.semibold)
                    }
                }
        }
        .task {
            edited = words
            // A beat, or the field takes focus before it is on screen and the keyboard does
            // not come up at all — which leaves a page that looks editable and is not.
            try? await Task.sleep(for: .milliseconds(120))
            typing = true
        }
    }
}
