import DeckhandKit
import SwiftUI

/// The addresses a session wrote down, in the Mac's order of what matters (`ranking.py`).
///
/// **Built to be glanced at, not read.** What deserves a look — shared just now, this project's
/// site, staging or atlas hostname — gets a full card each. What the session used recently is a
/// quiet list under it. Everything else, mostly URLs a tool printed out of some old file, is one
/// line saying how many there are, opened only on purpose. A row that works says nothing about
/// it: the dot is enough, and only a problem gets words — so the eye lands on what is broken.
///
/// The Mac does all of it — the scan, the checks, the ranking, atlas — and this draws the answer,
/// asking again every three seconds while the Mac says it is not complete.
struct AddressesView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var listing: AddressListing?
    /// Everything below "Recent", folded by default: the whole point of the tiers.
    @State private var showingRest = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.medium) {
                if let listing { tiers(Addresses.tiers(listing.addresses)) } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.large)
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.extraLarge)
        }
        .fadingEdges()
        .refreshable { await load() }
        .task {
            while !Task.isCancelled {
                await load()
                if listing?.complete ?? true { break }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    @ViewBuilder
    private func tiers(_ found: Addresses.Tiers) -> some View {
        if found.isEmpty { nothing }
        if !found.important.isEmpty {
            section("Worth a look") { ForEach(found.important) { row($0, big: true) } }
        }
        if !found.recent.isEmpty {
            section("Recent") { Card(spacing: Spacing.small) { ForEach(found.recent) { row($0, big: false) } } }
        }
        if !found.rest.isEmpty { rest(found.rest, open: found.important.isEmpty && found.recent.isEmpty) }
    }

    /// The long tail, behind one line. Opened already when it is all there is.
    @ViewBuilder
    private func rest(_ rows: [Address], open: Bool) -> some View {
        if showingRest || open {
            section("Everything else") { Card(spacing: Spacing.small) { ForEach(rows) { row($0, big: false) } } }
        } else {
            Button("\(rows.count) more, mostly from tool output") { withAnimation(.snappy) { showingRest = true } }
                .font(Typography.hint)
                .foregroundStyle(accent)
                .frame(minHeight: 44)
        }
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title.uppercased())
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(Palette.textTertiary)
            rows()
        }
    }

    private func load() async {
        guard let client = model.settings.client(),
              let read = try? await client.addresses(of: session.sessionId) else {
            if listing == nil { listing = AddressListing() }
            return
        }
        listing = read
    }

    /// A tap opens the URL that works from the phone; holding it offers the others.
    private func row(_ address: Address, big: Bool) -> some View {
        Button {
            if let url = Addresses.opens(address) { openURL(url) }
        } label: {
            if big { Card(spacing: Spacing.xxs) { face(address, big: true) } } else { face(address, big: false) }
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(Addresses.choices(address), id: \.self) { url in
                Button(url.absoluteString) { openURL(url) }
            }
            Button("Copy address", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = Addresses.opens(address)?.absoluteString ?? address.origin
            }
        }
        .accessibilityIdentifier("address-row")
    }

    /// A dot, the name, and under it the address and why it is here — or what is wrong with it.
    private func face(_ address: Address, big: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Circle().fill(colour(address)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(big ? Addresses.name(address) : Addresses.label(address))
                    .font(big ? Typography.primaryRow : Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if big, !address.title.isEmpty { quiet(Addresses.label(address), mono: true) }
                if let problem = Addresses.problem(address) {
                    Text(problem).font(Typography.hint).foregroundStyle(colour(address))
                } else if big { quiet(Addresses.why(address), mono: false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }

    private func quiet(_ words: String, mono: Bool) -> some View {
        Text(words)
            .font(mono ? Typography.mono : Typography.hint)
            .foregroundStyle(Palette.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func colour(_ address: Address) -> Color {
        switch address.state {
        case "loads": accent
        case "locked": Palette.lcdYellow
        case "fails", "down": Palette.lcdRed
        default: Palette.textTertiary
        }
    }

    private var nothing: some View {
        Text("This session has not written down any addresses")
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textTertiary)
            .padding(.top, Spacing.large)
    }
}
