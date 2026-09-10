import DeckhandKit
import SwiftUI

/// What this session has put on your phone: the questions it could not ask in a sentence.
///
/// The pages live in the project rather than with the session — `.deckhand/artifacts/` beside
/// the code — so they outlive the session that wrote one, and a second session working in the
/// same folder finds the first one's work. That is why this is a listing of a folder on the Mac
/// and not a thing the app keeps.
struct ArtifactsView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var open: Artifact?
    /// Which of them to show. Not remembered across opening the tab: what you want to see is
    /// decided by what has happened since you last looked, not by what you picked last time.
    @State private var show: Show = .all
    /// This listing's own recorder, lent to the viewer so a passage can be commented on and a page's
    /// own fields can be spoken into.
    ///
    /// Here rather than inside the cover, and that is the whole reason it is a `@State` on the
    /// presenter: a `.fullScreenCover(item:)`'s content is built and torn down in ways this view is
    /// not, and the one invariant a recorder has is that it outlives the clip. `AssetView` owns one
    /// for the same reason — this is the same shape, one hop shorter.
    @State private var recorder = Recorder()
    /// A tab inside the session's page, so its marks go orange with the rest of it.
    @Environment(\.accent) private var accent

    /// The minimum a finger can be asked to hit. Same raw number `FilesView` writes, for the
    /// same reason: no spacing token means "a finger".
    private static let target: CGFloat = 44

    /// Waiting or answered, and all of them. Answered is a real thing to want to see — it is
    /// what you said, and the page still holds the question you said it about.
    private enum Show: String, CaseIterable, Identifiable {
        case all = "All", waiting = "Waiting", answered = "Answered"
        var id: Self { self }
    }

    private var artifacts: [Artifact] { model.artifacts[session.sessionId] ?? [] }
    private var waiting: [Artifact] { artifacts.filter { !$0.answered } }
    private var answered: [Artifact] { artifacts.filter(\.answered) }

    private var shown: [Artifact] {
        switch show {
        case .all: artifacts
        case .waiting: waiting
        case .answered: answered
        }
    }

    /// One choice is not a choice. With every page in the same state the row would be furniture,
    /// and the rows below already say which state that is.
    private var mixed: Bool { !waiting.isEmpty && !answered.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Above the scroll view rather than in it, so it is still there after you have
            // scrolled past a dozen answered pages looking for the one that is not.
            if mixed { selector }
            list
        }
        .frame(maxHeight: .infinity)
        .task { await model.loadArtifacts(for: session) }
        // A cover rather than a sheet: a sheet keeps a grabber, a corner radius and an inch of
        // this page showing behind it, and all three are the chrome the viewer is meant not to
        // have. Answering is what changes the listing, so it is read again on the way back.
        .fullScreenCover(item: $open, onDismiss: reread) { artifact in
            // The session is known here and nowhere inside the cover, so it is named here: an
            // ambient "which session" is how a clip gets filed against the wrong one.
            ArtifactView(model: model,
                         session: session,
                         artifact: artifact,
                         say: Dictation(recorder: recorder,
                                        mode: model.preferences.talkMode,
                                        words: { await model.dictated($0, for: session) }))
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xxs) {
                if shown.isEmpty { empty }
                ForEach(shown) { artifact in
                    Button { open = artifact } label: { ArtifactRow(artifact: artifact) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("artifact-row")
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.top, mixed ? Spacing.extraSmall : Spacing.medium)
            .padding(.bottom, Spacing.extraLarge)
        }
        // Room at the end for the mark that floats over this.
        .contentMargins(.bottom, TalkMark.clearance, for: .scrollContent)
    }

    /// The same control the file list uses, because it is the same question asked of a different
    /// folder. Waiting comes before answered: it is the one with something owed on it.
    private var selector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xxs) {
                choice(.all, count: artifacts.count)
                choice(.waiting, count: waiting.count)
                choice(.answered, count: answered.count)
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.extraSmall)
        }
        .scrollIndicators(.hidden)
    }

    private func choice(_ option: Show, count: Int) -> some View {
        let chosen = show == option
        return Button { show = option } label: {
            HStack(spacing: Spacing.extraSmall) {
                Text(option.rawValue)
                Text(count.formatted())
                    .foregroundStyle(chosen ? Color.white.opacity(0.75) : Palette.textTertiary)
            }
            .font(Typography.primaryRow)
            .foregroundStyle(chosen ? Color.white : Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: Self.target)
            .background(Capsule().fill(chosen ? accent : Palette.tileIdle))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("artifact-filter")
        .accessibilityLabel("\(option.rawValue), \(count) pages")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    private var empty: some View {
        Text(show == .all
             ? "Nothing this session has put on your phone"
             : "No \(show.rawValue.lowercased()) pages")
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textSecondary)
            .padding(.vertical, Spacing.small)
    }

    private func reread() {
        Task { await model.loadArtifacts(for: session) }
    }
}

/// One page in the listing: what it is called, when it was written, and whether it is still
/// waiting on you.
///
/// A page you have answered is *done*, and has to look it from across the room. It used to say
/// so in one grey word at the end of a caption, which read the same as a page that had not been
/// answered at all — the whole row was identical but for a missing `WAIT`. Now the mark goes
/// from the page's own colour to a tick in the quiet one, and the title recedes with it. The
/// listing stays in one order and rows do not move under you when one is answered.
///
/// The waiting is still the word `WAIT` and nothing else — no dot, no capsule, no badge, which
/// is the one shape this app has banned outright. There is deliberately no second state word
/// for finished: "answered" is a fact about a file, not a state the session is in.
private struct ArtifactRow: View {
    let artifact: Artifact
    @Environment(\.accent) private var accent

    private var done: Bool { artifact.answered }

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: done ? "checkmark" : "doc.richtext")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(done ? Palette.textTertiary : accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 30 * 0.28, style: .continuous)
                        .fill(Palette.tileIdle)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.title)
                    .font(Typography.primaryRow)
                    .foregroundStyle(done ? Palette.textSecondary : Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(caption)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.extraSmall)
            if !done { StateWord(.wait) }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.extraSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
        // Answered pages stay readable and stay tappable — they are the record of what you said
        // — but they stop competing with the one that still wants something.
        .opacity(done ? 0.72 : 1)
        .contentShape(.rect)
    }

    /// When it was written, and the slug — which is the name an agent will say out loud when it
    /// tells you there is something on your phone.
    private var caption: String {
        let ago = artifact.changed.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        return done ? "answered · \(ago) · \(artifact.id)" : "\(ago) · \(artifact.id)"
    }
}
