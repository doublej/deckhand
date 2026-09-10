import DeckhandKit
import SwiftUI

/// One artifact, full screen, with no browser around it.
///
/// The page is the screen. There is no address bar, no toolbar, no reload, no back and forward,
/// no progress bar — nothing that says "this is a web page", because what it is is a question a
/// session asked. The only furniture is the way out, and the line that says what became of an
/// answer: a page can be answered more than once, so this screen has to be able to say "that
/// went" and "that did not" without closing.
///
/// The web view is left transparent on purpose, so a page that paints no background of its own
/// sits on the app's own ground rather than on white.
struct ArtifactView: View {
    @Bindable var model: AppModel
    let session: Session
    let artifact: Artifact
    /// What it takes to talk at this slip rather than at the session: the *listing's* recorder, the
    /// gesture the person set, and the one way a clip becomes words. A parameter rather than
    /// something read out of the environment, because it names the session the clip is filed
    /// against and an ambient "which session" is how a clip ends up on the wrong one.
    let say: Dictation
    /// The HTML, once the Mac has handed it over. Fetched here rather than with the listing:
    /// a page is kilobytes, and nobody wants every artifact in memory to read one.
    @State private var html: String?
    /// What the person answered last time, as JSON text for the bridge. Set before `html` is, so
    /// the one gate below guarantees a page is never built without it — a page drawing itself blank
    /// and then filling in a moment later is worse than the empty form this replaces.
    @State private var answer = "null"
    @State private var failed: String?
    /// What became of the last answer. Not cleared on a timer — it is the only receipt there is.
    @State private var said: Said?
    /// This screen's link to the page: what the page is holding, and the way to ask it things.
    @State private var talk = PageTalk()
    @Environment(\.dismiss) private var dismiss

    /// What the Mac said about an answer: it reached the session, or it did not and why.
    private enum Said {
        case sent(String?)
        case refused(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            furniture
            page
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surfaceGround.ignoresSafeArea())
        // Above the keyboard when there is one, which is where the thumb already is — the same
        // arrangement `PinWords` uses for the same problem. An inset rather than something floating
        // over the page, because the page is the screen and a control over it would cover the very
        // words it is about.
        .safeAreaInset(edge: .bottom) { saying }
        .task { await fetch() }
    }

    @ViewBuilder private var page: some View {
        if let html {
            ArtifactWeb(artifact: artifact,
                        html: html,
                        answer: answer,
                        talk: talk,
                        respond: respond,
                        close: { dismiss() })
                .accessibilityIdentifier("artifact-page")
        } else {
            waiting
        }
    }

    /// The way out, and the receipt. One row, no ground of its own: a band across the top to
    /// hold a single glyph is the thing this app takes out of every screen it can.
    private var furniture: some View {
        HStack(spacing: Spacing.extraSmall) {
            receipt
            Spacer(minLength: Spacing.extraSmall)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.tint)
                    .frame(width: 28, height: 30)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("artifact-close")
        }
        .padding(.horizontal, Spacing.small)
    }

    @ViewBuilder private var receipt: some View {
        switch said {
        case .sent(let route):
            Text(route.map { "Answered · \($0)" } ?? "Answered")
                .font(Typography.hint)
                .foregroundStyle(Palette.tint)
        case .refused(let why):
            Text(why)
                .font(Typography.hint)
                .foregroundStyle(Palette.lcdRed)
                .lineLimit(2)
        case nil:
            // The page's own title, quietly: the only thing up here while nothing has happened,
            // and it is what tells two open artifacts apart when one is half scrolled.
            Text(artifact.title)
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var waiting: some View {
        VStack(spacing: Spacing.small) {
            if let failed {
                Text(failed)
                    .font(Typography.subtitle)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.large)
    }

    /// Say something about a passage, or into a field — and nothing at all the rest of the time.
    ///
    /// Only once the page is up: a control offering to comment on a selection in a page that has not
    /// arrived has nothing to select, and one over the failure message would be furniture on a dead
    /// end. Commenting closes this screen, because what it makes is a card at the foot of the
    /// session's own page and that card is behind this one.
    @ViewBuilder private var saying: some View {
        if html != nil {
            SayOnPage(model: model,
                      session: session,
                      artifact: artifact,
                      say: say,
                      talk: talk,
                      commented: { dismiss() })
        }
    }

    /// Both halves at once, and the answer lands first. Together rather than one after the other
    /// because they are two requests to the same Mac about the same file, and the page cannot be
    /// shown until both are in.
    private func fetch() async {
        async let said = model.answered(to: artifact, in: session)
        async let page = model.page(of: artifact, in: session)
        do {
            answer = await said
            html = try await page
        } catch {
            _ = await said
            failed = reason(error)
        }
    }

    /// A 404 here is not the app's usual "that session is no longer running". The Mac answers one
    /// for a page it will not serve — gone since the listing was read, renamed to something that
    /// is not a slug, or over the 4 MB it will hand over — and a row can therefore exist for a
    /// page that does not open. Saying the session died would send somebody looking at the wrong
    /// thing entirely.
    private func reason(_ error: Error) -> String {
        guard case DeckhandError.notLive = error else { return model.reason(error) }
        return "The Mac would not serve that page — it is gone, or too big to send"
    }

    /// The page called `window.deckhand.respond`. Straight on to the Mac: the answer is the
    /// person's own and nothing here edits it or asks them to confirm it twice.
    private func respond(_ json: String) {
        Task {
            do {
                let sent = try await model.answer(artifact, in: session, valueJSON: json)
                said = sent.went ? .sent(sent.deliveredBy) : .refused(refusal(sent))
            } catch {
                said = .refused(reason(error))
            }
        }
    }

    /// `delivered` alone is not "it was said" anywhere in this app, and it is not here either.
    private func refusal(_ sent: Delivery) -> String {
        sent.stoppedBy.map { "Stopped by \($0)" }
            ?? sent.deliveryError
            ?? "The Mac did not pass that on"
    }
}
