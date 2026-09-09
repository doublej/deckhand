import DeckhandKit
import SwiftUI

/// A new name for a session, typed or said.
///
/// It was an `.alert` with a `TextField` in it, which is the right size for the job and is the one
/// shape that cannot hold this: an alert takes a field and buttons and nothing in between, so there
/// was nowhere to put the mark. A sheet is not a new arrangement either — the review card's editor
/// and a pin's remark are already this page, field focused on arrival with the keyboard up — so
/// this is the third of three rather than a shape invented for one field.
///
/// It seeds itself from the session's current name and keeps its own draft, which is why the page
/// no longer carries one: the only thing `SessionHead` has to do is open this.
struct Renaming: View {
    let session: Session
    let say: Dictation
    let rename: (String) -> Void
    @State private var wanted = ""
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    private var wantedName: String {
        wanted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.small) {
                field
                // The same sentence the alert carried. A name here is a command in a pane on the
                // Mac, and that is worth knowing before it runs rather than after.
                Text("Runs Claude Code's own /rename in its pane on the Mac.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.surfaceGround)
            .navigationTitle("Rename \(session.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(Palette.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rename") { hand() }
                        .tint(Palette.tint)
                        .fontWeight(.semibold)
                        // `/rename` with no argument opens a picker in the pane, which is a
                        // session left waiting on a keyboard nobody is at.
                        .disabled(wantedName.isEmpty)
                }
            }
        }
        // Two, the same pair a pin's remark offers, because a sheet with one detent cannot grow:
        // UIKit expands a sheet to its largest detent when a field in it takes focus, and with
        // `.medium` alone there is nowhere to expand to and the keyboard covers the lower half of
        // the sheet it is sitting in.
        .presentationDetents([.medium, .large])
        .task {
            wanted = session.name
            // A beat, or the field takes focus before it is on screen and the keyboard does not
            // come up at all — which leaves a page that looks editable and is not.
            try? await Task.sleep(for: .milliseconds(120))
            typing = true
        }
    }

    /// The field and the mark on one line, because a name is one short line and the two belong to
    /// each other: the mark fills this box and nothing else on the page.
    private var field: some View {
        HStack(spacing: Spacing.extraSmall) {
            TextField("Name", text: $wanted)
                .font(Typography.mono)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($typing)
                .submitLabel(.done)
                .onSubmit { hand() }
            SayInto(say: say, text: $wanted, compact: true)
        }
    }

    private func hand() {
        guard !wantedName.isEmpty else { return }
        rename(wantedName)
        dismiss()
    }
}
