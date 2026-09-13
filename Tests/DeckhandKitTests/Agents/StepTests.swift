import Testing

@testable import DeckhandKit

/// The arithmetic that lets one row hold any number of steps.
@Suite("Steps")
struct StepTests {
    private func tools(_ spec: [(String, Bool)]) -> [Tool] {
        spec.map { Tool(name: $0.0, detail: "", succeeded: $0.1) }
    }

    @Test("consecutive steps that draw alike become one run, and the order survives")
    func grouping() {
        let runs = Steps.runs(tools([
            ("Read", true), ("Grep", true), ("Bash", true), ("Bash", false), ("Bash", true)
        ]))
        #expect(runs.map(\.count) == [2, 1, 1, 1])
        #expect(runs.map(\.failed) == [false, false, true, false])
        // Read and Grep are both reading, so they share a run; a failure never joins one.
        #expect(runs[0].kind == .reading)
        #expect(runs[2].kind == .running)
    }

    @Test("the widths always add up to the row, at any number of steps")
    func exact() {
        for count in [1, 25, 400, 5000] {
            let runs = Steps.runs(tools((0..<count).map { _ in ("Read", true) }))
            let widths = Steps.widths(runs, in: 320)
            #expect(abs(widths.reduce(0, +) - 320) < 0.0001)
        }
        #expect(Steps.widths([], in: 320) == [])
        #expect(Steps.widths(Steps.runs(tools([("Read", true)])), in: 0) == [0])
    }

    @Test("one failure among five hundred steps is still visible")
    func theFailureFloor() {
        var spec = Array(repeating: ("Read", true), count: 500)
        spec[250] = ("Bash", false)
        let runs = Steps.runs(tools(spec))
        let widths = Steps.widths(runs, in: 320)
        let failing = zip(runs, widths).first { $0.0.failed }?.1 ?? 0
        // Honestly scaled it would be 320/500 = 0.64pt. The floor keeps it on the screen.
        #expect(failing >= 3)
        #expect(abs(widths.reduce(0, +) - 320) < 0.0001)
    }

    @Test("more failures than pixels gives up the floor rather than overflowing the row")
    func tooManyToFloor() {
        let spec = (0..<200).map { ($0.isMultiple(of: 2) ? "Read" : "Bash", false) }
        let runs = Steps.runs(tools(spec))
        let widths = Steps.widths(runs, in: 40)
        #expect(abs(widths.reduce(0, +) - 40) < 0.0001)  // never wider than the row it is in
    }
}
