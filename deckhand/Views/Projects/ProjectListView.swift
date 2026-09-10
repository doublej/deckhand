import DeckhandKit
import SwiftUI

/// Every project on the Mac, and starting a session in one of them.
///
/// A page, not the rail: the rail is the sessions that exist, and this is the folders that could
/// have one. It is the only screen in the app that reaches past the running sessions into the
/// Mac's own idea of what work there is — and it holds no such idea itself. The list is whatever
/// the Mac keeps (atlas here), consumed as name, folder and a line of description.
///
/// Four hundred rows means the field at the top is the screen. Everything else is one row per
/// project, ordered by the Mac as most-recently-touched first, so the ten you actually work in
/// are the ten you see before typing anything.
struct ProjectListView: View {
    @Bindable var model: AppModel
    /// Handed the session once one exists, so the rail can push straight into it. The sheet does
    /// not navigate: it is presented over the rail, and the rail owns where you end up.
    let opened: (Session) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @FocusState private var searching: Bool

    private var shown: [Project] {
        model.picker.projects.filter { $0.matches(typed) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                field
                listing
            }
            .background(Palette.surfaceGround)
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Palette.tint)
                }
            }
        }
        .task { await model.loadProjects() }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            HStack(spacing: Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                TextField("Name, folder, framework or domain", text: $typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(Typography.primaryRow)
                    .focused($searching)
                    .submitLabel(.done)
                    .accessibilityIdentifier("project-search")
                if !typed.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { typed = "" }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Palette.surfacePrimary)
            )
            if let caveat = model.picker.caveat {
                Text(caveat)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, Spacing.xxs)
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
    }

    @ViewBuilder private var listing: some View {
        if model.picker.projects.isEmpty {
            empty
        } else {
            ScrollView {
                // Lazy on purpose: four hundred rows built eagerly is a visible pause every time
                // the field changes, and the filter changes it per keystroke.
                LazyVStack(spacing: Spacing.extraSmall) {
                    ForEach(shown) { row($0) }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.large)
            }
            .scrollDismissesKeyboard(.immediately)
            .overlay(alignment: .top) { if shown.isEmpty { nothing } }
        }
    }

    private var empty: some View {
        VStack(spacing: Spacing.small) {
            if model.picker.loading {
                ProgressView().tint(Palette.textTertiary)
                Text("Asking the Mac what there is…")
            } else {
                Text(model.picker.caveat ?? "The Mac has no project list")
            }
        }
        .font(Typography.primaryRow)
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nothing: some View {
        Text("Nothing matches “\(typed)”")
            .font(Typography.primaryRow)
            .foregroundStyle(Palette.textSecondary)
            .padding(.top, Spacing.large)
    }

    /// One project. Tapping it starts a session and hands it back — and while that is happening
    /// the row says so, because opening a terminal and waiting for Claude Code to report itself
    /// takes seconds and a row that does nothing visible reads as a tap that missed.
    private func row(_ project: Project) -> some View {
        Button { begin(project) } label: { face(project) }
            .buttonStyle(.plain)
            .disabled(model.picker.starting != nil)
            // The one row that cannot work says so rather than being hidden: hidden is a project
            // you go looking for, and greyed out with no word is a row you press twice.
            .opacity(project.trusted ? 1 : 0.55)
            .accessibilityIdentifier("project-row")
    }

    private func face(_ project: Project) -> some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            words(project)
            Spacer(minLength: Spacing.extraSmall)
            trailing(project)
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
    }

    /// What it is called, where it lives, what it is for, and the short true things about it.
    ///
    /// The description gets two lines of its own rather than sharing one with the folder. Those
    /// were a single truncated line — `multi-stack/deckhand · iOS remote for live Cl…` — where the
    /// half worth reading is the half that gets cut. A row is taller now, which is the trade: the
    /// list is searched far more often than it is scrolled.
    private func words(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name)
                .font(Typography.primaryRow)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text(project.relative)
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
            detail(project)
        }
    }

    /// The two lines that are only there when there is something in them, so a project atlas
    /// knows nothing about stays a two-line row instead of a two-line row with gaps under it.
    @ViewBuilder private func detail(_ project: Project) -> some View {
        if !project.description.isEmpty {
            Text(project.description)
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !project.facts.isEmpty {
            // Teal rather than a third shade of grey: a different kind of fact from the
            // description above it, and a fourth grey line is how four hundred rows become a wall.
            Text(project.facts.joined(separator: " · "))
                .font(Typography.hint)
                .foregroundStyle(Palette.tint.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder private func trailing(_ project: Project) -> some View {
        if model.picker.starting == project.id {
            ProgressView().tint(Palette.tint)
        } else if let note = project.note {
            Text(note)
                .font(Typography.hint)
                .foregroundStyle(project.trusted ? Palette.textTertiary : Palette.lcdYellow)
                .lineLimit(1)
        }
    }

    private func begin(_ project: Project) {
        searching = false
        Task {
            guard let session = await model.start(project) else { return }
            dismiss()
            opened(session)
        }
    }
}
