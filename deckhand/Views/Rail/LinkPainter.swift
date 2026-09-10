import DeckhandKit
import SwiftUI

/// Draws one thread between two sessions: the line it runs on, a glow at each end, and the
/// particles travelling it.
///
/// **Why phosphor green and not the accent.** The rail's accent is a state, not a decoration —
/// teal means "this is the session you are in", and the whole rail turns utt orange for as long
/// as a recording is open. A thread that took the accent would either claim to be the current
/// session or fight the recording for the screen. `Palette.lcdGreen` is already in the ported
/// language, is used nowhere on this screen but a 6pt dot inside a pill, and reads as a trace
/// on a warm dark ground — which is what this is. It sits deliberately outside the accent so
/// that when the rail goes orange the threads recede instead of competing.
///
/// A link inside one project and a link across two are drawn identically. The geometry already
/// says which is which — one is a short hop inside a block, the other crosses the screen — and
/// encoding it a second time in colour would be chrome for a distinction the picture makes.
struct LinkPainter {
    let arc: LinkArc
    let trail: LinkTrail
    /// 1 the moment it was said, 0 at the far edge of the window.
    let strength: Double
    let date: Date

    /// Points per second on a fresh thread. An old one runs slower, so age is legible in the
    /// movement and not only in the brightness.
    private static let speed: CGFloat = 74
    /// Roughly one particle per this many points of curve. Spacing is held constant rather
    /// than counting messages: a long link across two projects and a short one inside a block
    /// have to read as the same kind of thing, and a fixed number of dots stretched over four
    /// hundred points reads as scattered debris rather than as a connection.
    private static let spacing: CGFloat = 45
    /// A burst is louder, not more numerous. The busiest pair on this Mac exchanged
    /// sixty-three messages in one sitting; sixty-three dots would be a screensaver, so weight
    /// of traffic goes into how fast the stream runs instead.
    private static let mostParticles = 10
    private static let colour = Palette.lcdGreen

    func paint(in context: inout GraphicsContext) {
        spine(in: &context)
        glow(in: &context, at: arc.start)
        glow(in: &context, at: arc.end)
        stream(in: &context, messages: trail.forward, backwards: false, inset: 0)
        // Two counter-flowing streams on two slightly different curves, plus a spine at twice
        // the weight. Back-and-forth has to be obvious without being studied.
        if trail.isMutual {
            stream(in: &context, messages: trail.back, backwards: true, inset: 8)
        }
    }

    /// The line itself, faint. It is what makes a thread with few particles still read as a
    /// connection rather than as two unrelated sparks.
    ///
    /// Broken when nobody put a person into the exchange. It is the quietest mark on the
    /// screen on purpose: which two sessions are talking and how recently is the thing being
    /// asked, and this is a footnote to it that costs no colour and no room.
    private func spine(in context: inout GraphicsContext) {
        // Bright enough that the path itself reads as a line. The particles say which way and
        // how lively; without a visible line under them a long link is just scattered dots.
        let weight = trail.isMutual ? 0.34 : 0.20
        let style = StrokeStyle(lineWidth: 0.75, dash: trail.isAutonomous ? [2, 3] : [])
        context.stroke(arc.path(), with: .color(Self.colour.opacity(weight * strength)), style: style)
        if trail.isMutual {
            context.stroke(
                arc.path(inset: 8),
                with: .color(Self.colour.opacity(weight * strength * 0.7)),
                style: style
            )
        }
    }

    /// A soft disc under a session's glyph, so the two rows that are talking light up. This is
    /// the part you see without looking — the thread is the explanation.
    private func glow(in context: inout GraphicsContext, at centre: CGPoint) {
        // Kept low: the glyph on the tile has to stay the thing you read, not the light on it.
        for (radius, alpha) in [(16.0, 0.045), (9.0, 0.07)] {
            let box = CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: box),
                with: .color(Self.colour.opacity(alpha * strength))
            )
        }
    }

    private func stream(
        in context: inout GraphicsContext,
        messages: Int,
        backwards: Bool,
        inset: CGFloat
    ) {
        let count = min(max(3, Int(arc.length / Self.spacing)), Self.mostParticles)
        // An old thread moves as slowly as it looks; a busy one visibly rushes.
        let pace = (0.35 + 0.65 * strength) * (1 + min(Double(messages), 60) / 60 * 0.6)
        let period = Double(arc.length) / Double(Self.speed * CGFloat(pace))
        let turn = date.timeIntervalSinceReferenceDate / max(period, 0.2) + phase
        for index in 0..<count {
            let along = (turn + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1)
            particle(in: &context, along: backwards ? 1 - along : along, inset: inset)
        }
    }

    /// One travelling dot: a wide halo, a body and a bright core, faded in and out at the two
    /// ends of the run so nothing pops into being on top of a glyph.
    private func particle(in context: inout GraphicsContext, along: Double, inset: CGFloat) {
        let spot = arc.point(at: along, inset: inset)
        let ease = sin(along * .pi)  // 0 at both glyphs, 1 in the middle of the flight
        let alpha = strength * ease
        for (radius, weight) in [(3.4, 0.16), (1.9, 0.42), (0.9, 0.95)] {
            let box = CGRect(
                x: spot.x - radius,
                y: spot.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: box), with: .color(Self.colour.opacity(weight * alpha)))
        }
    }

    /// A fixed offset per pair so two threads on screen never pulse in step. Derived from the
    /// ids rather than from `hashValue`, which Swift seeds per process — the rail would
    /// otherwise shuffle its own rhythm on every cold start.
    private var phase: Double {
        Double(trail.id.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 97 }) / 97
    }
}
