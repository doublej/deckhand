import SwiftUI

public extension EnvironmentValues {
    /// How this screen draws a diagram written in a fence, or nothing where it cannot.
    ///
    /// A mermaid block is a picture written down. Drawing one takes a web view, and a web view is
    /// UIKit — which cannot live in this module, because everything here has to be reachable by
    /// `just test` on the Mac with no simulator. So the shape of the seam is: `Markdown` knows a
    /// diagram when it parses one, and the app knows how to draw it.
    ///
    /// Nil is a working answer and the default on purpose. A surface that never sets one shows the
    /// source lines, which is what every surface did before this existed — so a diagram can never
    /// be the reason a transcript has a hole in it.
    ///
    /// The closure takes the fence's contents joined back into one string, because that is what a
    /// renderer wants: mermaid parses a document, not a line at a time.
    @Entry var diagram: (@MainActor (String) -> AnyView)?
}

public extension View {
    /// Teach everything inside this screen to draw the diagrams it finds.
    func diagrams(_ draw: @escaping @MainActor (String) -> AnyView) -> some View {
        environment(\.diagram, draw)
    }
}
