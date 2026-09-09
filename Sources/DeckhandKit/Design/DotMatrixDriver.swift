import Observation
import SwiftUI

/// The one clock every live mark runs on, ported from utt. A timer per view drifts: two marks
/// on screen start their cycles at different moments and never agree again, which reads as a
/// bug the moment both are visible.
///
/// Never stopped, and never idle-looking: utt's mark is always moving, six seconds a pattern
/// in silence down to a tenth of a second at full voice. That slow drift is a large part of
/// the identity, so a plugin runs this list rather than a loop of its own.
@MainActor
@Observable
public final class DotMatrixDriver {
    public static let shared = DotMatrixDriver()

    public private(set) var patternIndex = 0
    /// Written by whichever mark is on screen — they all pass the same meter.
    public var level: Double = 0

    private var phase: Double = 0
    private var timer: Timer?

    public var pattern: Set<Int> { DotMatrix.patterns[patternIndex % DotMatrix.patterns.count] }

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: DotMatrix.tick, repeats: true) { _ in
            Task { @MainActor in Self.shared.advance() }
        }
    }

    private func advance() {
        phase += DotMatrix.tick / DotMatrix.cycleInterval(for: level)
        guard phase >= 1 else { return }
        phase = 0
        patternIndex = (patternIndex + 1) % DotMatrix.patterns.count
    }
}
