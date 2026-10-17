import Foundation

/// The tray as the phone holds it: what is open now, and every update it has been told about.
///
/// The manager's own shape. What is open is replaced whole on every poll — the Mac reads it off
/// the disk each time, so the newest answer is the truth — and updates are appended by cursor,
/// because the Mac only sends what is new and a replace would empty the list on a quiet poll.
public struct TrayState: Sendable {
    public private(set) var open: [TraySession] = []
    public private(set) var updates: [TrayUpdate] = []
    /// The last update id this phone has. What the next poll asks for everything after.
    public private(set) var cursor = 0
    /// Whether the Mac has answered once. Before then an empty tray is not knowing, not quiet.
    public private(set) var loaded = false
    /// How many updates are kept. The Mac keeps the same, so a phone cannot hold more than it.
    public static let kept = 200

    public init() {}

    public mutating func absorb(_ feed: TrayFeed) {
        open = feed.open
        loaded = true
        // The file went: ids below ours are a new list, not old news.
        if feed.newest < cursor {
            updates = []
            cursor = 0
        }
        let fresh = feed.updates.filter { $0.id > cursor }
        updates = Array((updates + fresh).suffix(Self.kept))
        cursor = max(cursor, feed.newest)
    }

    /// One slip answered from here, gone at once rather than on the next poll.
    public mutating func drop(slip: String, of session: String) {
        open = open.compactMap { row in
            guard row.session == session else { return row }
            var left = row
            left.slips.removeAll { $0.id == slip }
            return left.slips.isEmpty && (left.waiting ?? "").isEmpty ? nil : left
        }
    }

    /// How many slips and calls are waiting on the person.
    public var waitingCount: Int {
        open.reduce(0) { $0 + $1.slips.count + (($1.waiting ?? "").isEmpty ? 0 : 1) }
    }

    /// The updates as the tray draws them, newest first: each ask a session finished folds into
    /// one card per stretch of work, closed by the list going clear.
    public var items: [TrayItem] { TrayItem.items(updates) }
}

/// One row of the tray's history.
public enum TrayItem: Hashable, Identifiable, Sendable {
    case update(TrayUpdate)
    case work(WorkDone)

    public var id: Int {
        switch self {
        case .update(let update): update.id
        case .work(let work): work.id
        }
    }

    /// The newest update in it, which is what "new since you last looked" is measured by.
    public var last: Int {
        switch self {
        case .update(let update): update.id
        case .work(let work): work.last
        }
    }

    var when: Double {
        switch self {
        case .update(let update): update.when
        case .work(let work): work.when
        }
    }

    /// Done asks are 12 an hour across a busy Mac, and a row each is a list of check marks
    /// drowning the answers. So a session's asks gather into one card until its list clears, and
    /// the clearing closes the card rather than adding a row of its own.
    public static func items(_ updates: [TrayUpdate]) -> [TrayItem] {
        var found: [TrayItem] = []
        var working: [String: Int] = [:]  // session → index of its open card in `found`
        for update in updates.sorted(by: { $0.id < $1.id }) {
            switch update.kind {
            case .done, .finished:
                let index = working[update.session] ?? found.count
                if index == found.count { found.append(.work(WorkDone(starting: update))) }
                guard case .work(var work) = found[index] else { continue }
                work.absorb(update)
                found[index] = .work(work)
                working[update.session] = work.cleared ? nil : index
            case .answered, .called, .blocked:
                found.append(.update(update))
            case .other:
                continue
            }
        }
        return found.sorted { $0.when > $1.when }
    }
}

/// A stretch of one session's work: the asks it finished, and whether its list is now clear.
public struct WorkDone: Hashable, Identifiable, Sendable {
    public let id: Int
    public let session: String
    public let name: String
    public var asks: [String]
    public var cleared: Bool
    public var when: Double
    public var last: Int

    public var moment: Date { Date(timeIntervalSince1970: when) }

    init(starting update: TrayUpdate) {
        id = update.id
        session = update.session
        name = update.name
        asks = []
        cleared = false
        when = update.when
        last = update.id
    }

    /// One more ask done, or the list gone clear — which says the whole list, and closes it.
    mutating func absorb(_ update: TrayUpdate) {
        if update.kind == .finished {
            asks = update.asks ?? asks
            cleared = true
        } else if let ask = update.ask, !asks.contains(ask) {
            asks.append(ask)
        }
        when = update.when
        last = update.id
    }
}
