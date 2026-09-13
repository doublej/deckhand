import DeckhandKit
import SwiftUI

/// A sound file a session made, open: play or pause, where it has got to, and how long it is.
///
/// It drives ``ClipPlayer``, which is why it lives beside it. A `VideoPlayer` over an `AVPlayer`
/// would have drawn a transport for free, and it was not worth what it costs: a second audio
/// stack to leave sounding behind a closed screen, a black rectangle where a film would be, and
/// playback through the earpiece for the reason written on `ClipPlayer.play`.
///
/// It starts on its own, because opening a sound file is asking to hear it — the file has already
/// been fetched by the time this is drawn, so there is nothing else the sheet could be waiting for.
///
/// The clock is this view's own ten-a-second read rather than something the player publishes:
/// `AVAudioPlayer.currentTime` is the only truth about where a sound is and nothing else on the
/// phone wants to watch it. It stands still while a finger is on the slider, or the scrub would
/// be dragged back out from under it.
struct Listening: View {
    let file: URL
    @State private var player = ClipPlayer()
    @State private var reached: TimeInterval = 0
    @State private var scrubbing = false

    private var sounding: Bool { player.playing != nil }

    var body: some View {
        VStack(spacing: Spacing.large) {
            Button { toggle() } label: {
                Image(systemName: sounding ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(Palette.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sounding ? "Pause" : "Play")
            .accessibilityIdentifier("sound-play")
            scrubber
        }
        .padding(Spacing.large)
        .task {
            player.play(file.path, at: file)
            await follow()
        }
        .onDisappear { player.stop() }
    }

    /// Where it is, and the two numbers that say what that means. Monospaced, because a digit
    /// that changes width shoves the whole line about ten times a second.
    private var scrubber: some View {
        VStack(spacing: Spacing.xxs) {
            Slider(value: $reached, in: 0...max(player.duration, 0.1)) { editing in
                scrubbing = editing
                if !editing { player.seek(to: reached) }
            }
            .tint(Palette.tint)
            .accessibilityIdentifier("sound-scrubber")
            HStack {
                Text(said(reached))
                Spacer()
                Text(said(player.duration))
            }
            .font(Typography.mono)
            .foregroundStyle(Palette.textTertiary)
        }
    }

    private func toggle() {
        if sounding { player.pause() } else { player.play(file.path, at: file) }
    }

    /// Minutes and seconds, off Foundation's own pattern rather than arithmetic written here.
    private func said(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }

    /// Cancelled with the view, which is what stops this being a timer somebody has to remember.
    private func follow() async {
        while !Task.isCancelled {
            if !scrubbing { reached = player.elapsed }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
