import Foundation

/// One name a session can be handed: a slash command or a skill, which from a phone are the
/// same thing — a word you put in front of what you were going to say anyway.
///
/// A phone dictates a sentence well and spells `/orchestrate-sessions` badly. That is the whole
/// reason this travels to the phone at all: the names are on the Mac, and picking one from a list
/// is the difference between a command that runs and a line of text that nearly is one.
public struct SlashCommand: Codable, Hashable, Identifiable, Sendable {
    public let name: String
    public let description: String
    /// What to say after the name, where the command says. Empty for most.
    public let hint: String
    /// "command" or "skill".
    public let kind: String
    /// "project" or "user".
    public let scope: String

    public var id: String { name }

    /// As it is typed, which is the only form that matters at the far end.
    public var typed: String { "/\(name)" }

    public var isSkill: Bool { kind == "skill" }

    /// Whether this is one of the words being looked for. Matched against the name and what it
    /// says it does, because you can remember either — and 193 of them is too many to scroll.
    public func matches(_ wanted: String) -> Bool {
        let looking = wanted.trimmingCharacters(in: .whitespaces).lowercased()
        guard !looking.isEmpty else { return true }
        return name.lowercased().contains(looking) || description.lowercased().contains(looking)
    }

    /// This name at the front of some words, in place of one already there.
    ///
    /// Picking a second command corrects the first rather than stacking on it: only the first
    /// word of a prompt is a command, so a second would arrive as an argument to the first —
    /// a prompt that runs something nobody chose.
    public func infront(of words: String) -> String {
        let rest = Self.arguments(in: words)
        return rest.isEmpty ? "\(typed) " : "\(typed) \(rest)"
    }

    /// Whatever a leading command left behind, or all of it where there was no command.
    ///
    /// A leading slash is not enough to go on: `/Users/jj/dev is where it lives` is a sentence
    /// about a path, and treating its first word as a command would eat the path. So the word
    /// after the slash has to look like a name — no slashes of its own, and nothing in it a
    /// command name could not contain.
    static func arguments(in words: String) -> String {
        let whole = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard whole.hasPrefix("/") else { return whole }
        let after = whole.dropFirst()
        let head = after.prefix { !$0.isWhitespace }
        guard !head.isEmpty, head.allSatisfy(isNameish) else { return whole }
        return String(after.dropFirst(head.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What a command name may be made of, which is the Mac's rule and not one invented here.
    private static func isNameish(_ letter: Character) -> Bool {
        letter.isLetter || letter.isNumber || letter == "-" || letter == "_" || letter == ":"
    }
}
