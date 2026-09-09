import Foundation
import Testing

@testable import DeckhandKit

@Suite("Artifact stylesheet")
struct ArtifactStyleTests {
    /// Both halves reach the page the viewer injects. `css` is built by concatenation across two
    /// files, which is exactly the join that can silently lose one of them.
    @Test("the sheet carries its tokens and its rules")
    func whole() {
        #expect(ArtifactStyle.css.contains(":root {"))
        #expect(ArtifactStyle.css.contains("--dh-tint: #3eafb4;"))
        #expect(ArtifactStyle.css.contains("main { max-width"))
        #expect(ArtifactStyle.css.contains("@media (prefers-color-scheme: dark)"))
    }

    /// Every property a rule reads is one the tokens declare. Renaming a token in one half and
    /// not the other leaves CSS that parses, renders, and is quietly missing a colour — which is
    /// the one failure here nobody would see on a phone.
    @Test("no rule reads a token that is not declared")
    func declared() {
        let declared = Set(matches(#"--dh-[a-z0-9-]+(?=\s*:)"#))
        let used = Set(matches(#"(?<=var\()--dh-[a-z0-9-]+"#))
        #expect(!declared.isEmpty)
        #expect(used.subtracting(declared).isEmpty)
    }

    /// A thumb. The floor is the reason this is a token at all, so it is worth pinning: the
    /// sheet is the only thing standing between an artifact and a 20pt tap target.
    @Test("nothing pressable is smaller than a thumb")
    func thumb() {
        #expect(ArtifactStyle.css.contains("--dh-touch: 44px;"))
        for rule in ["button {", ".rows > * {"] {
            #expect(ArtifactStyle.css.contains(rule))
        }
        #expect(ArtifactStyle.css.contains("min-height: var(--dh-touch);"))
    }

    private func matches(_ pattern: String) -> [String] {
        let expression = try? NSRegularExpression(pattern: pattern)
        let css = ArtifactStyle.css
        let range = NSRange(css.startIndex..., in: css)
        return (expression?.matches(in: css, range: range) ?? []).compactMap {
            Range($0.range, in: css).map { String(css[$0]) }
        }
    }
}
