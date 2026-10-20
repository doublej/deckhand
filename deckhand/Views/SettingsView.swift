import DeckhandKit
import SwiftUI

/// Groups of rows, utt's way: an uppercase label, one card, a title and a sentence saying
/// what the thing does. The sentence is on the page because a tooltip is only read by
/// someone who already suspects there is something to know.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Which of the two talk-mark word transitions is running. `@AppStorage` rather than a field
    /// on `Preferences`, which is a persisted document with an initialiser, defaults and tests
    /// behind it: this is a design question with an answer coming, and two lines either way.
    @AppStorage("talk.letters") private var letters = false
    /// The word list as this page is editing it, seeded from the Mac and written back on the way
    /// out. Held here rather than bound straight through to `wants.aliases`, so that a row half
    /// typed is not a row the card behind this page is already swapping on.
    @State private var aliases: [Alias] = []
    @State private var hints: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    mac
                    buzz
                    models
                    talking
                    words
                    listening
                    route
                    linking
                    hidden
                    footline
                }
                .padding(Spacing.medium)
            }
            .task {
                await model.loadSettings()
                await model.loadAliases()
                aliases = model.wants.aliases
                await model.loadHints()
                hints = model.wants.hints
            }
            // Both ways off this page come through here — Done and a swipe down — the same place
            // `SessionFilters` writes its chain, and for the same reason.
            .onDisappear {
                if aliases != model.wants.aliases { model.storeAliases(aliases) }
                if hints != model.wants.hints { model.storeHints(hints) }
            }
            .background(Palette.surfaceGround)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.saveSettings()
                        dismiss()
                    }
                    .tint(Palette.tint)
                }
            }
        }
    }

    private var mac: some View {
        SettingsGroup("Mac") {
            SettingRow("Address",
                       detail: "Where the daemon answers. `just daemon` prints it."
                       + (model.health?.remote.map { " Off the home network: \($0)" } ?? "")) {
                TextField("m2-2.local", text: $model.settings.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .multilineTextAlignment(.trailing)
                    .font(Typography.mono)
                    .frame(maxWidth: 150)
            }
            Beacons(model: model)
            PairCode(model: model)
            SettingRow("Token", detail: "Or the long code: Copy the long code, on Deckhand's page in utt.") {
                TextField("token", text: $model.settings.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(Typography.mono)
                    .frame(maxWidth: 150)
            }
            SettingRow("Connection", detail: model.status ?? model.connection.label) {
                Button("Check") {
                    model.saveSettings()
                    Task { await model.checkConnection() }
                }
                .buttonStyle(.bordered)
                .tint(Palette.tint)
            }
        }
    }

    /// The Mac's own answer about when it may interrupt you. Every project follows this until
    /// it says otherwise on its own page, which is why the foot says where that is — a switch
    /// that is quietly overridden somewhere is a switch you stop believing.
    private var buzz: some View {
        SettingsGroup("Buzz my phone when") {
            trigger("A session finishes", "It stopped and is waiting on you.", \.finished)
            trigger("A slip is waiting", "It wrote you a page and nothing has answered it.", \.slips)
            trigger("An agent asks for me", "In its own words, rather than the Mac noticing.",
                    \.called)
            trigger("Chase a quiet session", "The Mac asks it about the asks still on its list. "
                    + "Not a notification — the Mac speaking to the session.", \.chase)
            trigger("Summarise subagents", "Let the summariser read what a session's subagents "
                    + "did, not only what it said.", \.subagents)
            SettingRow("Per project", detail: overridesLine) {
                EmptyView()
            }
        }
    }

    /// What runs where, when nothing local says otherwise. Offered by the Mac rather than listed
    /// here: a phone offering a model the daemon refuses writes a setting that does not stick.
    private var models: some View {
        SettingsGroup("Models") {
            choice("New sessions", model.wants.settings?.offers.session ?? [], \.sessionModel)
            choice("Summaries", model.wants.settings?.offers.summary ?? [], \.summaryModel)
        }
    }

    private var overridesLine: String {
        guard let count = model.wants.settings?.projects.count, count > 0 else {
            return "Hold a row in the project picker to set one project apart from these."
        }
        return count == 1
            ? "One project overrides some of these on its own page."
            : "\(count) projects override some of these on their own pages."
    }

    private func trigger(_ words: String, _ detail: String,
                         _ key: WritableKeyPath<Wants, Bool>) -> some View {
        SettingRow(words, detail: detail) {
            Toggle(words, isOn: Binding(
                get: { model.wants.everywhere[keyPath: key] },
                set: { value in Task { await model.everywhere { $0[keyPath: key] = value } } }
            ))
            .labelsHidden()
            .tint(Palette.tint)
            .disabled(model.wants.settings == nil)
        }
    }

    private func choice(_ words: String, _ offered: [String],
                        _ key: WritableKeyPath<Wants, String>) -> some View {
        SettingRow(words, detail: nil) {
            Picker(words, selection: Binding(
                get: { model.wants.everywhere[keyPath: key] },
                set: { value in Task { await model.everywhere { $0[keyPath: key] = value } } }
            )) {
                Text("Default").tag("")
                ForEach(offered, id: \.self) { Text($0).tag($0) }
            }
            // The row already says what this is. A menu picker draws no label of its own outside
            // a `Form` anyway, but saying so means the row never depends on that staying true.
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Palette.tint)
            .disabled(model.wants.settings == nil)
        }
    }

    private var talking: some View {
        SettingsGroup("Talking") {
            SettingRow("Rolling letters", detail: "How the mark's word changes while it waits: letter by letter, or the whole word sliding.") {
                Toggle("Rolling letters", isOn: $letters)
                    .labelsHidden()
                    .tint(Palette.tint)
            }
            SettingRow("Button", detail: "Hold the mark down, or tap once to start and again to send.") {
                Picker("Button", selection: talkMode) {
                    ForEach(TalkMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
    }

    /// The Mac's word list, in full, with the way off it.
    ///
    /// The card is where an alias is *made*, one word at a time, standing over the mistake. This
    /// is where the list is read and pruned — an alias that fires on the wrong word is found by
    /// reading the list, not by waiting for it to happen again.
    ///
    /// Edited here and written on the way off the page, for `SessionFilters`' reason: a text
    /// field changes on every letter, and one sentence typed into the Mac's own plugin page was
    /// forty-odd writes in four seconds.
    private var words: some View {
        SettingsGroup("Aliases") {
            Pairs(label: "Heard, and meant",
                  hint: "Swapped on every clip, in every session and the manager alike.",
                  rows: $aliases)
            // This page writes on the way out too, so a row the Mac will not keep goes quietly
            // and is simply absent the next time the list is read. Same view as `Swapping`.
            NotKept(rows: aliases)
        }
    }

    private var listening: some View {
        SettingsGroup("Listened for") {
            HintWords(label: "Words utt listens for",
                      hint: "Every session hears these. A folder adds its own under a session's On the way in.",
                      words: $hints)
        }
    }

    private var route: some View {
        SettingsGroup("How it goes in") {
            SettingRow("Read it first", detail: "Hold the transcript so you can send or discard it. Off sends the moment it comes back.") {
                Toggle("Read it first", isOn: confirms)
                    .labelsHidden()
                    .tint(Palette.tint)
            }
            SettingRow("Route", detail: model.preferences.route.explanation) {
                Picker("Route", selection: routeChoice) {
                    ForEach(DeliveryRoute.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Palette.tint)
            }
        }
    }

    private var linking: some View {
        SettingsGroup("Sessions talking") {
            SettingRow(
                "Show for",
                detail: """
                    Sessions that messaged each other inside this go on the rail as light \
                    running between them, fading as it ages. The Mac reads back exactly this \
                    far, so nothing is drawn that was not looked for.
                    """
            ) {
                Picker("Show for", selection: linkWindow) {
                    ForEach(Preferences.linkWindows, id: \.self) {
                        Text(Preferences.windowLabel($0)).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Palette.tint)
            }
        }
    }

    @ViewBuilder private var hidden: some View {
        if !model.preferences.hidden.isEmpty {
            SettingsGroup("Hidden") {
                ForEach(Array(model.preferences.hidden).sorted(), id: \.self) { key in
                    SettingRow(Preferences.name(of: key), detail: "Hidden from the rail.") {
                        Button("Show") {
                            model.preferences.setHidden(key, false)
                            model.preferences.save()
                        }
                        .buttonStyle(.bordered)
                        .tint(Palette.tint)
                    }
                }
            }
        }
    }

    private var footline: some View {
        HStack(spacing: Spacing.medium) {
            Text("deckhand \(Bundle.main.version)")
            Text(model.connection.label)
        }
        .font(Typography.hint)
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, Spacing.xxs)
    }

    private var talkMode: Binding<TalkMode> {
        Binding(get: { model.preferences.talkMode }, set: { model.setTalkMode($0) })
    }

    private var confirms: Binding<Bool> {
        Binding(get: { model.preferences.confirms }, set: { model.setConfirms($0) })
    }

    private var routeChoice: Binding<DeliveryRoute> {
        Binding(get: { model.preferences.route }, set: { model.setRoute($0) })
    }

    private var linkWindow: Binding<TimeInterval> {
        Binding(get: { model.preferences.linkWindow }, set: { model.setLinkWindow($0) })
    }
}

extension Bundle {
    var version: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
