import SwiftUI

/// A shape on the 6×6 grid, drawn utt's way: lit dots at 0.34 of a cell in the tint, unlit at
/// 0.24 in `primary.opacity(0.28)` so the mark reads as a glyph on a visible grid rather than
/// as pixel art. Ported from `swift/utt/Utt/Views/Common/UttMark.swift`.
///
/// A mark is either a fixed shape — a session's face, the anchor — or `live`, in which case
/// it runs utt's own show off the shared driver and never sits still.
public struct DotMark: View {
    private let fixed: Set<Int>?
    private let size: CGFloat
    private let tint: Color
    private let recording: Bool
    private let level: Double
    /// How far a lit dot's centre is pushed towards white. A real emitter saturates in the
    /// middle and only shows its colour in the falloff; a flat disc is what makes a drawn dot
    /// look drawn. 0 below 44pt, where the gradient is invisible anyway.
    private let hotCore: Double

    @State private var litness: [Int: Double] = [:]
    private var driver: DotMatrixDriver { .shared }

    public init(
        _ pattern: Set<Int>,
        size: CGFloat = 18,
        tint: Color = Palette.tint,
        hotCore: Double = 0
    ) {
        self.fixed = pattern
        self.size = size
        self.tint = tint
        self.recording = false
        self.level = 0
        self.hotCore = hotCore
    }

    /// The living mark: utt's whole show, at utt's pace. `level` speeds it up and, while
    /// recording, drives the glow — the same two knobs utt's own mark has.
    public static func live(
        size: CGFloat = 18,
        tint: Color = Palette.tint,
        recording: Bool = false,
        level: Double = 0,
        hotCore: Double = 0
    ) -> DotMark {
        DotMark(fixed: nil, size: size, tint: tint, recording: recording, level: level, hotCore: hotCore)
    }

    private init(
        fixed: Set<Int>?,
        size: CGFloat,
        tint: Color,
        recording: Bool,
        level: Double,
        hotCore: Double
    ) {
        self.fixed = fixed
        self.size = size
        self.tint = tint
        self.recording = recording
        self.level = level
        self.hotCore = hotCore
    }

    public var body: some View {
        Canvas { context, canvasSize in
            for index in 0..<36 { draw(index, size: canvasSize.width, in: &context) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            settle(to: current)
            if fixed == nil { driver.level = level }
        }
        .onChange(of: level) { _, new in if fixed == nil { driver.level = new } }
        .onChange(of: driver.patternIndex) { _, _ in
            guard fixed == nil else { return }
            // Never let a transition outlast the cycle that triggered it, or a loud signal
            // leaves every dot stuck mid-fade.
            let fade = min(0.4, DotMatrix.cycleInterval(for: driver.level) * 0.5)
            withAnimation(.easeInOut(duration: fade)) { settle(to: current) }
        }
    }

    private var current: Set<Int> { fixed ?? driver.pattern }
    /// Lit dots follow the meter, but only while recording: at rest nothing feeds a level and
    /// every mark in the app would sit permanently dimmed.
    private var glow: Double { recording ? DotMatrix.glow(for: level) : 1 }

    private func draw(_ index: Int, size: CGFloat, in context: inout GraphicsContext) {
        let crossfade = litness[index] ?? (current.contains(index) ? 1 : 0)
        // Lit is decided on the crossfade alone: fold the glow in first and a quiet passage
        // drops every dot below the threshold, so the grid goes unlit rather than dim.
        let lit = crossfade > 0.5
        let rect = DotMatrix.rect(for: index, size: size, lit: lit)
        guard lit else {
            context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(0.28)))
            return
        }
        context.fill(Path(ellipseIn: rect), with: fill(rect, opacity: crossfade * glow))
    }

    private func fill(_ rect: CGRect, opacity: Double) -> GraphicsContext.Shading {
        guard hotCore > 0 else { return .color(tint.opacity(opacity)) }
        // The stop at 0.55 keeps the white to the inner half; spread over the whole dot it
        // stops reading as a hot centre and starts reading as a washed-out one.
        return .radialGradient(
            Gradient(stops: [
                .init(color: tint.mix(with: .white, by: hotCore).opacity(opacity), location: 0),
                .init(color: tint.opacity(opacity), location: 0.55),
                .init(color: tint.opacity(opacity), location: 1)
            ]),
            center: CGPoint(x: rect.midX, y: rect.midY),
            startRadius: 0,
            endRadius: rect.width / 2
        )
    }

    private func settle(to pattern: Set<Int>) {
        for index in 0..<36 { litness[index] = pattern.contains(index) ? 1 : 0 }
    }
}

/// The wordmark: the app's name in mono, with the period in the accent — utt's own shape,
/// which is the point. A guest writes its name the way the host writes theirs.
public struct Wordmark: View {
    private let text: String
    private let size: CGFloat

    public init(_ text: String = "deckhand", size: CGFloat = 13) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .tracking(-0.3)
                .foregroundStyle(.primary)
            Text(".")
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.tint)
        }
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}
