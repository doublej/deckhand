import CoreGraphics
import Foundation

/// The 6×6 grid every mark in utt's language is drawn on, ported from
/// `swift/utt/Utt/Design/DotMatrix.swift`. The geometry and the level curves are copied
/// exactly; utt's hundred-frame show is not, because Deckhand has shapes, not an animation.
public enum DotMatrix {
    /// Where dot `index` sits in a grid `size` points wide, each dot centred in its cell —
    /// any other divisor leaves the grid sitting off-centre in its frame.
    public static func rect(for index: Int, size: CGFloat, lit: Bool, columns: Int = 6) -> CGRect {
        let step = size / CGFloat(columns)
        let radius = step * (lit ? 0.34 : 0.24)
        return CGRect(
            x: step * (0.5 + CGFloat(index % columns)) - radius,
            y: step * (0.5 + CGFloat(index / columns)) - radius,
            width: radius * 2,
            height: radius * 2
        )
    }

    /// How often the phase accumulator advances, whatever the level is doing.
    public static let tick: TimeInterval = 0.05

    private static let slowestCycle: TimeInterval = 6
    private static let fastestCycle: TimeInterval = 0.1
    /// Never 0: a mark that goes dark between words cannot be told from one that has died.
    private static let quietestGlow: Double = 0.45

    /// 0 at silence, 1 at full scale. Peak amplitude is a terrible knob — ordinary speech
    /// peaks around 0.1, so a linear map spends its whole range on volumes nobody produces.
    /// The dBFS scale puts speech at roughly 0.6...0.9 instead.
    public static func loudness(for level: Double) -> Double {
        guard level > 0.001 else { return 0 }
        return min(max((max(-60, 20 * log10(level)) + 60) / 60, 0), 1)
    }

    /// Geometric, so every step up in level is a constant *factor* faster.
    public static func cycleInterval(for level: Double) -> TimeInterval {
        slowestCycle * pow(fastestCycle / slowestCycle, loudness(for: level))
    }

    /// The grid burns brighter the louder you speak, on the curve that drives the speed.
    public static func glow(for level: Double) -> Double {
        quietestGlow + (1 - quietestGlow) * loudness(for: level)
    }
}

/// The shapes themselves. Deckhand's own is the anchor; the rest are utt's, borrowed to give
/// each session a face — a glyph on the same grid, never a logo or an SF Symbol.
public enum DotGlyph {
    /// Deckhand's mark: an anchor. The one thing in the app that is its own.
    public static let anchor: Set<Int> = [
        2, 3,                   // ring
        8, 9,                   // shank
        12, 13, 14, 15, 16, 17, // stock
        20, 21,
        24, 26, 27, 29,         // arms
        31, 32, 33, 34          // crown
    ]

    /// One per session, picked by name so a session keeps its face between launches.
    /// utt's own mark is deliberately absent: it belongs to utt, and a session wearing it
    /// next to the real one is the one thing in this list that would read as a mistake.
    static let sessionGlyphs: [Set<Int>] = [
        [7, 8, 9, 10, 13, 16, 19, 22, 25, 26, 27, 28],           // ring
        [6, 7, 8, 9, 10, 11, 12, 17, 18, 23, 24, 25, 26, 27, 28, 29], // bridge
        [2, 3, 8, 9, 10, 13, 14, 15, 18, 19, 20, 26, 27, 28, 33, 34], // bolt
        [0, 5, 7, 10, 14, 15, 20, 21, 25, 28, 30, 35],           // snowflake
        [8, 9, 14, 15, 20, 21, 26, 27],                          // bar
        [0, 2, 3, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 26, 27, 32, 33], // star
        [1, 2, 7, 8, 14, 15, 20, 21, 26, 27, 31, 32, 33, 34]     // note
    ]

    /// The glyph for a session. Stable across launches: Swift's own hashing is seeded per
    /// process, so a session's face would change every time the app was opened.
    public static func forName(_ name: String) -> Set<Int> {
        sessionGlyphs[Int(stableHash(name) % UInt64(sessionGlyphs.count))]
    }

    /// FNV-1a, for no reason beyond being short and stable.
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
