import AVFoundation
import Observation

/// Plays one sound file at a time, so that a clip whose words never arrived is still
/// something a person can get their own words back out of — and so that an audio file a session
/// made is something the phone can listen to rather than only list.
///
/// One at a time on purpose: a list of clips where two can sound at once is a list nobody can
/// tell apart by ear, and starting the next is the commonest way to stop the last.
@MainActor
@Observable
final class ClipPlayer {
    /// Which file is sounding, by the id its caller knows it as, and nil when none is — a pause
    /// included. The rows read this rather than holding a playing flag each, which is how two of
    /// them end up both claiming to be it.
    private(set) var playing: String?

    /// Which file is *held*, which a pause does not change. It is what lets `play` be both verbs:
    /// `AVAudioPlayer.play()` picks up from `currentTime`, so resuming is starting a file the
    /// player is already holding.
    private var held: String?
    private var player: AVAudioPlayer?
    private var ending: Task<Void, Never>?

    /// Where the held file has got to and how long it is, for a transport that draws a scrubber.
    /// Both are zero while nothing is held, which is a slider with nothing to drag.
    var elapsed: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }

    /// The category has to be said. These clips were recorded under `.playAndRecord`, and a
    /// session left in it plays back through the earpiece at a whisper — which reads as a broken
    /// recording rather than as a wrong audio route.
    func play(_ id: String, at url: URL) {
        if held != id {
            stop()
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(contentsOf: url)
            held = player == nil ? nil : id
        }
        guard let player else { return }
        // A file that has played to its end is sitting at its end, and resuming from there sounds
        // nothing at all — so play means from the top again. The tenth of a second is the slack
        // `finish` already waits out: `currentTime` lands just short of `duration`, never on it.
        if player.currentTime >= player.duration - 0.1 { player.currentTime = 0 }
        guard player.play() else { return }
        playing = id
        finish(after: player.duration - player.currentTime)
    }

    /// Where it stopped is kept, so the next `play` of the same id picks up from there.
    func pause() {
        ending?.cancel()
        ending = nil
        player?.pause()
        playing = nil
    }

    /// Somewhere else in the same file. Sounding, it keeps sounding from there, which is why the
    /// wait for the end is started again: the end moved.
    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, seconds), player.duration)
        if playing != nil { finish(after: player.duration - player.currentTime) }
    }

    func stop() {
        ending?.cancel()
        ending = nil
        player?.stop()
        player = nil
        held = nil
        playing = nil
    }

    /// Its own wait rather than `AVAudioPlayerDelegate`, which would drag `NSObject` and a
    /// nonisolated callback into a type that is otherwise five lines. What is left of the file is
    /// exactly when it ends, and stopping, pausing or seeking cancels this before it can fire.
    private func finish(after seconds: TimeInterval) {
        ending?.cancel()
        ending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds + 0.1))
            guard !Task.isCancelled else { return }
            self?.playing = nil
        }
    }
}
