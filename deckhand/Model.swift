import DeckhandKit
import Foundation
import Observation

/// Everything the screens read: the server it talks to, the sessions it found, what they said.
@MainActor
@Observable
final class AppModel {
    var settings: ServerSettings
    var sessions: [Session] = []
    var turns: [Turn] = []
    var status: String?
    var lastReceipt: UploadReceipt?

    init(settings: ServerSettings = .load()) {
        self.settings = settings
        // Launch arguments (`-deckhand.host`, `-deckhand.token`) land in the same defaults,
        // so an install that was handed the pairing details keeps them after a cold start.
        if settings.isComplete { settings.save() }
    }

    var isConfigured: Bool { settings.isComplete }

    func saveSettings() {
        settings.save()
        status = nil
    }

    func refreshSessions() async {
        guard let client = settings.client() else {
            status = "Set the Mac's address and token first"
            return
        }
        await run { self.sessions = try await client.sessions() }
    }

    func loadTurns(for session: Session, limit: Int = 8) async {
        guard let client = settings.client() else { return }
        await run { self.turns = try await client.turns(of: session.sessionId, limit: limit) }
    }

    func focus(_ session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            try await client.focus(session.sessionId)
            self.status = "Focused \(session.name) on the Mac"
        }
    }

    func upload(clip: URL, to session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            let receipt = try await client.upload(clip: clip, to: session.sessionId)
            self.lastReceipt = receipt
            self.status = "Sent \(receipt.bytes / 1024) KB to the Mac"
            try? FileManager.default.removeItem(at: clip)
        }
    }

    /// Reports what the Mac answered, for the settings screen.
    func checkConnection() async {
        guard let client = settings.client() else {
            status = "Address or token missing"
            return
        }
        await run {
            let health = try await client.health()
            self.status = "\(health.name) \(health.version) at \(health.host)"
        }
    }

    private func run(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch let error as DeckhandError {
            status = describe(error)
        } catch {
            status = error.localizedDescription
        }
    }

    private func describe(_ error: DeckhandError) -> String {
        switch error {
        case .unauthorized: "Token rejected by the Mac"
        case .notLive: "That session is no longer running"
        case .http(let code, let body): "Mac said \(code): \(body.prefix(120))"
        case .badResponse: "Unreadable answer from the Mac"
        }
    }
}
