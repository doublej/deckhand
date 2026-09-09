import DeckhandKit
import SwiftUI

/// What the Mac does to words on their way into *this* session, in the order it does it.
///
/// Nothing on this page knows what a filter is. The Mac sends a name, a sentence and a list of
/// fields with a kind each; this draws a switch per filter and a control per kind. That is the
/// whole arrangement: a filter written on the Mac this afternoon is on this page this afternoon.
///
/// It lives on the session rather than in global Settings because a chain belongs to a terminal.
/// What you want done to words going into the project you are arguing with the build about is not
/// what you want done to words going into the one you are writing prose in.
struct SessionFilters: View {
    @Bindable var model: AppModel
    let session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    chain
                    footline
                }
                .padding(Spacing.medium)
            }
            .background(Palette.surfaceGround)
            .navigationTitle("On the way in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Palette.tint)
                }
            }
        }
        .task { await model.loadFilters(for: session) }
        // Both ways off this page come through here — Done and a swipe down — and a save per
        // keystroke is what the Mac's own plugin page learned not to do.
        .onDisappear { Task { await model.saveFilters() } }
    }

    private var chain: some View {
        SettingsGroup("On the way in") {
            if model.filterChain.isEmpty {
                SettingRow("Nothing", detail: empty) { EmptyView() }
            }
            ForEach(model.filterChain) { row in
                filter(row)
            }
        }
    }

    /// Which terminal this is for, said out loud. The same chain used to be the Mac's and is now
    /// one session's, and nobody should have to discover that by finding a different chain on the
    /// next session down.
    private var footline: some View {
        Text("Runs for \(session.name) only. Another session has its own chain.")
            .font(Typography.hint)
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, Spacing.xxs)
    }

    /// One filter: what it is, whether it runs, where it sits, and the fields it takes. The
    /// fields sit under it rather than on a page of their own — there are two or three of them
    /// and they mean nothing away from the switch that decides whether they are read at all.
    private func filter(_ row: FilterRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            SettingRow(model.describe(row)?.title ?? row.filter, detail: summary(row)) {
                HStack(spacing: Spacing.extraSmall) {
                    move(row, by: -1, symbol: "chevron.up")
                    move(row, by: 1, symbol: "chevron.down")
                    Toggle(row.filter, isOn: running(row.id))
                        .labelsHidden()
                        .tint(Palette.tint)
                }
            }
            if row.step.isOn, let fields = model.describe(row)?.fields, !fields.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(fields) { control($0, in: row.id) }
                }
                .padding(.leading, Spacing.small)
            }
        }
    }

    /// An empty list is two different things and only one of them is about filters: a Mac that
    /// runs none, and a Mac that has not answered. Saying the first when it is the second is the
    /// quiet kind of lie the rest of this app goes out of its way not to tell.
    private var empty: String {
        model.connection.isHealthy
            ? "This Mac runs no filters over what you say."
            : "Not asked yet — the Mac has not answered."
    }

    /// The Mac's own sentence about the filter. A step it no longer offers says so instead:
    /// the setting is kept and still switchable, but there is nothing here to describe it with.
    private func summary(_ row: FilterRow) -> String {
        guard let filter = model.describe(row) else {
            return "This Mac no longer offers this filter."
        }
        return filter.summary
    }

    /// Up and down rather than a drag. This page is a card of rows, and `onMove` belongs to a
    /// `List` — which this design does not use anywhere.
    private func move(_ row: FilterRow, by places: Int, symbol: String) -> some View {
        Button { model.shiftFilter(row.id, by: places) } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.tint)
        .disabled(!model.canShift(row.id, by: places))
        .accessibilityLabel(places < 0 ? "Move up" : "Move down")
    }

    /// One field, drawn from the kind the Mac gave it. A kind this phone has never heard of
    /// arrives decoded as `text`, so this switch is the whole of what it has to cover.
    @ViewBuilder private func control(_ field: FilterField, in row: FilterRow.ID) -> some View {
        switch field.kind {
        case .bool:
            SettingRow(field.label, detail: field.hint) {
                Toggle(field.label, isOn: flag(field, in: row))
                    .labelsHidden()
                    .tint(Palette.tint)
            }
        case .pairs:
            Pairs(label: field.label, hint: field.hint, rows: rows(field, in: row))
        case .text, .number:
            SettingRow(field.label, detail: field.hint) {
                TextField(field.label, text: typed(field, in: row))
                    .keyboardType(field.kind == .number ? .decimalPad : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(Typography.mono)
                    .frame(maxWidth: 150)
            }
        }
    }

    // Every control reads the model rather than the row it was drawn with, and addresses that row
    // by its id. Not by index — the chain is reordered underneath these, so an index is the wrong
    // row by the time anybody types into it — and not by filter name, because the same filter can
    // be in the chain twice and by name both rows would be the first one.

    private func running(_ row: FilterRow.ID) -> Binding<Bool> {
        Binding(get: { model.isRunning(row) },
                set: { model.setFilter(row, running: $0) })
    }

    private func flag(_ field: FilterField, in row: FilterRow.ID) -> Binding<Bool> {
        Binding(get: { model.value(of: field, in: row).flag },
                set: { model.setValue(.bool($0), of: field.key, in: row) })
    }

    /// A number is typed, so it is a string until it is read back. `JSONValue.number` keeps a
    /// whole number whole — the Mac wrote 5, not 5.0, and it is getting 5 back.
    private func typed(_ field: FilterField, in row: FilterRow.ID) -> Binding<String> {
        Binding(get: { model.value(of: field, in: row).text },
                set: { typed in
                    let value: JSONValue = field.kind == .number ? .number(typed) : .string(typed)
                    model.setValue(value, of: field.key, in: row)
                })
    }

    private func rows(_ field: FilterField, in row: FilterRow.ID) -> Binding<[[String]]> {
        Binding(get: { model.value(of: field, in: row).rows },
                set: { model.setValue(.rows($0), of: field.key, in: row) })
    }
}
