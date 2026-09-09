import SwiftUI

/// utt's four-letter state vocabulary. A pill says what something *is*; it is never a label,
/// never a button, and never invents a word outside this list.
public enum PillState: String, Sendable {
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

/// 9pt mono semibold tracked 1.4, a 6pt dot, 10% fill and a 25% hairline. Copied from utt's
/// `RecorderStatePill` so the two apps' states are the same object on two screens.
public struct StatePill: View {
    private let state: PillState

    public init(_ state: PillState) { self.state = state }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.tint)
                .frame(width: 6, height: 6)
            Text(state.rawValue)
                .font(Typography.pill)
                .tracking(1.4)
                .foregroundStyle(state.tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(state.tint.opacity(0.10)))
        .overlay(Capsule().strokeBorder(state.tint.opacity(0.25), lineWidth: 0.5))
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
