import DeckhandKit
import SwiftUI

/// What the Mac does to words on their way into a session, in the order it does it.
///
/// Nothing on this screen knows what a filter is. The Mac sends a name, a sentence and a list of
/// fields with a kind each; this draws a switch per filter and a control per kind. That is the
/// whole arrangement: a filter written on the Mac this afternoon is on this page this afternoon.
struct FilterSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsGroup("On the way in") {
            if model.filterChain.isEmpty {
                SettingRow("Nothing", detail: empty) { EmptyView() }
            }
            ForEach(model.filterChain) { row in
                filter(row)
            }
        }
        .task { await model.loadFilters() }
        // Both ways out of Settings come through here — Done and a swipe down — and a save per
        // keystroke is what the Mac's own plugin page learned not to do.
        .onDisappear { Task { await model.saveFilters() } }
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

    /// Up and down rather than a drag. The settings page is a card of rows, and `onMove` belongs
    /// to a `List` — which this design does not use anywhere.
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

/// A replacement list: rows of two, a way to add one and a way to take one away.
///
/// Its own control for one reason — a pair does not fit in a text box, which is the whole reason
/// the `pairs` kind exists. Full width rather than in a row's control slot: two fields and an
/// arrow squeezed into the right-hand third of a row is not something anyone can type into.
private struct Pairs: View {
    let label: String
    let hint: String
    @Binding var rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label).font(Typography.primaryRow)
            if !hint.isEmpty {
                Text(hint).font(Typography.hint).foregroundStyle(Palette.textTertiary)
            }
            // By index, because the rows are what is being edited: keyed by content, a row would
            // change identity on every letter typed into it and lose the keyboard mid-word.
            ForEach(rows.indices, id: \.self) { spot in
                row(spot)
            }
            Button("Add a replacement") { rows.append(["", ""]) }
                .buttonStyle(.plain)
                .font(Typography.hint)
                .foregroundStyle(Palette.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ spot: Int) -> some View {
        HStack(spacing: Spacing.extraSmall) {
            TextField("from", text: side(spot, 0))
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
            TextField("to", text: side(spot, 1))
            Button { rows.remove(at: spot) } label: {
                Image(systemName: "minus.circle").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textTertiary)
            .accessibilityLabel("Remove this replacement")
        }
        .font(Typography.mono)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    /// Guarded on both sides: a removal and the redraw that follows it are not one step, and an
    /// index into a row that has just gone is the crash this kind of editor is known for.
    private func side(_ spot: Int, _ half: Int) -> Binding<String> {
        Binding(get: { rows.indices.contains(spot) ? rows[spot][half] : "" },
                set: { typed in
                    guard rows.indices.contains(spot) else { return }
                    rows[spot][half] = typed
                })
    }
}
