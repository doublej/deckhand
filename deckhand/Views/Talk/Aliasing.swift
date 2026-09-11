import DeckhandKit
import SwiftUI

/// Fixing a misheard word where you are reading it, and for good.
///
/// The staging card shows what utt made of a clip. When one word of it is wrong, the two things
/// somebody wants are the same move: correct it here, and never see it again. This is that move.
/// The correction goes onto the Mac's own alias list, which runs on every clip from then on —
/// this session's, every other session's, and the manager's.
///
/// **Why tapping words rather than the system's selection menu.** The prompt is a `Text` in a
/// `ScrollView` on a card that hugs its own height, and the menu that could carry a custom item
/// belongs to `UITextView` — which scrolls itself, posts no height back and would take the card's
/// layout with it. The thing actually being picked is usually two words ("deck hand"), which a
/// double-tap cannot select anyway. So this is the app's own surface, the same answer
/// `SayOnPage` reaches for a web view's selection: tap the words that came out wrong, type what
/// was said, done. `Sources/DeckhandKit/CLAUDE.md` has the WebKit half of that story.
///
/// The right-hand side is typed and not spoken, for `Pairs`' reason: it is the spelling the
/// transcriber will not give you, which is the whole point of the row.
struct Aliasing: View {
    /// The words as they stand on the card, corrections and all — what is on screen is what you
    /// are pointing at.
    let words: String
    /// Everything already on the Mac's list, so a word aliased twice is one row rather than two.
    let existing: [Alias]
    /// The new list whole, and the words on the card with the new alias already applied to them.
    /// Both together, because they are one move: the person is looking at the mistake, and a rule
    /// saved without fixing what is on screen asks them to correct the same word twice.
    let save: ([Alias], String) -> Void
    @Environment(\.dismiss) private var dismiss
    /// Which words are tapped, by their place in the sentence. A set of indices rather than the
    /// strings themselves: the same word twice in one prompt is two chips, and tapping the second
    /// must not light the first.
    @State private var picked: Set<Int> = []
    @State private var meant = ""
    @FocusState private var typing: Bool

    private var parts: [String] { AliasText.words(of: words) }

