import DeckhandKit
import SwiftUI

/// Which daemon this app talks to, and whether it starts at login.
///
/// Empty on this Mac's own daemon: `Desk` reads the token off disk and talks over loopback. The
/// fields are for a Mac reaching another one's daemon, and the login item is here because a
/// notifier that is not running notifies nobody.
struct PairingForm: View {
    @Bindable var desk: Desk
    @State private var host = ""
    @State private var token = ""

    private var typed: ServerSettings { ServerSettings(host: host, token: token) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            TextField("Address", text: $host)
            SecureField("Token", text: $token)
            HStack {
                Toggle("Open at login", isOn: Binding(get: { desk.opensAtLogin },
                                                      set: { desk.setOpensAtLogin($0) }))
                Spacer()
                Button("Pair") { desk.pair(typed) }
                    .disabled(!typed.isComplete)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(Typography.hint)
        .onAppear {
            host = desk.settings.host
            token = desk.settings.token
        }
    }
}
