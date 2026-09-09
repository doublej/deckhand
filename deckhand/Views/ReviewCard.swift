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
            Text(text)
                .font(compact ? .system(size: 10) : Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(compact ? 4 : 6)
                .fixedSize(horizontal: false, vertical: true)
            if !snaps.isEmpty { pinned }
            HStack(spacing: Spacing.extraSmall) {
                attachments
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

    /// The two ways a picture gets in: the clipboard, when it holds one, and the library. Both
    /// are icons — this row already carries the two decisions that matter.
    @ViewBuilder private var attachments: some View {
        if let attach {
            if paste != nil, UIPasteboard.general.hasImages {
                Button("Paste a picture", systemImage: "doc.on.clipboard") { paste?() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tint)
            }
            PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tint)
            }
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
