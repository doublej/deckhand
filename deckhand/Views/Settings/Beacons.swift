import DeckhandKit
import SwiftUI

/// The Macs answering on this network, under the Address field. A tap fills the field in.
///
/// The list never touches the Token field: discovery is an unauthenticated broadcast and finds
/// an address, never a secret. What it also never does is move a pairing that is working —
/// `ServerSettings.adopts` is that whole rule and it lives beside the setting it guards.
///
/// Which of a Mac's two addresses goes in is `Beacon.answering`, asked over `/health` at the
/// moment of the tap: the `.local` name is preferred and the raw IP is what a link with no
/// working mDNS resolution leaves. Asked here rather than guessed at, because the phone is the
/// only thing that knows whether that name resolves *for it*.
struct Beacons: View {
    @Bindable var model: AppModel
    @State private var lookout = Lookout()
    /// Filled in at most once per visit to this page. Without it, an address the person has
    /// just cleared is written straight back and the field cannot be emptied by hand.
    @State private var adopted = false
    /// The Mac currently being asked which of its addresses answers. A tap can cost seconds when
    /// one of them has to time out, and a control that fires a request has to say so where the
    /// thumb is — the same rule the slip's send button is written to.
    @State private var trying: Beacon?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            SettingRow("On this network", detail: sentence) { EmptyView() }
            ForEach(macs) { mac in
                Button { take(mac) } label: { row(mac) }
                    .buttonStyle(.plain)
            }
        }
        .onAppear { lookout.start() }
        .onDisappear { lookout.stop() }
        .onChange(of: macs) { _, found in adopt(found) }
    }

    /// One sentence per state, and they are deliberately not interchangeable: a look that has
    /// not finished, a look that heard nothing and a look this phone refused to run are three
    /// different facts, and only the middle one means there is no Mac here.
    private var sentence: String {
        if let trying { return "Asking \(trying.name) which of its addresses answers…" }
        return switch lookout.state {
        case .looking:
            "Listening for Macs…"
        case .heard(let found):
            found.count == 1 ? "One Mac is answering." : "\(found.count) Macs are answering."
        case .nothing:
            "No Mac answered. Its daemon may be off, or the phone may be on another network."
        case .refused:
            "This phone will not let Deckhand look. Settings › Deckhand › Local Network."
        case .broken(let why):
            "Could not look: \(why)"
        }
    }

    private var macs: [Beacon] {
        if case .heard(let found) = lookout.state { return found }
        return []
    }

    private func row(_ mac: Beacon) -> some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name).font(Typography.primaryRow)
                if let version = mac.version {
                    Text("deckhand \(version)")
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer(minLength: Spacing.extraSmall)
            Text(mac.host)
                .font(Typography.mono)
                .foregroundStyle(taken(mac) ? Palette.tint : Palette.textSecondary)
        }
        .contentShape(Rectangle())
    }

    /// Either address counts as taken: the field may well hold the IP because the name did not
    /// resolve, and a row that then looks untouched invites the same tap again.
    private func taken(_ mac: Beacon) -> Bool { mac.candidates.contains(model.settings.host) }

    private func take(_ mac: Beacon) {
        adopted = true
        trying = mac
        Task { @MainActor in
            let address = await mac.answering()
            trying = nil
            model.settings.host = address
        }
    }

    private func adopt(_ found: [Beacon]) {
        guard !adopted, let first = found.first,
              ServerSettings.adopts(model.settings.host, answering: model.connection.answering)
        else { return }
        take(first)
    }
}
