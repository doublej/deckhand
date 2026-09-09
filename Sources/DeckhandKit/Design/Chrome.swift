import SwiftUI

/// The surfaces a page is built from. One card, rows inside it, and never a card inside a
/// card — nesting surfaces is the muddy look utt's design notes name by name.
public struct Card<Content: View>: View {
    private let content: () -> Content
    private let spacing: CGFloat

    public init(spacing: CGFloat = Spacing.small, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Palette.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Palette.strokeHairline, lineWidth: 0.5)
            )
    }
}

/// An uppercase label over one card of rows. The label is the only thing above the card;
/// a group never carries a second title inside it.
public struct SettingsGroup<Content: View>: View {
    private let title: String
    private let content: () -> Content

    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Text(title.uppercased())
                .font(Typography.cardLabel)
                .tracking(0.3)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Spacing.xxs)
            Card(spacing: Spacing.small) {
                Group(subviews: content()) { rows in
                    ForEach(rows) { row in
                        row
                        if row.id != rows.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

/// One setting: the name, what it does underneath in smaller type, the control on the right.
/// The explanation lives here rather than in a tooltip, because a tooltip is only read by
/// someone who already suspects there is something to know.
public struct SettingRow<Control: View>: View {
    private let title: String
    private let detail: String?
    private let control: () -> Control

    public init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.primaryRow)
                if let detail {
                    Text(detail)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.extraSmall)
            control()
        }
    }
}

/// The top of a page: a glyph on its tile, the name, one line saying what this is, and room
/// on the right for the page's own control.
public struct PageHeader<Trailing: View>: View {
    private let glyph: Set<Int>
    private let title: String
    private let subtitle: String
    private let trailing: () -> Trailing

    public init(
        glyph: Set<Int>,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.glyph = glyph
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Spacing.small) {
            GlyphTile(glyph, size: 32, ground: Palette.lcdGround)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.pageTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Typography.subtitle)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.extraSmall)
            trailing()
        }
    }
}
