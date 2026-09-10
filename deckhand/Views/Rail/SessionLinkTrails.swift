import DeckhandKit
import SwiftUI

/// Where each session's glyph sits on the rail right now, collected from the rows themselves.
///
/// Anchors rather than measured offsets: rows scroll, projects come and go, and a session that
/// has scrolled out simply stops reporting one, which is exactly when its thread should stop
/// being drawn. Nothing here knows the row's height or the list's padding.
struct SessionNodes: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, newer in newer }
    }
}

/// Sessions messaging each other, drawn behind the rail as light running between their glyphs.
///
/// One `Canvas` for every thread on screen rather than a view per particle: the rail is the
/// screen this app spends its life on, and sixty particle views re-laying-out each frame is
/// how a list starts dropping them.
///
/// **Behind the rows, not over them.** The rows are the figure and this is the ground, so the
/// slabs and glyph tiles — both translucent — sit on top of the light rather than the other
/// way round. It costs nothing in legibility and no particle can ever cross a session's name.
struct SessionLinkTrails: View {
    let trails: [LinkTrail]
    let window: TimeInterval
    let nodes: [String: CGRect]

    /// Points per second a particle covers on a fresh thread. Slow enough to read as travel
    /// rather than flicker; a fading thread runs slower still.
    private static let speed: CGFloat = 74

    /// Threads with both ends on screen and something left to say. Nothing here means no
    /// `TimelineView` is built at all, which is what keeps a quiet rail genuinely still.
    private var drawable: [LinkTrail] {
        trails.filter { nodes[$0.source] != nil && nodes[$0.target] != nil }
    }

    var body: some View {
        if drawable.isEmpty {
            Color.clear
        } else {
            TimelineView(.animation) { timeline in
                Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                    draw(in: &context, at: timeline.date)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func draw(in context: inout GraphicsContext, at date: Date) {
        for (index, trail) in drawable.enumerated() {
            let strength = trail.intensity(now: date, window: window)
            guard strength > 0.01, let arc = arc(for: trail, lane: index) else { continue }
            LinkPainter(arc: arc, trail: trail, strength: strength, date: date)
                .paint(in: &context)
        }
    }

    /// The curve one thread runs along: out of the sender's glyph, bowed into the space left
    /// of the tiles, and back into the receiver's. Every row's glyph shares an x, so without a
    /// bow a thread would be a straight line hidden under the tiles it connects.
    private func arc(for trail: LinkTrail, lane: Int) -> LinkArc? {
        guard let from = nodes[trail.source], let into = nodes[trail.target] else { return nil }
        let start = CGPoint(x: from.midX, y: from.midY)
        let end = CGPoint(x: into.midX, y: into.midY)
        // Never past the leading edge: a thread clipped off the side reads as a glitch.
        let room = max(4, start.x - 4)
        // Enough bow that two adjacent rows still get a lens rather than a bulge, growing
        // with the distance until it runs out of margin.
        let reach = min(14 + abs(end.y - start.y) * 0.05 + CGFloat(lane) * 5, room)
        return LinkArc(start: start, end: end, reach: reach)
    }
}

/// A quadratic curve bowing left of the two glyphs it joins.
struct LinkArc {
    let start: CGPoint
    let end: CGPoint
    let reach: CGFloat

    func control(inset: CGFloat = 0) -> CGPoint {
        CGPoint(x: start.x - max(2, reach - inset), y: (start.y + end.y) / 2)
    }

    func path(inset: CGFloat = 0) -> Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control(inset: inset))
        return path
    }

    /// Where a particle sits, `progress` of the way along.
    func point(at progress: CGFloat, inset: CGFloat = 0) -> CGPoint {
        let control = control(inset: inset)
        let rest = 1 - progress
        return CGPoint(
            x: rest * rest * start.x + 2 * rest * progress * control.x + progress * progress * end.x,
            y: rest * rest * start.y + 2 * rest * progress * control.y + progress * progress * end.y
        )
    }

    /// Close enough for a travel time: the straight run plus what the bow adds to it.
    var length: CGFloat {
        hypot(end.x - start.x, end.y - start.y) + reach
    }
}
