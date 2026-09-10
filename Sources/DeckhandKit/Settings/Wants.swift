import Foundation

/// What this Mac has been set to do — everywhere, and in one folder where they differ.
///
/// Four things on the Mac act without being asked, and each is one switch. Three of them put
/// something on this phone; the fourth talks to a session instead, which is exactly why it is
/// listed beside them rather than hidden as an implementation detail of the daemon.
public struct Wants: Codable, Hashable, Sendable {
    /// A session there stopped and is waiting on you.
    public var finished: Bool
    /// A slip written there has not been answered.
    public var slips: Bool
    /// An agent there asked for you outright, in its own words.
    public var called: Bool
    /// The idle check may ask a session there about the asks still open on its list. Not a
    /// notification: the Mac speaking to a session. It is here because it is the other thing
    /// that happens on its own, and a screen of switches that hid it would be lying by omission.
    public var chase: Bool
    /// The summariser may read what that folder's subagents did, not only what the session said.
    public var subagents: Bool
    /// What a session started there runs on. Empty is Claude Code's own default.
    public var sessionModel: String
    /// What writes the briefings there. Empty is whatever the Mac's prompt file says.
    public var summaryModel: String

    public init(finished: Bool = true, slips: Bool = true, called: Bool = true,
                chase: Bool = true, subagents: Bool = false,
                sessionModel: String = "", summaryModel: String = "") {
        self.finished = finished
        self.slips = slips
        self.called = called
        self.chase = chase
        self.subagents = subagents
        self.sessionModel = sessionModel
        self.summaryModel = summaryModel
    }

    /// Spelled out, and this is the whole reason `Settings` decodes without a key strategy: see
    /// the note on `DeckhandClient.settings()`. Two names on this wire are snake case and the
    /// converter that would fix them for free would silently break something far worse.
    enum CodingKeys: String, CodingKey {
        case finished, slips, called, chase, subagents
        case sessionModel = "session_model"
        case summaryModel = "summary_model"
    }
}

/// What one folder says for itself. Every field optional, because `nil` is the answer that
/// matters here — it means "no opinion", and a folder with no opinion follows the Mac and goes
/// on following it when the Mac's answer changes.
public struct Overrides: Codable, Hashable, Sendable {
    public var finished: Bool?
    public var slips: Bool?
    public var called: Bool?
    public var chase: Bool?
    public var subagents: Bool?
    public var sessionModel: String?
    public var summaryModel: String?

    public init() {}

    /// Nothing overridden. The Mac drops one of these rather than storing it, so the phone must
    /// not draw a folder as "configured" on the strength of an empty object.
    public var isEmpty: Bool {
        finished == nil && slips == nil && called == nil && chase == nil
            && subagents == nil && sessionModel == nil && summaryModel == nil
    }

    enum CodingKeys: String, CodingKey {
        case finished, slips, called, chase, subagents
        case sessionModel = "session_model"
        case summaryModel = "summary_model"
    }
}

/// The whole document: what holds everywhere, what each folder says for itself, and the models
/// this Mac will accept. The offers come from the Mac rather than a list in the app — a phone
/// offering a model the daemon refuses is a picker that writes settings which do not stick.
public struct Settings: Codable, Sendable {
    public var everywhere: Wants
    public var projects: [String: Overrides]
    public var offers: Offers

    public struct Offers: Codable, Sendable {
        public var session: [String]
        public var summary: [String]

        public init(session: [String] = [], summary: [String] = []) {
            self.session = session
            self.summary = summary
        }
    }

    public init(everywhere: Wants = Wants(),
                projects: [String: Overrides] = [:],
                offers: Offers = Offers()) {
        self.everywhere = everywhere
        self.projects = projects
        self.offers = offers
    }

    enum CodingKeys: String, CodingKey { case projects, offers }

    /// The global answers are at the top level of the same object rather than nested under a
    /// key, so they are decoded from this decoder directly. It reads oddly and it is what keeps
    /// the document one flat thing on the wire, which is what a person editing it sees.
    public init(from decoder: Decoder) throws {
        everywhere = try Wants(from: decoder)
        let box = try decoder.container(keyedBy: CodingKeys.self)
        projects = try box.decodeIfPresent([String: Overrides].self, forKey: .projects) ?? [:]
        offers = try box.decodeIfPresent(Offers.self, forKey: .offers) ?? Offers()
    }

    public func encode(to encoder: Encoder) throws {
        try everywhere.encode(to: encoder)
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(projects, forKey: .projects)
    }

    /// What actually applies in one folder: the global answers with that folder's own laid over
    /// them, per key. The Mac answers the same question at `/settings/project`, and this has to
    /// agree with it — two answers to one question is how they come apart, so the rule is
    /// written once here and read from the Mac wherever the Mac is the one acting on it.
    public func resolved(for path: String) -> Wants {
        guard let over = projects[path] else { return everywhere }
        var here = everywhere
        if let value = over.finished { here.finished = value }
        if let value = over.slips { here.slips = value }
        if let value = over.called { here.called = value }
        if let value = over.chase { here.chase = value }
        if let value = over.subagents { here.subagents = value }
        if let value = over.sessionModel { here.sessionModel = value }
        if let value = over.summaryModel { here.summaryModel = value }
        return here
    }

    /// Whether this folder has an opinion of its own about anything.
    public func overridden(_ path: String) -> Bool {
        !(projects[path]?.isEmpty ?? true)
    }
}
