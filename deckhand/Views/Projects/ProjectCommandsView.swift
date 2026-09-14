import DeckhandKit
import SwiftUI

/// Running a project's own `just` recipes from the phone — a deploy, a server, anything else its
/// justfile knows how to do, without a session or a terminal in the way. The same recipes atlas's
/// own pickers already turn into buttons; this is the same idea, one folder at a time.
///
/// Its own loading rather than an `AppModel` extension, the `OrdersView` reason: `deckhand/` sits
/// on its 16-file gate, this is one sheet's own state, and nothing else in the app wants it.
///
/// A recipe's panel polls its status every couple of seconds for as long as it stays open —
/// running or not, so a log that is still growing keeps growing on screen — and stops the moment
/// it is collapsed or the sheet closes, because `.task(id:)` cancels with the view that opened it.
struct ProjectCommandsView: View {
    @Bindable var model: AppModel
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var listing = RecipeListing()
    @State private var loading = true
    /// The recipe whose panel is open. Nil collapses every panel and stops the poll.
    @State private var watching: Recipe?
    @State private var statuses: [String: CommandStatus] = [:]
    @State private var acting = false

    var body: some View {
        NavigationStack {
            content
                .background(Palette.surfaceGround)
                .navigationTitle(project.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }.tint(Palette.tint)
                    }
                }
        }
        .task { await load() }
        .task(id: watching) { await poll() }
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView().tint(Palette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !listing.hasJustfile {
            Text("No justfile in this folder.")
                .font(Typography.primaryRow)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    ForEach(grouped, id: \.0) { group, recipes in
                        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                            if !group.isEmpty {
                                Text(group.uppercased())
                                    .font(Typography.groupLabel)
                                    .foregroundStyle(Palette.textTertiary)
                                    .padding(.horizontal, Spacing.xxs)
                            }
                            VStack(spacing: Spacing.extraSmall) {
                                ForEach(recipes) { row($0) }
                            }
                        }
                    }
                }
                .padding(Spacing.medium)
            }
        }
    }

    /// Recipes in the order `just` gave them, folded into their groups without losing that order —
    /// the same reading `just --list` itself draws, ungrouped ones landing wherever they fall.
    private var grouped: [(String, [Recipe])] {
        var order: [String] = []
        var byGroup: [String: [Recipe]] = [:]
        for recipe in listing.recipes {
            if byGroup[recipe.group] == nil { order.append(recipe.group) }
            byGroup[recipe.group, default: []].append(recipe)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    private func row(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Button {
                watching = (watching == recipe) ? nil : recipe
            } label: { face(recipe, status: statuses[recipe.name]) }
                .buttonStyle(.plain)
                .disabled(recipe.needsArgs)
            if watching == recipe {
                detail(recipe, status: statuses[recipe.name])
            }
        }
        .padding(Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
    }

    private func face(_ recipe: Recipe, status: CommandStatus?) -> some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: 3) {
                Text("just \(recipe.name)")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                if !recipe.doc.isEmpty {
                    Text(recipe.doc)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textSecondary)
                }
                if recipe.needsArgs {
                    Text("needs arguments — run this one from a terminal")
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: Spacing.extraSmall)
            trailing(status)
        }
    }

    @ViewBuilder private func trailing(_ status: CommandStatus?) -> some View {
        if status?.running == true {
            Text("RUNNING")
                .font(Typography.state)
                .foregroundStyle(Palette.lcdGreen)
        } else if let verdict = status?.verdict {
            Text(verdict.uppercased())
                .font(Typography.state)
                .foregroundStyle(verdict == "finished" ? Palette.textTertiary : Palette.lcdRed)
        }
    }

    /// The log and the one button that fits its state — Run when nothing is going, Stop while it
    /// is. `acting` covers the round trip either way, so a slow Mac cannot be asked twice.
    @ViewBuilder private func detail(_ recipe: Recipe, status: CommandStatus?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            if let log = status?.log, !log.isEmpty { logView(log) }
            controls(recipe, running: status?.running == true)
        }
        .padding(.top, Spacing.xxs)
    }

    private func logView(_ log: String) -> some View {
        ScrollView {
            Text(log)
                .font(Typography.mono)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 180)
        .padding(Spacing.extraSmall)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Palette.surfaceGround)
        )
    }

    private func controls(_ recipe: Recipe, running: Bool) -> some View {
        HStack(spacing: Spacing.small) {
            if running {
                Button("Stop", role: .destructive) { Task { await stop(recipe) } }
                    .disabled(acting)
            } else {
                Button("Run") { Task { await start(recipe) } }
                    .disabled(acting)
            }
            if acting { ProgressView().tint(Palette.textTertiary) }
        }
        .font(Typography.primaryRow)
        .tint(Palette.tint)
    }

    private func load() async {
        guard let client = model.settings.client() else { return }
        loading = true
        await model.run { listing = try await client.recipes(for: project) }
        loading = false
    }

    /// Runs for as long as a panel stays open, whether or not the recipe under it is. A stopped
    /// recipe still gets refreshed: its exit code arrives this way, not from `start`/`stop`.
    private func poll() async {
        guard let recipe = watching, let client = model.settings.client() else { return }
        while !Task.isCancelled {
            if let status = try? await client.status(of: recipe, in: project) {
                statuses[recipe.name] = status
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func start(_ recipe: Recipe) async {
        guard let client = model.settings.client() else { return }
        acting = true
        await model.run { try await client.run(recipe, in: project) }
        acting = false
        statuses[recipe.name] = try? await client.status(of: recipe, in: project)
    }

    private func stop(_ recipe: Recipe) async {
        guard let client = model.settings.client() else { return }
        acting = true
        await model.run { try await client.stop(recipe, in: project) }
        acting = false
        statuses[recipe.name] = try? await client.status(of: recipe, in: project)
    }
}
