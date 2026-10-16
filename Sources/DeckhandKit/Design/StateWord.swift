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
    private let size: CGFloat?

    /// `size` is for a surface read at a different distance, and it is the only thing that may
    /// vary. A Lock Screen card is read at arm's length where 9pt is a smudge, and the widget
    /// had grown a near-copy of this view to say so — which is how a design language stops being
    /// one. The voice travels with the word: still mono, still semibold, still tracked.
    public init(_ state: RunState, size: CGFloat? = nil) {
        self.state = state
        self.size = size
    }

    private var font: Font {
        guard let size else { return Typography.state }
        return .system(size: size, weight: .semibold, design: .monospaced)
    }

    public var body: some View {
        Text(state.rawValue)
            .font(font)
            .tracking(2)
            .lineLimit(1)
            .foregroundStyle(state.tint)
            .accessibilityElement()
            .accessibilityLabel(state.rawValue)
    }
}

/// The word a Codex or OpenCode session carries beside its state, on the rail and on its own page
/// — `Session.providerWord`.
///
/// Not a `RunState`: it never changes, so it is not a state and has no state's colour. It borrows
/// the state word's voice — 9pt mono, tracked — in the quietest ink, with nothing around it for
/// `StateWord`'s reason. A Claude session carries nothing: every surface was written for one.
public struct ProviderWord: View {
    private let word: String

    public init(_ word: String) {
        self.word = word
    }

    public var body: some View {
        Text(word)
            .font(Typography.state)
            .tracking(2)
            .lineLimit(1)
            .foregroundStyle(Palette.textTertiary)
            .accessibilityLabel(word.capitalized)
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
    /// The screen's accent, not Deckhand's teal: a tile on a screen being dictated into goes
    /// utt orange with everything else on it, and the tile has no idea that is what happened.
    @Environment(\.accent) private var accent

    public init(_ glyph: Set<Int>, size: CGFloat = 24, prominent: Bool = false, ground: Color? = nil) {
        self.glyph = glyph
        self.size = size
        self.prominent = prominent
        self.ground = ground
    }

    public var body: some View {
        DotMark(glyph, size: size * 0.62, tint: prominent ? .white : accent)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(prominent ? accent : ground ?? Palette.tileIdle)
            )
            .accessibilityHidden(true)
    }
}
