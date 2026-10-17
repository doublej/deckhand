import DeckhandKit
import SwiftUI

/// What one marked place says, beside the marker rather than on a page of its own.
///
/// This replaced a full-height sheet with a `TextEditor` and the keyboard up. The sheet was wrong
/// twice over: it covered the picture the remark is *about*, so you could not see the thing you
/// were describing while describing it, and it led with a field — which invited typing, when the
/// entire reason for pointing at a picture on a phone is to say the sentence out loud.
///
/// So the controls come to the marker. Choosing a place shows this next to it, the picture stays
/// where it was, and there is one thing to press. A place with nothing said yet offers `Say`; one
/// that already has words shows them and offers `Replace`, because a remark dictated twice is a
/// remark corrected, never two remarks run together — that is what `Underneath.words` is for, and
/// it is deliberately not used here.
///
/// There is no field. Nothing on this is typed into, and that is the point of it.
struct PinCallout: View {
    /// The id on the marker, letter and number both, which is also the id in the list the session
    /// reads. A string rather than a number because the letter is what says *which picture* — see
    /// `Pin.lettering(round:)`.
    let place: String
    let words: String
    /// What it takes to say the remark. Nil means this picture was opened somewhere with no
    /// recorder to lend, in which case the only honest controls are the number and Delete.
    var say: Dictation?
    /// New words for this place, in place of whatever it held.
    let heard: (String) async -> Void
    let drop: () -> Void

    /// Narrow on purpose. It sits over a picture and points at one spot on it, so it has to leave
    /// the picture visible; past this width it stops being a callout and becomes a panel.
    static let wide: CGFloat = 248

    private var said: String { words.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            remark
            controls
        }
        .padding(Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfacePrimary)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Place \(place)")
    }

    /// The number and what was said at it. Three lines, because a remark is a sentence and the
    /// fourth line is where a callout starts covering the picture it is about; the whole of it is
    /// still in the numbered list the session reads.
    private var remark: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
            Text(place)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.lcdGround)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Palette.tint))
            Text(said.isEmpty ? "Nothing said here yet" : said)
                .font(Typography.hint)
                .foregroundStyle(said.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Say or Replace, and the way to take the place off again. Delete is a word rather than a
    /// glyph and sits at the far end from the microphone: distance is what this app uses in place
    /// of a confirmation, the same answer `ReviewActions` gives to pressing the wrong thing.
    private var controls: some View {
        HStack(spacing: Spacing.extraSmall) {
            if let say {
                SayInto(say: say, label: said.isEmpty ? "Say" : "Replace", heard: heard)
            }
            Spacer(minLength: 0)
            Button("Delete", role: .destructive, action: drop)
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Spacing.extraSmall)
                .frame(minHeight: 44)
                .contentShape(.rect)
                .accessibilityIdentifier("pin-delete")
                .accessibilityLabel("Delete place \(place)")
        }
    }
}
