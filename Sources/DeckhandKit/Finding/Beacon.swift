import Foundation
import Network

/// A Mac heard saying where its daemon answers, and the look around the network that heard it.
///
/// The addresses travel in the **TXT record**, which is why this browses with
/// `bonjourWithTXTRecord`: the metadata then arrives on the browse result itself and nothing
/// has to be resolved. The older dance — open an `NWConnection` to the `NWEndpoint.service` and
/// read `currentPath.remoteEndpoint` — buys one IP address, where what is wanted is the Mac's
/// own pair of answers in its own order of preference.
///
/// **No token is in here, and none is coming.** mDNS is an unauthenticated broadcast to the
/// whole network. A beacon says where the Mac is; the pairing code is still typed once.
public struct Beacon: Equatable, Identifiable, Sendable {
    /// The Mac as it named itself — the Bonjour instance name, which is its hostname.
    public let name: String
    /// The address to try first, verbatim. The `.local` name when the Mac offered one, because
    /// that is the answer that survives DHCP.
    public let host: String
    /// The raw IP behind it, when the Mac offered a second address that is not the first one.
    public let lan: String?
    /// The daemon's version, when it said one. Nil is an older daemon, not an error.
    public let version: String?

    public var id: String { host }

    /// Both addresses in the order they are worth trying, and never the same one twice.
    public var candidates: [String] { lan.map { [host, $0] } ?? [host] }

    public init(name: String, host: String, lan: String? = nil, version: String? = nil) {
        self.name = name
        self.host = host
        self.lan = lan
        self.version = version
    }

    /// The one thing that has to be read right. A record with no usable address is not a beacon:
    /// the service type alone would put a row on the screen that fills the field with nothing.
    ///
    /// Both addresses are checked through `ServerSettings` rather than by a rule of their own,
    /// so whatever the Address field accepts by hand is exactly what a tap can fill in — and a
    /// Mac that could work out only one of the two is a beacon with one candidate rather than
    /// no beacon at all.
    public static func read(name: String, txt: [String: String]) -> Beacon? {
        let offered = [txt["host"], txt["lan"]].compactMap { $0.flatMap(usable) }
        guard let host = offered.first else { return nil }
        let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Beacon(name: named.isEmpty ? host : named,
                      host: host,
                      lan: offered.dropFirst().first { $0 != host },
                      version: txt["version"].flatMap { $0.isEmpty ? nil : $0 })
    }

    private static func usable(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ServerSettings(host: trimmed).baseURL != nil else { return nil }
        return trimmed
    }

    /// How long the name is given to answer before the IP is used instead.
    ///
    /// A `.local` name that resolves answers in tens of milliseconds; this is the budget for one
    /// that does not, and the whole of what a person waits through after a tap.
    public static let patience: TimeInterval = 5

    /// Which of this beacon's addresses goes into the Address field.
    ///
    /// **One question, asked of the name only: does this phone's link resolve it?** That is the
    /// failure the second address exists for, and the name is the answer worth preferring
    /// because it survives DHCP. A Mac that offered only the one address is not asked at all —
    /// there is nothing to choose between.
    ///
    /// **The IP is deliberately not verified**, and this was measured rather than assumed. In the
    /// simulator on 2026-09-14, a first connection to a raw private address took longer than five
    /// seconds and came back `-1001` timed out, while the same address through `DeckhandClient`
    /// and its twenty-second budget connected fine — so a probe strict enough to be quick would
    /// reject a working address, and one patient enough to be right would sit under the thumb for
    /// twenty seconds. A fallback that has to prove itself before it may be used is not a
    /// fallback. Both ways of being wrong here are cheap: the IP reaches the same daemon, and an
    /// address that turns out to be dead is what the Connection row is for.
    public func answering(timeout: TimeInterval = Beacon.patience,
                          urlSession: URLSession = .shared) async -> String {
        guard let lan else { return host }
        return await Beacon.reaches(host, timeout: timeout, urlSession: urlSession) ? host : lan
    }

