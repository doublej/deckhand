import SwiftUI

/// Pairing: where the Mac is, and the token the daemon printed when it started.
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
            .navigationTitle("Pair")
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
}
