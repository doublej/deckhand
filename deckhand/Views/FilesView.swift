import DeckhandKit
import SwiftUI

/// What the session actually made: the shot it took, the note it wrote, the clip it rendered.
///
/// The Mac reads these out of the same transcript everything else here comes from, and it will
/// only ever hand back a file that transcript named — so this is a window onto one session's
/// work, not a file browser pointed at somebody's Mac.
struct FilesView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var open: Asset?

    private var assets: [Asset] { model.assets[session.sessionId] ?? [] }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xxs) {
                if assets.isEmpty { empty }
                ForEach(assets) { asset in
                    Button { open = asset } label: { AssetRow(asset: asset) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("file-row")
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.medium)
            .padding(.bottom, Spacing.extraLarge)
        }
        .frame(maxHeight: .infinity)
        // Room at the end for the bar that floats over this.
        .contentMargins(.bottom, TalkMark.clearance, for: .scrollContent)
        // Asked for once, when the tab is opened. Nobody watches a file list change, and it
        // is a transcript scan on the Mac rather than a field on the session.
        .task { await model.loadFiles(for: session) }
        .sheet(item: $open) { AssetView(model: model, session: session, asset: $0) }
    }

    private var empty: some View {
        Text("Nothing this session made that a phone can open")
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textSecondary)
            .padding(.vertical, Spacing.small)
    }
}

/// One file, said the way the rest of the app says a session: a glyph, a name, a quiet line
/// of what it is underneath.
private struct AssetRow: View {
    let asset: Asset

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 30 * 0.28, style: .continuous)
                        .fill(Palette.tileIdle)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(Typography.primaryRow)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(caption)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: Spacing.extraSmall)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.extraSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
        .contentShape(.rect)
    }

    private var symbol: String {
        switch asset.sort {
        case .image: "photo"
        case .video: "film"
        case .text: "doc.text"
        }
    }

    /// Size and age say whether it is worth opening; the folder says which `report.md` it is.
    private var caption: String {
        let size = asset.size.formatted(.byteCount(style: .file))
        let ago = asset.changed.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        return "\(size) · \(ago) · \(asset.folder)"
    }
}
