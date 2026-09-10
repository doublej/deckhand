import DeckhandKit
import SwiftUI

/// The two things the Mac's own statusline says that a phone in another room cannot see: how much
/// of the week's token window is gone, and what the rail is running.
///
/// Quiet text, never a pill — neither is a state and neither is pressable. One group, set tighter
/// to each other than to the state word beside them, because they are one kind of thing; that is
/// also what buys the room, since at the footer's own 12pt the pair does not fit a 375pt phone and
/// the type is not going any smaller. The percentage is the only thing here that takes a colour,
/// and only over pace: amber is "this is going", which is what being ahead of your own week is.
///
/// A view of its own rather than a property of the overview, because that file reached its 300
/// lines. It reads better here anyway: it is about the Mac, and everything around it is about one
/// session or another.
struct Statusline: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            if let week = model.week {
                Text(week.line)
                    .font(Typography.hint)
                    .foregroundStyle(week.overPace ? Palette.lcdYellow : Palette.textTertiary)
                    // Never the one that gives way. A truncated percentage is a wrong number,
                    // where a clipped effort word is only an ugly one.
                    .fixedSize()
                    .accessibilityLabel(week.spoken)
            }
            if let running = Session.running(model.visibleSessions) {
                Text(running)
                    .font(Typography.hint)
                    .lineLimit(1)
                    .accessibilityLabel("Running \(running)")
            }
        }
    }
}
