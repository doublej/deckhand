import DeckhandKit
import SwiftUI

/// The manager panel's first half: every session that needs you, then what happened lately.
///
/// **Needs you** is a card per session, each slip in it asked in place — a yes is two buttons, a
/// pick is its rows, a text slip is a field — so the common answer never opens a page. Only what
/// the Mac could not read as one of those opens the slip itself. **Lately** is one card of rows:
/// answers given from anywhere, calls, and each session's finished asks gathered into one row.
///
/// The rail surface, like the rest of the panel. One card per session and rows inside it, never a
/// card inside a card.
struct TrayView: View {
    @Bindable var model: AppModel
    @State private var opened: OpenedSlip?
    /// Lent to a slip's page, as `WaitingSlip` lends one, so its fields can be spoken into.
    @State private var recorder = Recorder()

    private var desk: ManagerDesk { model.manager }
    /// Enough history to scroll back through a day; the Mac keeps 200 and so does the phone.
    private static let shown = 40

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.small) {
                if let trouble = desk.trayTrouble {
                    Text(trouble).font(Typography.hint).foregroundStyle(Palette.lcdRed)
                }
                if let note = desk.trayNote {
                    Button { desk.trayNote = nil } label: {
                        Text(note).font(Typography.hint).foregroundStyle(Palette.lcdRed)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Dismisses this note")
                }
                if !desk.tray.loaded {
                    if desk.trayTrouble == nil { asking }
                } else if desk.tray.open.isEmpty && desk.tray.updates.isEmpty {
                    quiet
                }
                if !desk.tray.open.isEmpty {
                    eyebrow("NEEDS YOU", count: desk.tray.waitingCount)
                    ForEach(desk.tray.open) { row in
                        AttentionCard(model: model, row: row) { open($0, of: row) }
                    }
                }
                let items = Array(desk.tray.items.prefix(Self.shown))
                if !items.isEmpty {
                    eyebrow("LATELY", count: nil).padding(.top, Spacing.extraSmall)
                    Card(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Hairline() }
                            TrayHistoryRow(item: item, fresh: item.last > desk.seen) { id in
                                Task { await model.goTo(session: id) }
                            }
                        }
                    }
                }
            }
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.small)
        }
        .scrollIndicators(.hidden)
        .fadingEdges()
        .refreshable { await model.pollTray() }
        // What was new when you looked is not new the next time.
        .onDisappear { desk.markSeen() }
        .fullScreenCover(item: $opened, onDismiss: reread) { slip in
            ArtifactView(model: model, session: slip.session, artifact: slip.artifact,
                         say: Dictation(recorder: recorder, mode: model.preferences.talkMode,
                                        words: { await model.dictated($0, for: slip.session) }))
        }
    }

    /// Before the Mac has answered once: "nothing needs you" would be a guess.
    private var asking: some View {
        Text("Asking the Mac…")
            .font(Typography.prose)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.extraSmall)
    }

    /// Nothing open and nothing has happened: said once, plainly, rather than an empty screen.
    private var quiet: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            eyebrow("TRAY", count: nil)
            Text("Nothing needs you. A slip a session leaves for you shows up here, and you can "
                 + "answer it without opening it. So does a session calling for you, and every "
                 + "ask a session finishes.")
                .font(Typography.prose)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.extraSmall)
    }

    private func eyebrow(_ word: String, count: Int?) -> some View {
        HStack(spacing: Spacing.xxs) {
            Text(word)
            if let count { Text("\(count)").foregroundStyle(Palette.lcdYellow) }
        }
        .font(Typography.eyebrow)
        .tracking(1)
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, Spacing.extraSmall)
    }

    /// Back from a page: whatever was answered there leaves the tray now, not on the next poll.
    private func reread() { Task { await model.pollTray() } }

    /// A slip's own page, over everything. The session has to be one the phone is holding; one it
    /// is not is opened on its own page instead, where the slips square has it.
    private func open(_ slip: TraySlip, of row: TraySession) {
        guard let session = model.sessions.first(where: { $0.sessionId == row.session }) else {
            Task { await model.goTo(session: row.session) }
            return
        }
        opened = OpenedSlip(session: session, artifact: slip.artifact)
    }
}

/// A slip opened from the tray: the page and the session it answers into.
struct OpenedSlip: Identifiable {
    let session: Session
    let artifact: Artifact
    var id: String { artifact.id }
}

/// The line between rows in one card.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.strokeHairline).frame(height: 1)
    }
}
