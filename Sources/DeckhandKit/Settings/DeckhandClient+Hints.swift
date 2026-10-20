import Foundation

/// The words utt is told to listen for in every clip — `daemon/…/settings/hints.py`.
///
/// Not a swap, and not an alias: a hint lets utt turn text that is nearly the word into the
/// word. It is still a word on the card changed into another, so the list is read and pruned
/// from the phone like the aliases are.
public extension DeckhandClient {
    /// Every word on the Mac's list.
    func hints() async throws -> [String] {
        try JSONDecoder().decode(HintList.self, from: try await send(request(.get, "hints"))).hints
    }

    /// Replace the list whole, and take back what the Mac stored: blanks and repeats are dropped.
    @discardableResult
    func saveHints(_ hints: [String]) async throws -> [String] {
        var req = request(.put, "hints")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(HintList(hints: hints))
        return try JSONDecoder().decode(HintList.self, from: try await send(req, body: body)).hints
    }
}

/// Tolerant on the way in: a Mac a version behind answers 404, and a missing key is no words.
struct HintList: Codable {
    var hints: [String] = []

    init(hints: [String]) {
        self.hints = hints
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        hints = try box.decodeIfPresent([String].self, forKey: .hints) ?? []
    }
}
