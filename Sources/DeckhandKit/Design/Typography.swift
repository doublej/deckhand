import SwiftUI

/// System fonts only — SF and SF Mono. utt has no typeface of its own and neither does a guest.
public enum Typography {
    public static let pageTitle = Font.system(size: 20, weight: .semibold)
    public static let subtitle = Font.system(size: 12, weight: .regular)
    /// The opening sentence of a briefing. Larger than anything around it because it is the
    /// one line that has to survive being read at arm's length.
    public static let lead = Font.system(size: 17, weight: .regular)
    /// Body copy on a page given over to reading, as opposed to a row in a list.
    public static let prose = Font.system(size: 14, weight: .regular)
    public static let primaryRow = Font.system(size: 14, weight: .regular)
    public static let hint = Font.system(size: 11, weight: .regular)
    public static let railRow = Font.system(size: 13, weight: .regular)
    public static let railRowSelected = Font.system(size: 13, weight: .semibold)
    /// A rail group's title: 10pt, uppercase, tracked 0.6 by the caller.
    public static let groupLabel = Font.system(size: 10, weight: .semibold)
    /// A settings group's title, one point larger than the rail's.
    public static let cardLabel = Font.system(size: 11, weight: .semibold)
    public static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// The pill, and anything that borrows its voice: 9pt mono semibold, tracked 1.4.
    public static let state = Font.system(size: 9, weight: .semibold, design: .monospaced)
    /// The eyebrow on a turn card: YOU / CLAUDE.
    public static let eyebrow = Font.system(size: 9, weight: .semibold, design: .monospaced)
}

extension View {
    /// Tracked text centred on its ink rather than on its layout box.
    ///
    /// `tracking` adds its space after *every* character, the last one included, so a tracked
    /// word carries an empty column on its right that no ink occupies. Centre that box inside
    /// symmetric padding and the ink sits half the tracking left of true centre — 0.7pt at the
    /// talk pill's 1.4, which sounds like nothing and is plainly visible. Leading padding of the
    /// full tracking puts it back: the box moves right by half of what is added, which is exactly
    /// the error. Measured, not guessed: it widens the shape by the tracking and by nothing else.
    ///
    /// **CANCEL is where it shows**, and that is the tell rather than a coincidence. The error is
    /// the same 0.7pt for every word; on the shortest one both gaps fall inside a single glance
    /// and the eye compares them directly, where on `TAP TO PREVIEW` they are a pill apart and
    /// nobody can.
    ///
    /// Only for text centred inside a shape. Tracked text aligned to a leading edge is already
    /// right, and this would indent it — which is why it is not folded into `Typography` itself.
    public func trackedCentred(_ points: CGFloat) -> some View {
        tracking(points).padding(.leading, points)
    }
}
