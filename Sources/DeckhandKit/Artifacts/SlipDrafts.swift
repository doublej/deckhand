import Foundation

/// What was said to a multi-question slip before it was sent.
///
/// `Aloud.said` reads back what the Mac has on file — nothing until Send actually reaches it.
/// Between opening a slip with several questions and finishing it, the person can back out for
/// any reason: the close button, a lock screen, a phone call arriving mid-answer. Losing what
/// was already said over that is the whole bug this exists to fix — a card stack that forgot
/// three answers because a fourth one took a moment longer is worse than no draft at all.
///
/// Keyed by artifact id and kept on the phone only: a draft is what *this* phone has typed or
/// said, not a fact the Mac has any reason to know until it is sent. `AloudCards` is the one
/// place that writes it, on every change, and the one place that clears it — the moment a send
/// actually goes through, because a delivered slip has no draft left to protect.
public struct SlipDrafts: Equatable, Sendable {
    public var byArtifact: [String: [String: String]]
    /// A web slip's draft: whatever the page last handed `window.deckhand.keep`, as the JSON text
    /// of it. Only the page knows its own shape, so it is kept as text and handed back verbatim.
    public var pages: [String: String]

    /// Past this a page is keeping more than an answer, and UserDefaults is no place for it.
    public static let pageLimit = 256 * 1024

    public init(byArtifact: [String: [String: String]] = [:], pages: [String: String] = [:]) {
        self.byArtifact = byArtifact
        self.pages = pages
    }

    /// What was said to one slip, or empty where nothing was.
    public func draft(for artifact: String) -> [String: String] {
        byArtifact[artifact] ?? [:]
    }

    /// Replaces one slip's draft. Blank answers are dropped on the way in, the same rule
    /// `Aloud.value` sends by — and a slip left with nothing worth keeping drops out of the
    /// dictionary entirely rather than sitting in it as an empty entry forever.
    public mutating func set(_ said: [String: String], for artifact: String) {
        let kept = said.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if kept.isEmpty {
            byArtifact.removeValue(forKey: artifact)
        } else {
            byArtifact[artifact] = kept
        }
    }

    /// What a web slip last kept, or `"null"` — the bridge's word for nothing.
    public func page(for artifact: String) -> String { pages[artifact] ?? "null" }

    /// Replaces a web slip's draft. `null` drops it, and so does text over `pageLimit`: a draft
    /// that cannot be kept is no draft, rather than a stale one that reads as the latest.
    public mutating func setPage(_ json: String, for artifact: String) {
        let text = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "null" || text.utf8.count > Self.pageLimit {
            pages.removeValue(forKey: artifact)
        } else {
            pages[artifact] = text
        }
    }

    public mutating func clear(_ artifact: String) {
        byArtifact.removeValue(forKey: artifact)
        pages.removeValue(forKey: artifact)
    }

    // MARK: - storage

    private static let key = "deckhand.slipDrafts"
    private static let pagesKey = "deckhand.pageDrafts"

    public static func load(from defaults: UserDefaults = .standard) -> SlipDrafts {
        let byArtifact = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) }
        let pages = defaults.dictionary(forKey: pagesKey) as? [String: String]
        return SlipDrafts(byArtifact: byArtifact ?? [:], pages: pages ?? [:])
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(byArtifact) { defaults.set(data, forKey: Self.key) }
        defaults.set(pages, forKey: Self.pagesKey)
    }
}
