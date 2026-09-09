import DeckhandKit
import SwiftUI

/// Groups of rows, utt's way: an uppercase label, one card, a title and a sentence saying
/// what the thing does. The sentence is on the page because a tooltip is only read by
/// someone who already suspects there is something to know.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    mac
                    talking
                    route
                    hidden
                    footline
                }
                .padding(Spacing.medium)
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
            SettingRow("Address", detail: "Where the daemon answers. `just daemon` prints it.") {
                TextField("m2-2.local", text: $model.settings.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .multilineTextAlignment(.trailing)
                    .font(Typography.mono)
                    .frame(maxWidth: 150)
            }
            SettingRow("Token", detail: "From the menu bar app: Copy token.") {
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

    private var talking: some View {
        SettingsGroup("Talking") {
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
