import Foundation

/// A slip whose questions are answered by talking, and the one thing in this folder a web view
/// never sees.
///
/// A phone dictates better than it types, and an agent with six questions has until now had two
/// bad options: six textareas on a page, or six sentences in a row in the session. This is the
/// third — the agent writes one page holding its questions, and the person gets one card per
/// question with the app's own talk mark on it.
///
/// **The page is still the page.** It is ordinary HTML, it renders in a browser, it passes
/// `demos/check.py`, and an app that has never heard of any of this shows it as a form and gets
/// the same answer back. What makes it an aloud slip is a block of JSON inside it that says what
/// the questions are — the same block the page renders *itself* from, so the two renderings
/// cannot drift apart. The app reads that block and draws cards instead; the HTML is the
/// representation and SwiftUI is the rendering.
///
/// It is parsed out of the HTML here rather than asked of a live web view. The app already holds
/// the page as a string before anything is drawn, string work needs no WebKit and no simulator to
/// test, and the aloud path then never builds a web view at all.
///
/// Every way this can fail lands on the same side: nothing parses, `declared` answers nil, and the
/// slip is a web page like every other slip. A page that gets the block wrong is a page that
/// works.
public struct Aloud: Equatable, Sendable {
    /// One question, and one card.
    public struct Question: Equatable, Identifiable, Sendable {
        /// The key this question's answer arrives under. The agent's own, so it reads the answer
        /// by the name it asked under: `{"answer": {"scope": "…"}}`.
        public let id: String
        /// The question itself, as it is said to the person.
        public let ask: String
        /// The line under it, where there is one — what the agent would have added in brackets.
        public let hint: String

        public init(id: String, ask: String, hint: String = "") {
            self.id = id
            self.ask = ask
            self.hint = hint
        }
    }

    public let questions: [Question]

    public init(questions: [Question]) { self.questions = questions }

    /// The attribute that marks the block. Written by the template; a page that spells it any
    /// other way is a page that renders as HTML, which is a working page and not a broken one.
    public static let marker = "id=\"deckhand-aloud\""

    /// The questions a page declares, or nil where it declares none.
    ///
    /// Deliberately not a parse of the whole document. Everything between the marked tag's `>`
    /// and its `</script` is handed to `JSONDecoder`, which is the strict half — a block that is
    /// not JSON, or is JSON of the wrong shape, is no block at all.
    public static func declared(in html: String) -> Aloud? {
        guard let block = block(in: html),
              let found = try? JSONDecoder().decode(Declared.self, from: Data(block.utf8)) else {
            return nil
        }
        var seen = Set<String>()
        let questions = found.questions.compactMap { row -> Question? in
            let id = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let ask = row.ask.trimmingCharacters(in: .whitespacesAndNewlines)
            // A question with no id has nowhere to put its answer, and a second question sharing
            // an id would quietly overwrite the first one's — so the first spelling wins and the
            // rest are dropped rather than merged.
            guard !id.isEmpty, !ask.isEmpty, seen.insert(id).inserted else { return nil }
            return Question(id: id,
                            ask: ask,
                            hint: (row.hint ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return questions.isEmpty ? nil : Aloud(questions: questions)
    }

    /// The text between the marked tag and the end of the script it is on.
    private static func block(in html: String) -> String? {
        guard let mark = html.range(of: marker),
              let opened = html.range(of: ">", range: mark.upperBound..<html.endIndex),
              let closed = html.range(of: "</script", options: .caseInsensitive,
                                      range: opened.upperBound..<html.endIndex) else { return nil }
        return String(html[opened.upperBound..<closed.lowerBound])
    }

    /// What the person answered last time, per question.
    ///
    /// The same shape a form slip answers with, read back the same way the demo page reads its
    /// own: `{"answer": {id: words}}`. Anything else is nothing answered — a page whose questions
    /// have changed since it was answered is the page's problem to survive, and the honest way to
    /// survive it is an empty card rather than somebody else's words in it.
    public static func said(in answerJSON: String) -> [String: String] {
        guard let data = answerJSON.data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = body["answer"] as? [String: Any] else { return [:] }
        return answers.compactMapValues { $0 as? String }
    }

    /// Everything said, as the JSON text of one answer.
    ///
    /// `{"answer": …, "completedCount": …}`, which is what `ask` `type: "form"` comes back with
    /// and what `demos/form.html` already sends — so an agent that can read a form answer reads
    /// this one without learning anything new. A question nobody said anything to is left out
    /// rather than sent empty: absent means unanswered everywhere else in this system.
    ///
    /// Nil where nothing at all was said. There is no answer to send then, and `respond(null)`
    /// is refused by the Mac on purpose.
    public static func value(of said: [String: String]) -> String? {
        let kept = said
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }
        guard !kept.isEmpty else { return nil }
        let body: [String: Any] = ["answer": kept, "completedCount": kept.count]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        return String(bytes: data, encoding: .utf8)
    }
}

/// The block as it is written, tolerant of a missing hint and nothing else. At file scope rather
/// than inside `Aloud`, where the row would be a type two levels deep and the lint refuses those.
private struct Declared: Decodable {
    let questions: [DeclaredQuestion]
}

private struct DeclaredQuestion: Decodable {
    let id: String
    let ask: String
    let hint: String?
}
