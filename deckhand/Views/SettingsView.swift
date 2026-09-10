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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    mac
                    buzz
                    models
                    talking
                    route
                    hidden
                    footline
                }
                .padding(Spacing.medium)
            }
            .task { await model.loadSettings() }
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
            SettingRow("Address", detail: "Where the daemon answers. `just daemon` prints it.") {
                TextField("m2-2.local", text: $model.settings.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .multilineTextAlignment(.trailing)
                    .font(Typography.mono)
                    .frame(maxWidth: 150)
            }
            SettingRow("Token", detail: "Deckhand's page in utt: Copy pairing code.") {
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

    @ViewBuilder private var hidden: some View {
        if !model.preferences.hidden.isEmpty {
            SettingsGroup("Hidden") {
                ForEach(Array(model.preferences.hidden).sorted(), id: \.self) { name in
                    SettingRow(name, detail: "Hidden from the rail.") {
                        Button("Show") {
                            model.preferences.setHidden(name, false)
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
}

extension Bundle {
    var version: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
