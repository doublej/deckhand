import Foundation
import SwiftUI

/// How present a session looks on the rail, as a function of how long it has been quiet.
///
/// The rail is a list of things competing for one glance, and most of them are not what you
/// came for. Nothing here adds a decoration to say which is which: the row that last did
/// something is drawn exactly as the app has always drawn it, and the ones that have gone quiet
/// recede from it. So this can only ever take contrast away — full is the design, and age is what
/// spends it, along with a session no client on the Mac has open any more.
///
/// One multiplier over the whole row rather than a second palette. Opacity on the rail's dark
/// ground moves ink, tile and border toward that ground together, which is what "less contrast"
/// means here; picking dimmer colours for each of them would be three values to keep in step
/// and the same result.
public enum Fade {
    /// Dim, never gone. A session you have not touched since this morning is still a session you
    /// can read the name of and tap — the floor is what separates receding from hiding, and
    /// hiding is already a thing the app does on purpose and elsewhere.
    public static let floor = 0.5
    /// Full contrast inside this, because a session that stopped a minute ago has not gone
    /// quiet, it is between turns.
    static let grace: TimeInterval = 120
    /// Where the floor is reached. Past a working day's distance there is nothing left to say
    /// with contrast — eight hours ago and three days ago are both "not today".
    static let span: TimeInterval = 8 * 3600

    /// Logarithmic, so most of the travel happens in the first hour.
    ///
    /// Linear in seconds spends nearly all of its range on the difference between four hours and
    /// eight, which is a difference nobody is reading the rail for. The hour after a session
    /// stops is the hour you are deciding whether to go back to it, so that is where the visible
    /// change belongs: ten minutes reads as 0.85, an hour as 0.69, three hours as 0.59.
    public static func contrast(idleFor age: TimeInterval) -> Double {
        guard age > grace else { return 1 }
        let reach = log(min(age, span) / grace) / log(span / grace)
        return 1 - (1 - floor) * reach
    }
}

public extension Session {
    /// How this row should be drawn, given the clock.
    ///
    /// A busy session is never faded whatever its timestamp says, and that is not a nicety: the
    /// registry's `updated_at` is the moment the status last *changed*, not a heartbeat, so a
    /// session that has been working for an hour carries an hour-old timestamp. Measured on this
    /// Mac — a session reporting `busy` with `updated_at` 1553 s old while it was mid-turn.
    /// Reading that as idle age would make the hardest-working row on the rail the faintest one.
    ///
    /// A session no client has open is at the floor straight away. Its OFF says so in words, and
    /// it is the same receding the clock would give it in a few hours, arrived at now: a session
    /// nobody has open is not one you are deciding whether to go back to.
    func contrast(asOf now: Date = Date()) -> Double {
        if isBusy { return 1 }
        return isOpen ? Fade.contrast(idleFor: now.timeIntervalSince(lastActive)) : Fade.floor
    }
}

/// The soft edge on a scroll view, drawn only where there is something past it.
///
/// The seam was a mask on the container holding the panes, so both edges were always soft
/// whatever was in them. On a pane whose content fits, that is a gradient laid over the first
/// and last rows for no reason — it dims things sitting exactly where they belong and reads as
/// a rendering fault rather than as depth. A fade means *there is more this way*, so it may
/// only be drawn when there is.
///
/// It belongs to the scroll view rather than to whatever contains one: only the scroll view
/// knows its own content height, and a container holding four of them cannot answer for the one
/// on screen. `onScrollGeometryChange` is the whole mechanism and it is an iOS 18 API, which is
/// this app's floor.
///
/// The top is the deeper of the two, as it was on the container: what runs under the header
/// needs more room to disappear into than what runs off the foot.
public struct FadingEdges: ViewModifier {
    /// Whether there is content above the top edge, and below the bottom one.
    private struct Past: Equatable {
        var above = false
        var below = false
    }

    @State private var past = Past()

    public init() {}

    public func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Past.self) { geometry in
                let top = geometry.contentOffset.y + geometry.contentInsets.top
                let bottom = geometry.contentSize.height - geometry.contentOffset.y
                    - geometry.containerSize.height + geometry.contentInsets.bottom
                // A point of slack at each end: a scroll view at rest lands a fraction past
                // its own edge often enough that an exact test flickers the gradient on and
                // off while nothing is moving.
                return Past(above: top > 1, below: bottom > 1)
            } action: { _, now in past = now }
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [past.above ? .clear : .black, .black],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 20)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, past.below ? .clear : .black],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 12)
                }
            }
            .animation(Motion.fading, value: past)
    }
}

public extension View {
    /// Soften this scroll view's top and bottom, each only while there is content past it.
    func fadingEdges() -> some View { modifier(FadingEdges()) }
}
