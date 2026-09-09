import SwiftUI

/// utt's colours, copied from `swift/utt/Utt/Design/Palette.swift`, not re-picked.
///
/// Deckhand is a guest in utt's language: it takes the ground, the type and the grid whole.
/// The one thing of its own is `tint`, which does inside Deckhand exactly the job utt's
/// orange does inside utt — "this is the current one" — and nothing else.
public enum Palette {
    /// Deckhand's own colour, #3EAFB4. Sea teal, picked against the warm ground. Every accent
    /// in the app reads this one token, so the hex is never written twice.
    public static let tint = Color(red: 0.243, green: 0.686, blue: 0.706)
    /// utt's orange, #D4501E. Recording is utt's job in every plugin, so this is the only
    /// thing it is ever used for here.
    public static let recording = Color(red: 0.831, green: 0.314, blue: 0.118)
    /// The warm dark ground, #303027 — never black, which is what stops a full screen of it
    /// reading as a hole punched in the display.
    public static let lcdGround = Color(red: 0.188, green: 0.188, blue: 0.153)
    public static let lcdGreen = Color(red: 0.604, green: 0.820, blue: 0.478)
    public static let lcdYellow = Color(red: 0.878, green: 0.627, blue: 0.133)
    public static let lcdRed = Color(red: 1.0, green: 0.353, blue: 0.180)
    public static let strokeHairline = Color.primary.opacity(0.08)
    public static let textPrimary = Color.primary
    public static let textSecondary = Color.secondary
    public static let textTertiary = Color.secondary.opacity(0.7)
    /// The tile a glyph sits on when it is not the current one.
    public static let tileIdle = Color.primary.opacity(0.08)

    /// A card's fill. utt reads this off an AppKit control colour, which iOS does not have;
    /// the grouped background is the same idea — one step up from the page it sits on.
    public static var surfacePrimary: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor).opacity(0.82)
        #endif
    }

    /// The page a card sits on.
    public static var surfaceGround: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}
