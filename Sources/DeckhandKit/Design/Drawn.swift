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

/// Pulling the diagrams out of text that is otherwise shown as it was written.
///
/// A transcript is not markdown and is not going to become markdown: a turn is drawn as the words
/// the session actually said, with addresses marked and nothing else interpreted. That is
/// deliberate — a model's asterisks are its asterisks. But a mermaid fence is the one thing in
/// there whose *contents* are not the answer, so it is lifted out and the rest is left exactly as
/// it was.
///
/// Only mermaid fences. A ```` ```swift ```` block stays inside the words with its backticks
/// showing, which is what a transcript did before this existed and what it should keep doing.
public enum Fenced {
    public enum Part: Equatable {
        case words(String)
        case diagram(String)
    }

    /// The text split into what to show and what to draw.
    ///
    /// One part for text with no fence in it, so the common case allocates nothing worth
    /// mentioning. An unterminated fence stays words — losing the back half of somebody's message
    /// to a missing line of backticks is a far worse failure than not drawing a picture.
    public static func parts(_ text: String) -> [Part] {
        guard text.contains("```mermaid") else { return [.words(text)] }
        var walk = Walk()
        for line in text.components(separatedBy: "\n") { walk.take(line) }
        let found = walk.finished()
        return found.isEmpty ? [.words(text)] : found
    }

    /// A line at a time, because a fence has state: everything between two of them belongs to the
    /// diagram whatever the line says.
    private struct Walk {
        private var found: [Part] = []
        private var words: [String] = []
        private var diagram: [String]?

        mutating func take(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if diagram != nil {
                if trimmed.hasPrefix("```") { close() } else { diagram?.append(line) }
                return
            }
            if opens(trimmed) {
                if let said = settled(words) { found.append(.words(said)) }
                words = []
                diagram = []
                return
            }
            words.append(line)
        }

        mutating func finished() -> [Part] {
            // Whatever a fence was still collecting was never a diagram, so it goes back as the
            // lines it was — the opening fence included, or the text would lose a line in silence.
            if let open = diagram { words.append(contentsOf: ["```mermaid"] + open) }
            diagram = nil
            if let said = settled(words) { found.append(.words(said)) }
            return Walk.merged(found)
        }

        /// Two runs of words with nothing between them are one run.
        ///
        /// It happens exactly once: a fence opened and never closed, so the words before it were
        /// already put down and the fence's own lines come back as words after it. Left as two,
        /// they draw as two blocks — a paragraph break through the middle of a sentence somebody
        /// wrote, which is a smaller version of the failure this whole branch exists to avoid.
        private static func merged(_ parts: [Part]) -> [Part] {
            parts.reduce(into: []) { out, part in
                if case .words(let text) = part, case .words(let before)? = out.last {
                    out[out.count - 1] = .words(before + "\n" + text)
                } else {
                    out.append(part)
                }
            }
        }

        private mutating func close() {
            if let open = diagram, !open.isEmpty {
                found.append(.diagram(open.joined(separator: "\n")))
            }
            diagram = nil
        }
    }

    /// ```` ```mermaid ```` and ```` ```mermaid title=x ````, and not ```` ```mermaidish ````.
    private static func opens(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("```") else { return false }
        let word = trimmed.dropFirst(3)
            .trimmingCharacters(in: .whitespaces)
            .prefix { !$0.isWhitespace }
            .lowercased()
        return word == "mermaid"
    }

    /// The collected lines, or nothing where they were all blank — a diagram between two
    /// paragraphs must not leave an empty line of text above and below it.
    private static func settled(_ lines: [String]) -> String? {
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}
