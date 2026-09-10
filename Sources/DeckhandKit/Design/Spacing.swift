import SwiftUI

/// utt's spacing scale. Nothing between the steps, so two screens never disagree by 2 points.
public enum Spacing {
    public static let xxs: CGFloat = 4
    public static let extraSmall: CGFloat = 8
    public static let small: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let extraLarge: CGFloat = 32
}

/// Rows, cards, sheets, panels.
public enum Radius {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let extraLarge: CGFloat = 20
    public static let pill: CGFloat = 999
}

/// How long a thing takes, and the shape of it.
///
/// The one part of this folder that is **not** a port. `swift/utt/Utt/Design/` has no motion
/// tokens either, so there was nothing there to copy — which makes this a deliberate exception to
/// the rule at the top of this packet rather than an oversight, and a candidate to push back to
/// utt. Every call site had been picking its own: 0.18, 0.20, 0.22 and 0.25 across eleven files,
/// four values nobody can tell apart, chosen independently. That is the drift a token set exists
/// to stop, and it is the same shape as the radius problem one folder over.
///
/// Named for what the motion is *for* rather than for its curve, because that is the question
/// being asked at a call site. All ease and no spring: `.snappy` is a spring with bounce in it,
/// and a word landing beside a button somebody is about to press should land, not wobble.
public enum Motion {
    /// Something arriving beside your thumb — a pill sliding out from under the talk mark, a
    /// control appearing under a page. Ease-out: entering wants a quick start and a soft landing.
    public static let arriving = Animation.easeOut(duration: 0.34)

    /// The same thing leaving. Shorter than it arrived and ease-in, because a departure is
    /// courteous when it is quick and nothing needs to watch it land.
    public static let leaving = Animation.easeIn(duration: 0.24)

    /// Something opening, closing or resizing where it already is: a disclosure, a card taking
    /// the slot, a pane. Symmetric, because it is neither entering nor leaving.
    public static let opening = Animation.easeInOut(duration: 0.28)

    /// A colour or an opacity with nothing travelling under it. It can afford to be the slowest
    /// thing here precisely because there is no movement to sit through.
    public static let fading = Animation.easeInOut(duration: 0.35)

    /// One word replacing another in a control that stays put.
    ///
    /// The one token with a ceiling on it rather than a feel: the talk mark's narration changes
    /// word every 600 ms at its fastest (`ClipNarration`), so a swap has to be finished well
    /// before the next one is due or the pill never rests. 0.22 leaves two thirds of the beat.
    public static let word = Animation.easeOut(duration: 0.22)

    /// One letter of a word rolling out or in.
    public static let letter = Animation.easeOut(duration: 0.26)

    /// How far behind a letter starts on the one before it, in seconds.
    ///
    /// 18 ms, not the 50–100 ms a *list* stagger wants: a list has five rows and a word has
    /// sixteen letters, so a list's offset would take 800 ms to say one word. Sixteen at 18 ms
    /// is 288 ms of stagger over a 260 ms roll — 548 ms in all, which is nearly the whole budget
    /// a 600 ms beat leaves, and the reason the staggered roll is the alternative rather than
    /// the default.
    public static let stagger = 0.018
}
