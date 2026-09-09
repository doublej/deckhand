/// Deckhand's design language as one stylesheet, injected into an artifact before its own styles.
///
/// A mirror of `Palette.swift`, `Typography.swift`, `Spacing.swift`, `Prose.swift`,
/// `Chrome.swift` and `StateWord.swift`. Every value here is **copied** from those files and
/// never re-picked — the same rule that governs how this app treats utt's tokens governs this
/// too. A change there is a change here, or an artifact stops looking like the app it opens
/// inside. The values live next door in `ArtifactTokens.swift`; this file is what a page gets
/// for writing plain semantic HTML.
///
/// Two things it is not. It is not a component library: an artifact writes plain semantic HTML
/// and this gives that HTML the app's voice. And it is not authoritative — it goes in *before*
/// the page, so element selectors and single classes only, no `!important` except `[hidden]`,
/// and nothing a page cannot take back in a line.
///
/// Phone-shaped only: one column, nothing a thumb can press smaller than `--dh-touch`, the
/// safe-area insets respected, and both schemes, because an artifact is a page on the system's
/// own ground rather than the rail's forced dark.
public enum ArtifactStyle {
    /// The stylesheet, for the viewer to inject ahead of the artifact's own `<style>`.
    public static let css: String = tokens + "\n" + page

