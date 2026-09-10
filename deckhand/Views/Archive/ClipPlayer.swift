import AVFoundation
import DeckhandKit
import Observation

/// Plays one archived clip at a time, so that a clip whose words never arrived is still
/// something a person can get their own words back out of.
///
/// One at a time on purpose: a list of clips where two can sound at once is a list nobody can
/// tell apart by ear, and starting the next is the commonest way to stop the last.
@MainActor
@Observable
final class ClipPlayer {
    /// Which clip is sounding, by its id, and nil when none is. The rows read this rather than
    /// holding a playing flag each, which is how two of them end up both claiming to be it.
    private(set) var playing: String?

    private var player: AVAudioPlayer?
    private var ending: Task<Void, Never>?

    /// The category has to be said. These clips were recorded under `.playAndRecord`, and a
    /// session left in it plays back through the earpiece at a whisper — which reads as a broken
    /// recording rather than as a wrong audio route.
    func play(_ kept: KeptClip, at url: URL) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let made = try? AVAudioPlayer(contentsOf: url), made.play() else { return }
        player = made
        playing = kept.id
        finish(after: made.duration)
    }

    func stop() {
        ending?.cancel()
        ending = nil
        player?.stop()
        player = nil
        playing = nil
    }

    /// Its own wait rather than `AVAudioPlayerDelegate`, which would drag `NSObject` and a
    /// nonisolated callback into a type that is otherwise five lines. The clip's own duration is
    /// exactly when it ends, and stopping early cancels this before it can fire.
    private func finish(after seconds: TimeInterval) {
        ending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds + 0.1))
            guard !Task.isCancelled else { return }
            self?.playing = nil
        }
    }
}
