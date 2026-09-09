import SwiftUI

/// utt's four-letter state vocabulary. A state says what something *is*; it is never a label,
/// never a button, and never invents a word outside this list.
public enum RunState: String, Sendable {
    /// Running, reachable, nothing to do.
    case online = "ON"
    /// Switched off by the person, or nothing asked of it yet.
    case off = "OFF"
    /// Waiting on a person or on the other side.
    case wait = "WAIT"
    /// Alive and doing nothing.
    case idle = "IDLE"
    /// Working right now.
    case busy = "BUSY"
    /// On and broken. Something next to it says why, in one sentence.
    case err = "ERR"
    /// The recorder's, and only while the phone is actually recording.
    case rec = "REC"

    public var tint: Color {
        switch self {
        case .online: Palette.lcdGreen
        case .off, .idle: .secondary
        case .wait, .busy: Palette.lcdYellow
        case .err: Palette.lcdRed
        case .rec: Palette.recording
        }
    }
}

/// The state, as the one word it is: 9pt mono semibold tracked wide, in the state's colour.
///
/// Nothing around it. It was a dot and a label inside a bordered capsule — utt's own badge —
/// and that shape is not to appear in this app again: a badge reads as a thing you can press,
/// and every one of these sits beside something you actually can. The colour does the work the
/// fill and the hairline were doing, and a screen of these reads as a terminal rather than as a
/// row of buttons.
public struct StateWord: View {
    private let state: RunState

    public init(_ state: RunState) { self.state = state }

    public var body: some View {
        Text(state.rawValue)
            .font(Typography.state)
            .tracking(2)
            .foregroundStyle(state.tint)
            .accessibilityElement()
            .accessibilityLabel(state.rawValue)
    }
}

/// A glyph on its tile: grey until it is the current one, when it fills with the accent.
/// The corner is 0.28 of the size at every size, which is what keeps 20pt and 36pt tiles
/// looking like the same object.
public struct GlyphTile: View {
    private let glyph: Set<Int>
    private let size: CGFloat
    private let prominent: Bool
    private let ground: Color?

    public init(_ glyph: Set<Int>, size: CGFloat = 24, prominent: Bool = false, ground: Color? = nil) {
        self.glyph = glyph
        self.size = size
        self.prominent = prominent
        self.ground = ground
    }

    public var body: some View {
        DotMark(glyph, size: size * 0.62, tint: prominent ? .white : Palette.tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(prominent ? Palette.tint : ground ?? Palette.tileIdle)
            )
            .accessibilityHidden(true)
    }
}
