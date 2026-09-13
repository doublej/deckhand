import Testing
@testable import DeckhandKit

/// What is in force over one session's words, and in what order. The screen this holds up is
/// the answer to "why did my word change", so the thing worth testing is the part a list of
/// pairs does not show: which scope a rule came from, and what the scope below does to it.
@Suite("What gets swapped")
struct ReplacementTests {
    private let words = Filter(
        name: "words", title: "Replace words", summary: "Swap words dictation gets wrong.",
        fields: [FilterField(key: "pairs", label: "Words", kind: .pairs, defaultValue: .rows([]))]
    )
    private let craft = Filter(
        name: "craft", title: "Craft the prompt", summary: "Hands the sentence to a model."
    )

    private func step(_ pairs: [[String]], isOn: Bool = true) -> FilterStep {
        FilterStep(filter: "words", isOn: isOn, settings: ["pairs": .rows(pairs)])
    }

    @Test("aliases come first, and are always a scope even when empty")
    func aliasesLead() {
        let stages = Replacements.inForce(aliases: [], chain: [], known: [words])
        #expect(stages.count == 1)
        #expect(stages[0].source == .aliases)
        #expect(stages[0].rules.isEmpty)
    }

    @Test("a running step is a scope, a switched-off one is not")
    func onlyRunningSteps() {
        let chain = [step([["a", "b"]]), step([["c", "d"]], isOn: false)]
        let stages = Replacements.inForce(aliases: [], chain: chain, known: [words])
        #expect(stages.count == 2)
        #expect(stages[1].source == .filter(place: 0, name: "words"))
        #expect(stages[1].rules.map(\.heard) == ["a"])
    }

    @Test("rules are numbered across every scope, in the order they run")
    func numberedAcrossScopes() {
        let stages = Replacements.inForce(aliases: [["one", "1"], ["two", "2"]],
                                          chain: [step([["three", "3"]])],
                                          known: [words])
        #expect(stages.flatMap(\.rules).map(\.order) == [1, 2, 3])
        #expect(stages[1].rules[0].source == .filter(place: 0, name: "words"))
    }

    @Test("a blank left side is not a rule, the same as on the Mac")
    func blankRowsDropped() {
        let stages = Replacements.inForce(aliases: [["", "x"], [" ", "y"], ["z", ""]],
                                          chain: [], known: [])
        #expect(stages[0].rules.map(\.heard) == ["z"])
        #expect(stages[0].rules[0].label.contains("becomes nothing"))
    }

    // MARK: - the cascade, which is the whole reason precedence is drawn

    @Test("a rule whose output is swapped again says what it ends as")
    func chained() {
        let stages = Replacements.inForce(aliases: [["we", "web"]],
                                          chain: [step([["web", "website"]])],
                                          known: [words])
        #expect(stages[0].rules[0].follow == .chained(into: "website"))
        #expect(stages[1].rules[0].follow == nil)
    }

    @Test("a rule the scope above already swapped may never fire")
    func shadowed() {
        let stages = Replacements.inForce(aliases: [["we", "weather"]],
                                          chain: [step([["we", "web"]])],
                                          known: [words])
        #expect(stages[1].rules[0].follow == .shadowed(behind: "we"))
    }

    @Test("shadowing wins over chaining — a rule that never fires has no output")
    func shadowedBeatsChained() {
        // "we" is gone by the time the third rule runs, so saying what "web" becomes further
        // down would be describing something that does not happen.
        let stages = Replacements.inForce(aliases: [["we", "weather"], ["web", "site"]],
                                          chain: [step([["we", "web"]])],
                                          known: [words])
        #expect(stages[1].rules[0].follow == .shadowed(behind: "we"))
    }

    @Test("case and whole words follow the Mac's own rule, not a looser one")
    func matchingRule() {
        let stages = Replacements.inForce(aliases: [["We", "web"], ["webbing", "rope"]],
                                          chain: [step([["we", "us"]])],
                                          known: [words])
        // Case-insensitive, so "we" below is shadowed by "We" above.
        #expect(stages[1].rules[0].follow == .shadowed(behind: "We"))
        // Whole words only: "web" is not the front of "webbing", so nothing chains.
        #expect(stages[0].rules[0].follow == nil)
    }

    // MARK: - a step that is not a list of pairs

    @Test("a filter with no pairs field carries the Mac's own sentence")
    func otherwise() {
        let chain = [FilterStep(filter: "craft")]
        let stages = Replacements.inForce(aliases: [], chain: chain, known: [craft])
        #expect(stages[1].doing == .otherwise("Hands the sentence to a model."))
        #expect(stages[1].rules.isEmpty)
    }

    @Test("a step naming a filter this Mac no longer has keeps its place and says so")
    func unknownFilter() {
        let stages = Replacements.inForce(aliases: [], chain: [FilterStep(filter: "gone")],
                                          known: [words])
        #expect(stages[1].title == "gone")
        #expect(stages[1].doing == .otherwise("This Mac no longer offers this filter."))
    }

    // MARK: - hints

    @Test("hints mirror the Mac: alias meanings, the name split, the last of the folder")
    func hints() {
        let hints = Replacements.hints(aliases: [["we", "web"], ["x", "no"], ["", "skipped"]],
                                       name: "multi-stack-deckhand",
                                       cwd: "/Users/jurrejan/dev/multi-stack/deckhand")
        // "no" is two letters and does not travel; an alias with no left side is not an alias.
        #expect(hints.fromAliases == ["skipped", "web"])
        #expect(hints.fromSession == ["deckhand", "multi", "multi-stack", "stack"])
    }

    @Test("the home folder is not a hint")
    func hintsSkipUsers() {
        let hints = Replacements.hints(aliases: [], name: "x", cwd: "/Users/jurrejan")
        #expect(hints.fromSession == ["jurrejan"])
        #expect(Replacements.hints(aliases: [], name: "", cwd: "/").isEmpty)
    }

    // MARK: - what a row says to somebody not looking at it

    @Test("every rule names where it came from")
    func labels() {
        let stages = Replacements.inForce(aliases: [["we", "web"]],
                                          chain: [step([["deck hand", "deckhand"]])],
                                          known: [words])
        #expect(stages[0].rules[0].label ==
                #""we" becomes "web", from this Mac's aliases"#)
        #expect(stages[1].rules[0].label ==
                #""deck hand" becomes "deckhand", from the words step of this session's chain"#)
    }
}
