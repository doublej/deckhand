import Foundation

/// One clip this phone recorded, and what became of it.
///
/// Everything on it is written before it could be lost: the entry exists from the moment the clip
/// stops recording, and the words and the outcome are laid onto it as they arrive. A clip the Mac
/// never answered for is still an entry — it simply has no transcript yet.
public struct KeptClip: Codable, Hashable, Identifiable, Sendable {
    /// The clip's own file name inside the archive. It is the id because it is already unique and
    /// already the thing the audio is found by; a second field could only disagree with it.
    public let id: String
    public let recordedAt: Date
    public let sessionId: String
    /// Who it was recorded for, under the name that session went by then. Names change and
    /// sessions end, and this list has to say something months later either way.
    public let sessionName: String
    /// What the Mac heard, once it has been asked. Nil while nothing has reached a Mac at all —
    /// which is exactly the case this archive exists for.
    public var transcript: String?
    /// Whether those words actually landed in the session. `Delivery.went`, never `delivered` on
    /// its own: a filter's refusal is a deliberate no and not a delivery failure.
    public var delivered = false
    /// Why they did not, in whatever words the failure arrived in. Nil while nothing has gone
    /// wrong, which is not the same as nil while nothing has been tried.
    public var failure: String?

    public init(id: String, recordedAt: Date, sessionId: String, sessionName: String) {
        self.id = id
        self.recordedAt = recordedAt
        self.sessionId = sessionId
        self.sessionName = sessionName
    }

    /// Nothing reached the session and nothing said why. A clip whose upload never came back at
    /// all reads as this, and it is worth telling apart from a refusal that was explained.
    public var isOrphan: Bool { !delivered && failure == nil }
}

/// Every clip this phone has recorded, on disk, with a small index beside it.
///
/// It exists because a clip used to live in the temporary directory until its upload succeeded.
/// The upload ran inside a block that swallows a throw, so a sleeping Mac, a rejected token or a
/// timeout left the file sitting in `tmp` with nothing referencing it and the words nowhere at
/// all. The clip is therefore moved in here *before* the upload is attempted, and every outcome
/// is written back onto its entry — kept whether or not anything reached a session.
///
/// A crash *while a clip is still being recorded* is not covered, and cannot be by any archive:
/// AAC writes its index when the recorder stops, so a clip cut off mid-write is unplayable bytes
/// wherever those bytes happen to be.
///
/// No state of its own beyond the folder, so it is `Sendable` without a lock: every call reads the
/// index, changes it and writes it back atomically. The index is a handful of entries, and one
/// person's thumb is the only thing that ever writes it.
public struct ClipArchive: Sendable {
    /// How long a clip that actually reached its session is kept before `sweep` drops it. Anything
    /// that failed, or was never sent anywhere, is never swept — losing that is the whole thing
    /// this exists to prevent, and no number of days makes it safe to guess.
    public static let sweptAfterDays = 7

    public let folder: URL

    /// Application Support rather than the caches directory, which iOS is free to empty under
    /// pressure — the one thing this must not be is a place clips can quietly leave.
    public init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Deckhand/Clips", isDirectory: true)
    }

    private var index: URL { folder.appendingPathComponent("clips.json") }

    // MARK: - reading

    /// Newest first, which is the order somebody looking for what they just lost wants it in.
    public func clips() -> [KeptClip] {
        guard let data = try? Data(contentsOf: index),
              let kept = try? JSONDecoder().decode([KeptClip].self, from: data) else { return [] }
        return kept.sorted { $0.recordedAt > $1.recordedAt }
    }

    public func url(of kept: KeptClip) -> URL {
        folder.appendingPathComponent(kept.id)
    }

    // MARK: - writing

    /// Moves the clip in and files an entry for it. Called before the upload, never after: the
    /// point of the whole type is that there is no window in which the only copy is in `tmp`.
    ///
    /// The name carries the second it was recorded, so the folder reads in order on its own, and a
    /// short random tail, so two clips in the same second cannot collide.
    public func keep(_ clip: URL,
                     for sessionId: String,
                     named: String,
                     at when: Date = .now) throws -> KeptClip {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tail = clip.pathExtension.isEmpty ? "m4a" : clip.pathExtension
        let name = "\(Int(when.timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).\(tail)"
        try FileManager.default.moveItem(at: clip, to: folder.appendingPathComponent(name))
        let kept = KeptClip(id: name, recordedAt: when, sessionId: sessionId, sessionName: named)
        write([kept] + clips())
        return kept
    }

    /// What the Mac made of it. Written on every answer, the failed ones included — a transcript
    /// that arrived and then could not be delivered is the case this list exists for.
    ///
    /// The transcript is never cleared by a later answer: words heard once are words heard.
    public func finish(_ id: String, transcript: String?, delivered: Bool, failure: String?) {
        change(id) { kept in
            kept.transcript = transcript ?? kept.transcript
            kept.delivered = delivered
            kept.failure = failure
        }
    }

    /// The words reached the session after all — sent from the review card, or handed to a session
    /// by hand out of this archive long afterwards. Both clear the failure with it: the sentence
    /// said why it had not arrived, and now it has.
    public func markSent(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var all = clips()
        for spot in all.indices where ids.contains(all[spot].id) {
            all[spot].delivered = true
            all[spot].failure = nil
        }
        write(all)
    }

    /// By hand, and the only way a clip that was never said leaves. The audio goes with it.
    public func remove(_ id: String) {
        let all = clips()
        guard let gone = all.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: url(of: gone))
        write(all.filter { $0.id != id })
    }

    /// Drops what was actually said and is now a week old, and nothing else. Stated on the archive
    /// screen itself, because a folder that empties on its own has to say so somewhere a person
    /// will read it before they come to rely on it.
    public func sweep(_ now: Date = .now) {
        let all = clips()
        let age = TimeInterval(Self.sweptAfterDays * 24 * 60 * 60)
        let stale = all.filter { $0.delivered && now.timeIntervalSince($0.recordedAt) > age }
        guard !stale.isEmpty else { return }
        for old in stale { try? FileManager.default.removeItem(at: url(of: old)) }
        let ids = Set(stale.map(\.id))
        write(all.filter { !ids.contains($0.id) })
    }

    // MARK: - the index

    private func change(_ id: String, _ edit: (inout KeptClip) -> Void) {
        var all = clips()
        guard let spot = all.firstIndex(where: { $0.id == id }) else { return }
        edit(&all[spot])
        write(all)
    }

    /// Atomic, because the alternative is a half-written index — and an index this cannot read is
    /// every clip on this phone gone from the list at once.
    private func write(_ all: [KeptClip]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: index, options: .atomic)
    }
}
