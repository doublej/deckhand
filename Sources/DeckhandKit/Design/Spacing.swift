import CoreGraphics

/// utt's spacing scale. Nothing between the steps, so two screens never disagree by 2 points.
public enum Spacing {
    public static let xxs: CGFloat = 4
    public static let extraSmall: CGFloat = 8
    public static let small: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let extraLarge: CGFloat = 32
}

/// Rows, cards, sheets, panels.
public enum Radius {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let extraLarge: CGFloat = 20
    public static let pill: CGFloat = 999
}
