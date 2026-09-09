import Foundation

// What the Mac does to words on their way into a session, and nothing about what any of it is.
// The phone has no list of filters in it and is not supposed to grow one: the Mac describes what
// it has — a name, a sentence, and the fields each one takes — and the settings screen draws
// controls from that description. A filter added on the Mac is therefore not an app release.

/// A JSON value carried exactly as it arrived.
///
/// A filter's settings belong to the filter: a word list, a language, a ceiling, a switch. The
/// phone has no type for any of them and must hand every one back unchanged, so this is as wide
/// as JSON and no wider. Anything narrower flattens something — a `[String: String]` would spell
/// a number and lose a replacement list entirely, and the Mac would read its own setting back
/// as a different setting.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        // The order is the whole of the correctness here. `true` is not 1 in JSON, so bool is
        // asked first; a whole number is asked before a fractional one, or a ceiling of 5 goes
        // back to the Mac as 5.0. The last case cannot throw in practice: these are all of JSON.
        if box.decodeNil() {
            self = .null
        } else if let flag = try? box.decode(Bool.self) {
            self = .bool(flag)
        } else if let whole = try? box.decode(Int.self) {
            self = .int(whole)
        } else if let number = try? box.decode(Double.self) {
            self = .double(number)
        } else if let text = try? box.decode(String.self) {
            self = .string(text)
        } else if let list = try? box.decode([JSONValue].self) {
            self = .array(list)
        } else {
            self = .object(try box.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let text): try box.encode(text)
        case .int(let whole): try box.encode(whole)
        case .double(let number): try box.encode(number)
        case .bool(let flag): try box.encode(flag)
        case .array(let list): try box.encode(list)
        case .object(let fields): try box.encode(fields)
        case .null: try box.encodeNil()
        }
    }

    /// What a text box shows. Everything scalar spells itself, because a field whose kind this
    /// phone has never heard of is drawn as text and still has to show what is in it.
    public var text: String {
        switch self {
        case .string(let text): text
        case .int(let whole): String(whole)
        case .double(let number): String(number)
        case .bool(let flag): flag ? "true" : "false"
        default: ""
        }
    }

    public var flag: Bool {
        switch self {
        case .bool(let flag): flag
        case .int(let whole): whole != 0
        case .string(let text): text == "true"
        default: false
        }
    }

    public var number: Double {
        switch self {
        case .int(let whole): Double(whole)
        case .double(let number): number
        case .string(let text): Double(text) ?? 0
        default: 0
        }
    }

    /// A replacement list as rows of two. Anything that is not a pair is dropped rather than
    /// padded: the editor can only show a row it can put back, and half a row written back to
    /// the Mac is a silent edit of somebody's word list.
    public var rows: [[String]] {
        guard case .array(let list) = self else { return [] }
        return list.compactMap { item in
            guard case .array(let pair) = item, pair.count == 2 else { return nil }
            return [pair[0].text, pair[1].text]
        }
    }

    /// Back the other way, for the pairs editor.
    public static func rows(_ rows: [[String]]) -> JSONValue {
        .array(rows.map { row in .array(row.map { .string($0) }) })
    }

    /// What a number box holds, in the shape the Mac wrote it in: a whole number stays whole.
    public static func number(_ typed: String) -> JSONValue {
        if let whole = Int(typed) { return .int(whole) }
        return .double(Double(typed) ?? 0)
    }
}

/// One setting a filter takes, described well enough for the phone to draw a control for it.
public struct FilterField: Codable, Hashable, Sendable, Identifiable {
    /// What to draw. A Mac a version ahead can name a kind this phone has never heard of, and
    /// the decoder reads that as `text` — a box showing the value is a worse control than the
    /// right one and a far better answer than a settings screen that fails to decode.
    public enum Kind: String, Codable, Sendable {
        case text, bool, number, pairs
    }

    public let key: String
    public let label: String
    public let kind: Kind
    /// What the field holds until somebody sets it. `default` on the wire, which is a keyword.
    public let defaultValue: JSONValue
    public let hint: String

