import Foundation

/// A run of consecutive steps that would draw the same way.
///
/// A run rather than a tally per kind, because the order is the information: twelve reads, a
/// failure, then eight commands is a different afternoon from a failure buried among twelve
/// reads, and a tally of the same numbers cannot tell you which.
public struct StepRun: Equatable, Identifiable, Sendable {
    public let id: Int
    public let kind: Tool.Kind
    public var count: Int
    public let failed: Bool

    public init(id: Int, kind: Tool.Kind, count: Int, failed: Bool) {
        self.id = id
        self.kind = kind
        self.count = count
        self.failed = failed
    }
}

/// The arithmetic behind drawing any number of steps in a fixed width.
///
/// Here rather than in the view because it is the part that can be wrong: a strip that overflows
/// its row, or one where the single failure among four hundred steps rounds away to nothing, is a
/// bug you find by looking at a phone. Pure, so it is a bug you find by running the tests.
public enum Steps {
    /// How many steps still read as things you could count. Past this a row of dots is a row of
    /// dots — you stop reading it and start estimating — and estimating is what the strip does
    /// properly. Twenty-four is where a phone's width runs out at this dot size, which is about
    /// where the eye gives up anyway.
    public static let countable = 24

    /// Consecutive steps that would draw alike, collapsed.
    public static func runs(_ tools: [Tool]) -> [StepRun] {
        var found: [StepRun] = []
        for tool in tools {
            let failed = !tool.succeeded
            if var last = found.last, last.kind == tool.kind, last.failed == failed {
                last.count += 1
                found[found.count - 1] = last
            } else {
                found.append(StepRun(id: found.count, kind: tool.kind, count: 1, failed: failed))
            }
        }
        return found
    }

    /// Each run's share of `total`: every failure's floor first, then whatever is left split by
    /// how many steps each run holds.
    ///
    /// The two parts always sum to exactly `total`, so nothing overflows the row and no last
    /// segment is left short by accumulated rounding. A failing run keeps its floor *and* takes
    /// its proportional share, which over-represents it slightly — deliberately, because "did
    /// anything break" is the first question this row is asked.
    ///
    /// A total too small to hold every floor gives them up proportionally rather than overflowing:
    /// with more failures than pixels there is nothing honest left to draw, and a strip wider than
    /// its row would push the step count off the screen.
    public static func widths(_ runs: [StepRun], in total: Double,
                              minFailure: Double = 3) -> [Double] {
        let steps = runs.reduce(0) { $0 + $1.count }
        guard steps > 0, total > 0 else { return runs.map { _ in 0 } }
        var floors = runs.map { $0.failed ? minFailure : 0 }
        let wanted = floors.reduce(0, +)
        if wanted > total {
            floors = floors.map { $0 * total / wanted }
        }
        let spare = max(0, total - floors.reduce(0, +))
        return runs.indices.map { index in
            floors[index] + spare * Double(runs[index].count) / Double(steps)
        }
    }
}