    /// What the tokens are *for*: a page that writes a heading, a bullet, a row of settings or
    /// a button, and gets the app's voice without naming a single value of its own.
    static let page = """
    *,
    *::before,
    *::after { box-sizing: border-box; }

    /* The one !important here: a page toggles a section with el.hidden, and several rules
       below set display, which would otherwise win and show it anyway. */
    [hidden] { display: none !important; }

    html { -webkit-text-size-adjust: 100%; }

    body {
      margin: 0;
      min-height: 100dvh;
      background: var(--dh-ground);
      color: var(--dh-text-primary);
      font-family: var(--dh-face);
      font-size: var(--dh-t-body);
      line-height: 1.5;
      padding:
        calc(env(safe-area-inset-top) + var(--dh-l))
        calc(env(safe-area-inset-right) + var(--dh-m))
        calc(env(safe-area-inset-bottom) + var(--dh-l))
        calc(env(safe-area-inset-left) + var(--dh-m));
    }

    /* One column, phone width, centred if the viewer is ever wider than a phone. */
    main { max-width: 30rem; margin: 0 auto; }

    /* Prose. The app renders a heading, a bullet, a paragraph and inline code in a particular
       way; an artifact's h2, ul and code read as the same family. */

    h1 {
      font-size: var(--dh-t-page-title);
      font-weight: 600;
      line-height: 1.25;
      margin: 0 0 var(--dh-s);
    }

    /* Prose.heading and the label over a SettingsGroup are one object: 9pt mono, tracked,
       uppercase, tertiary. The air above it is what separates one section from the last, and it
       is deliberately far larger than the gap between the lines inside one. */
    h2,
    h3,
    .eyebrow {
      font-family: var(--dh-face-mono);
      font-size: var(--dh-t-state);
      font-weight: 600;
      letter-spacing: 1px;
      text-transform: uppercase;
      color: var(--dh-text-tertiary);
      margin: var(--dh-xl) 0 var(--dh-s);
    }

    .eyebrow,
    h2:first-child,
    h3:first-child { margin-top: 0; }

    p { margin: 0 0 var(--dh-m); color: var(--dh-text-secondary); }

    /* The line that has to survive being read at arm's length. One big jump near the top does
       more for a page than several small ones spread through it. */
    .lead {
      font-size: var(--dh-t-lead);
      line-height: 1.45;
      color: var(--dh-text-primary);
      margin-bottom: var(--dh-l);
    }

    ul { list-style: none; padding: 0; margin: 0 0 var(--dh-m); }
    ul li { position: relative; padding: var(--dh-xs) 0 var(--dh-xs) var(--dh-m); }

    /* A dot from the grid the marks are drawn on, not a typographic bullet. */
    ul li::before {
      content: "";
      position: absolute;
      left: 0;
      top: 1.1em;
      width: 4px;
      height: 4px;
      border-radius: 50%;
      background: var(--dh-tint);
    }

    code { font-family: var(--dh-face-mono); font-size: var(--dh-t-mono); color: var(--dh-tint); }

    pre {
      font-family: var(--dh-face-mono);
      font-size: var(--dh-t-mono);
      overflow-x: auto;
      margin: 0;
      padding: var(--dh-s);
      background: var(--dh-surface);
      border: 0.5px solid var(--dh-hairline);
      border-radius: var(--dh-r-s);
    }

    strong { font-weight: 600; color: var(--dh-text-primary); }
    a { color: var(--dh-tint); }
    hr { border: 0; border-top: 0.5px solid var(--dh-hairline); margin: var(--dh-l) 0; }
    small, .hint { font-size: var(--dh-t-hint); color: var(--dh-text-tertiary); }

    /* Chrome.swift. One card, rows inside it, and never a card inside a card. */

    .card,
    .rows {
      background: var(--dh-surface);
      border: 0.5px solid var(--dh-hairline);
      border-radius: var(--dh-r-m);
      margin: 0 0 var(--dh-m);
    }

    .card { padding: var(--dh-m); }

    /* Each child of .rows is a SettingRow: its words take the space, its control sits at the
       end, and it is never shorter than a thumb. */
    .rows > * {
      display: flex;
      align-items: center;
      gap: var(--dh-m);
      min-height: var(--dh-touch);
      padding: var(--dh-xs) var(--dh-m);
    }

    .rows > * + * { border-top: 0.5px solid var(--dh-hairline); }
    .rows > * > :first-child { flex: 1; min-width: 0; }
    .rows small { display: block; }

    button {
      font-family: inherit;
      font-size: var(--dh-t-body);
      min-height: var(--dh-touch);
      padding: 0 var(--dh-m);
      color: var(--dh-text-primary);
      background: var(--dh-surface);
      border: 0.5px solid var(--dh-hairline);
      border-radius: var(--dh-r-m);
      -webkit-tap-highlight-color: transparent;
    }

    button.primary { color: #fff; background: var(--dh-tint); border-color: transparent; font-weight: 600; }
    button:disabled { opacity: 0.4; }

    /* The answer: the thing the page came for, last, with air above it. */
    .actions { display: flex; gap: var(--dh-s); margin-top: var(--dh-l); }
    .actions > button { flex: 1; }

    input[type="text"],
    input[type="password"],
    textarea {
      font-family: inherit;
      /* 16px rather than a row's 14: under 16 WebKit zooms the page when the field takes focus,
         and pinch-zoom stays available, which a maximum-scale on the viewport would cost. */
      font-size: 16px;
      width: 100%;
      min-height: var(--dh-touch);
      padding: var(--dh-s);
      color: var(--dh-text-primary);
      background: var(--dh-surface);
      border: 0.5px solid var(--dh-hairline);
      border-radius: var(--dh-r-s);
      -webkit-appearance: none;
      appearance: none;
    }

    input[type="radio"],
    input[type="checkbox"] { flex: none; width: 22px; height: 22px; margin: 0; }
    input[type="range"] { width: 100%; height: var(--dh-touch); margin: 0; background: none; }
    :focus-visible { outline: 2px solid var(--dh-tint); outline-offset: 2px; }

    /* StateWord: the word alone — no dot, no capsule, no border. A badge reads as something you
       press and sits beside things you actually can; it is banned app-wide and here too. */
    .state {
      font-family: var(--dh-face-mono);
      font-size: var(--dh-t-state);
      font-weight: 600;
      letter-spacing: 2px;
      color: var(--dh-text-secondary);
      margin: 0;
    }

    .state.on { color: var(--dh-lcd-green); }
    .state.wait,
    .state.busy { color: var(--dh-lcd-yellow); }
    .state.err { color: var(--dh-lcd-red); }
    .state.rec { color: var(--dh-recording); }

    /* Chrome.Meter: how full something is, and nothing else. No number of its own. */
    .meter { height: 3px; border-radius: var(--dh-r-pill); background: var(--dh-tint-soft); overflow: hidden; }
    .meter > span { display: block; height: 100%; border-radius: var(--dh-r-pill); background: var(--dh-tint); }

    /* A slider: what it is and where it stands on one line, the track under it. */
    .slider { margin-bottom: var(--dh-s); }
    .slider > .eyebrow { display: flex; justify-content: space-between; gap: var(--dh-s); margin: 0; }
    .slider .value { font-family: var(--dh-face-mono); letter-spacing: 0; color: var(--dh-tint); }
    """
}
