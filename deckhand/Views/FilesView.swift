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
    /// Which part of the tab is showing. It opens on all of them every time — what you picked
    /// last is not something a file list should decide for you on arrival. View state and not
    /// the model's, for the same reason.
    @State private var only: Showing = .all
    /// The standing instructions a session here runs under. Empty until the Mac answers, and
    /// empty forever for a folder with no CLAUDE.md anywhere above or below it — in which case
    /// there is no choice to offer and none is drawn.
    @State private var context = ContextDocs()

    /// The three things this tab can be. A suffix narrows the list; the tree is not a list at
    /// all, which is why this is an enum rather than one more optional string.
    private enum Showing: Hashable { case all, context, suffix(String) }
    /// This is a tab inside the session's page, not a surface of its own, so it goes orange with
    /// the rest of the page while the mark at the foot of it is open.
    @Environment(\.accent) private var accent

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
        guard case .suffix(let suffix) = only,
              let group = groups.first(where: { $0.suffix == suffix }) else { return assets }
        return group.assets
    }

    var body: some View {
        VStack(spacing: 0) {
            // Above the scroll view rather than inside it, so it is still there after you have
            // scrolled past eleven screenshots looking for the one note.
            if groups.count > 1 || !context.documents.isEmpty { selector }
            if only == .context {
                ContextTree(context: context) { open = $0 }
            } else {
                list
            }
        }
        .frame(maxHeight: .infinity)
        // Asked for once, when the tab is opened. Nobody watches either of these change, and
        // both are a walk on the Mac rather than a field on the session.
        .task {
            await model.loadFiles(for: session)
            context = await model.context(for: session)
        }
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
        .fadingEdges()
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
                choice(.all, "All", count: assets.count)
                // Second, not last: what a session was told is worth more than what it happened
                // to open, and a row you have to scroll sideways to find is a row nobody finds.
                if !context.documents.isEmpty {
                    choice(.context, "CLAUDE", count: context.documents.count)
                }
                ForEach(groups) { choice(.suffix($0.suffix), $0.suffix, count: $0.assets.count) }
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
    private func choice(_ what: Showing, _ words: String, count: Int) -> some View {
        let chosen = only == what
        return Button { only = what } label: {
            HStack(spacing: Spacing.extraSmall) {
                Text(words)
                Text(count.formatted())
                    .foregroundStyle(chosen ? Color.white.opacity(0.75) : Palette.textTertiary)
            }
            .font(Typography.primaryRow)
            .foregroundStyle(chosen ? Color.white : Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: Self.target)
            .background(Capsule().fill(chosen ? accent : Palette.tileIdle))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("file-filter")
        .accessibilityLabel("\(words), \(count) files")
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
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(accent)
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
        case .audio: "waveform"
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
