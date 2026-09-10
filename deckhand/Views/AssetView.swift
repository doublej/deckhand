import AVKit
import DeckhandKit
import SwiftUI

/// One file, open. Three kinds and three ways of showing them: an image fits the sheet, text
/// scrolls and can be selected, a video gets a player.
///
/// The file is fetched to disk when the sheet appears and deleted when it closes. It arrives
/// as one thing, ready, rather than as bytes that become a picture a frame later — a video
/// rendered from half-loaded state is how "it cannot play this" gets on the screen while the
/// clip is perfectly fine.
struct AssetView: View {
    @Bindable var model: AppModel
    let session: Session
    let asset: Asset
    @State private var ready: Ready?
    @State private var failed: String?
    /// The downloaded file, kept only so it can be deleted again.
    @State private var local: URL?
    /// What has been marked on the picture, seeded from whatever was marked last time and kept
    /// when the sheet closes. Here rather than inside `Marking` because the toolbar is here, and
    /// the toolbar is what has to know whether there is anything to send.
    @State private var markup = Markup()
    @State private var pencilling = false
    /// Sent, so the marks are the review card's now and must not be written back on the way out.
    @State private var sent = false
    /// This sheet's own, and the session page's is two sheets away and unreachable. One control
    /// uses it — the mark under a pin's remark — and this is the surface that outlives the remark
    /// being opened, closed and opened again, which is what a recorder has to do.
    @State private var recorder = Recorder()
    @Environment(\.dismiss) private var dismiss

