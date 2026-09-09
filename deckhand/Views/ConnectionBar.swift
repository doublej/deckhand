import SwiftUI

/// The Mac's state, in words, at the top of every screen. Never a blank space.
struct ConnectionBar: View {
    let connection: Connection
    let status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                marker
                Text(connection.label)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(connection.isHealthy ? Color.secondary : Color.white)
                Spacer()
            }
            if let status, status != connection.label {
                Text(status)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06))
    }

    @ViewBuilder private var marker: some View {
        if connection.isWorking {
            ProgressView().controlSize(.mini).tint(.white)
        } else {
            Rectangle()
                .fill(connection.isHealthy ? .white : .white.opacity(0.3))
                .frame(width: 8, height: 8)
        }
    }
}
