import Foundation
import Testing

@testable import DeckhandKit

/// The archive is the only thing standing between a failed upload and a lost clip, so what
/// is tested here is mostly the failure side: an entry that exists before anything is attempted,
/// and one that survives every answer the Mac can give.
@Suite("The clip archive")
struct ClipArchiveTests {
    /// Its own folder per test. `ClipArchive` writes files, and two tests sharing a folder would
    /// be two tests reading each other's index.
    private func makeArchive() -> ClipArchive {
        ClipArchive(folder: FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-archive-\(UUID().uuidString)", isDirectory: true))
    }

    /// A clip somewhere else on disk, standing in for the one the recorder just wrote to `tmp`.
    private func makeClip(_ bytes: String = "audio") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorded-\(UUID().uuidString.prefix(8)).m4a")
        try Data(bytes.utf8).write(to: url)
        return url
    }

    /// The whole point. Keeping happens before the upload, so the file has already left `tmp`
    /// by the time anything can throw.
    @Test("keeping a clip moves it out of where it was and files it")
    func keeps() throws {
        let archive = makeArchive()
        let clip = try makeClip()
        let kept = try archive.keep(clip, for: "s1", named: "deckhand")

        #expect(!FileManager.default.fileExists(atPath: clip.path))
        #expect(FileManager.default.fileExists(atPath: archive.url(of: kept).path))
        #expect(archive.clips() == [kept])
        #expect(kept.sessionName == "deckhand")
        // Nothing has been tried yet, which is not the same as something having gone wrong.
        #expect(kept.transcript == nil)
        #expect(kept.isOrphan)
    }

    /// The loss this replaces: the upload throws, the clip used to stay in `tmp` unreferenced.
    @Test("a clip whose upload never answered is still in the list, with the reason on it")
    func survivesAFailedUpload() throws {
        let archive = makeArchive()
        let kept = try archive.keep(try makeClip(), for: "s1", named: "deckhand")

        archive.finish(kept.id, transcript: nil, delivered: false, failure: "Token rejected")

        let listed = try #require(archive.clips().first)
        #expect(listed.failure == "Token rejected")
        #expect(!listed.delivered)
        #expect(FileManager.default.fileExists(atPath: archive.url(of: listed).path))
    }

    /// Words heard once are words heard: a later answer that carries none must not blank them.
    @Test("a transcript survives an answer that has nothing to say about it")
    func keepsTheWords() throws {
        let archive = makeArchive()
        let kept = try archive.keep(try makeClip(), for: "s1", named: "deckhand")

        archive.finish(kept.id, transcript: "fix the build", delivered: false, failure: "no route")
        archive.finish(kept.id, transcript: nil, delivered: false, failure: "still no route")

        #expect(archive.clips().first?.transcript == "fix the build")
    }

    /// What the review card's Send does to the clip its words came from.
    @Test("marking a clip sent clears the reason it had not been")
    func marksSent() throws {
        let archive = makeArchive()
        let kept = try archive.keep(try makeClip(), for: "s1", named: "deckhand")
        archive.finish(kept.id, transcript: "fix the build", delivered: false, failure: "held")

        archive.markSent([kept.id])

        let listed = try #require(archive.clips().first)
        #expect(listed.delivered)
        #expect(listed.failure == nil)
    }

    @Test("the list is newest first, whatever order they were filed in")
    func newestFirst() throws {
        let archive = makeArchive()
        let old = try archive.keep(try makeClip(), for: "s1", named: "one", at: .now - 600)
        let new = try archive.keep(try makeClip(), for: "s1", named: "two", at: .now)

        #expect(archive.clips().map(\.id) == [new.id, old.id])
    }

    /// The stated rule, and the half of it that matters: nothing that failed is ever swept.
    @Test("the sweep drops delivered clips a week old and nothing else")
    func sweeps() throws {
        let archive = makeArchive()
        let long = TimeInterval(ClipArchive.sweptAfterDays * 24 * 60 * 60) + 60
        let said = try archive.keep(try makeClip(), for: "s1", named: "one", at: .now - long)
        let failed = try archive.keep(try makeClip(), for: "s1", named: "two", at: .now - long)
        let fresh = try archive.keep(try makeClip(), for: "s1", named: "three", at: .now)
        archive.markSent([said.id, fresh.id])
        archive.finish(failed.id, transcript: "never arrived", delivered: false, failure: "asleep")

        archive.sweep()

        #expect(Set(archive.clips().map(\.id)) == [failed.id, fresh.id])
        #expect(!FileManager.default.fileExists(atPath: archive.url(of: said).path))
        #expect(FileManager.default.fileExists(atPath: archive.url(of: failed).path))
    }

    @Test("deleting one takes its audio with it and leaves the rest alone")
    func removes() throws {
        let archive = makeArchive()
        let gone = try archive.keep(try makeClip(), for: "s1", named: "one")
        let stays = try archive.keep(try makeClip(), for: "s1", named: "two")

        archive.remove(gone.id)

        #expect(archive.clips().map(\.id) == [stays.id])
        #expect(!FileManager.default.fileExists(atPath: archive.url(of: gone).path))
        #expect(FileManager.default.fileExists(atPath: archive.url(of: stays).path))
    }

    /// A fresh install, and a folder somebody emptied by hand. Neither is an error.
    @Test("an archive with nothing in it answers with nothing rather than failing")
    func emptyIsNotBroken() {
        let archive = makeArchive()
        #expect(archive.clips().isEmpty)
        archive.sweep()
        archive.remove("nothing")
        archive.finish("nothing", transcript: "x", delivered: true, failure: nil)
        #expect(archive.clips().isEmpty)
    }
}
