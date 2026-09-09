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
            ForEach(model.filterChain) { step in
                filter(step)
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
    private func filter(_ step: FilterStep) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            SettingRow(model.describe(step)?.title ?? step.filter, detail: summary(step)) {
                HStack(spacing: Spacing.extraSmall) {
                    move(step, by: -1, symbol: "chevron.up")
                    move(step, by: 1, symbol: "chevron.down")
                    Toggle(step.filter, isOn: running(step.filter))
                        .labelsHidden()
                        .tint(Palette.tint)
                }
            }
            if step.isOn, let fields = model.describe(step)?.fields, !fields.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(fields) { control($0, in: step) }
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
    private func summary(_ step: FilterStep) -> String {
        guard let filter = model.describe(step) else {
            return "This Mac no longer offers this filter."
        }
        return filter.summary
    }

    /// Up and down rather than a drag. The settings page is a card of rows, and `onMove` belongs
    /// to a `List` — which this design does not use anywhere.
    private func move(_ step: FilterStep, by places: Int, symbol: String) -> some View {
        Button { model.shiftFilter(step.filter, by: places) } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.tint)
        .disabled(!model.canShift(step.filter, by: places))
        .accessibilityLabel(places < 0 ? "Move up" : "Move down")
    }

    /// One field, drawn from the kind the Mac gave it. A kind this phone has never heard of
    /// arrives decoded as `text`, so this switch is the whole of what it has to cover.
    @ViewBuilder private func control(_ field: FilterField, in step: FilterStep) -> some View {
        switch field.kind {
        case .bool:
            SettingRow(field.label, detail: field.hint) {
                Toggle(field.label, isOn: flag(field, in: step.filter))
                    .labelsHidden()
                    .tint(Palette.tint)
            }
        case .pairs:
            Pairs(label: field.label, hint: field.hint, rows: rows(field, in: step.filter))
        case .text, .number:
            SettingRow(field.label, detail: field.hint) {
                TextField(field.label, text: typed(field, in: step.filter))
                    .keyboardType(field.kind == .number ? .decimalPad : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(Typography.mono)
                    .frame(maxWidth: 150)
            }
        }
    }

    // Every control reads the model rather than the step its row was drawn with, and writes by
    // filter name: the chain is reordered underneath these, so an index would be the wrong row
    // by the time anybody typed into it.

    private func running(_ name: String) -> Binding<Bool> {
        Binding(get: { model.isRunning(name) },
                set: { model.setFilter(name, running: $0) })
    }

    private func flag(_ field: FilterField, in name: String) -> Binding<Bool> {
        Binding(get: { model.value(of: field, in: name).flag },
                set: { model.setValue(.bool($0), of: field.key, in: name) })
    }

    /// A number is typed, so it is a string until it is read back. `JSONValue.number` keeps a
    /// whole number whole — the Mac wrote 5, not 5.0, and it is getting 5 back.
    private func typed(_ field: FilterField, in name: String) -> Binding<String> {
        Binding(get: { model.value(of: field, in: name).text },
                set: { typed in
                    let value: JSONValue = field.kind == .number ? .number(typed) : .string(typed)
                    model.setValue(value, of: field.key, in: name)
                })
    }

    private func rows(_ field: FilterField, in name: String) -> Binding<[[String]]> {
        Binding(get: { model.value(of: field, in: name).rows },
                set: { model.setValue(.rows($0), of: field.key, in: name) })
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
