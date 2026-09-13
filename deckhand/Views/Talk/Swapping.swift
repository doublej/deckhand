import DeckhandKit
import SwiftUI

/// Everything this Mac changes about what you say, in the order it happens.
///
/// The page exists because the answer was in two places and the question is one question. A word
/// comes out wrong, and the person is standing over it wanting to know *why* — and "why" is
/// either the Mac's own alias list, a step in this terminal's chain, or a hint that biased the
/// recogniser before there were any words to swap. Three different screens, or none at all in
/// the hints' case, and no way to see that two of them were arguing over the same word.
///
/// So: one list, in run order, each rule saying where it came from. The order is not decoration
/// — aliases run before the chain, the chain runs top to bottom, and each rule sees whatever the
/// one above it left behind. `Replacements.Follow` is that cascade said out loud.
///
/// Editable where editing already exists and nowhere else. The alias list is this Mac's and is
/// written straight back through `Pairs`, the same control the chain's own editor uses; a
/// filter's settings belong to `SessionFilters`, which is one button away rather than copied
/// here. A second editor for the same rows would be a second place for them to be wrong.
struct Swapping: View {
    @Bindable var model: AppModel
    let session: Session
    /// The session page's own recorder, lent on to the chain editor. Nil where there is none.
    var say: Dictation?
    @Environment(\.dismiss) private var dismiss
    /// The Mac's word list as this page is editing it, seeded on the way in and written on the
    /// way out. Held here rather than bound through to `wants.aliases` for `SettingsView`'s
    /// reason: a row half typed is not a row anything should be swapping on yet.
    @State private var aliases: [Alias] = []
    @State private var editingChain = false

    /// Every scope in force, worked out on the Mac side of the app so it can be tested there.
    /// The aliases are the ones being edited rather than the ones last loaded, so a row typed in
    /// takes its number and its place in the cascade as it is typed.
    private var stages: [Replacements.Stage] {
        Replacements.inForce(aliases: aliases,
                             chain: model.filterChain.map(\.step),
                             known: model.knownFilters)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    before
                    ForEach(Array(stages.enumerated()), id: \.element.id) { place, stage in
                        group(stage, number: place + 1)
                    }
                    elsewhere
                }
                .padding(Spacing.medium)
            }
            .background(Palette.surfaceGround)
            .navigationTitle("What gets swapped")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Palette.tint)
                }
            }
        }
        .task {
            await model.loadFilters(for: session)
            await model.loadAliases()
            aliases = model.wants.aliases
        }
        // Both ways off this page come through here — Done and a swipe down — the same place
        // `SettingsView` and `SessionFilters` write theirs, and for the same reason: a text field
        // changes on every letter, and a PUT per letter is that again over the network.
        .onDisappear {
            if aliases != model.wants.aliases { model.storeAliases(aliases) }
        }
        .sheet(isPresented: $editingChain) {
            SessionFilters(model: model, session: session, say: say)
        }
    }

    /// The one thing on this page that is not a replacement, first because it happens first.
    ///
    /// A hint does not swap anything — it tells utt which words to expect, so a word that is
    /// nearly one of them comes back as it. That is how a word changes with no rule below having
    /// fired, and it is the only answer this page can give to "nothing here matches, and it still
    /// came out wrong". The alias half is the sharp end: a word corrected *to*, once, is from then
    /// on a word the recogniser leans towards in every session.
    private var before: some View {
        SettingsGroup("Before there are any words") {
            SettingRow("Hints", detail: "utt is told which words to expect, so a word that is "
                       + "nearly one of these comes back as it. A bias, not a swap — and the "
                       + "reason a word can come out wrong with nothing below matching it.") {
                EmptyView()
            }
            if !hints.fromAliases.isEmpty {
                words("From your aliases", hints.fromAliases)
            }
            if !hints.fromSession.isEmpty {
                words("From this session", hints.fromSession)
            }
            words("Also", ["Deckhand's own jargon, built into the Mac"])
        }
    }

    private var hints: Replacements.Hints {
        Replacements.hints(aliases: aliases, name: session.name, cwd: session.cwd)
    }

    private func words(_ label: String, _ list: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Typography.hint).foregroundStyle(Palette.textSecondary)
            Text(list.joined(separator: "  ·  "))
                .font(Typography.mono)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(list.joined(separator: ", "))")
    }

    /// One scope: its number in the run, what it covers, and everything it does. The number is
    /// the precedence, and it is in the label rather than beside a rule because precedence is a
    /// property of the scope — every rule in a group runs before every rule in the next one.
    @ViewBuilder private func group(_ stage: Replacements.Stage, number: Int) -> some View {
        SettingsGroup("\(number) · \(stage.title)") {
            SettingRow(stage.title, detail: stage.detail) { EmptyView() }
            switch stage.doing {
            case .swaps(let rules) where stage.source == .aliases:
                Pairs(label: "Heard, and meant",
                      hint: "Swapped on every clip, in every session and the manager alike.",
                      rows: $aliases,
                      say: say)
                NotKept(rows: aliases)
                // Only the rows with something to say: the rest are already on screen in the
                // editor above, and printing all of them twice makes the warned one harder to
                // find rather than easier.
                ForEach(rules.filter { $0.follow != nil }) { rule($0) }
            case .swaps(let rules):
                // Read-only, and the button under them is the whole reason: these rows have a
                // home already. Two editors writing one list is two answers to one question.
                if rules.isEmpty { sentence("This step swaps nothing — it has no words in it.") }
                ForEach(rules) { rule($0) }
                editChain
            case .otherwise(let said):
                sentence(said)
                editChain
            }
        }
    }

    private func sentence(_ said: String) -> some View {
        Text(said)
            .font(Typography.hint)
            .foregroundStyle(Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One rule: what it matches, what it becomes, and what happens to those words below.
    private func rule(_ rule: Replacements.Rule) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.extraSmall) {
                Text(rule.heard)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
                Text(rule.meant.isEmpty ? "—" : rule.meant)
            }
            .font(Typography.mono)
            if let follow = rule.follow {
                Text(follow.label)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.lcdYellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rule.label)
    }

    private var editChain: some View {
        Button("Edit the chain") { editingChain = true }
            .buttonStyle(.plain)
            .font(Typography.hint)
            .foregroundStyle(Palette.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The honest end of the list. A swap that is in none of the groups above came from utt's own
    /// replacements, and this Mac can neither read that list nor write to it — see the head of
    /// `settings/aliases.py`. Saying so is the difference between a page that answers the
    /// question and one that quietly answers most of it.
    private var elsewhere: some View {
        Text("Nothing else on this Mac changes your words. utt keeps replacement lists of its "
             + "own, which Deckhand cannot read or write — a swap matching nothing above came "
             + "from there, and utt's own settings are where to turn it off.")
            .font(Typography.hint)
            .foregroundStyle(Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.xxs)
    }
}
