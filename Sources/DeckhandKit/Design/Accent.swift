import SwiftUI

public extension EnvironmentValues {
    /// The colour the screen around this view draws its accents in: Deckhand's teal at rest,
    /// utt orange while somebody is dictating into that screen.
    ///
    /// Recording is the single exception to Deckhand's own teal — it goes utt orange, because
    /// recording is utt's job in every plugin — and the exception belongs to the whole screen,
    /// not to the one mark being held. Reading it here is what makes that one decision instead
    /// of one per view: a screen that can record sets it once at its top with `accent(_:)`,
    /// every descendant follows, and a view written next month is right by reading `accent`
    /// rather than by remembering that microphones exist.
    ///
    /// A view on a screen that cannot record reads the default and is teal for ever, which is
    /// why reading this is never wrong — there is nothing to opt into.
    @Entry var accent: Color = Palette.tint
}

public extension Palette {
    /// Which colour a screen's accents take, given whether it is recording. Same shape as
    /// `pressure(_:)`: one question with one answer, written down once.
    static func accent(recording: Bool) -> Color {
        recording ? Palette.recording : Palette.tint
    }
}

public extension View {
    /// Hand this screen's accent to everything inside it, and to the system's own chrome with
    /// it — a spinner, a swipe action, an alert's buttons are tinted by SwiftUI rather than by
    /// us, and teal furniture on an orange screen is the one thing worse than no switch at all.
    ///
    /// One crossfade, and deliberately not a spring: the switch has to be seen, but the mark it
    /// happens beside is already moving on `DotMatrixDriver`'s clock and anything with a bounce
    /// in it fights that.
    ///
    /// Nothing here remembers the colour, which is why it cannot get stuck: the screen derives
    /// it from its recorder, and every way out of recording — sent, discarded, refused,
    /// cancelled, the app put away mid-hold — is that recorder going quiet.
    func accent(_ colour: Color) -> some View {
        environment(\.accent, colour)
            .tint(colour)
            .animation(.easeInOut(duration: 0.2), value: colour)
    }
}
