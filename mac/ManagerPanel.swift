import AppKit
import DeckhandKit
import SwiftUI

/// The manager's conversation, in the menu bar's panel and in the window alike.
///
/// The phone's panel at a desk: the rail surface, the person's words trailing and the manager's
/// leading, and what the manager *did* as a line rather than a bubble — `ManagerLine` and
/// `ManagerStarters` are the phone's own files, compiled into this target too. No talk mark:
/// utt already dictates into any field on this Mac, this one included.
struct ManagerPanel: View {
    enum Place: Hashable { case menu, window }

    static let window = "manager"

    @Bindable var desk: Desk
    let place: Place
    @State private var pairing = false
    @State private var clearing = false
    @FocusState private var typing: Bool
    @Environment(\.appearsActive) private var active
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: Spacing.extraSmall) {
            head
            if pairing { PairingForm(desk: desk) }
            conversation
            foot
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.lcdGround.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .accent(Palette.accent(recording: false))
        // A session the manager named is a `deckhand://sessions/<id>` link — the Lock Screen
        // card's own shape. Here it brings that session's terminal forward; anything else opens.
        .environment(\.openURL, OpenURLAction { url in
            guard let session = CardLink.session(openedBy: url) else { return .systemAction }
            Task { await desk.focus(session) }
            return .handled
        })
        .onChange(of: active, initial: true) { _, now in
            desk.look(place, active: now)
            if now { typing = true }
        }
        .onDisappear { desk.look(place, active: false) }
        .confirmationDialog("Start over?", isPresented: $clearing) {
            Button("Start over", role: .destructive) { Task { await desk.clear() } }
        } message: {
            Text("The manager forgets this conversation and everything in it.")
        }
    }

    private var head: some View {
        HStack {
            Text("MANAGER")
                .font(Typography.eyebrow)
                .tracking(2)
                .foregroundStyle(Palette.textTertiary)
            Spacer()
            Menu {
                if place == .menu {
                    Button("Open in a Window") {
                        openWindow(id: Self.window)
                        AppActivation.front()
                    }
                }
                Button(pairing ? "Hide Pairing" : "Pairing…") { pairing.toggle() }
                Button("Start Over…") { clearing = true }
                    .disabled(desk.entries.isEmpty)
                Divider()
                Button("Quit Deckhand") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    /// Everything said, oldest first, then what is on its way and what the manager is doing.
    private var conversation: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    ForEach(desk.entries) { ManagerLine(entry: $0) }
                    ForEach(desk.pending, id: \.self) { ManagerBubble(text: $0, mine: true).opacity(0.6) }
                    if !desk.partial.isEmpty { ManagerBubble(text: desk.partial, mine: false) }
                    if desk.working { workingLine }
                    Color.clear.frame(height: 1).id("end")
                }
            }
            .scrollIndicators(.never)
            .onAppear { scroller.scrollTo("end", anchor: .bottom) }
            .onChange(of: desk.entries.last?.id) { scroller.scrollTo("end", anchor: .bottom) }
            .onChange(of: desk.partial) { scroller.scrollTo("end", anchor: .bottom) }
            .onChange(of: desk.working) { scroller.scrollTo("end", anchor: .bottom) }
        }
    }

    private var workingLine: some View {
        HStack(spacing: Spacing.extraSmall) {
            ProgressView().controlSize(.mini)
            Text(desk.doing.isEmpty ? "WORKING" : desk.doing.uppercased())
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, Spacing.extraSmall)
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            if let failure = desk.failure {
                Text(failure)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.lcdRed)
            }
            if desk.draft.isEmpty && !desk.working {
                ManagerStarters { send($0) }.buttonStyle(.plain)
            }
            HStack(alignment: .bottom, spacing: Spacing.extraSmall) {
                TextField("Ask the manager", text: $desk.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typography.prose)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1...6)
                    .focused($typing)
                    .onSubmit { send(desk.draft) }
                    .padding(.horizontal, Spacing.extraSmall)
                    .padding(.vertical, Spacing.xxs + 2)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .fill(Palette.textPrimary.opacity(0.06))
                    )
                Button("Send", systemImage: "arrow.up.circle.fill") { send(desk.draft) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.accent(recording: false))
                    .disabled(desk.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func send(_ words: String) {
        Task { await desk.ask(words) }
    }
}