    public var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, kind, hint
        case defaultValue = "default"
    }

    public init(
        key: String,
        label: String,
        kind: Kind = .text,
        defaultValue: JSONValue = .string(""),
        hint: String = ""
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.defaultValue = defaultValue
        self.hint = hint
    }

    /// Tolerant like everything else off this wire — the Mac and the phone are updated
    /// separately and are routinely a version apart. A field with no label is labelled with its
    /// own key, which is ugly and readable, rather than blank.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        key = try box.decodeIfPresent(String.self, forKey: .key) ?? ""
        label = try box.decodeIfPresent(String.self, forKey: .label) ?? key
        kind = Kind(rawValue: try box.decodeIfPresent(String.self, forKey: .kind) ?? "") ?? .text
        defaultValue = try box.decodeIfPresent(JSONValue.self, forKey: .defaultValue) ?? .string("")
        hint = try box.decodeIfPresent(String.self, forKey: .hint) ?? ""
    }
}

/// A step the Mac can run, and enough about it that nothing here has to know what it is.
public struct Filter: Codable, Hashable, Sendable, Identifiable {
    public let name: String
    public let title: String
    public let summary: String
    public let fields: [FilterField]

    public var id: String { name }

    public init(name: String, title: String, summary: String = "", fields: [FilterField] = []) {
        self.name = name
        self.title = title
        self.summary = summary
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? ""
        title = try box.decodeIfPresent(String.self, forKey: .title) ?? name
        summary = try box.decodeIfPresent(String.self, forKey: .summary) ?? ""
        fields = try box.decodeIfPresent([FilterField].self, forKey: .fields) ?? []
    }
}

/// One place in the chain: which filter, whether it runs, and what the person set on it.
///
/// Identified by the filter it names, so the chain holds each filter once. That is what the
/// settings screen can edit — a switch and a position per filter — and running the same filter
/// twice with two settings is not a thing anybody has asked for.
public struct FilterStep: Codable, Hashable, Sendable, Identifiable {
    public let filter: String
    public var isOn: Bool
    /// Only what was actually set. The Mac merges its own defaults over the top, so sending the
    /// merged set instead would freeze today's defaults into the person's saved chain.
    public var settings: [String: JSONValue]

    public var id: String { filter }

    enum CodingKeys: String, CodingKey {
        case filter, settings
        case isOn = "on"
    }

    public init(filter: String, isOn: Bool = true, settings: [String: JSONValue] = [:]) {
        self.filter = filter
        self.isOn = isOn
        self.settings = settings
    }

    /// A step written down with no switch is a step that runs: it is in the chain, which is the
    /// only reason for it to be written down at all.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        filter = try box.decodeIfPresent(String.self, forKey: .filter) ?? ""
        isOn = try box.decodeIfPresent(Bool.self, forKey: .isOn) ?? true
        settings = try box.decodeIfPresent([String: JSONValue].self, forKey: .settings) ?? [:]
    }
}

public extension FilterStep {
    /// The chain as a screen needs it: the saved steps in the order they run, then every filter
    /// the Mac offers that nobody has put in one yet, off.
    ///
    /// A step naming a filter the Mac no longer offers stays where it is rather than being
    /// dropped. Dropping it would be the phone quietly deleting a setting it cannot draw — which
    /// is what an app one version behind its Mac would do to every filter added since.
    static func chain(_ steps: [FilterStep], over known: [Filter]) -> [FilterStep] {
        let named = Set(steps.map(\.filter))
        return steps + known
            .filter { !named.contains($0.name) }
            .map { FilterStep(filter: $0.name, isOn: false) }
    }
}

/// What `GET /filters` answers with: everything this Mac can do, and the chain it is running.
struct FilterOffer: Decodable {
    var known: [Filter] = []
    var steps: [FilterStep] = []

    /// Spelled out because nothing here is synthesised: with the decoder written by hand and no
    /// encode side, the compiler has no reason to work these out for itself.
    enum CodingKeys: String, CodingKey {
        case known, steps
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        known = try box.decodeIfPresent([Filter].self, forKey: .known) ?? []
        steps = try box.decodeIfPresent([FilterStep].self, forKey: .steps) ?? []
    }
}

/// What a save sends, and what comes back from it. The chain and nothing else.
struct FilterChain: Codable {
    var steps: [FilterStep] = []

    init(steps: [FilterStep]) {
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        steps = try box.decodeIfPresent([FilterStep].self, forKey: .steps) ?? []
    }
}
