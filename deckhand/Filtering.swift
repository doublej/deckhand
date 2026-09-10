import DeckhandKit
import Foundation

/// What the chain had to say about the words sitting in the review card.
///
/// Both halves come off the preview response, which is the point of it: `?deliver=false` runs the
/// chain without delivering anything, so the card can say what was changed *and* that Send is
/// going to be refused before anybody presses it, rather than after.
struct Filtered: Equatable {
    /// What the chain changed on the way here, as one quiet line. Nil when it changed nothing.
    var note: String?
    /// What will happen when Send is pressed, when what will happen is nothing. Nil otherwise.
    var refusal: String?
    /// The words as utt heard them, before this Mac's own chain swapped anything. Nil when the
    /// chain left them alone — the card is already showing them, and a second identical copy
    /// under a heading saying it changed would be a lie of its own.
    var heard: String?
    /// The words before utt's *own* pipeline rewrote them.
    ///
    /// Nil on every utt shipped today, and drawn only when `uttStages` says a stage actually
    /// changed something — never on `raw != text`, because the pipeline trims and whitespace is
    /// not a rewrite worth showing anybody. Same rule as utt's own `ProcessedTranscript.changed`.
    var raw: String?
    /// Which of utt's stages changed the words, as utt named them. This is what the disclosure
    /// is attributed with: `raw` is from before *everything*, and one of the stages between it
    /// and the transcript is `hints` — which is this repo's own vocabulary list rather than
    /// anything utt did. Naming utt for our own substitution would be the UI lying.
    var uttStages: [String] = []
}

/// The chain of steps the Mac runs over words on their way into one session, from this side of it.
///
/// Nothing here names a filter or knows what one does, and that is the design rather than an
/// omission: the Mac sends what it has and what each one takes, this builds a chain out of it,
/// and a filter added on the Mac needs no build of the app. Split from `Model.swift` the way
/// `Reading.swift` and `Controlling.swift` are — one job, one file, and that file was at its size.
///
/// A chain belongs to one terminal rather than to the Mac. What this Mac *can* do is still global,
/// which is why `knownFilters` is: only which of them run, in what order, on what settings, is a
/// property of the session you are talking to.
///
/// Everything is addressed by a row's id rather than by its filter's name. The same filter may be
/// in the chain twice with different settings, and by name the second one would be invisible to
/// every edit on this page.
@MainActor
extension AppModel {
    /// Everything the Mac offers and the chain this session is running, as one list the page can
    /// reorder. Always off the Mac: it is one request, it is the source of truth, and a chain
    /// cached per session would be a second place for the answer to be wrong.
    func loadFilters(for session: Session) async {
        guard let client = settings.client() else { return }
        filterSession = session
        guard let offered = try? await client.filters(of: session.sessionId) else { return }
        knownFilters = offered.known
        filterChain = FilterRow.chain(offered.steps, over: offered.known)
        filtersDirty = false
    }

    /// Saved on the way off the page, not as it is typed. A text field changes on every letter —
    /// one sentence into the Mac's own plugin page was forty-odd writes in four seconds — and a
    /// PUT per letter would be that again over the network.
    ///
    /// What comes back is what the Mac will actually run, so the screen follows that rather than
    /// what it just sent. A save it refuses says which filter this Mac does not have.
    func saveFilters() async {
        guard filtersDirty, let client = settings.client(), let session = filterSession else {
            return
        }
        filtersDirty = false
        let sending = filterChain.map(\.step)
        await run {
            let saved = try await client.saveFilters(sending, of: session.sessionId)
            self.filterChain = FilterRow.chain(saved, over: self.knownFilters)
        }
    }

    /// What the Mac said this row's filter is. Nil for a filter it no longer offers, which the
    /// screen draws as a name and an apology rather than as nothing at all.
    func describe(_ row: FilterRow) -> Filter? {
        knownFilters.first { $0.name == row.filter }
    }

    func setFilter(_ id: FilterRow.ID, running: Bool) {
        guard let spot = index(of: id) else { return }
        filterChain[spot].step.isOn = running
        filtersDirty = true
    }

