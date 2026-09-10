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
    /// What this span is made of, where whoever spent it says so. Only utt does, and only on a
    /// utt new enough to measure its own stages — on every other one this is empty and the span
    /// stays the single opaque number it has always been.
    public var children: [Stage] = []

    public var id: String { name }

    public init(name: String, took: Double, children: [Stage] = []) {
        self.name = name
        self.took = took
        self.children = children
    }

    enum CodingKeys: String, CodingKey {
        case name
        case took = "ms"
        case children = "inside"
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decode(String.self, forKey: .name)
        took = try box.decodeIfPresent(Double.self, forKey: .took) ?? 0
        children = try box.decodeIfPresent([Stage].self, forKey: .children) ?? []
    }

    /// What this stage is, in words. Written out rather than derived from the name: `utt` is
    /// not "Utt", and "read" on its own says nothing about what was read.
    public var title: String { Self.titles[name] ?? Self.uttTitles[name] ?? name }

    /// The same name inside utt's span, where it means something else. `hints` is the whole
    /// reason this exists: at the top level it is Deckhand building the word list, and inside
    /// utt's span it is utt applying it.
    public var titleInsideUtt: String { Self.uttTitles[name] ?? title }

    /// Which side of the wire spent it. The whole question a breakdown is opened to answer is
    /// "is it me, the network, or the Mac", so it is on every row rather than in a legend.
    public var side: Side {
        if Self.mine.contains(name) { return .phone }
        return name == "network" ? .wire : .mac
    }

    /// The sentence a number needs beside it to mean what it looks like it means.
    ///
    /// utt looks in its jobs folder every 300 ms (`ExtensionJobs.interval`) and takes what is
    /// already queued first, so a clip can sit there while utt is busy with somebody else's —
    /// measured at 2.1 s and 10.1 s for the same clip, minutes apart. On a utt that measures
    /// its own stages that wait is its own row; on one that does not, the whole span carries
    /// the warning, because otherwise the number reads as "utt is slow" when it means "utt has
    /// not looked yet".
    public var note: String? {
        switch name {
        case "waiting": "utt looks every 300 ms, and takes what is already queued first"
        case "utt" where children.isEmpty: "up to 300 ms of this is utt not having looked yet"
        default: nil
        }
    }

    /// The stages of utt's pipeline that can change the words. `decode` is not among them — it
    /// produced the words rather than changing them, and utt never puts it in `stages` — and
    /// neither is `waiting`, which is this side's arithmetic rather than a stage of utt's.
    public static let textStages: Set<String> = [
        "hints", "replacements", "cleanup", "formatting", "filter"
    ]

    public enum Side: String, Codable, Sendable {
        case phone, wire, mac
    }

    private static let mine: Set<String> = ["arming", "finishing", "keeping", "showing"]

    /// Two `hints` entries and they are not the same thing: ours is building the word list
    /// before the clip goes over, utt's is applying it to what the recogniser heard. They are
    /// told apart by where they sit — the second is only ever inside utt's span.
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

    /// utt's own stage names, which are `TranscriptStage`'s raw values.
    private static let uttTitles = [
        "waiting": "Waiting to be picked up",
        "decode": "Recognising the speech",
        "hints": "Applying the word list",
        "replacements": "Your word replacements",
        "cleanup": "Transcript cleanup",
        "formatting": "Text formatting",
        "filter": "Another utt extension"
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
    /// Which of utt's stages actually changed the words, as utt reported them.
    ///
    /// A record parallel to the timings and never a subset of them: a stage that ran and left
    /// the words alone is timed all the same. Two different questions about one stage, kept
    /// apart here because conflating them is how a breakdown starts lying.
    public var changedByUtt: [String] = []
    /// Why utt's cleanup did not run, when it was switched on and did not.
    public var cleanupSkipped: String?

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
    public static func merged(phone: PhoneSpans,
                              mac: [Stage],
                              macTotal: Double?,
                              changedByUtt: [String] = [],
                              cleanupSkipped: String? = nil) -> ClipTiming {
        var stages = [Stage(name: "arming", took: phone.arming),
                      Stage(name: "finishing", took: phone.finishing),
                      Stage(name: "keeping", took: phone.keeping),
                      Stage(name: "network", took: max(0, phone.upload - (macTotal ?? phone.upload)))]
        stages += mac.filter { $0.name != "total" }
        var timing = ClipTiming(stages: stages, spoken: phone.spoken)
        timing.changedByUtt = changedByUtt
        timing.cleanupSkipped = cleanupSkipped
        return timing
    }

    /// What to say beside one of utt's own stages, and the only honest thing there is to say.
    ///
    /// A stage with a number either changed the words or it did not, and utt's `stages` is the
    /// one record that answers that. Absence from it means the words came out **unchanged** —
    /// it does not mean a stage looked at them and approved. "Reviewed", "checked" and
    /// "approved" are all claims utt never made, and this is exactly the seam where a JSON key
    /// turns into a sentence somebody reads and believes.
    ///
    /// Nil for `decode` and `waiting`, neither of which is a stage that could change anything.
    public func verdict(on stage: Stage) -> String? {
        guard Stage.textStages.contains(stage.name) else { return nil }
        return changedByUtt.contains(stage.name) ? "changed the words" : "unchanged"
    }

    /// Why utt's cleanup did not run, in words. utt's own reasons, kept in utt's own terms so
    /// the sentence points at the thing a person would go and look at.
    public var cleanupNote: String? {
        guard let reason = cleanupSkipped else { return nil }
        let why = switch reason {
        case "unavailable": "no on-device model was available"
        case "guardrail": "the model's own content check fired"
        case "timeout": "the model was still going when the deadline passed"
        case "tooLong": "more transcript than the model's context holds"
        case "tooShort": "it dropped more than the verifier allows"
        case "failedVerification": "the result was not a deletion-only edit"
        default: reason
        }
        return "utt's cleanup did not run: \(why)"
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
