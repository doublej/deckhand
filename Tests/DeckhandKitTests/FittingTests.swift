import CoreGraphics
import Foundation
import Testing

@testable import DeckhandKit

@Suite("Fitting a picture")
struct FittingTests {
    /// Round numbers on purpose, so a failure is an arithmetic mistake and not float drift. A
    /// 1000×500 picture fitted into a 400pt square lands at 400×200, a scale of 0.4.
    let picture = CGSize(width: 1000, height: 500)
    let sheet = CGSize(width: 400, height: 400)
    /// Where that picture is drawn at fit.
    let fitted = CGRect(x: 0, y: 0, width: 400, height: 200)
    /// And the same picture pinched to 4× and panned, which is how it is actually marked up: the
    /// rectangle is four times the fitted one and its origin has walked off the top left.
    let zoomed = CGRect(x: -300, y: -100, width: 1600, height: 800)

    @Test("a wide picture fits by its width")
    func fits() {
        #expect(Fitting.scale(of: picture, into: sheet) == 0.4)
        // Taller than the box, so the height is what runs out first.
        #expect(Fitting.scale(of: CGSize(width: 500, height: 1000), into: sheet) == 0.4)
        // A picture smaller than the sheet grows to fill it, which a cropped screenshot does.
        #expect(Fitting.scale(of: CGSize(width: 100, height: 100), into: sheet) == 4)
        #expect(Fitting.scale(of: .zero, into: sheet) == 1)
    }

    @Test("a tap on the fitted picture is a pixel of the picture")
    func onFit() {
        #expect(Fitting.pixel(at: CGPoint(x: 200, y: 100), of: picture, drawn: fitted)
            == CGPoint(x: 500, y: 250))
        #expect(Fitting.pixel(at: .zero, of: picture, drawn: fitted) == .zero)
        #expect(Fitting.pixel(at: CGPoint(x: 40, y: 20), of: picture, drawn: fitted)
            == CGPoint(x: 100, y: 50))
    }

    @Test("the same screen point zoomed in is a different pixel")
    func onZoom() {
        // 100pt in from the left of a rectangle that starts 300pt off-screen: four hundred points
        // into a picture drawn at 1.6×, so a quarter of the way along it.
        #expect(Fitting.pixel(at: CGPoint(x: 100, y: 300), of: picture, drawn: zoomed)
            == CGPoint(x: 250, y: 250))
        // The top left pixel is off the top left of the sheet, which is what panning means.
        #expect(Fitting.pixel(at: CGPoint(x: -300, y: -100), of: picture, drawn: zoomed) == .zero)
    }

    @Test("a tap that missed the picture is not a pixel of it")
    func offPicture() {
        // Below the fitted picture: the letterboxing, which is two hundred points of the sheet.
        #expect(Fitting.pixel(at: CGPoint(x: 200, y: 300), of: picture, drawn: fitted) == nil)
        // Past its right edge, and past the zoomed one's too.
        #expect(Fitting.pixel(at: CGPoint(x: 401, y: 100), of: picture, drawn: fitted) == nil)
        #expect(Fitting.pixel(at: CGPoint(x: 1301, y: 300), of: picture, drawn: zoomed) == nil)
        // Nothing is on a picture of no size.
        #expect(Fitting.pixel(at: .zero, of: picture, drawn: .zero) == nil)
    }

    @Test("a marker goes back where the tap that made it came from")
    func inverse() {
        #expect(Fitting.point(of: CGPoint(x: 250, y: 250), of: picture, drawn: zoomed)
            == CGPoint(x: 100, y: 300))
        #expect(Fitting.point(of: CGPoint(x: 500, y: 250), of: picture, drawn: fitted)
            == CGPoint(x: 200, y: 100))
        // The real case, where the numbers are not round: a 3024×1964 screenshot on a phone.
        let shot = CGSize(width: 3024, height: 1964)
        let scale = Fitting.scale(of: shot, into: CGSize(width: 390, height: 700))
        let drawn = CGRect(x: 0, y: 0, width: shot.width * scale, height: shot.height * scale)
        let spot = CGPoint(x: 137, y: 92)
        let pixel = Fitting.pixel(at: spot, of: shot, drawn: drawn)
        let back = Fitting.point(of: pixel ?? .zero, of: shot, drawn: drawn)
        #expect(abs(back.x - spot.x) < 0.001)
        #expect(abs(back.y - spot.y) < 0.001)
    }
}
