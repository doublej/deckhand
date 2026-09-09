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
