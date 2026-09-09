/// The values, as custom properties. The other half of `ArtifactStyle`.
///
/// Copied from `Palette.swift`, `Spacing.swift` and `Typography.swift` — never re-picked. A
/// colour with no name on the web (`Color.primary`, `Color.secondary`, the grouped backgrounds)
/// is written out as the value UIKit resolves it to, under the name of the token it stands in
/// for, so the two can still be read side by side.
extension ArtifactStyle {
    static let tokens = """
    :root {
      color-scheme: light dark;
      /* Carries the tint into a radio, a checkbox and a slider's filled track, for free. */
      accent-color: var(--dh-tint);

      /* Palette.swift */
      --dh-tint: #3eafb4;
      /* Palette.tint at 0.15, the share Chrome.Meter draws its track with. */
      --dh-tint-soft: rgba(62, 175, 180, 0.15);
      --dh-recording: #d4501e;
      --dh-lcd-ground: #303027;
      --dh-lcd-green: #9ad17a;
      --dh-lcd-yellow: #e0a022;
      --dh-lcd-red: #ff5a2e;
      /* Color.primary / .secondary / .secondary.opacity(0.7), as UIKit resolves them. */
      --dh-text-primary: #000;
      --dh-text-secondary: rgba(60, 60, 67, 0.6);
      --dh-text-tertiary: rgba(60, 60, 67, 0.42);
      --dh-hairline: rgba(0, 0, 0, 0.08);
      --dh-tile-idle: rgba(0, 0, 0, 0.08);
      /* secondarySystemGroupedBackground, and the page it sits on. */
      --dh-surface: #fff;
      --dh-ground: #f2f2f7;

      /* Spacing.swift */
      --dh-xxs: 4px;
      --dh-xs: 8px;
      --dh-s: 12px;
      --dh-m: 16px;
      --dh-l: 24px;
      --dh-xl: 32px;

      /* Radius */
      --dh-r-s: 8px;
      --dh-r-m: 12px;
      --dh-r-l: 16px;
      --dh-r-xl: 20px;
      --dh-r-pill: 999px;

      /* Typography.swift — system faces only, because utt has none of its own. */
      --dh-face: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
      --dh-face-mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace;
      --dh-t-page-title: 20px;
      --dh-t-lead: 17px;
      /* primaryRow and prose are the same size; body copy and a row are the same voice. */
      --dh-t-body: 14px;
      --dh-t-subtitle: 12px;
      --dh-t-mono: 12px;
      /* hint, and a card's label. */
      --dh-t-hint: 11px;
      --dh-t-state: 9px;

      /* A thumb. Not a Swift token: UIKit hands this out and the web does not. */
      --dh-touch: 44px;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --dh-text-primary: #fff;
        --dh-text-secondary: rgba(235, 235, 245, 0.6);
        --dh-text-tertiary: rgba(235, 235, 245, 0.42);
        --dh-hairline: rgba(255, 255, 255, 0.08);
        --dh-tile-idle: rgba(255, 255, 255, 0.08);
        --dh-surface: #1c1c1e;
        --dh-ground: #000;
      }
    }
    """
}
