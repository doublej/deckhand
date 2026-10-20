import Foundation
import Testing

@testable import DeckhandKit

/// Connected folders. An `extension ClientTests` for `ClientTests+Aliases.swift`'s reason.
extension ClientTests {
    @Test("a project's folders and suggestions come back, and a Mac that names none means none")
    func decodesFolders() async throws {
        StubProtocol.respond(with: Data(#"{"path":"/p","folders":["/r"],"suggested":["/o"]}"#.utf8))
        let found = try await client().folders(of: "s1")
        #expect(found == ConnectedFolders(folders: ["/r"], suggested: ["/o"]))
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/s1/folders")
        StubProtocol.respond(with: Data(#"{}"#.utf8))
        #expect(try await client().folders(of: "s1") == ConnectedFolders())
    }

    @Test("connecting a folder sends the whole list and keeps the Mac's reading of it")
    func savesFolders() async throws {
        StubProtocol.respond(with: Data(#"{"folders":["/private/tmp/r"],"suggested":[]}"#.utf8))
        let kept = try await client().saveFolders(["/tmp/r"], of: "s1")
        #expect(kept.folders == ["/private/tmp/r"])
        #expect(StubProtocol.lastRequest?.httpMethod == "PUT")
        let body = try #require(StubProtocol.lastBody)
        #expect(String(bytes: body, encoding: .utf8)?.contains(#""folders""#) == true)
    }

    @Test("a file from a connected folder says which one, and one the transcript named does not")
    func decodesConnectedAsset() async throws {
        StubProtocol.respond(with: Data(#"""
        {"files":[{"path":"/r/a.png","name":"a.png","kind":"image","size":3,"modified":1,"connected":"/r"},
                  {"path":"/p/b.md","name":"b.md","kind":"text","size":3,"modified":1}]}
        """#.utf8))
        let found = try await client().files(of: "s1")
        #expect(found.map(\.connected) == ["/r", nil])
    }
}
