import DeckhandKit
import SwiftUI
import UIKit

/// One clip in the archive: what it was for, what was heard, and why it never arrived.
///
/// The words are the row, not a detail behind it. A list of timestamps would make somebody play
/// every clip to find the one they came for, and the whole reason the transcript is kept beside
/// the audio is that reading is faster than listening.
struct ClipRow: View {
    let kept: KeptClip
    let isPlaying: Bool
    /// Every session this phone can see right now, for handing the words to one of them. Live
    /// sessions rather than the one it was recorded for: that one is very often the reason the
    /// clip is in this list, and by now it may not be running at all.
    let sessions: [Session]
    let play: () -> Void
    let send: (Session) -> Void
    /// The clip itself, up to the Mac again. Nil where there is nothing to try: a clip whose
    /// words already reached a session, or one whose audio has gone. Nil rather than a second
    /// flag, so the row cannot draw the menu item and then have nothing behind it.
    let tryAgain: ((Session) -> Void)?
    let remove: () -> Void
    /// Shut, because the breakdown is fourteen numbers and the row is here to be read for its
    /// words. One tap, and only on a clip that has one — a clip from before any of this was
    /// measured shows nothing rather than an empty state.
    @State private var breakdown = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            listen
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                heading
                words
                // The colour is the whole of the difference, as everywhere else in this app: the
                // sentence in the state's own colour, never a label inside a capsule.
                if let failure = kept.failure {
                    Text(failure)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.lcdRed)
                }
                cost
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            more
        }
        .padding(.vertical, Spacing.xxs)
    }

    /// Big enough to hit, and it says which of the two it is doing rather than only what it will
    /// do next — a list where three rows all show a play triangle cannot say which one is audible.
    private var listen: some View {
        Button(action: play) {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 13))
                .foregroundStyle(isPlaying ? Palette.recording : Palette.tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.tileIdle))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop" : "Play this clip")
    }

    private var heading: some View {
        Text("\(kept.sessionName) · \(kept.recordedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(Typography.eyebrow)
            .tracking(1.2)
            .foregroundStyle(Palette.textTertiary)
            .lineLimit(1)
    }

    /// A clip whose words never came back says so, because an empty row reads as a bug. The audio
    /// is still there and still the point — that is what the button to the left is for.
    @ViewBuilder private var words: some View {
        if let transcript = kept.transcript, !transcript.isEmpty {
            Text(transcript)
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(kept.isOrphan ? "Never reached the Mac — the clip is still here"
                               : "No words came back")
                .font(Typography.prose)
                .italic()
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// What the clip cost, one tap under the words it produced. The total is the resting state
    /// because it is the one number worth glancing at; the stages are what you open when the
    /// total is worse than it should be.
    @ViewBuilder private var cost: some View {
        if let timing = kept.timings {
            Button { breakdown.toggle() } label: {
                HStack(spacing: Spacing.xxs) {
                    Text(TimingsView.spelled(timing.total))
                    if let slowest = timing.slowest, !breakdown {
                        Text("· \(slowest.title.lowercased()) \(TimingsView.spelled(slowest.took))")
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Image(systemName: breakdown ? "chevron.up" : "chevron.down")
                }
                .font(Typography.hint)
                .foregroundStyle(Palette.tint)
                .frame(minHeight: 28, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What this clip cost, stage by stage")
            if breakdown {
                TimingsView(timing: timing, compact: true)
                    .padding(.top, Spacing.xxs)
            }
        }
    }

    /// Everything you can do with a clip that was said to nobody. Copying is first because it is
    /// the one that works with the Mac switched off.
    ///
    /// Only the first two need words. Trying the clip again does not — a clip with no words is
    /// the one it is for — so it sits outside that check, which is where it used to be trapped.
    private var more: some View {
        Menu {
            if let transcript = kept.transcript {
                Button("Copy the words") { UIPasteboard.general.string = transcript }
                sending
            }
            trying
            Button("Delete", systemImage: "trash", role: .destructive, action: remove)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .accessibilityLabel("What to do with this clip")
    }

    /// Into any session that is running, not only the one it was recorded for. A menu with
    /// nothing in it is worse than no menu, so with nothing live there is nothing to open.
    @ViewBuilder private var sending: some View {
        if !sessions.isEmpty {
            Menu("Send to…") {
                ForEach(sessions) { session in
                    Button(session.name) { send(session) }
                }
            }
        }
    }

    /// The audio back up to the Mac, to be heard afresh. The same shape as `sending` and empty
    /// under the same rule, because the choice being made is the same one: which live session.
    @ViewBuilder private var trying: some View {
        if let tryAgain, !sessions.isEmpty {
            Menu("Try again on…") {
                ForEach(sessions) { session in
                    Button(session.name) { tryAgain(session) }
                }
            }
        }
    }
}