    /// One address, one `/health`. That is the only route with no token on it, which is what
    /// makes any of this askable at pairing time — there is nothing to authenticate with yet.
    static func reaches(_ address: String, timeout: TimeInterval,
                        urlSession: URLSession) async -> Bool {
        guard let url = ServerSettings(host: address).baseURL?.appending(path: "health")
        else { return false }
        let answer = try? await urlSession
            .data(for: URLRequest(url: url, timeoutInterval: timeout))
        return (answer?.1 as? HTTPURLResponse)?.statusCode == 200
    }
}

/// What a look around the local network has to say.
///
/// Five answers rather than a list, because a look that has not finished, a look that found
/// nothing and a look this phone would not allow are three different sentences — and a screen
/// that draws all three as "no Mac here" is wrong twice over.
public enum Looking: Equatable, Sendable {
    /// Browsing. Nothing has answered *yet*, which is not the same as nothing being there.
    case looking
    case heard([Beacon])
    /// Browsing, long enough that silence means silence.
    case nothing
    /// The local network permission is not granted, so this app is not allowed to look.
    case refused
    case broken(String)
}

/// Browses for `_deckhand._tcp` and says what it heard.
///
/// One of these per pairing screen, started when it appears and cancelled when it goes: an mDNS
/// browse is multicast traffic and there is nothing to hear when nobody is reading it.
@MainActor
@Observable
public final class Lookout {
    /// Matches `beacon.SERVICE` in the daemon, and `NSBonjourServices` in `project.yml` — iOS
    /// silently finds nothing for a type the app has not declared there.
    public static let service = "_deckhand._tcp"
    /// How long silence is allowed to mean "still looking". A Bonjour answer on a quiet LAN is
    /// back well inside a second; this is slack before the screen is permitted to say nothing
    /// is there, not a timeout on anything.
    public static let settle: Duration = .seconds(4)

    public private(set) var state: Looking = .looking

    private var browser: NWBrowser?
    private var settling: Task<Void, Never>?

    public nonisolated init() {}

    public func start() {
        guard browser == nil else { return }
        state = .looking
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.service, domain: nil),
                                using: .tcp)
        browser.stateUpdateHandler = { [weak self] update in
            Task { @MainActor in self?.took(update) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.heard(results) }
        }
        self.browser = browser
        browser.start(queue: .main)
        settling = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else { return }
            self?.quieten()
        }
    }

    public func stop() {
        settling?.cancel()
        settling = nil
        browser?.cancel()
        browser = nil
    }

    private func heard(_ results: Set<NWBrowser.Result>) {
        var found: [String: Beacon] = [:]
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint,
                  case .bonjour(let txt) = result.metadata,
                  let beacon = Beacon.read(name: name, txt: txt.dictionary) else { continue }
            // Keyed by preferred address: the same Mac is heard once per interface it is
            // reachable on — measured, `if 1` and `if 17` on this network — and two rows
            // offering the identical Mac is one row twice.
            found[beacon.host] = beacon
        }
        state = found.isEmpty ? .nothing : .heard(found.values.sorted { $0.name < $1.name })
    }

    private func took(_ update: NWBrowser.State) {
        switch update {
        case .failed(let error), .waiting(let error): state = Self.reading(error)
        case .setup, .ready, .cancelled: break
        @unknown default: break
        }
    }

    /// Only from `.looking`: a browse that has already heard something, or already been
    /// refused, has an answer and this is not it.
    private func quieten() {
        if state == .looking { state = .nothing }
    }

    /// A refused local network permission comes back as a DNS policy error, and it comes back
    /// the same way whether the person said no or has never been asked. Both readings are "this
    /// phone would not let me look" and neither is "there is no Mac here".
    ///
    /// The constant is spelled out because it lives in `dns_sd.h`, which `Network` does not
    /// re-export: `kDNSServiceErr_PolicyDenied = -65570`, verified against the SDK header.
    static func reading(_ error: NWError) -> Looking {
        if case .dns(let code) = error, code == -65570 { return .refused }
        return .broken(error.localizedDescription)
    }
}
