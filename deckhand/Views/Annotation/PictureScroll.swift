import DeckhandKit
import PencilKit
import UIKit

/// Its own delegate and its own layout: the fit has to be redone whenever the sheet changes size,
/// and `layoutSubviews` is the only place that is reliably known.
///
/// It carries the marking as well as the zoom, because the zoom is what makes the marking hard: a
/// tap has to become a pixel of the picture, a marker has to go back onto that pixel after every
/// pinch, and the freehand layer has to sit exactly over the picture at whatever size it is
/// currently being drawn at. All three answers are here, and all three are one call to `Fitting`.
final class PictureScroll: UIScrollView, UIScrollViewDelegate, PKCanvasViewDelegate {
    private let picture = UIImageView()
    /// The freehand layer, a subview of the picture itself so that a stroke travels with the thing
    /// it was drawn on: the zoom is a transform on `picture`, and anything inside it is carried
    /// along for free. It is never taken away, only switched out of the touch path — strokes have
    /// to stay visible with the pencil put down.
    private let canvas = PKCanvasView()
    private let tools = PKToolPicker()
    /// The markers, one per pin, outside `picture` and so never scaled by the zoom. See
    /// `Marker.onScreen` for why that is the choice.
    private var markers: [UILabel] = []
    private var pins: [Pin] = []
    /// Which pin wears the chosen ring. Here rather than above because `place()` is the one thing
    /// that knows where a marker is, and both the ring and the reported point come out of it.
    private var picked: UUID?
    /// The strokes as they are kept: in the picture's pixels, not the canvas's points.
    private var strokes = PKDrawing()
    /// The last thing written *into* the canvas, so the change it reports back can be told from a
    /// change somebody drew. `PKDrawing` is Equatable, so this is exact and needs no flag that has
    /// to be unset on every path out.
    private var pushed = PKDrawing()
    /// The bounds the current fit was worked out for. Refitting on every layout pass would throw
    /// away the zoom the person just pinched.
    private var fittedFor: CGSize = .zero
    private lazy var once = UITapGestureRecognizer(target: self, action: #selector(tappedOnce))

    /// What the surface above is told. The scroll view decides nothing about what a tap means.
    var dropped: ((CGPoint) -> Void)?
    var opened: ((Pin) -> Void)?
    var drew: ((PKDrawing) -> Void)?
    /// Where the chosen marker currently is, in **this view's** coordinates rather than the
    /// content's — the controls beside it are drawn over the top of this and do not scroll, so a
    /// content point would put them in the right place exactly once. Nil when nothing is chosen.
    ///
    /// It carries the pin's id as well as the point, and that is not bookkeeping: the surface above
    /// draws the controls only while the id matches the pin it thinks is chosen, so a report that
    /// never arrives shows nothing rather than showing the last marker's position.
    var moved: (((UUID, CGPoint)?) -> Void)?

    init(image: UIImage) {
        super.init(frame: .zero)
        delegate = self
        maximumZoomScale = 12
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .clear
        picture.contentMode = .scaleAspectFit
        picture.image = image
        // A UIImageView takes no touches at all by default, and the freehand layer is inside it.
        picture.isUserInteractionEnabled = true
        addSubview(picture)
        prepareCanvas()
        prepareTaps()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    func show(_ image: UIImage) {
        guard picture.image !== image else { return }
        picture.image = image
        fittedFor = .zero
        setNeedsLayout()
    }

    /// What is marked, as it stands. The drawing is only pushed when it is news — the canvas is the
    /// one that reported the last change, and handing it straight back would start a round trip
    /// that never settles.
    func mark(_ markup: Markup) {
        if markup.drawing != strokes { push(markup.drawing) }
        pins = markup.pins
        place()
    }

    /// The pencil is a mode. With it on the canvas takes the touches and PencilKit owns what
    /// happens to them; with it off the canvas is out of the touch path entirely, which is
    /// `isUserInteractionEnabled` and not `isDrawingEnabled` — a scroll view inside a scroll view
    /// that merely refuses to draw still swallows the tap that was meant to drop a pin.
    func pencil(_ inking: Bool) {
        guard inking != canvas.isUserInteractionEnabled else { return }
        canvas.isUserInteractionEnabled = inking
        once.isEnabled = !inking
        tools.setVisible(inking, forFirstResponder: canvas)
        if inking { canvas.becomeFirstResponder() } else { canvas.resignFirstResponder() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedFor { fit() }
        centre()
    }

    /// The picture is sized to the rectangle it actually fills, not to the whole sheet, so a
    /// zoomed-in pan runs out at the edge of the image rather than in the letterboxing.
    private func fit() {
        guard picture.image != nil, bounds.width > 0, bounds.height > 0 else { return }
        fittedFor = bounds.size
        zoomScale = 1
        let scale = Fitting.scale(of: pixels, into: bounds.size)
        let fitted = CGSize(width: pixels.width * scale, height: pixels.height * scale)
        picture.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        canvas.frame = picture.bounds
        // The canvas is a different size than it was, so the kept strokes have to be re-scaled
        // into it — turning the phone would otherwise move every stroke off the thing it circled.
        push(strokes)
        place()
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

    @objc private func tappedOnce(_ tap: UITapGestureRecognizer) {
        if let near = nearest(to: tap.location(in: self)) {
            opened?(near)
            return
        }
        // Read in the picture's own bounds, which the zoom transform does not touch: the same
        // conversion the double tap has always done, one division further on.
        let spot = tap.location(in: picture)
        guard let pixel = Fitting.pixel(at: spot, of: pixels, drawn: picture.bounds) else { return }
        dropped?(pixel)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
        // The markers are not inside the picture, so the zoom does not carry them. This is the
        // price of their staying a readable size, and it is one line.
        place()
    }

    /// A pan moves no marker — they are the content's children and travel with it — but it does
    /// move them relative to *this view*, which is the space the controls beside one are drawn in.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        report()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard canvasView.drawing != pushed, pixels.width > 0, canvas.bounds.width > 0 else { return }
        let scale = pixels.width / canvas.bounds.width
        strokes = canvasView.drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
        drew?(strokes)
    }

    /// The picture's own pixels, which is the space every mark is kept in.
    private var pixels: CGSize { picture.image.map(pixelSize) ?? .zero }

    private func prepareCanvas() {
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // It is a scroll view itself, and a scroll view inside a zooming scroll view fights it for
        // the pan. The zoom here is the outer one's job; the canvas only has to take ink.
        canvas.isScrollEnabled = false
        // A finger has to draw. `.default` is Pencil-only on anything that has ever met an Apple
        // Pencil, and this is a phone being marked up with a thumb.
        canvas.drawingPolicy = .anyInput
        canvas.isUserInteractionEnabled = false
        canvas.delegate = self
        tools.addObserver(canvas)
        picture.addSubview(canvas)
    }

    private func prepareTaps() {
        let twice = UITapGestureRecognizer(target: self, action: #selector(tappedTwice))
        twice.numberOfTapsRequired = 2
        addGestureRecognizer(twice)
        // Which way round matters. The single tap waits for the double tap to fail; without that
        // the first tap of a zoom-in also drops a pin, on the very spot about to be zoomed to. The
        // cost is the third of a second iOS spends waiting for a second tap before the pin
        // appears, which is what two taps on one picture cost. Neither fights the pan or the
        // pinch: a tap that moves is not a tap, so there is nothing to arbitrate.
        once.require(toFail: twice)
        addGestureRecognizer(once)
    }

    /// The strokes go into the canvas in the canvas's own space and come back out in pixels. The
    /// canvas is only as big as the sheet made it, so a stroke kept in its points would move and
    /// change thickness the moment the phone was turned.
    private func push(_ drawing: PKDrawing) {
        strokes = drawing
        guard pixels.width > 0, canvas.bounds.width > 0 else { return }
        let scale = canvas.bounds.width / pixels.width
        pushed = drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
        canvas.drawing = pushed
    }

    /// One marker per pin, renumbered from the top every time, because a pin's number is its place
    /// in the list and nothing is written on the pin itself.
    private func place() {
        while markers.count > pins.count { markers.removeLast().removeFromSuperview() }
        while markers.count < pins.count { markers.append(addMarker()) }
        for (index, marker) in markers.enumerated() {
            let mine = pins[index].id == picked
            marker.text = "\(index + 1)"
            marker.center = Fitting.point(of: pins[index].spot, of: pixels, drawn: picture.frame)
            Marker.dress(marker, chosen: mine)
        }
        report()
    }

    /// Where the chosen marker is now, less what has been scrolled past. Called from `place()`, so
    /// every zoom, pan, fit and turn of the phone carries the controls with the marker.
    private func report() {
        guard let picked,
              let index = pins.firstIndex(where: { $0.id == picked }),
              index < markers.count
        else {
            moved?(nil)
            return
        }
        let spot = markers[index].center
        moved?((picked, CGPoint(x: spot.x - contentOffset.x, y: spot.y - contentOffset.y)))
    }

    /// Which marker is chosen. Nil puts the ring away and reports no position.
    ///
    /// The position is reported again on the next tick, and that second report is the whole reason
    /// this is not one line. This is called from `updateUIView`, which runs inside SwiftUI's own
    /// update pass, and a state change made in there is dropped. Choosing a *second* marker kept
    /// the first one's position for exactly that reason: dropping a new pin also mutates the
    /// markup binding, which buys another pass that picks the change up, and a plain change of
    /// selection buys nothing. So the synchronous report stands for the case where it works, and
    /// the deferred one covers the case where it does not.
    func choose(_ pin: UUID?) {
        guard picked != pin else { return }
        picked = pin
        place()
        DispatchQueue.main.async { [weak self] in
            guard let self, picked == pin else { return }
            report()
        }
    }

    private func addMarker() -> UILabel {
        let marker = Marker.label()
        addSubview(marker)
        return marker
    }

    /// The pin whose marker was tapped, if one was. A marker is small and a thumb is not, so the
    /// reach is the marker's own width: tapping beside a marker reopens it rather than dropping a
    /// second pin on top of the first.
    private func nearest(to spot: CGPoint) -> Pin? {
        let found = zip(pins, markers)
            .map { (pin: $0.0, gap: hypot($0.1.center.x - spot.x, $0.1.center.y - spot.y)) }
            .min { $0.gap < $1.gap }
        guard let found, found.gap <= Marker.onScreen else { return nil }
        return found.pin
    }
}
