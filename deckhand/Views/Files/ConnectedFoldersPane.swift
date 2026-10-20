import DeckhandKit
import SwiftUI

/// The folders connected to this session's project, and the way to connect one.
///
/// A session that renders into a temp folder names the folder and none of the frames, so the
/// files list never sees them. Connecting the folder here is what lets the Mac list and serve
/// what is inside it: the person's choice is the permission (`daemon/…/settings/folders.py`).
/// Per project, not per session — every session in this folder sees the same ones.
///
/// The folders this session wrote into come first, so a render folder is usually one tap; a
/// typed path is the fallback, and `~` means the Mac's home, not the phone's.
struct ConnectedFoldersPane: View {
    @Bindable var model: AppModel
    let session: Session
    @Binding var folders: ConnectedFolders
    @State private var typed = ""
    @State private var saving = false
    /// Said under the field when the Mac kept the list but dropped the typed path from it.
    @State private var refused = false
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Every picture, clip and note inside a connected folder is listed with this "
                     + "session's files, newest first. Every session in \(project) sees them.")
                    .font(Typography.subtitle)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.bottom, Spacing.small)
                ForEach(folders.folders, id: \.self) { folder in
                    row(folder, symbol: "minus.circle", says: "Disconnect") {
                        save(folders.folders.filter { $0 != folder })
                    }
                }
                if !folders.suggested.isEmpty {
                    heading("Where this session wrote")
                    ForEach(folders.suggested, id: \.self) { folder in
                        row(folder, symbol: "plus.circle", says: "Connect") {
                            save(folders.folders + [folder])
                        }
                    }
                }
                heading("A folder on the Mac")
                field
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.extraSmall)
            .padding(.bottom, Spacing.extraLarge)
        }
        .disabled(saving)
    }

    private var project: String { (session.cwd as NSString).lastPathComponent }

    private func heading(_ words: String) -> some View {
        Text(words)
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textSecondary)
            .padding(.top, Spacing.small)
    }

    /// One folder: its own name, where it is, and the one thing a press does to it.
    private func row(_ folder: String, symbol: String, says: String,
                     act: @escaping () -> Void) -> some View {
        HStack(spacing: Spacing.small) {
            FolderName(folder: folder)
            Spacer(minLength: Spacing.extraSmall)
            Button(action: act) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(says) \(folder)")
            .accessibilityIdentifier("folder-\(says.lowercased())")
        }
        .padding(.leading, Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            HStack(spacing: Spacing.small) {
                TextField("~/renders or /tmp/out", text: $typed)
                    .font(Typography.mono)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(connectTyped)
                    .padding(.horizontal, Spacing.small)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .fill(Palette.surfacePrimary)
                    )
                    .accessibilityIdentifier("folder-field")
                Button("Connect", action: connectTyped)
                    .font(Typography.primaryRow)
                    .foregroundStyle(accent)
                    .frame(minHeight: 44)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if refused {
                Text("The Mac connects a full path only, and never / or the home folder itself.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func connectTyped() {
        let path = typed.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }
        save(folders.folders + [path], typing: true)
    }

    /// The whole list goes up and the Mac's reading of it comes back; a typed path that did not
    /// make it into that reading was refused, and is left in the field to be fixed.
    private func save(_ list: [String], typing: Bool = false) {
        saving = true
        Task {
            if let kept = await model.saveFolders(list, for: session) {
                refused = typing && kept.folders.count <= folders.folders.count
                if !refused { typed = "" }
                folders = kept
            }
            saving = false
        }
    }
}

/// A folder glyph, its own name, and where it is under that — the way `AssetRow` says a file.
private struct FolderName: View {
    let folder: String
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: "folder")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text((folder as NSString).lastPathComponent)
                    .font(Typography.primaryRow)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(folder)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }
}
