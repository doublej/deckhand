import DeckhandKit
import SwiftUI

/// What the clip in the review card cost, as one line under it, opening into the whole breakdown.
///
/// One number at rest and the slowest stage beside it, because that is the whole of what a
/// person wants while reading their own words back: is this normal, and if it is not, which end
/// was it. Everything else is a tap away rather than in the way.
struct ClipCost: View {
    let timing: ClipTiming
    @State private var open = false

    var body: some View {
        Button { open = true } label: { line }
            .buttonStyle(.plain)
            .accessibilityIdentifier("clip-cost")
            .accessibilityLabel("What this clip cost, stage by stage")
            .sheet(isPresented: $open) { sheet }
    }

    private var line: some View {
        HStack(spacing: Spacing.xxs) {
            Text(TimingsView.spelled(timing.total))
            if let slowest = timing.slowest {
                Text("· \(slowest.title.lowercased()) \(TimingsView.spelled(slowest.took))")
                    .foregroundStyle(Palette.textTertiary)
            }
            Image(systemName: "chevron.right").font(.system(size: 8))
            Spacer(minLength: 0)
        }
        .font(Typography.hint)
        .foregroundStyle(Palette.textSecondary)
        .frame(minHeight: 24, alignment: .leading)
        .contentShape(.rect)
    }

    /// A page, on the system's own ground: it is a table of numbers to read, not part of the rail.
    private var sheet: some View {
        NavigationStack {
            ScrollView {
                TimingsView(timing: timing)
                    .padding(Spacing.medium)
            }
            .navigationTitle("What that cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { open = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
