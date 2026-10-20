import DeckhandKit
import Foundation

/// What this Mac has been set to do, as the phone holds it.
///
/// One document, fetched whole and written whole — the same deal `Filtering` is on, and for the
/// same reason: it is small, a person edits several things at once on one screen, and a partial
/// write would need a merge rule nothing else here has.
///
/// Its own object rather than four more properties on `AppModel`, which sits at its 300-line
/// gate — the same reason `ProjectPicker` exists.
@MainActor
@Observable
final class Switchboard {
    /// Nil until the Mac has answered once. A screen of switches drawn from defaults, before the
    /// Mac has said anything, is a screen showing somebody else's settings as if they were theirs.
    var settings: Settings?
    var loading = false
    /// Which folder is being written, or nil. Per folder rather than a flag, so one project's
    /// spinner does not appear on every row.
    var saving: String?
    /// Why the last write did not land. Kept until the next attempt: it is the only receipt.
    var failed: String?
    /// Every word this Mac swaps on the way out of utt, as rows of two: heard, then meant.
    ///
    /// Here rather than beside the filter chain, because that is what it is: a chain belongs to
    /// one terminal and this list belongs to the Mac. Empty until the Mac has answered, which on
    /// this one is honest — an empty list and an unasked question both swap nothing.
    var aliases: [Alias] = []
    /// Every word utt is told to listen for in every clip. Empty until the Mac has answered.
    var hints: [String] = []

    /// What applies in a folder right now, with nothing from the Mac yet standing in as the
    /// defaults — which are the daemon's own defaults, so the screen is not wrong, only early.
    func here(_ path: String) -> Wants {
        settings?.resolved(for: path) ?? Wants()
    }

    var everywhere: Wants { settings?.everywhere ?? Wants() }
}

@MainActor
extension AppModel {
    /// Read once when a screen of switches opens. Not polled: nothing but this phone changes it.
    func loadSettings() async {
        guard let client = settings.client(), !wants.loading else { return }
        wants.loading = true
        defer { wants.loading = false }
        do {
            wants.settings = try await client.settings()
            wants.failed = nil
        } catch {
            wants.failed = reason(error)
        }
    }

    /// The Mac's word list. Read where a card that might alias one is about to be drawn, and on
    /// the settings page — cheap, and the alternative is a sheet offering to correct a word it
    /// has already been told about.
    func loadAliases() async {
        guard let client = settings.client() else { return }
        guard let list = try? await client.aliases() else { return }
        wants.aliases = list
    }

    /// Replace the list, and keep the Mac's own reading of it: a row with nothing on its left is
    /// dropped and a word aliased twice keeps only the later answer, so what was sent is not
    /// always what is running. A failure leaves the screen showing what the Mac still has.
    func storeAliases(_ list: [Alias]) {
        guard let client = settings.client() else { return }
        Task {
            do {
                wants.aliases = try await client.saveAliases(list)
                wants.failed = nil
            } catch {
                wants.failed = reason(error)
            }
        }
    }

    /// The words utt listens for, read with the aliases and for the same reason.
    func loadHints() async {
        guard let client = settings.client(), let list = try? await client.hints() else { return }
        wants.hints = list
    }

    /// Replace the list, and keep the Mac's own reading of it, as `storeAliases` does.
    func storeHints(_ list: [String]) {
        guard let client = settings.client() else { return }
        Task {
            do {
                wants.hints = try await client.saveHints(list)
                wants.failed = nil
            } catch {
                wants.failed = reason(error)
            }
        }
    }

    /// Every word list a session in this folder hears, outermost first — the CLAUDE.md way: the
    /// global list, then each folder's own down to this one. Nil where the Mac would not say.
    func hintLayers(for session: Session) async -> [HintLayer]? {
        guard let client = settings.client() else { return nil }
        return try? await client.hintLayers(for: session.cwd)
    }

    /// Write back each layer that was edited, and nothing else.
    func storeHintLayers(_ layers: [HintLayer], over before: [HintLayer]) {
        guard let client = settings.client() else { return }
        let edited = layers.filter { !before.contains($0) }
        guard !edited.isEmpty else { return }
        Task {
            do {
                for layer in edited { try await client.saveHints(layer) }
                wants.failed = nil
            } catch {
                wants.failed = reason(error)
            }
        }
    }

    /// Write the whole document and keep what the Mac stored, which is not always what was sent:
    /// a model it does not offer is refused and a folder that overrides nothing is dropped. A
    /// screen that kept its own copy would show settings that are not the Mac's.
    func save(_ document: Settings, for folder: String = "") async {
        guard let client = settings.client() else { return }
        wants.saving = folder
        defer { wants.saving = nil }
        do {
            wants.settings = try await client.saveSettings(document)
            wants.failed = nil
        } catch {
            wants.failed = reason(error)
        }
    }

    /// What the Mac does everywhere, changed and written. The counterpart of `override`, and
    /// the one a folder with no opinion of its own is following.
    func everywhere(_ change: (inout Wants) -> Void) async {
        guard var document = wants.settings else { return }
        change(&document.everywhere)
        await save(document)
    }

    /// One folder's opinion, changed and written. Handed the overrides rather than the whole
    /// document, because every caller of this is a switch on one project's page.
    func override(_ path: String, _ change: (inout Overrides) -> Void) async {
        guard var document = wants.settings else { return }
        var over = document.projects[path] ?? Overrides()
        change(&over)
        // An opinion about nothing is not an opinion. The Mac drops these on write; dropping it
        // here too means the screen agrees with the Mac before the answer comes back.
        if over.isEmpty {
            document.projects.removeValue(forKey: path)
        } else {
            document.projects[path] = over
        }
        await save(document, for: path)
    }
}
