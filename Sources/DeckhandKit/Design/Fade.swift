import Foundation

/// How present a session looks on the rail, as a function of how long it has been quiet.
///
/// The rail is a list of things competing for one glance, and most of them are not what you
/// came for. Nothing here adds a decoration to say which is which: the row that last did
/// something is drawn exactly as the app has always drawn it, and the ones that have gone quiet
/// recede from it. So this can only ever take contrast away — full is the design, and age is the
/// only thing that spends it.
///
/// One multiplier over the whole row rather than a second palette. Opacity on the rail's dark
/// ground moves ink, tile and border toward that ground together, which is what "less contrast"
/// means here; picking dimmer colours for each of them would be three values to keep in step
/// and the same result.
public enum Fade {
    /// Dim, never gone. A session you have not touched since this morning is still a session you
    /// can read the name of and tap — the floor is what separates receding from hiding, and
    /// hiding is already a thing the app does on purpose and elsewhere.
    public static let floor = 0.5
    /// Full contrast inside this, because a session that stopped a minute ago has not gone
    /// quiet, it is between turns.
    static let grace: TimeInterval = 120
    /// Where the floor is reached. Past a working day's distance there is nothing left to say
    /// with contrast — eight hours ago and three days ago are both "not today".
    static let span: TimeInterval = 8 * 3600

    /// Logarithmic, so most of the travel happens in the first hour.
    ///
    /// Linear in seconds spends nearly all of its range on the difference between four hours and
    /// eight, which is a difference nobody is reading the rail for. The hour after a session
    /// stops is the hour you are deciding whether to go back to it, so that is where the visible
    /// change belongs: ten minutes reads as 0.85, an hour as 0.69, three hours as 0.59.
    public static func contrast(idleFor age: TimeInterval) -> Double {
        guard age > grace else { return 1 }
        let reach = log(min(age, span) / grace) / log(span / grace)
        return 1 - (1 - floor) * reach
    }
}

public extension Session {
    /// How this row should be drawn, given the clock.
    ///
    /// A busy session is never faded whatever its timestamp says, and that is not a nicety: the
    /// registry's `updated_at` is the moment the status last *changed*, not a heartbeat, so a
    /// session that has been working for an hour carries an hour-old timestamp. Measured on this
    /// Mac — a session reporting `busy` with `updated_at` 1553 s old while it was mid-turn.
    /// Reading that as idle age would make the hardest-working row on the rail the faintest one.
    func contrast(asOf now: Date = Date()) -> Double {
        isBusy ? 1 : Fade.contrast(idleFor: now.timeIntervalSince(lastActive))
    }
}
