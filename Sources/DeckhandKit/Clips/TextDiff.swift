import Foundation

/// One run of a word-level diff: words both versions have, words only the earlier one had, words
/// only the later one has. Merged, so a span is a phrase rather than a word.
public enum DiffSpan: Equatable {
    case same(String)
    case removed(String)
    case added(String)
}

/// What one version of a sentence did to another, word by word.
///
/// Here rather than in the app for the reason everything pure is here: `just test` reaches it on
/// the Mac, and the one thing that goes quietly wrong in a diff — the order the removals and the
/// insertions come back in — is exactly the thing a screen cannot show you is wrong. In `Clips/`
/// because the only sentences ever handed to it are one clip's: what utt heard before its own
/// cleanup, what it handed over, and what this Mac's chain made of that.
///
/// **`CollectionDifference` numbers its two halves against two different collections.** A removal
/// carries an offset into `before`, an insertion an offset into `after`, so neither list can be
/// walked on its own. ``walkWords(_:_:cut:put:)`` advances one cursor per side and asks each in
/// turn, which is what puts a substitution's two halves in the right order — the struck words
/// first, then the ones that replaced them.
///
/// Whitespace travels with the word in front of it and is never compared, so a paragraph break
/// survives the diff and a line that only had its spacing changed is not reported as a rewrite.
public func diffWords(from before: String, to after: String) -> [DiffSpan] {
    let old = splitWords(before)
    let new = splitWords(after)
    let (cut, put) = markChanges(from: old.bare, to: new.bare)
    var runs = walkWords(old, new, cut: cut, put: put)
    // The last run carries the sentence's own trailing whitespace, which would be drawn — struck
    // through, if the sentence ended on a removal. No run can begin with whitespace, so trimming
    // both ends of that one is the same as trimming its end.
    if let last = runs.popLast() {
        runs.append((last.kind, last.words.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    return runs.map { run -> DiffSpan in
        switch run.kind {
        case .same: .same(run.words)
        case .removed: .removed(run.words)
        case .added: .added(run.words)
        }
    }
}

/// Which side a word came from, before it is a span. Its own type so merging is one comparison
/// rather than three cases of the same shape.
private enum Kind {
    case same, removed, added
}

/// A span being built: everything accumulated for one kind so far.
private typealias Run = (kind: Kind, words: String)

/// A sentence as the diff sees it: the bare words, which is what is compared, and each word with
/// the whitespace that followed it, which is what is drawn. The two lists are the same length, so
/// an offset out of `CollectionDifference` indexes either.
private struct Sentence {
    let bare: [String]
    let drawn: [String]
}

/// Which offsets of `old` are gone and which offsets of `new` are fresh. Two sets rather than the
/// change list itself, because the walk asks about one position at a time and in its own order.
private func markChanges(from old: [String], to new: [String]) -> (cut: Set<Int>, put: Set<Int>) {
    var cut: Set<Int> = []
    var put: Set<Int> = []
    for change in new.difference(from: old) {
        switch change {
        case .remove(let offset, _, _): cut.insert(offset)
        case .insert(let offset, _, _): put.insert(offset)
        }
    }
    return (cut, put)
}

/// Both sentences at once, one cursor each, in reading order.
///
/// The invariant that makes this correct: what is left of `old` once the removals are taken out
/// is, word for word, what is left of `new` once the insertions are — that is what a diff *is*.
/// So whenever neither cursor is standing on a change, the two words under them are the same
/// word, and both cursors move together. Removals are asked about first, which is why a
/// substitution reads as the old phrase struck through followed by the new one.
private func walkWords(_ old: Sentence, _ new: Sentence, cut: Set<Int>, put: Set<Int>) -> [Run] {
    var runs: [Run] = []
    var here = 0
    var there = 0
    while here < old.bare.count || there < new.bare.count {
        if here < old.bare.count, cut.contains(here) {
            append(.removed, old.drawn[here], to: &runs)
            here += 1
        } else if there < new.bare.count, put.contains(there) {
            append(.added, new.drawn[there], to: &runs)
            there += 1
        } else if here < old.bare.count, there < new.bare.count {
            append(.same, old.drawn[here], to: &runs)
            here += 1
            there += 1
        } else {
            // Unreachable: whatever is left past the other side's end is all change, so one of
            // the branches above always takes it. Here so the loop cannot spin.
            break
        }
    }
    return runs
}

/// One more word onto the run being built, or a new run where the kind has changed. This is the
/// whole of the merging: a span is only ever finished by the next word disagreeing with it.
private func append(_ kind: Kind, _ word: String, to runs: inout [Run]) {
    if runs.last?.kind == kind {
        runs[runs.count - 1].words += word
    } else {
        runs.append((kind, word))
    }
}

/// A sentence cut into words, each kept twice: bare for comparing, and with its trailing
/// whitespace for drawing.
///
/// Leading whitespace belongs to no word and is dropped — attached to the first one it would make
/// an indent read as a rewrite of the word after it.
private func splitWords(_ text: String) -> Sentence {
    var bare: [String] = []
    var drawn: [String] = []
    var index = scan(text, from: text.startIndex) { $0.isWhitespace }
    while index < text.endIndex {
        let gap = scan(text, from: index) { !$0.isWhitespace }
        let next = scan(text, from: gap) { $0.isWhitespace }
        bare.append(String(text[index..<gap]))
        drawn.append(String(text[index..<next]))
        index = next
    }
    return Sentence(bare: bare, drawn: drawn)
}

/// The first index at or after `index` where `match` stops holding.
private func scan(_ text: String, from index: String.Index, while match: (Character) -> Bool) -> String.Index {
    var index = index
    while index < text.endIndex, match(text[index]) {
        index = text.index(after: index)
    }
    return index
}
