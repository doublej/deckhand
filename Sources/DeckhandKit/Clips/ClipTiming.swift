import Foundation

/// One stage of a clip's journey and what it cost, in milliseconds.
///
/// The name is the wire's, lowercase and single-word on both sides: the client decodes with
/// `convertFromSnakeCase`, which rewrites dictionary *keys* as happily as struct ones — so the
/// Mac sends a list of these rather than an object, and a stage name travels as a value where
/// nothing can rename it.
public struct Stage: Codable, Hashable, Sendable, Identifiable {
    public let name: String
    /// Milliseconds. Not `ms`: SwiftLint refuses a two-letter identifier, and the doc line is
    /// the unit either way.
    public let took: Double

    public var id: String { name }

    public init(name: String, took: Double) {
        self.name = name
        self.took = took
    }

    enum CodingKeys: String, CodingKey {
        case name
        case took = "ms"
    }

    /// What this stage is, in words. Written out rather than derived from the name: `utt` is
    /// not "Utt", and "read" on its own says nothing about what was read.
    public var title: String { Self.titles[name] ?? name }

    /// Which side of the wire spent it. The whole question a breakdown is opened to answer is
    /// "is it me, the network, or the Mac", so it is on every row rather than in a legend.
    public var side: Side {
        if Self.mine.contains(name) { return .phone }
        return name == "network" ? .wire : .mac
    }

    /// The one stage that needs a sentence under it, and it is the largest one.
    ///
    /// utt looks in its jobs folder every 300 ms (`ExtensionJobs.interval`), so up to that much
    /// of this span is utt not having noticed the clip yet. Without the sentence the number
    /// reads as "utt is slow" when it often means "utt has not looked".
    public var note: String? {
        name == "utt" ? "up to 300 ms of this is utt not having looked yet" : nil
    }

    public enum Side: String, Codable, Sendable {
        case phone, wire, mac
    }

    private static let mine: Set<String> = ["arming", "finishing", "keeping", "showing"]

    private static let titles = [
        "arming": "Microphone opened",
        "finishing": "Clip closed",
        "keeping": "Filed on this phone",
        "network": "There and back",
        "session": "Session looked up",
        "read": "Clip read in",
        "write": "Clip written",
        "hints": "Hints built",
        "handoff": "Handed to utt",
        "utt": "utt transcribed",
        "answer": "Answer read",
        "filters": "Filters ran",
        "deliver": "Delivered",
        "showing": "Card on screen"
    ]
}

/// What one clip cost from the press to the words on screen, phone and Mac in one list.
///
/// Kept on the clip's own archive entry, so a run last week can be held against one today —
/// which is the whole reason for measuring rather than guessing.
public struct ClipTiming: Codable, Hashable, Sendable {
    /// In the order the clip travelled. `total` from the Mac is deliberately not among them:
    /// it is the sum of the Mac's own stages and would be counted twice.
    public var stages: [Stage] = []
    /// How long the person actually talked, in milliseconds. Not a cost and not in `total` —
    /// a breakdown dominated by however long somebody spoke says nothing about what is slow.
    public var spoken: Double = 0

    public init(stages: [Stage] = [], spoken: Double = 0) {
        self.stages = stages
        self.spoken = spoken
    }

    public var total: Double { stages.reduce(0) { $0 + $1.took } }

    /// The stage worth looking at first.
    public var slowest: Stage? { stages.max { $0.took < $1.took } }

    /// The phone's own spans and the Mac's, in the order the clip actually travelled them.
    ///
    /// The network is derived rather than measured, because nothing on the phone can see when
    /// its request arrived: the upload span with the Mac's own total taken out of it is what
    /// was spent on the wire, both ways. Clamped at zero — the two clocks are different clocks,
    /// and a negative sliver would be measurement noise printed as fact.
    public static func merged(phone: PhoneSpans, mac: [Stage], macTotal: Double?) -> ClipTiming {
        var stages = [Stage(name: "arming", took: phone.arming),
                      Stage(name: "finishing", took: phone.finishing),
                      Stage(name: "keeping", took: phone.keeping),
                      Stage(name: "network", took: max(0, phone.upload - (macTotal ?? phone.upload)))]
        stages += mac.filter { $0.name != "total" }
        return ClipTiming(stages: stages, spoken: phone.spoken)
    }

    /// The last span, filled in when the card holding the words actually appears.
    ///
    /// It arrives after the rest because it ends in a view, which is the one place none of the
    /// rest of this can measure from. Replaced rather than appended, so a card that comes back
    /// on screen after a swipe between panes cannot add a second one.
    public mutating func showed(_ took: Double) {
        stages.removeAll { $0.name == "showing" }
        stages.append(Stage(name: "showing", took: took))
    }
}

/// What this phone itself spent on one clip, in milliseconds, as it spent it.
///
/// Filled in three places — the recorder knows the first three, the upload knows the next two,
/// and the card knows the last — which is why it is a value carried along rather than a
/// measurement taken anywhere in particular.
public struct PhoneSpans: Codable, Hashable, Sendable {
    /// The settled press to a live microphone. Permission and `AVAudioSession.setActive` are
    /// both in here, and both are real and variable. What is *not* in here is the settle
    /// itself: `TalkGesture` waits a fixed 200 ms before a press counts as talking at all, and
    /// no gesture on this phone can report the moment a finger landed.
    public var arming: Double = 0
    /// The clip's own length.
    public var spoken: Double = 0
    /// Stop to a finished file. AAC writes its index here, so it is not free.
    public var finishing: Double = 0
    /// The archive write that has to happen before anything goes on the wire.
    public var keeping: Double = 0
    /// Request sent to answer read. The Mac's own total comes out of this to leave the network.
    public var upload: Double = 0

    public init() {}

    /// Milliseconds from an instant to now. Every span on this phone is measured this way.
    public static func since(_ mark: Date) -> Double {
        Date.now.timeIntervalSince(mark) * 1000
    }
}