    /// One place up or down. Not a drag: this is a card of rows rather than a `List`, and
    /// `onMove` is a `List`'s own gesture.
    func shiftFilter(_ id: FilterRow.ID, by places: Int) {
        guard let from = index(of: id), canShift(id, by: places) else { return }
        filterChain.swapAt(from, from + places)
        filtersDirty = true
    }

    func canShift(_ id: FilterRow.ID, by places: Int) -> Bool {
        guard let from = index(of: id) else { return false }
        return filterChain.indices.contains(from + places)
    }

    /// The row as it stands, rather than the copy it was drawn with. A control that reads the
    /// copy it was handed shows the value from before the keystroke, which is how a text field
    /// drops letters.
    func row(_ id: FilterRow.ID) -> FilterRow? {
        filterChain.first { $0.id == id }
    }

    func isRunning(_ id: FilterRow.ID) -> Bool {
        row(id)?.step.isOn ?? false
    }

    /// What this field holds right now: what the person set, or the Mac's own default until
    /// they set something.
    func value(of field: FilterField, in id: FilterRow.ID) -> JSONValue {
        row(id)?.step.settings[field.key] ?? field.defaultValue
    }

    /// Only what was set is stored. The Mac merges its defaults over the top, so writing the
    /// whole merged set here would freeze today's defaults into somebody's saved chain.
    func setValue(_ value: JSONValue, of key: String, in id: FilterRow.ID) {
        guard let spot = index(of: id) else { return }
        filterChain[spot].step.settings[key] = value
        filtersDirty = true
    }

    // MARK: - what a filter wants said

    /// Words waiting to be read, and everything the chain wanted said about them. The one way
    /// into the review card, so neither line can outlive the words it was written about — last
    /// clip's note under this clip's text would be worse than saying nothing at all.
    ///
    /// `Markups.swift` adds prose to text already held, which is a different move: it changes
    /// what is in the card, and what the chain said about those words still stands.
    func hold(
        _ text: String?,
        for session: Session,
        notes: [String] = [],
        stoppedBy: String? = nil,
        because reason: String? = nil,
        heard: String? = nil,
        raw: String? = nil,
        uttStages: [String] = []
    ) {
        review[session.sessionId] = text
        reviewFiltered[session.sessionId] = text == nil ? nil : Filtered(
            note: notes.isEmpty ? nil : notes.joined(separator: " · "),
            refusal: stoppedBy.map { refusal(by: $0, because: reason) },
            heard: heard == text ? nil : heard,
            raw: raw,
            uttStages: uttStages
        )
    }

    /// A refusal that has not happened yet. Present tense on purpose: Send stays pressable, and
    /// this is what pressing it will do. A greyed-out button with no sentence beside it is the
    /// worse version of this — it leaves somebody holding words and no way to learn why.
    func refusal(by filter: String, because reason: String?) -> String {
        guard let reason, !reason.isEmpty else { return "\(title(of: filter)) will refuse this" }
        return "\(title(of: filter)) will refuse this: \(reason)"
    }

    /// A filter by the name it goes by on screen. `stoppedBy` carries the wire name, and "words
    /// stopped it" is not a sentence anybody wants to read about their own message.
    func title(of filter: String) -> String {
        knownFilters.first { $0.name == filter }?.title ?? filter
    }

    /// One line for the status strip: what happened, then anything a filter wanted to add. The
    /// notes are quiet on purpose — a swapped word is worth seeing and not worth a card.
    func said(_ outcome: String, notes: [String]) -> String {
        ([outcome] + notes).joined(separator: " · ")
    }

    /// What a refusal reads as: the words did not go, which filter would not have them, and why.
    ///
    /// The filter is named by its title, because `stoppedBy` carries the wire name and "words
    /// stopped it" is not a sentence anybody wants to read about their own message. The reason
    /// comes in the ordinary `delivery_error`, and it is the half that says what to do about it.
    func stopped(by name: String, because reason: String?, notes: [String]) -> String {
        guard let reason, !reason.isEmpty else {
            return said("Not sent — \(title(of: name)) stopped it", notes: notes)
        }
        return said("Not sent — \(title(of: name)): \(reason)", notes: notes)
    }

    private func index(of id: FilterRow.ID) -> Int? {
        filterChain.firstIndex { $0.id == id }
    }
}
