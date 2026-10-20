import DeckhandKit
import SwiftUI

/// Every address the session and its subagents wrote down, grouped by where it can be opened
/// from, each with what the Mac found when it tried it.
///
/// The Mac does all of it — the scan, the checks, atlas — and this draws the answer. It asks
/// again every three seconds while the Mac says the answer is not complete, which is how a check
/// that outran the route's budget lands without anybody pulling to refresh.
struct AddressesView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var listing: AddressListing?
    @Environment(\.openURL) private var openURL
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.medium) {
                if let listing {
                    if listing.addresses.isEmpty { nothing }
                    ForEach(Addresses.sections(listing.addresses), id: \.title) { section in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(section.title.uppercased())
                                .font(Typography.eyebrow)
                                .tracking(1)
                                .foregroundStyle(Palette.textTertiary)
                            ForEach(section.rows) { row($0) }
                        }
                    }
                } else {
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

    private func load() async {
        guard let client = model.settings.client(),
              let read = try? await client.addresses(of: session.sessionId) else {
            if listing == nil { listing = AddressListing() }
            return
        }
        listing = read
    }

    /// One address: what to call it, whether it answers, what it is, and where it came from.
    /// A tap opens the URL that works from the phone; holding it offers the others.
    private func row(_ address: Address) -> some View {
        Button {
            if let url = Addresses.opens(address) { openURL(url) }
        } label: { card(address) }
        .buttonStyle(.plain)
        .opacity(address.state == "down" ? 0.55 : 1)
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

    private func card(_ address: Address) -> some View {
        Card(spacing: Spacing.xxs) {
            head(address)
            if let line = [address.title, address.note].first(where: { !$0.isEmpty }) {
                Text(line).font(Typography.hint).foregroundStyle(Palette.textSecondary).lineLimit(2)
            }
            let small = facts(address)
            if !small.isEmpty {
                Text(small.joined(separator: " · "))
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
            ForEach(address.paths.prefix(3), id: \.self) { path in
                Text(path).font(Typography.mono).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
        }
    }

    /// The address as said, and the check's verdict on the same line.
    private func head(_ address: Address) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Addresses.label(address))
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Spacing.small)
            Text(Addresses.verdict(address))
                .font(Typography.eyebrow)
                .foregroundStyle(colour(address))
        }
    }

    /// The small print: atlas's project, where the address can be reached from, and who wrote it.
    private func facts(_ address: Address) -> [String] {
        var out: [String] = []
        if let atlas = address.atlas { out.append("atlas: \(atlas.name)") }
        if !address.lanUrl.isEmpty { out.append("opens from the phone") }
        if address.inAgents { out.append("a subagent named it") }
        if !address.said { out.append("only in tool output") }
        if address.mentions > 1 { out.append("\(address.mentions)×") }
        return out
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
