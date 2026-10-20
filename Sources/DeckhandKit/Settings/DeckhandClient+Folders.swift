import Foundation

/// The folders connected to a session's project — `daemon/…/settings/folders.py`.
///
/// A session that renders into a temp folder names the folder and none of the frames, so the
/// files tab never sees them. Connecting the folder is the person's choice, made here, and it is
/// what lets the Mac list and serve what is inside it.
public extension DeckhandClient {
    /// What is connected to this session's project, and the folders it wrote into that are not.
    func folders(of sessionId: String) async throws -> ConnectedFolders {
        try await get("sessions/\(sessionId)/folders")
    }

    /// Replace the project's folders whole, and take back the Mac's reading of them: a relative
    /// path, the disk's root and the home folder are dropped, and every path comes back resolved.
    @discardableResult
    func saveFolders(_ folders: [String], of sessionId: String) async throws -> ConnectedFolders {
        var req = request(.put, "sessions/\(sessionId)/folders")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(["folders": folders])
        return try decode(try await send(req, body: body))
    }
}

/// Tolerant on the way in: a missing key is nothing connected and nothing to suggest.
public struct ConnectedFolders: Decodable, Equatable, Sendable {
    public var folders: [String] = []
    public var suggested: [String] = []

    public init(folders: [String] = [], suggested: [String] = []) {
        self.folders = folders
        self.suggested = suggested
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        folders = try box.decodeIfPresent([String].self, forKey: .folders) ?? []
        suggested = try box.decodeIfPresent([String].self, forKey: .suggested) ?? []
    }

    private enum CodingKeys: String, CodingKey { case folders, suggested }
}