    /// The left-hand side as it stands: the tapped words in the order they were said, whatever
    /// order they were tapped in.
    private var heard: String { AliasText.heard(picked.sorted().map { parts[$0] }) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    said
                    if !heard.isEmpty { correction }
                    if !existing.isEmpty { already }
                }
                .padding(Spacing.medium)
            }
            .background(Palette.surfaceGround)
            .navigationTitle("Alias a word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Palette.tint)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store() }
                        .tint(Palette.tint)
                        .disabled(heard.isEmpty)
                        .accessibilityIdentifier("save-alias")
                }
            }
        }
    }

    /// The prompt, word by word, each one a target. Nothing is pre-selected: the app has no idea
    /// which word is wrong and a guess would be one more thing to undo.
    private var said: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Text("Tap the words that came out wrong")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
            Wrapped(spacing: Spacing.xxs) {
                ForEach(parts.indices, id: \.self) { spot in
                    word(spot)
                }
            }
        }
    }

    private func word(_ spot: Int) -> some View {
        let lit = picked.contains(spot)
        return Button {
            if lit { picked.remove(spot) } else { picked.insert(spot) }
        } label: {
            Text(parts[spot])
                .font(Typography.mono)
                .foregroundStyle(lit ? Palette.lcdGround : Palette.textPrimary)
                .chip(lit ? Palette.tint : Palette.surfacePrimary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("alias-word")
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
    }

    /// What the pair will be. The left side is drawn rather than typed, because it is the one
    /// string that must be exactly what the transcriber produced — a letter out and the alias
    /// never fires, and nothing on screen would say so.
    private var correction: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Always write it as")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
            HStack(spacing: Spacing.extraSmall) {
                Text(heard)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
                TextField("what you said", text: $meant)
                    .font(Typography.mono)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit { store() }
                    .accessibilityIdentifier("alias-meant")
            }
            .padding(Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Palette.surfacePrimary)
            )
            // Only ever about what is already there: an empty right-hand side is a deletion, and
            // a person choosing that should be told so rather than stopped.
            if meant.isEmpty {
                Text("Leave it empty to drop the word instead.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        // The box appears the moment a word is tapped, so the keyboard comes with it rather than
        // asking for a second press on a field nobody has to look for.
        .onAppear { typing = true }
    }

    /// What is already on the list, and the way off it. A list that can only be added to is a
    /// list nobody trusts — and the alias that fires wrongly is the one you most want gone from
    /// the screen you are standing on. The fuller editor is in Settings.
    private var already: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("ALREADY ALIASED")
                .font(Typography.eyebrow)
                .tracking(1.0)
                .foregroundStyle(Palette.textTertiary)
            ForEach(existing.indices, id: \.self) { spot in
                HStack(spacing: Spacing.extraSmall) {
                    Text(existing[spot].first ?? "")
                        .foregroundStyle(Palette.textTertiary)
                        .strikethrough(true, color: Palette.textTertiary)
                    Image(systemName: "arrow.right").font(.system(size: 9))
                    Text(existing[spot].last ?? "").foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                    Button {
                        // The words on the card are left exactly as they are: an alias being
                        // dropped says nothing about the sentence it already corrected, and
                        // putting the misheard word back would be the app undoing a reading
                        // nobody asked it to undo.
                        save(existing.enumerated().filter { $0.offset != spot }.map(\.element),
                             words)
                        dismiss()
                    } label: {
                        Image(systemName: "minus.circle").font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityLabel("Remove this alias")
                }
                .font(Typography.mono)
                .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    /// The new row goes on the end, and a word already on the list is corrected rather than
    /// doubled — the Mac does the same on its side, but a screen that sent two rows and got one
    /// back would have shown somebody a list that never existed.
    private func store() {
        guard !heard.isEmpty else { return }
        let said = meant.trimmingCharacters(in: .whitespaces)
        let folded = heard.lowercased()
        var rows = existing.filter { ($0.first ?? "").lowercased() != folded }
        rows.append([heard, said])
        save(rows, AliasText.swapped(words, heard: heard, meant: said))
        dismiss()
    }
}

/// A row of things that wraps, which SwiftUI has no stack for.
///
/// Written against `Layout` rather than measured with a `GeometryReader` and a grid of guesses:
/// the protocol hands over the real proposed width and each subview's real size, which is the
/// whole problem. Words are what this lays out, so it reads as the sentence it is — a
/// `LazyVGrid` of equal columns would space "a" and "transcription" alike and stop being prose.
struct Wrapped: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let places = laidOut(in: proposal.width ?? .infinity, subviews: subviews)
        let height = places.map(\.bottom).max() ?? 0
        return CGSize(width: proposal.width ?? places.map(\.trailing).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for (spot, place) in laidOut(in: bounds.width, subviews: subviews).enumerated() {
            subviews[spot].place(
                at: CGPoint(x: bounds.minX + place.across, y: bounds.minY + place.down),
                proposal: ProposedViewSize(width: place.width, height: place.height)
            )
        }
    }

    /// Where one thing goes, relative to the layout's own origin. `across` and `down` rather
    /// than the two letters everybody reaches for: SwiftLint wants three characters, and the
    /// two words say which way each one runs. See `.claude/rules/swift-naming.md`.
    private struct Place {
        var across: CGFloat
        var down: CGFloat
        var width: CGFloat
        var height: CGFloat
        var trailing: CGFloat { across + width }
        var bottom: CGFloat { down + height }
    }

    /// One pass, left to right, breaking when the next thing would not fit. `line` carries the
    /// tallest thing in the row so far, which is what the next row drops by — a word with a
    /// descender must not be sat on by the row under it.
    private func laidOut(in width: CGFloat, subviews: Subviews) -> [Place] {
        var places: [Place] = []
        var across: CGFloat = 0
        var down: CGFloat = 0
        var line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // Never break on the first thing in a row: something wider than the whole width has
            // to go somewhere, and a row it overflows is better than an empty one above it.
            if across > 0, across + size.width > width {
                down += line + spacing
                across = 0
                line = 0
            }
            places.append(Place(across: across, down: down,
                                width: size.width, height: size.height))
            across += size.width + spacing
            line = max(line, size.height)
        }
        return places
    }
}
