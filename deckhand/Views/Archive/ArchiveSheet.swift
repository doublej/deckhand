import DeckhandKit
import SwiftUI

/// Every clip this phone has recorded, newest first.
///
/// The answer to the one thing this app could genuinely lose. A clip used to exist only in the
/// temporary directory until its upload succeeded, and a transcript only in memory until it was
/// sent — so a Mac asleep, a token refused or a request that timed out took the words with it and
/// left nothing to try again with. `ClipArchive` keeps both; this is where they are read.
///
/// Reached by the press talking does not use — a tap where talking is a hold, a long press where
/// talking is a tap — because a hold of any length is already the recording. See `ReachGesture`.
struct ArchiveSheet: View {
    @Bindable var model: AppModel
    /// Read once on the way in and after every change, rather than watched. The archive is a
    /// folder on disk with one writer, and nothing else on this phone touches it while this is up.
    @State private var clips: [KeptClip] = []
    @State private var player = ClipPlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Clips")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onAppear { clips = model.archive.clips() }
        // Nothing may still be sounding behind a screen that is gone. It is the one piece of this
        // that keeps running on its own, so it is the one piece that has to be told.
        .onDisappear { player.stop() }
    }

    @ViewBuilder private var list: some View {
        if clips.isEmpty {
            empty
        } else {
            List {
                Section(footer: Text(Self.rule).font(Typography.hint)) {
                    ForEach(clips) { kept in row(kept) }
                        .onDelete { spots in spots.map { clips[$0].id }.forEach(drop) }
                }
            }
            .listStyle(.plain)
        }
    }

    /// Said on the screen itself rather than in a settings page nobody opens, because a folder
    /// that empties on its own is only safe if the person knows which half of it does.
    private static let rule = """
        Kept on this phone. A clip whose words reached its session is dropped after \
        \(ClipArchive.sweptAfterDays) days; anything that failed, or that you never sent, stays \
        until you delete it here. A clip interrupted midway is not kept — an unfinished \
        clip is unplayable wherever it is stored.
        """

    private func row(_ kept: KeptClip) -> some View {
        ClipRow(kept: kept,
                isPlaying: player.playing == kept.id,
                sessions: model.visibleSessions,
                play: { listen(to: kept) },
                send: { session in hand(kept, to: session) },
                remove: { drop(kept.id) })
    }

    private var empty: some View {
        ContentUnavailableView(
            "No clips yet",
            systemImage: "waveform",
            description: Text("Every clip you record is kept here until its words reach a session.")
        )
    }

    // MARK: - what the rows do

    private func listen(to kept: KeptClip) {
        if player.playing == kept.id {
            player.stop()
        } else {
            player.play(kept, at: model.archive.url(of: kept))
        }
    }

    /// The words, into a live session, long after the clip they came from failed. The list is read
    /// again because a send that lands clears the sentence saying it had not.
    private func hand(_ kept: KeptClip, to session: Session) {
        Task {
            await model.resend(kept, to: session)
            clips = model.archive.clips()
        }
    }

    /// The only way a clip that was never said leaves this phone, which is why it is a deliberate
    /// swipe or a menu item and not something a stray tap can do.
    private func drop(_ id: String) {
        if player.playing == id { player.stop() }
        model.archive.remove(id)
        clips = model.archive.clips()
    }
}
