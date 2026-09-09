import DeckhandKit
import Foundation

/// The chain of steps the Mac runs over words on their way into a session, from this side of it.
///
/// Nothing here names a filter or knows what one does, and that is the design rather than an
/// omission: the Mac sends what it has and what each one takes, this builds a chain out of it,
/// and a filter added on the Mac needs no build of the app. Split from `Model.swift` the way
/// `Reading.swift` and `Controlling.swift` are — one job, one file, and that file was at its size.
@MainActor
extension AppModel {
    /// Everything the Mac offers and the chain it is running, as one list the screen can reorder.
    func loadFilters() async {
        guard let client = settings.client() else { return }
        guard let offered = try? await client.filters() else { return }
        knownFilters = offered.known
        filterChain = FilterStep.chain(offered.steps, over: offered.known)
        filtersDirty = false
    }

    /// Saved on the way out of Settings, not as it is typed. A text field changes on every
    /// letter — one sentence into the Mac's own plugin page was forty-odd writes in four seconds
    /// — and a PUT per letter would be that again over the network.
    func saveFilters() async {
        guard filtersDirty, let client = settings.client() else { return }
        filtersDirty = false
        let sending = filterChain
        await run {
            let saved = try await client.saveFilters(sending)
            self.filterChain = FilterStep.chain(saved, over: self.knownFilters)
        }
    }

    /// What the Mac said this step is. Nil for a step it no longer offers, which the screen
    /// draws as a name and an apology rather than as nothing at all.
    func describe(_ step: FilterStep) -> Filter? {
        knownFilters.first { $0.name == step.filter }
    }

    func setFilter(_ name: String, running: Bool) {
        guard let spot = index(of: name) else { return }
        filterChain[spot].isOn = running
        filtersDirty = true
    }

    /// One place up or down. Not a drag: this is a card of rows rather than a `List`, and
    /// `onMove` is a `List`'s own gesture.
    func shiftFilter(_ name: String, by places: Int) {
        guard let from = index(of: name), canShift(name, by: places) else { return }
        filterChain.swapAt(from, from + places)
        filtersDirty = true
    }

    func canShift(_ name: String, by places: Int) -> Bool {
        guard let from = index(of: name) else { return false }
        return filterChain.indices.contains(from + places)
    }

    /// The step as it stands, rather than the copy a row was drawn with. A control that reads
    /// the copy it was handed shows the value from before the keystroke, which is how a text
    /// field drops letters.
    func step(named name: String) -> FilterStep? {
        filterChain.first { $0.filter == name }
    }

    func isRunning(_ name: String) -> Bool {
        step(named: name)?.isOn ?? false
    }

    /// What this field holds right now: what the person set, or the Mac's own default until
    /// they set something.
    func value(of field: FilterField, in name: String) -> JSONValue {
        step(named: name)?.settings[field.key] ?? field.defaultValue
    }

    /// Only what was set is stored. The Mac merges its defaults over the top, so writing the
    /// whole merged set here would freeze today's defaults into somebody's saved chain.
    func setValue(_ value: JSONValue, of key: String, in name: String) {
        guard let spot = index(of: name) else { return }
        filterChain[spot].settings[key] = value
        filtersDirty = true
    }

    // MARK: - what a filter wants said

    /// One line for the status strip: what happened, then anything a filter wanted to add. The
    /// notes are quiet on purpose — a swapped word is worth seeing and not worth a card.
    func said(_ outcome: String, notes: [String]) -> String {
        ([outcome] + notes).joined(separator: " · ")
    }

    /// What a refusal reads as. It says the words did not go and names the filter by its title,
    /// because `stoppedBy` is the wire name and "words stopped it" is not a sentence anybody
    /// wants to read about their own message.
    func stopped(by name: String, notes: [String]) -> String {
        let title = knownFilters.first { $0.name == name }?.title ?? name
        return said("Not sent — \(title) stopped it", notes: notes)
    }

    private func index(of name: String) -> Int? {
        filterChain.firstIndex { $0.filter == name }
    }
}
