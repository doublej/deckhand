import DeckhandKit
import SwiftUI

/// Pairing and the two choices that change how the whole app behaves.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    TextField("m2-2.local", text: $model.settings.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("token", text: $model.settings.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .font(.system(.body, design: .monospaced))

                Section("Talking") {
                    Picker("Button", selection: talkMode) {
                        ForEach(TalkMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                hiddenSection

                Section {
                    Button("Check connection") {
                        model.saveSettings()
                        Task { await model.checkConnection() }
                    }
                } footer: {
                    Text(model.status ?? "The daemon prints its address and token on start: just daemon")
                        .font(.system(.caption2, design: .monospaced))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.saveSettings()
                        dismiss()
                    }
                }
            }
        }
    }

    private var talkMode: Binding<TalkMode> {
        Binding(get: { model.preferences.talkMode }, set: { model.setTalkMode($0) })
    }

    @ViewBuilder private var hiddenSection: some View {
        if !model.preferences.hidden.isEmpty {
            Section("Hidden") {
                ForEach(Array(model.preferences.hidden).sorted(), id: \.self) { name in
                    Button("Show \(name)", systemImage: "eye") {
                        model.preferences.setHidden(name, false)
                        model.preferences.save()
                    }
                    .font(.system(.footnote, design: .monospaced))
                }
            }
        }
    }
}
