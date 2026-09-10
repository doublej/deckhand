import DeckhandKit
import SwiftUI

/// A glyph, and the word beside it where there is room for one. A deck column has room for two
/// glyphs and nothing else. Its own view because a picker's label is built outside the main
/// actor, which a method on the card cannot be.
struct Attach: View {
    let word: String
    let symbol: String
    let compact: Bool

    var body: some View {
        if compact {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
        } else {
            Label(word, systemImage: symbol)
        }
    }
}
