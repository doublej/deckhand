import DeckhandKit
import SwiftUI

/// What is wrong at one marked place, as a page of its own with the keyboard already up.
///
/// The same arrangement as the review card's editor, for the same reason: writing or correcting one
/// short remark on a phone only beats saying it out loud if the field is focused by the time the
/// page has finished arriving. Tapping a marker comes back here, so this is also where a remark
/// gets fixed and where a place gets taken off again.
///
/// Swiping it down keeps the pin and leaves it wordless, which is a real answer — a marker with no
/// words still reads as "look here", and `Pin.prose` says so in as many words.
///
/// The mark sits under the field for the same reason it sits under the review card's editor: what
/// is wrong with a screenshot is a sentence, you are holding the picture while you say it, and
/// typing it on a phone is the slow way to the same place.
struct PinWords: View {
    let place: Int
    let words: String
    /// What it takes to say the remark instead of typing it. Nil leaves the page as it was.
    var say: Dictation?
    let keep: (String) -> Void
    let drop: () -> Void
    @State private var written = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $written)
                .font(Typography.mono)
                .focused($typing)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surfaceGround)
                // Above the keyboard, which is where the thumb already is. A blank line between
                // two things said one after the other: one pin can hold two complaints.
                .safeAreaInset(edge: .bottom) {
                    if let say {
                        SayInto(say: say, text: $written, gap: "\n\n")
                            .padding(.horizontal, Spacing.medium)
                            .padding(.bottom, Spacing.extraSmall)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .navigationTitle("Place \(place)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Delete", role: .destructive, action: drop)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { keep(written) }
                            .tint(Palette.tint)
                            .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .task {
            written = words
            // A beat, or the field takes focus before it is on screen and the keyboard does not
            // come up at all — which leaves a page that looks editable and is not.
            try? await Task.sleep(for: .milliseconds(120))
            typing = true
        }
    }
}
