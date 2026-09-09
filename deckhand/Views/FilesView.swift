import DeckhandKit
import SwiftUI

/// What the session actually made: the shot it took, the note it wrote, the clip it rendered.
///
/// The Mac reads these out of the same transcript everything else here comes from, and it will
/// only ever hand back a file that transcript named — so this is a window onto one session's
/// work, not a file browser pointed at somebody's Mac.
///
/// In sections by suffix, the biggest first. A session that took eleven screenshots and wrote one
/// note was a flat list of twelve rows where the note was indistinguishable from the noise, and
/// the suffix is the one thing that says which part of such a list you are looking at.
struct FilesView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var open: Asset?
    /// Which sections are folded shut. Nothing is in here to begin with, so the tab opens as the
    /// whole list every time — folding is for pushing a big section out of the way, not something
    /// the tab should do to you on arrival. View state and not the model's: folding PNG away is
    /// something you do while reading this list, not something you decide about the session.
    @State private var folded: Set<String> = []

    private var groups: [Asset.Group] { Asset.grouped(model.assets[session.sessionId] ?? []) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xxs) {
                if groups.isEmpty { empty }
                ForEach(groups) { section($0) }
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

    /// One suffix and the files under it. A header `Button` rather than a `DisclosureGroup`: the
    /// rows are already buttons carrying their own card and their own hit area, and a
    /// DisclosureGroup brings a chevron, an inset and a row background of its own that all three
    /// fight. The header is the same uppercase label the session rail groups with.
    @ViewBuilder private func section(_ group: Asset.Group) -> some View {
        Button { fold(group.suffix) } label: { header(group) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("file-group")
        if !folded.contains(group.suffix) {
            ForEach(group.assets) { asset in
                Button { open = asset } label: { AssetRow(asset: asset) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("file-row")
            }
        }
    }

    /// The suffix, and how many files are under it. The count is there for the folded state: a
    /// section shut with no number on it gives you nothing to decide whether to open it again.
    private func header(_ group: Asset.Group) -> some View {
        HStack(spacing: Spacing.extraSmall) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .rotationEffect(.degrees(folded.contains(group.suffix) ? -90 : 0))
                .accessibilityHidden(true)
            Text(group.suffix)
                .foregroundStyle(Palette.textSecondary)
            Text(group.assets.count.formatted())
            Spacer(minLength: 0)
        }
        .font(Typography.groupLabel)
        .tracking(0.6)
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, Spacing.small)
        .padding(.top, Spacing.extraSmall)
        .contentShape(.rect)
    }

    private func fold(_ suffix: String) {
        if folded.contains(suffix) { folded.remove(suffix) } else { folded.insert(suffix) }
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
