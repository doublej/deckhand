import DeckhandKit
import SwiftUI

/// Every machine the Mac can reach, one swipe past the manager.
///
/// **What this page is for.** The rail answers "what can I talk to" — a machine that is asleep
/// simply contributes nothing to it, which is right, and which is exactly why a person needs
/// somewhere else to find out that a machine is missing and why. That is this page, and it is
/// the reason reachability is not drawn on the rail at all.
///
/// **No colour per machine.** In this app a state is a *word* (`StateWord`) and `Palette.tint`
/// is the only accent there is. A machine reads as a word plus its own glyph, the same way a
/// session does — inventing a colour per machine would be a second vocabulary for the one thing
/// this app already says one way.
struct MachinesView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: Spacing.xxs) {
                    ForEach(model.machines) { machine in
                        row(machine)
                    }
                    if model.machines.isEmpty { nothing }
                }
                .padding(.bottom, Spacing.medium)
            }
            Spacer(minLength: 0)
            foot
        }
        .padding(.horizontal, Spacing.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.lcdGround.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        Text("MACHINES")
            .font(Typography.groupLabel)
            .tracking(0.6)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.small)
    }

    /// One machine: what it is called, what it is running, and whether the Mac can reach it.
    /// Tapping it shows only its sessions on the rail; tapping the same one again shows all of
    /// them, so the filter can always be undone from the row that set it.
    private func row(_ machine: Machine) -> some View {
        Button {
            model.show(only: machine)
            withAnimation(Motion.opening) { model.manager.page = 0 }
        } label: {
            slab(machine)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(machine.title), \(detail(machine))")
        .accessibilityHint(chosen(machine) ? "Shows every machine again" : "Shows only this one")
    }

    private func slab(_ machine: Machine) -> some View {
        HStack(spacing: Spacing.small) {
            GlyphTile(DotGlyph.forName(machine.id), size: 28, prominent: chosen(machine))
            VStack(alignment: .leading, spacing: 1) {
                Text(machine.title)
                    .font(Typography.railRow)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(detail(machine))
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: Spacing.xxs)
            StateWord(machine.state)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.extraSmall)
        .background(Color.primary.opacity(chosen(machine) ? 0.11 : 0.045))
        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    private func chosen(_ machine: Machine) -> Bool { model.onlyMachine == machine.id }

    /// The second line: why it cannot be reached, or what it is running. The error wins — a
    /// machine that is off has no session count worth printing, and the reason is the thing
    /// this page exists to say.
    private func detail(_ machine: Machine) -> String {
        if !machine.reachable {
            return machine.error.isEmpty ? "Not reachable" : machine.error
        }
        let count = model.sessionCount(on: machine)
        let sessions = count == 1 ? "1 session" : "\(count) sessions"
        return "\(machine.system) · \(sessions)"
    }

    private var nothing: some View {
        Text("This Mac has not named any machines yet.")
            .font(Typography.hint)
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.small)
    }

    /// The one control: put the rail back to every machine. Only when it is not already.
    @ViewBuilder private var foot: some View {
        if model.onlyMachine != nil {
            Button("Show every machine") {
                model.show(only: nil)
                withAnimation(Motion.opening) { model.manager.page = 0 }
            }
            .font(Typography.hint)
            .foregroundStyle(Palette.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.small)
        }
    }
}
