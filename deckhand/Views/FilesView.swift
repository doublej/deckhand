import DeckhandKit
import SwiftUI

/// What the session actually made: the shot it took, the note it wrote, the clip it rendered.
///
/// The Mac reads these out of the same transcript everything else here comes from, and it will
/// only ever hand back a file that transcript named — so this is a window onto one session's
/// work, not a file browser pointed at somebody's Mac.
///
/// One row of suffixes across the top says what the list below it is, and the list is flat.
/// It was sections by suffix running down the list, each under its own 9pt uppercase header,
/// and JJ called that unusable on a phone: the header was too small to read at arm's length and
/// too small to hit, and a list mostly made of headers is one you scroll past rather than read.
/// The row above says which part of the list you are looking at, so nothing inside it has to.
///
/// The chosen one is a filled capsule, which the **no badges** rule bans — for a *state*. What
/// that rule is against is a capsule that only reports, sitting beside things you can press and
/// claiming to be one of them. This is the thing you press, so it ought to look pressable, and
/// `StateWord` is the wrong thing to reach for here: a selector reports nothing.
struct FilesView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var open: Asset?
    /// The one suffix the list is showing, or nil for all of them. The tab opens on all of them
    /// every time — which suffix you picked last is not something a file list should decide for
    /// you on arrival. View state and not the model's, for the same reason.
    @State private var only: String?

    /// The minimum a finger can be asked to hit, and the whole point of this rework. The one raw
    /// number in the file, because no spacing token means "a finger" and rounding it to the
    /// nearest step either lies about the minimum or overshoots it.
    private static let target: CGFloat = 44

    private var assets: [Asset] { model.assets[session.sessionId] ?? [] }
    private var groups: [Asset.Group] { Asset.grouped(assets) }

    /// What the list draws, newest first either way: the Mac sorts these and `Asset.grouped`
    /// leaves the order inside a group exactly as it arrived. A suffix that is no longer there
    /// falls back to all of them, which is what happens when the session's last PNG is renamed
    /// away while PNG is the one you are looking at.
    private var shown: [Asset] {
        guard let only, let group = groups.first(where: { $0.suffix == only }) else { return assets }
        return group.assets
    }

    var body: some View {
        VStack(spacing: 0) {
            // Above the scroll view rather than inside it, so it is still there after you have
            // scrolled past eleven screenshots looking for the one note.
            if groups.count > 1 { selector }
            list
        }
        .frame(maxHeight: .infinity)
        // Asked for once, when the tab is opened. Nobody watches a file list change, and it
        // is a transcript scan on the Mac rather than a field on the session.
        .task { await model.loadFiles(for: session) }
        .sheet(item: $open) { AssetView(model: model, session: session, asset: $0) }
    }

    /// Flat, with no header anywhere in it. Every row is the same object, and what they have in
    /// common is written once, above.
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xxs) {
                if shown.isEmpty { empty }
                ForEach(shown) { asset in
                    Button { open = asset } label: { AssetRow(asset: asset) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("file-row")
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.extraSmall)
            .padding(.bottom, Spacing.extraLarge)
        }
        // Room at the end for the bar that floats over this.
        .contentMargins(.bottom, TalkMark.clearance, for: .scrollContent)
    }

    /// All of them first, then one choice per suffix the session actually wrote, the biggest
    /// first — `Asset.grouped`'s order, which is the order it already sorts in.
    ///
    /// It scrolls sideways and never wraps: a second line would shove every row under it down
    /// the moment a session writes a new kind of file, and shrinking the type to fit is what was
    /// wrong with the thing this replaces. A session whose files are all one kind gets no row at
    /// all — one choice is not a choice, and the row would be furniture.
    private var selector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xxs) {
                choice(nil, count: assets.count)
                ForEach(groups) { choice($0.suffix, count: $0.assets.count) }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.extraSmall)
        }
        .scrollIndicators(.hidden)
    }

    /// One choice: what it is, how many files it has, and a fill that says it is the current one.
    /// `nil` is all of them, written as a word rather than uppercased like the suffixes, because
    /// it is not one. One line is stated rather than assumed: `NO SUFFIX` is the only label here
    /// with a space in it, and it is the one that would wrap inside its capsule.
    private func choice(_ suffix: String?, count: Int) -> some View {
        let chosen = only == suffix
        return Button { only = suffix } label: {
            HStack(spacing: Spacing.extraSmall) {
                Text(suffix ?? "All")
                Text(count.formatted())
                    .foregroundStyle(chosen ? Color.white.opacity(0.75) : Palette.textTertiary)
            }
            .font(Typography.primaryRow)
            .foregroundStyle(chosen ? Color.white : Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: Self.target)
            .background(Capsule().fill(chosen ? Palette.tint : Palette.tileIdle))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("file-filter")
        .accessibilityLabel("\(suffix ?? "All"), \(count) files")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
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
