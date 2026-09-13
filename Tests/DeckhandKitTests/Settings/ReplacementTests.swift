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

    // MARK: - the number a square has room for

    @Test("the tally counts every scope, not the chain alone")
    func tallyCountsEverything() {
        let stages = Replacements.inForce(aliases: [["we", "web"], ["deck hand", "deckhand"]],
                                          chain: [step([["a", "b"]]), FilterStep(filter: "craft")],
                                          known: [words, craft])
        let tally = Replacements.tally(stages)
        // Two aliases and one filter row: the alias half is the half a chain count misses.
        #expect(tally.swaps == 3)
        // A model handed the whole sentence is not a row and is not counted as one.
        #expect(tally.others == 1)
    }

    @Test("nothing in force is empty, and an alias alone is not")
    func tallyEmptiness() {
        #expect(Replacements.tally(Replacements.inForce(aliases: [], chain: [], known: [])).isEmpty)
        let aliased = Replacements.inForce(aliases: [["we", "web"]], chain: [], known: [])
        #expect(!Replacements.tally(aliased).isEmpty)
    }

    // MARK: - rows the Mac will not keep

    @Test("a fresh empty row is not a mistake and says nothing")
    func freshRowIsSilent() {
        #expect(Replacements.dropped([["", ""]]).isEmpty)
        #expect(Replacements.dropped([[" ", "  "]]).isEmpty)
    }

    @Test("a row with a meaning but nothing to match is named by its meaning")
    func blankLeftIsNamed() {
        let gone = Replacements.dropped([["we", "web"], ["", "deckhand"]])
        #expect(gone.map(\.row) == [1])
        #expect(gone[0].why.contains(#""deckhand""#))
        #expect(gone[0].why.contains("nothing on its left"))
    }

    @Test("the earlier of two rows for one word goes, and the later answer wins")
    func duplicateLosesTheEarlier() {
        let gone = Replacements.dropped([["we", "first"], ["other", "x"], ["we", "second"]])
        // Row 2 survives — marking it dropped would be false, its answer is the one that runs.
        #expect(gone.map(\.row) == [0])
        #expect(gone[0].why.contains(#""we" is aliased again below"#))
    }

    @Test("case is ignored deciding a duplicate, the way the Mac decides it")
    func duplicateIgnoresCase() {
        #expect(Replacements.dropped([["We", "a"], ["we", "b"]]).map(\.row) == [0])
    }

    @Test("a list the Mac keeps whole drops nothing")
    func nothingDropped() {
        #expect(Replacements.dropped([["we", "web"], ["deck hand", "deckhand"]]).isEmpty)
    }

    /// The two halves have to agree: a row that is dropped is not a rule in force, and a rule in
    /// force is not a dropped row. They are worked out separately and would drift silently.
    @Test("what is dropped and what is in force do not overlap")
    func droppedIsNotInForce() {
        let list = [["we", "first"], ["", "orphan"], ["we", "second"]]
        let inForce = Replacements.inForce(aliases: list, chain: [], known: [])[0].rules
        #expect(Replacements.dropped(list).map(\.row) == [0, 1])
        // One rule, not two: the Mac keys its list on the heard side, so a word written twice is
        // one alias written twice. Listing both would show a rule that cannot exist — and worse,
        // `follow` would mark the *surviving* answer as shadowed by the one being thrown away,
        // which is the truth exactly inverted.
        #expect(inForce.map(\.meant) == ["second"])
        #expect(inForce[0].follow == nil)
    }

    @Test("a duplicate keeps the earlier row's place and the later row's answer")
    func duplicateKeepsPlaceAndLaterAnswer() {
        let list = [["we", "first"], ["deck hand", "deckhand"], ["WE", "second"]]
        let inForce = Replacements.inForce(aliases: list, chain: [], known: [])[0].rules
        // Position of the first, answer of the last — `aliases._kept`'s rule, so that correcting
        // an alias does not move it to the bottom of the list.
        #expect(inForce.map(\.heard) == ["WE", "deck hand"])
        #expect(inForce.map(\.meant) == ["second", "deckhand"])
    }

    /// The chain is not deduplicated and must not be: `aliases._pairs` keeps both rows for a
    /// filter's `pairs`, so both fire, the second on the first's output. Only the Mac's own list
    /// is keyed by word.
    @Test("a filter's pairs are not deduplicated the way aliases are")
    func chainKeepsBothRows() {
        let stages = Replacements.inForce(aliases: [],
                                          chain: [step([["we", "first"], ["we", "second"]])],
                                          known: [words])
        #expect(stages[1].rules.map(\.meant) == ["first", "second"])
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
