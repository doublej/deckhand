import DeckhandKit
import PhotosUI
import SwiftUI

/// What was heard, held until you say so. Borrowed from utt's own review HUD: the transcript,
/// where it is going, and the two things you can do about it. utt offers ⏎ and ⎋ because a
/// panel that never takes focus makes the keys the real interface; a phone has no keys, so
/// the buttons are the whole affordance.
struct ReviewCard: View {
    let text: String
    let target: String
    let send: () -> Void
    let discard: () -> Void
    /// Small enough for a deck column, which has no room for a full card.
    var compact = false
    /// What is already pinned to these words, and the two ways to pin another. Left out where
    /// there is nobody to hand a picture to.
    var snaps: [Snap] = []
    var attach: ((Snap) -> Void)?
    var paste: (() -> Void)?
    var unattach: ((Snap) -> Void)?
    @State private var picked: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            attachments
            Text(text)
                .font(compact ? .system(size: 10) : Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(compact ? 4 : 6)
                .fixedSize(horizontal: false, vertical: true)
            if !snaps.isEmpty { pinned }
            HStack(spacing: Spacing.extraSmall) {
                Text("→ \(target)")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.extraSmall)
                Button("Discard", action: discard)
                    .buttonStyle(.plain)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
                Button("Send", action: send)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Palette.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? Spacing.extraSmall : Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Palette.tint.opacity(0.4), lineWidth: 1)
        )
    }

    /// The two ways a picture gets in, above the words they will go with. Both are always
    /// offered: the clipboard one was hidden whenever the clipboard held no image, which from
    /// the outside is a button that comes and goes for no visible reason.
    @ViewBuilder private var attachments: some View {
        if let attach {
            HStack(spacing: Spacing.small) {
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    Attach(word: "Photo", symbol: "photo.on.rectangle", compact: compact)
                }
                if let paste {
                    Button(action: paste) {
                        Attach(word: "Clipboard", symbol: "doc.on.clipboard", compact: compact)
                    }
                        .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .font(Typography.hint)
            .foregroundStyle(Palette.tint)
            // The picker hands back an item, not bytes; the bytes come over a moment later.
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    if let bytes = try? await item.loadTransferable(type: Data.self),
                       let snap = Snap(bytes: bytes, name: "photo.\(suffix(of: bytes))") {
                        attach(snap)
                    }
                    picked = nil
                }
            }
        }
    }

    /// What a photo library hands over can be anything; the Mac decides by suffix, so the
    /// suffix has to match the bytes rather than the guess.
    private func suffix(of bytes: Data) -> String {
        let head = bytes.prefix(4)
        if head.starts(with: [0x89, 0x50]) { return "png" }
        if head.starts(with: [0xFF, 0xD8]) { return "jpg" }
        return "heic"
    }

    /// What is pinned, small, with a way to take each one off again.
    private var pinned: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xxs) {
                ForEach(snaps) { snap in
                    Image(uiImage: snap.picture)
                        .resizable()
                        .scaledToFill()
                        .frame(width: compact ? 34 : 48, height: compact ? 34 : 48)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                        .overlay(alignment: .topTrailing) { cross(snap) }
                        .onTapGesture { unattach?(snap) }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: compact ? 34 : 48)
    }

    @ViewBuilder private func cross(_ snap: Snap) -> some View {
        if unattach != nil {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white, .black.opacity(0.5))
                .padding(2)
        }
    }
}

/// A glyph, and the word beside it where there is room for one. A deck column has room for two
/// glyphs and nothing else. Its own view because a picker's label is built outside the main
/// actor, which a method on the card cannot be.
private struct Attach: View {
    let word: String
    let symbol: String
    let compact: Bool

    var body: some View {
        if compact {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
        } else {
            Label(word, systemImage: symbol)
        }
    }
}
