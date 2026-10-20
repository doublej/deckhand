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

/// One list a session hears: the global one (`path` empty) or one folder's own words.
///
/// Layered the way CLAUDE.md files are — a session hears every layer from the global list down to
/// its own folder, appended in that order. The Mac works the layers out (`/hints/folder`); the
/// phone only draws them and writes back the one that was edited.
public struct HintLayer: Codable, Equatable, Sendable {
    public var path: String
    public var hints: [String]

    public init(path: String, hints: [String]) {
        self.path = path
        self.hints = hints
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        path = try box.decodeIfPresent(String.self, forKey: .path) ?? ""
        hints = try box.decodeIfPresent([String].self, forKey: .hints) ?? []
    }
}

public extension DeckhandClient {
    /// Every layer a session working in `folder` hears, outermost first.
    func hintLayers(for folder: String) async throws -> [HintLayer] {
        let escaped = folder.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await send(request(.get, "hints/folder?path=\(escaped)"))
        return try JSONDecoder().decode(Layers.self, from: data).layers
    }

    /// Replace one layer's own words, and take back what the Mac stored.
    @discardableResult
    func saveHints(_ layer: HintLayer) async throws -> HintLayer {
        var req = request(.put, "hints/folder")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(layer)
        return try JSONDecoder().decode(HintLayer.self, from: try await send(req, body: body))
    }
}

/// Tolerant like `HintList`: a Mac without layers yet answers 404 and the section shows nothing.
struct Layers: Decodable {
    var layers: [HintLayer] = []

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        layers = try box.decodeIfPresent([HintLayer].self, forKey: .layers) ?? []
    }

    enum CodingKeys: String, CodingKey { case layers }
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
