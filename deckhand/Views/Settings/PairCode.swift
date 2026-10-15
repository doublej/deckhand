import DeckhandKit
import SwiftUI
import UIKit

/// The six digits the Mac is showing, traded for a token of this phone's own.
///
/// It needs only the Address: `POST /pair` is the one route besides `/health` with no token on
/// it, and the window it spends was opened by the person at the Mac (`just pair`, or Pair a
/// device on Deckhand's page in utt). The Token field above stays, because the Mac's own token
/// still works everywhere — from outside the house, for one.
struct PairCode: View {
    @Bindable var model: AppModel
    @State private var code = ""
    @State private var pairing = false
    @State private var said: String?

    var body: some View {
        SettingRow("Code", detail: said ?? "On the Mac: just pair, or Pair a device in utt.") {
            HStack(spacing: Spacing.small) {
                TextField("123 456", text: $code)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(Typography.mono)
                    .frame(maxWidth: 90)
                Button(pairing ? "Pairing…" : "Pair") { Task { await pair() } }
                    .buttonStyle(.bordered)
                    .tint(Palette.tint)
                    .disabled(pairing || code.filter(\.isNumber).count != 6)
            }
        }
    }

    private func pair() async {
        guard let base = model.settings.baseURL else {
            said = "Pick a Mac or type its address first."
            return
        }
        pairing = true
        defer { pairing = false }
        do {
            let paired = try await DeckhandClient(baseURL: base, token: "")
                .pair(code: code, name: UIDevice.current.name)
            model.settings.token = paired.token
            model.settings.mac = paired.mac.id
            model.saveSettings()
            code = ""
            said = "Paired with \(paired.mac.name)."
            await model.checkConnection()
        } catch {
            said = model.reason(error)
        }
    }
}
