import DeckhandKit
import SwiftUI

/// The page this session is waiting on an answer for, at the top of its summary.
///
/// A page with no answer file beside it is a session that has stopped and is waiting on a person,
/// and until now the only way to find out was to open the page tab and look. So it is said on the
/// first screen of the session instead, as the one thing on it you press.
///
/// Straight to the page rather than to the tab that lists them: the tap is for answering, and a
/// list with one unanswered page in it is a step that exists only to be got past. The newest one
/// when several are open — the Mac sorts them newest first, and the newest is the one the agent
/// was talking about when it said there was something on your phone. The rest are a count, so
/// nothing is hidden and the summary is not five bars deep.
///
/// It looks pressable on purpose. The filled capsule is the shape `FilesView` uses for the thing
/// you choose, not the badge shape this app has banned: that ban is on a capsule that only
/// reports state while sitting next to things you can actually press, and this is the press.
struct WaitingPage: View {
    @Bindable var model: AppModel
    let session: Session
    /// The page the tap opens.
    let artifact: Artifact
    /// How many more are waiting behind it.
    let more: Int
    @State private var open = false
    /// This row's own recorder, lent to the viewer so a passage can be commented on and the page's
    /// own fields can be spoken into. Owned here — the thing that presents the cover — because a
    /// recorder has to outlive the clip and a cover's content does not outlive much. The session
    /// page's own recorder is four hops up through a summary, which is the threading `AssetView`
    /// already declined for the same reason.
    @State private var recorder = Recorder()
    /// The page's own accent, so this goes utt orange with the rest of the screen while the mark
    /// at the foot of it is open.
    @Environment(\.accent) private var accent

    /// The minimum a finger can be asked to hit, as `FilesView` spells it: no spacing token
    /// means "a finger", and rounding it to the nearest step either lies or overshoots.
    private static let target: CGFloat = 44

    var body: some View {
        Button { open = true } label: { face }
            .buttonStyle(.plain)
            .accessibilityIdentifier("waiting-page")
            .accessibilityLabel(spoken)
            // A cover rather than a sheet, and for the reasons the page tab uses one: a sheet
            // keeps a grabber, a corner radius and an inch of this page behind it, and all three
            // are the chrome the viewer is meant not to have. Answering is what makes this
            // disappear, so the listing is read again on the way back.
            .fullScreenCover(isPresented: $open, onDismiss: reread) {
                ArtifactView(model: model,
                             session: session,
                             artifact: artifact,
                             say: Dictation(recorder: recorder,
                                            mode: model.preferences.talkMode,
                                            words: { await model.dictated($0, for: session) }))
            }
    }

    private var face: some View {
        HStack(spacing: Spacing.extraSmall) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 15, weight: .medium))
            // The verb, then the page's own title: "Answer" is what makes it plainly a thing to
            // press rather than a line reporting that something exists somewhere else.
            Text("Answer “\(artifact.title)”")
                .lineLimit(1)
                .truncationMode(.tail)
            if more > 0 {
                Text("\(more) more")
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            Spacer(minLength: Spacing.extraSmall)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
        }
        .font(Typography.primaryRow)
        .foregroundStyle(Color.white)
        .padding(.horizontal, Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: Self.target)
        .background(Capsule().fill(accent))
        .contentShape(.rect)
    }

    private var spoken: String {
        let one = "Answer \(artifact.title), waiting on you"
        return more > 0 ? "\(one). \(more) more waiting" : one
    }

    private func reread() {
        Task { await model.loadArtifacts(for: session) }
    }
}
