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

    private var artifacts: [Artifact] { model.artifacts[session.sessionId] ?? [] }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xxs) {
                if artifacts.isEmpty { empty }
                ForEach(artifacts) { artifact in
                    Button { open = artifact } label: { ArtifactRow(artifact: artifact) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("artifact-row")
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.medium)
            .padding(.bottom, Spacing.extraLarge)
        }
        .frame(maxHeight: .infinity)
        // Room at the end for the mark that floats over this.
        .contentMargins(.bottom, TalkMark.clearance, for: .scrollContent)
        .task { await model.loadArtifacts(for: session) }
        // A cover rather than a sheet: a sheet keeps a grabber, a corner radius and an inch of
        // this page showing behind it, and all three are the chrome the viewer is meant not to
        // have. Answering is what changes the listing, so it is read again on the way back.
        .fullScreenCover(item: $open, onDismiss: reread) { artifact in
            ArtifactView(model: model, session: session, artifact: artifact)
        }
    }

    private var empty: some View {
        Text("Nothing this session has put on your phone")
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
/// The waiting is the word `WAIT` and nothing else — no dot, no capsule, no badge, which is the
/// one shape this app has banned outright. An answered page says so in its own line instead of
/// wearing a second state word: "answered" is a fact about the file, and the state vocabulary
/// has no word for finished.
private struct ArtifactRow: View {
    let artifact: Artifact

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 30 * 0.28, style: .continuous)
                        .fill(Palette.tileIdle)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.title)
                    .font(Typography.primaryRow)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(caption)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.extraSmall)
            if !artifact.answered { StateWord(.wait) }
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
        .contentShape(.rect)
    }

    /// When it was written, and the slug — which is the name an agent will say out loud when it
    /// tells you there is something on your phone.
    private var caption: String {
        let ago = artifact.changed.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        return artifact.answered ? "answered · \(ago) · \(artifact.id)" : "\(ago) · \(artifact.id)"
    }
}
