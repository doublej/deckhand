import DeckhandKit
import SwiftUI

/// The rows this Mac will not keep, said under the editor holding them.
///
/// Both screens that edit the alias list write it on the way *off* the page, so `PUT /aliases`
/// answers with what it stored long after there is anything left to show that answer on. A row
/// the Mac declined is then simply absent the next time the list is opened, with nothing tying
/// the absence to the typing that caused it. Said here instead, while the row is still on screen
/// and still editable, it is a correction somebody can make.
///
/// One view rather than the same seven lines on two pages, because the two must not drift: a
/// warning that appears in Settings and not on the session's own screen would be worse than
/// neither, and the rule it draws is one rule.
struct NotKept: View {
    let rows: [Alias]

    var body: some View {
        ForEach(Replacements.dropped(rows)) { gone in
            Text(gone.why)
                .font(Typography.hint)
                // The same amber a cascade note wears. Not red: a row with nothing on its left
                // yet is somebody mid-sentence, not a fault, and the two share this space.
                .foregroundStyle(Palette.lcdYellow)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("This row will not be kept: \(gone.why)")
        }
    }
}
