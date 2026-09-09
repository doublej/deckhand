import Foundation

// Splitting a markdown file into blocks. Here rather than beside the views because every
// interesting part of it is a string edge case — a hash inside a fence, a list that starts at
// three, a dash that is the start of a sentence — and DeckhandKit is the half `just test` reaches.

extension Markdown {
    /// The five shapes a line of a real document turns into.
    ///
    /// `verbatim` carries both a fence's contents and a table's rows, because the answer to both
    /// is the same: show the source. A fence is source by definition, and a table is source
    /// because half a rendered table is worse to read than the pipes were.
    enum Block: Equatable {
        case heading(Int, String)
        case bullet(Int, String)
        case numbered(String, String)
        case paragraph(String)
        case verbatim([String])

        static func parse(_ text: String) -> [Block] {
            var walk = Walk()
            // A file's final newline is a terminator, not a blank line. Everywhere else an empty
            // line is dropped anyway; inside a fence it would be kept and draw a blank row of
            // code at the foot of the block, which is the one place it shows.
            let body = text.hasSuffix("\n") ? String(text.dropLast()) : text
            for line in body.components(separatedBy: "\n") { walk.take(line) }
            return walk.finished()
        }

        /// One line that is known not to be inside a fence or a table.
        ///
        /// Order is the precedence: a marker is only a marker at the front of the line, and the
        /// fall-through is a paragraph, so nothing is ever dropped for not being recognised.
        static func one(_ line: String) -> Block? {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { return nil }
            if let heading = heading(text) { return heading }
            if let bullet = text.afterMarker("- ") ?? text.afterMarker("* ") {
                return .bullet(depth(of: line), bullet)
            }
            if let numbered = numbered(text) { return numbered }
            return .paragraph(text)
        }

        /// `#` through `###`, and anything deeper drawn as the third.
        ///
        /// A `####` is rare in a report and three sizes is already as many as a phone column can
        /// tell apart, so a fourth hash shares the smallest heading rather than landing on the
        /// screen as four literal characters. Seven is not a heading at all, which is markdown's
        /// own rule, and the space is required: `#hashtag` is a word somebody wrote.
        private static func heading(_ text: String) -> Block? {
            let hashes = text.prefix { $0 == "#" }.count
            guard hashes > 0, hashes <= 6, text.dropFirst(hashes).hasPrefix(" ") else { return nil }
            return .heading(min(hashes, 3), String(text.dropFirst(hashes + 1)))
        }

        /// `3. text`, handing on the 3 rather than a position in a list.
        private static func numbered(_ text: String) -> Block? {
            let digits = text.prefix(while: \.isNumber)
            guard !digits.isEmpty, text.dropFirst(digits.count).hasPrefix(". ") else { return nil }
            return .numbered(String(digits), String(text.dropFirst(digits.count + 2)))
        }

        /// One step of nesting, not a count of spaces: two spaces, four spaces and a tab all
        /// mean "this belongs to the line above", and a report written by hand uses all three.
        /// One step is also the ceiling — a grandchild draws level with its parent, because a
        /// phone column has no room for a third indent and losing the line would be worse.
        private static func depth(of line: String) -> Int {
            line.hasPrefix(" ") || line.hasPrefix("\t") ? 1 : 0
        }
    }

    /// A line-by-line walk carrying two memories: whether we are inside a fence, and whether we
    /// are part-way through a table.
    ///
    /// Those two are why this cannot be a `map` over the lines the way `Prose`'s parse is.
    /// Everything between two fences is literal — a `#` in a code block is a hash and a `- ` is
    /// a dash — and that is the one bug this shape exists to make impossible.
    private struct Walk {
        private var out: [Block] = []
        /// Non-nil means we are between two fences, where every line is code whatever it says.
        private var fenced: [String]?
        /// A table is a run of adjacent rows, so it is collected until something else arrives.
        private var table: [String] = []

        mutating func take(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fenced != nil {
                // The closing fence is the only line in here with any meaning of its own.
                if trimmed.hasPrefix("```") { close() } else { fenced?.append(line) }
                return
            }
            if trimmed.hasPrefix("```") {
                close()
                fenced = []
                return
            }
            if trimmed.hasPrefix("|") {
                table.append(trimmed)
                return
            }
            close()
            if let block = Block.one(line) { out.append(block) }
        }

        mutating func finished() -> [Block] {
            // An unterminated fence at the end of the file is still the code it was. Dropping it
            // would lose the rest of a document over one missing line of backticks.
            close()
            return out
        }

        /// Whatever was being collected, finished and added. An empty fence adds nothing, or a
        /// stray pair of backticks would draw an empty box.
        private mutating func close() {
            if let open = fenced {
                if !open.isEmpty { out.append(.verbatim(open)) }
                fenced = nil
            }
            if !table.isEmpty {
                out.append(.verbatim(table))
                table = []
            }
        }
    }
}

private extension String {
    /// The rest of the line after a marker, or nil — the space is part of the marker, so a
    /// sentence beginning "-5 degrees" is a sentence and not a bullet with a number in it.
    func afterMarker(_ marker: String) -> String? {
        hasPrefix(marker) ? String(dropFirst(marker.count)) : nil
    }
}
