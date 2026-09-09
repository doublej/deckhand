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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }.tint(Palette.tint)
                    }
                }
        }
        .task { await load() }
        .onDisappear { discard() }
    }

    @ViewBuilder private var content: some View {
        switch ready {
        case .picture(let image):
            // Zoomable, because half of what a session makes is a screenshot of something
            // small in the corner of something large.
            Zoomable(image: image)
        case .words(let text):
            ScrollView {
                Text(text)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.medium)
            }
        case .film(let player):
            VideoPlayer(player: player)
        case nil:
            waiting
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

    private func discard() {
        if let local { try? FileManager.default.removeItem(at: local) }
        ready = nil
    }
}

/// A picture that fits the sheet and zooms.
///
/// This is UIScrollView's own job and it does the whole of it: fit on open, pinch to zoom,
/// pan inside the picture, double tap in and out, and the bounce at the edges. A SwiftUI
/// `ScrollView` was doing none of it — asked for both axes it proposes unbounded space, so
/// `scaledToFit` had nothing to fit to and a screenshot drew at its full pixel size.
struct Zoomable: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> PictureScroll {
        PictureScroll(image: image)
    }

    func updateUIView(_ view: PictureScroll, context: Context) {
        view.show(image)
    }
}

/// Its own delegate and its own layout: the fit has to be redone whenever the sheet changes
/// size, and `layoutSubviews` is the only place that is reliably known.
final class PictureScroll: UIScrollView, UIScrollViewDelegate {
    private let picture = UIImageView()
    /// The bounds the current fit was worked out for. Refitting on every layout pass would
    /// throw away the zoom the person just pinched.
    private var fittedFor: CGSize = .zero

    init(image: UIImage) {
        super.init(frame: .zero)
        delegate = self
        maximumZoomScale = 12
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .clear
        picture.contentMode = .scaleAspectFit
        picture.image = image
        addSubview(picture)
        let twice = UITapGestureRecognizer(target: self, action: #selector(tappedTwice))
        twice.numberOfTapsRequired = 2
        addGestureRecognizer(twice)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    func show(_ image: UIImage) {
        guard picture.image !== image else { return }
        picture.image = image
        fittedFor = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedFor { fit() }
        centre()
    }

    /// The picture is sized to the rectangle it actually fills, not to the whole sheet, so a
    /// zoomed-in pan runs out at the edge of the image rather than in the letterboxing.
    private func fit() {
        guard let image = picture.image, bounds.width > 0, bounds.height > 0 else { return }
        fittedFor = bounds.size
        zoomScale = 1
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        picture.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
    }

    /// Kept in the middle while it is smaller than the sheet, which is most of the time.
    private func centre() {
        let sideways = max(0, (bounds.width - picture.frame.width) / 2)
        let upright = max(0, (bounds.height - picture.frame.height) / 2)
        contentInset = UIEdgeInsets(top: upright, left: sideways, bottom: upright, right: sideways)
    }

    @objc private func tappedTwice(_ tap: UITapGestureRecognizer) {
        guard zoomScale <= minimumZoomScale else {
            return setZoomScale(minimumZoomScale, animated: true)
        }
        // In on the spot that was tapped, not on the middle of the picture.
        let spot = tap.location(in: picture)
        let side = bounds.width / 3
        zoom(to: CGRect(x: spot.x - side / 2, y: spot.y - side / 2, width: side, height: side),
             animated: true)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centre() }
}
