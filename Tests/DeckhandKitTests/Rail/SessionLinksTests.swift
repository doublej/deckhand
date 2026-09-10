import Foundation
import Testing

@testable import DeckhandKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func link(_ source: String, _ target: String, secondsAgo: Double, count: Int = 1) -> SessionLink {
    SessionLink(
        source: source,
        target: target,
        latest: now.timeIntervalSince1970 - secondsAgo,
        count: count
    )
}

@Suite("Folding wire edges into threads to draw")
struct LinkTrailTests {
    @Test("one-way traffic is one thread that knows it is one-way")
    func oneWay() {
        let trails = LinkTrail.fold([link("a", "b", secondsAgo: 10, count: 3)])
        #expect(trails.count == 1)
        #expect(trails[0].source == "a")
        #expect(trails[0].forward == 3)
        #expect(trails[0].back == 0)
        #expect(trails[0].isMutual == false)
    }

    @Test("both directions fold into one mutual thread")
    func mutual() {
        let trails = LinkTrail.fold([
            link("a", "b", secondsAgo: 60, count: 2),
            link("b", "a", secondsAgo: 10, count: 5)
        ])
        #expect(trails.count == 1)
        #expect(trails[0].isMutual)
        // oriented towards whoever spoke last
        #expect(trails[0].source == "b")
        #expect(trails[0].forward == 5)
        #expect(trails[0].back == 2)
    }

    @Test("a pair keeps one identity however the traffic turns around")
    func identityIsThePair() {
        let one = LinkTrail(source: "a", target: "b", forward: 1, back: 0, latest: now)
        let other = LinkTrail(source: "b", target: "a", forward: 1, back: 0, latest: now)
        #expect(one.id == other.id)
    }

    @Test("threads come back newest first")
    func ordering() {
        let trails = LinkTrail.fold([
            link("a", "b", secondsAgo: 200),
            link("c", "d", secondsAgo: 5),
            link("e", "f", secondsAgo: 90)
        ])
        #expect(trails.map(\.source) == ["c", "e", "a"])
    }

    @Test("separate pairs stay separate")
    func separatePairs() {
        let trails = LinkTrail.fold([
            link("a", "b", secondsAgo: 10),
            link("a", "c", secondsAgo: 20)
        ])
        #expect(trails.count == 2)
    }

    @Test("nothing to fold is nothing to draw")
    func empty() {
        #expect(LinkTrail.fold([]).isEmpty)
    }
}

@Suite("How loudly a thread is drawn as it ages")
struct LinkIntensityTests {
    private func trail(secondsAgo: Double) -> LinkTrail {
        LinkTrail(
            source: "a",
            target: "b",
            forward: 1,
            back: 0,
            latest: now.addingTimeInterval(-secondsAgo)
        )
    }

    @Test("a message just now is at full strength")
    func fresh() {
        #expect(trail(secondsAgo: 0).intensity(now: now, window: 300) == 1.0)
    }

    @Test("thirty seconds in is still vivid, and the far end of the window is nearly gone")
    func theCurveJJAskedFor() {
        let early = trail(secondsAgo: 30).intensity(now: now, window: 300)
        let late = trail(secondsAgo: 290).intensity(now: now, window: 300)
        #expect(early > 0.8)
        #expect(late < 0.02)
        #expect(late > 0)
    }

    @Test("past the window it is not drawn at all")
    func gone() {
        #expect(trail(secondsAgo: 300).intensity(now: now, window: 300) == 0)
        #expect(trail(secondsAgo: 5000).intensity(now: now, window: 300) == 0)
    }

    @Test("it only ever fades")
    func monotonic() {
        let ages = stride(from: 0.0, through: 300.0, by: 10.0)
        let values = ages.map { trail(secondsAgo: $0).intensity(now: now, window: 300) }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test("a longer window keeps the same message brighter for longer")
    func windowIsRelative() {
        let short = trail(secondsAgo: 120).intensity(now: now, window: 300)
        let long = trail(secondsAgo: 120).intensity(now: now, window: 1800)
        #expect(long > short)
    }

    @Test("a nonsense window draws nothing rather than dividing by zero")
    func noWindow() {
        #expect(trail(secondsAgo: 1).intensity(now: now, window: 0) == 0)
    }
}
