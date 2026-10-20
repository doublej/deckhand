import DeckhandKit
import SwiftUI

/// The files tab arranged as folders: the way back up, the folders here, then the files here.
///
/// It arranges whatever the chips above already narrowed the list to (`FileTree` says why), so a
/// suffix chosen while drilled in filters this folder's subtree, and the counts on the folders
/// say how many of *those* are inside.
struct FolderBrowse: View {
    let files: [Asset]
    /// Where the person has drilled to; nil is the top. Held by `FilesView` so a chip tap keeps it.
    @Binding var location: String?
    let open: (Asset) -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        let tree = FileTree(files, at: location)
        LazyVStack(alignment: .leading, spacing: Spacing.xxs) {
            if tree.trail.count > 1 { trail(tree) }
            ForEach(tree.folders) { folder in
                Button { location = folder.path } label: { row(folder) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("folder-row")
            }
            ForEach(tree.files) { asset in
                Button { open(asset) } label: { AssetRow(asset: asset) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("file-row")
            }
        }
    }

    /// Every folder from the top down to here; each one a tap back to it.
    private func trail(_ tree: FileTree) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.extraSmall) {
                ForEach(tree.trail) { crumb in
                    if crumb.path != tree.root {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Button(crumb.name) { location = crumb.path == tree.root ? nil : crumb.path }
                        .font(Typography.primaryRow)
                        .foregroundStyle(crumb.path == tree.here ? Palette.textPrimary : accent)
                        .disabled(crumb.path == tree.here)
                        .frame(minHeight: 44)
                }
            }
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.trailing)
    }

    /// The same 30pt tile `AssetRow` draws its kind in.
    private var glyph: some View {
        Image(systemName: "folder")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(accent)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 30 * 0.28, style: .continuous).fill(Palette.tileIdle))
    }

    /// A folder, drawn like a file row so the list reads as one list: a glyph, the name, how many.
    private func row(_ folder: FileTree.Folder) -> some View {
        HStack(spacing: Spacing.small) {
            glyph
            Text(folder.name)
                .font(Typography.primaryRow)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: Spacing.extraSmall)
            Text(folder.count.formatted())
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.extraSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.surfacePrimary))
        .contentShape(.rect)
    }
}
