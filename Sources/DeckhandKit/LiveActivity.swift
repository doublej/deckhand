#if os(iOS)
import ActivityKit
import Foundation

/// What the Lock Screen and the Dynamic Island show about the Mac, and the shape the daemon
/// has to produce on the other side of APNs.
///
/// Every field is a plain value on purpose. This struct is decoded by iOS from JSON the daemon
/// composed in Python, so there is no Swift on the sending side to keep in step — the wire
/// format *is* the contract. `at` is Unix seconds rather than a `Date` for the same reason:
/// Foundation would encode a `Date` as its own reference-date offset, which is a trap for
/// anything not written in Swift.
public struct Deck: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Sessions that have stopped and are waiting for you. The number is the whole point.
        public var waiting: Int
        /// The one that most recently stopped, and the first thing it said when it did.
        public var name: String
        public var line: String
        /// Unix seconds. The view makes it tick by itself so a glance says how stale this is.
        public var when: Double

        public init(waiting: Int, name: String, line: String, when: Double) {
            self.waiting = waiting
            self.name = name
            self.line = line
            self.when = when
        }

        public var moment: Date { Date(timeIntervalSince1970: when) }
    }

    /// Which Mac this is, so a second one is never mistaken for the first.
    public var mac: String

    public init(mac: String) {
        self.mac = mac
    }
}
#endif