    /// A file that has arrived and been read as what it is.
    private enum Ready {
        case picture(UIImage)
        case words(String)
        case film(AVPlayer)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surfaceGround)
                .navigationTitle(asset.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        marking
                        formatting
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if !markup.isEmpty {
                            // Not Send: it sends nothing. See `SnapView.hand`.
                            Button("Add to card") { hand() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(Palette.tint)
                        }
                        Button("Close") { dismiss() }.tint(Palette.tint)
                    }
                }
        }
        .task { await load() }
        .onDisappear { discard() }
    }

    /// What a pin's remark is lent so it can be said out loud. Complaining about a screenshot is
    /// the thing on this phone most worth saying rather than typing: you are holding the picture
    /// and pointing at it, and the remark is one sentence.
    private var say: Dictation {
        Dictation(recorder: recorder, mode: model.preferences.talkMode) {
            await model.dictated($0, for: session)
        }
    }

    @ViewBuilder private var content: some View {
        switch ready {
        case .picture(let image):
            // Zoomable, because half of what a session makes is a screenshot of something
            // small in the corner of something large — and markable, because pointing at the
            // small thing beats describing where it is.
            Marking(picture: image,
                    lettered: model.lettering(for: session),
                    markup: $markup,
                    pencilling: pencilling,
                    say: say)
        case .words(let text):
            ScrollView {
                words(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.medium)
            }
        case .film(let player):
            VideoPlayer(player: player)
        case nil:
            waiting
        }
    }

    /// Two ways of reading the same file, and the source is still one of them.
    ///
    /// A `report.md` is written to be read, so it opens formatted — but the source is what you
    /// want the moment the rendering is the thing in question, or you need to copy a fenced
    /// command out of it, and selection lives on the source view for exactly that reason. A long
    /// press inside a sideways-scrolling code block would be fighting the scroll.
    @ViewBuilder private func words(_ text: String) -> some View {
        if asset.isMarkdown, model.preferences.formatsMarkdown {
            Markdown(text)
        } else {
            Text(text)
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
        }
    }

    /// Markdown is the one text file with two ways of reading it, so it is the one that gets a
    /// switch. `.txt`, `.json` and `.log` arrive through the same case and there is nothing in
    /// any of them a document view would do differently.
    ///
    /// Tinted when the formatting is on, the way the pencil beside it is tinted when it is armed.
    /// No label and nothing around it: one glyph that says which of the two you are looking at.
    @ViewBuilder private var formatting: some View {
        if case .words = ready, asset.isMarkdown {
            let formatted = model.preferences.formatsMarkdown
            Button {
                setFormatted(!formatted)
            } label: {
                Image(systemName: "textformat")
            }
            .tint(formatted ? Palette.tint : Palette.textSecondary)
            .accessibilityLabel(formatted ? "Show the source" : "Show it formatted")
        }
    }

    /// Written straight through to the app's preferences rather than held in this sheet, because
    /// it is a reading preference and not a property of this file: the next report opens the way
    /// you left the last one.
    private func setFormatted(_ formats: Bool) {
        model.preferences.formatsMarkdown = formats
        model.preferences.save()
    }

    /// Only a picture can be marked, so only a picture gets a pencil — and a Discard, which is the
    /// only way marks go away without being sent: closing the sheet keeps them.
    @ViewBuilder private var marking: some View {
        if case .picture = ready {
            Button {
                pencilling.toggle()
            } label: {
                Image(systemName: pencilling ? "pencil.tip.crop.circle.fill"
                                             : "pencil.tip.crop.circle")
            }
            .tint(pencilling ? Palette.tint : Palette.textSecondary)
            .accessibilityLabel("Draw on the picture")
            if !markup.isEmpty {
                Button("Discard") { forget() }.tint(Palette.textSecondary)
            }
        }
    }

    @ViewBuilder private var waiting: some View {
        if let failed {
            Text(failed)
                .font(Typography.subtitle)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(Spacing.large)
        } else {
            VStack(spacing: Spacing.small) {
                ProgressView()
                // A rendered clip takes a moment over the LAN, and a spinner with no number
                // beside it is how a working download reads as a hung one.
                Text("\(asset.size.formatted(.byteCount(style: .file))) from the Mac")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func load() async {
        do {
            let file = try await model.download(asset, in: session)
            local = file
            ready = try open(file)
            // Kept until sent or thrown away: the same picture opened again comes back with its
            // pins on it, which is the difference between marking one up and having to start over.
            markup = model.markup(of: asset)
        } catch {
            failed = reason(error)
        }
    }

    private func open(_ file: URL) throws -> Ready {
        switch asset.sort {
        case .video:
            return .film(AVPlayer(url: file))
        case .image:
            guard let image = UIImage(contentsOfFile: file.path) else {
                throw Trouble.unreadable("Not an image this phone can draw")
            }
            return .picture(image)
        case .text:
            return .words(try String(contentsOf: file, encoding: .utf8))
        }
    }

    private enum Trouble: Error { case unreadable(String) }

    /// Says which wall it hit. "Could not hand that over" for every failure is how a file that
    /// is simply too big to send reads as a broken app.
    private func reason(_ error: Error) -> String {
        if case Trouble.unreadable(let why) = error { return why }
        guard let error = error as? DeckhandError else { return "Could not open \(asset.name)" }
        switch error {
        case .http(413, _): return "\(asset.name) is too big for the Mac to send"
        case .notLive: return "The Mac no longer has that file"
        case .unauthorized: return "The Mac refused the pairing token"
        default: return "The Mac could not hand that over"
        }
    }

    /// One piece of feedback: the flattened copy, the numbered remarks under it, and then the
    /// marks are gone — they were only ever being held until this.
    private func hand() {
        guard case .picture(let image) = ready, !markup.isEmpty else { return }
        model.feedback(markup, of: asset, picture: image, in: session)
        sent = true
        dismiss()
    }

    /// Thrown away on purpose, which is the only thing that stops them being kept.
    private func forget() {
        markup = Markup()
        model.forget(markupOf: asset)
    }

    private func discard() {
        keep()
        if let local { try? FileManager.default.removeItem(at: local) }
        ready = nil
    }

    /// What survives the sheet closing. An emptied markup is forgotten rather than kept, or
    /// deleting the last pin and closing would bring the first one back on the next open.
    private func keep() {
        guard !sent, case .picture = ready else { return }
        if markup.isEmpty {
            model.forget(markupOf: asset)
        } else {
            model.keep(markup, of: asset)
        }
    }
}
