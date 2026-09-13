import DeckhandKit
import SwiftUI

/// One project's own page: what the Mac may do about it, what it runs on, and what is running
/// in it right now.
///
/// A page, not the rail. It is reached from the project picker and it is about a folder — which
/// is what a settings key can be, where a session id cannot: an id changes every restart, so a
/// preference filed under one would be gone by morning. From here it still reads as "this
/// session", because the sessions running in this folder are on it.
///
/// Every switch shows the Mac's answer until this folder says otherwise, and says so when it
/// does. Nothing here is three-state to the thumb: a switch is on or off, and "no opinion" is a
/// thing you get back to with one button rather than a third position nobody can hit on purpose.
struct ProjectSettingsView: View {
    @Bindable var model: AppModel
    let project: Project
    @Environment(\.dismiss) private var dismiss
    /// The control awaiting an answer, for the two that cannot be undone.
    @State private var confirming: Pending?

    private struct Pending: Identifiable {
        let control: Control
        let session: Session
        var id: String { "\(control.rawValue)-\(session.sessionId)" }
    }

    private var here: Wants { model.wants.here(project.path) }
    /// What the dialog says, which the control carries rather than the sheet — a sheet that knew
    /// only how to say "Clear" is the bug that put those words on the control in the first place.
    private var asking: Caution? {
        confirming.flatMap { $0.control.caution(about: $0.session.name) }
    }
    private var running: [Session] {
        model.sessions.filter { $0.cwd == project.path }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    switches
                    models
                    sessions
                    footer
                }
                .padding(Spacing.medium)
            }
            .background(Palette.surfaceGround)
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Palette.tint)
                }
            }
        }
        .task { await model.loadSettings() }
        .confirmationDialog(
            asking?.title ?? "",
            isPresented: .init(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button(asking?.verb ?? "", role: .destructive) {
                if let pending = confirming {
                    Task { await model.control(pending.control, of: pending.session) }
                }
                confirming = nil
            }
            Button("Keep it", role: .cancel) { confirming = nil }
        } message: {
            Text(asking?.because ?? "")
        }
    }

    private var switches: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            eyebrow("BUZZ MY PHONE WHEN")
            card {
                toggle("A session here finishes", now: here.finished, over: \.finished)
                toggle("A slip here is waiting", now: here.slips, over: \.slips)
                toggle("An agent here asks for me", now: here.called, over: \.called)
            }
            eyebrow("AND ON THE MAC")
            card {
                toggle("Chase a session that goes quiet owing work", now: here.chase, over: \.chase)
                toggle("Let the summariser read this folder's subagents",
                       now: here.subagents, over: \.subagents)
            }
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            eyebrow("MODELS")
            card {
                picker("New sessions", chosen: here.sessionModel,
                       offered: model.wants.settings?.offers.session ?? [], over: \.sessionModel)
                picker("Summaries", chosen: here.summaryModel,
                       offered: model.wants.settings?.offers.summary ?? [], over: \.summaryModel)
            }
        }
    }

    /// What is running in this folder now, and the two things you do to a conversation rather
    /// than say to it. Here because this is where somebody comes to deal with a project — the
    /// alternative was finding each session on the rail first.
    @ViewBuilder private var sessions: some View {
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.small) {
                eyebrow(running.count == 1 ? "ONE SESSION HERE" : "\(running.count) SESSIONS HERE")
                card {
                    ForEach(running) { session in
                        HStack(spacing: Spacing.small) {
                            Text(session.name)
                                .font(Typography.primaryRow)
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: Spacing.extraSmall)
                            // Both are typed into a pane; a Codex thread has none to type into.
                            if !session.isCodex {
                                act(.compact, on: session)
                                act(.exit, on: session)
                            }
                        }
                        .frame(minHeight: 40)
                    }
                }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if let why = model.wants.failed {
            Text(why).font(Typography.hint).foregroundStyle(Palette.lcdRed)
        }
        if model.wants.settings?.overridden(project.path) == true {
            Button("Follow the Mac for everything here") {
                Task { await model.override(project.path) { $0 = Overrides() } }
            }
            .font(Typography.hint)
            .tint(Palette.tint)
            .accessibilityIdentifier("project-follow-mac")
        }
        Text("A switch here overrides what every other project does. The path is the key, so it "
             + "survives a session restart.")
            .font(Typography.hint)
            .foregroundStyle(Palette.textTertiary)
    }

    private func act(_ control: Control, on session: Session) -> some View {
        Button {
            if control.asksFirst {
                confirming = Pending(control: control, session: session)
            } else {
                Task { await model.control(control, of: session) }
            }
        } label: {
            Image(systemName: control.symbol)
                .font(.system(size: 15))
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .tint(Palette.tint)
        .accessibilityLabel(control.label)
    }

    private func toggle(_ words: String,
                        now: Bool,
                        over key: WritableKeyPath<Overrides, Bool?>) -> some View {
        Toggle(isOn: Binding(
            get: { now },
            set: { value in Task { await model.override(project.path) { $0[keyPath: key] = value } } }
        )) {
            label(words, over: key)
        }
        .tint(Palette.tint)
        .frame(minHeight: 44)
    }

    /// Empty means "the default", which is a real answer and the one most projects want — so it
    /// is an option rather than an absence, and it is first.
    ///
    /// The label is drawn here rather than handed to the `Picker`, which is the whole reason this
    /// is a row and not one control: a menu picker only shows the label it was given inside a
    /// `Form` or a `List`, and this card is neither. Both rows read "Default" and nothing else,
    /// so there was no telling which model either of them was about.
    private func picker(_ words: String,
                        chosen: String,
                        offered: [String],
                        over key: WritableKeyPath<Overrides, String?>) -> some View {
        HStack(spacing: Spacing.small) {
            label(words, over: key)
            Spacer(minLength: Spacing.extraSmall)
            Picker(words, selection: Binding(
                get: { chosen },
                set: { value in
                    Task { await model.override(project.path) { $0[keyPath: key] = value } }
                }
            )) {
                Text("Default").tag("")
                ForEach(offered, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Palette.tint)
        }
        .frame(minHeight: 44)
    }

    /// What a row is about, and whether this folder is the one saying so. Shared by both kinds
    /// of control: the marker means the same thing on a model as it does on a switch.
    private func label<Value>(_ words: String, over key: KeyPath<Overrides, Value?>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(words).font(Typography.primaryRow).foregroundStyle(Palette.textPrimary)
            if model.wants.settings?.projects[project.path]?[keyPath: key] != nil {
                Text("only here").font(Typography.hint).foregroundStyle(Palette.tint)
            }
        }
    }

    private func eyebrow(_ words: String) -> some View {
        Text(words)
            .font(Typography.eyebrow)
            .tracking(1)
            .foregroundStyle(Palette.textTertiary)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Spacing.extraSmall) { content() }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Palette.surfacePrimary)
            )
    }
}
