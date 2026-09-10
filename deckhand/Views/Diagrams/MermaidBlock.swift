import DeckhandKit
import SwiftUI
import WebKit

/// A mermaid diagram from a fence, drawn.
///
/// An agent that wants to show you a shape — a flow, a sequence, a state machine — has had one
/// option on a phone: eleven lines of `A-->B` in a code block. This is the other one.
///
/// The renderer is bundled, not fetched (`deckhand/Resources/mermaid.min.js`, MIT, 11.12.3), and
/// injected as a `WKUserScript` at document start. That is the same lane the slip bridge uses —
/// host-initiated script, which is the app asking the document a question rather than script the
/// page loaded — so nothing about the artifact policy was loosened to make this work, and a
/// diagram draws with the Mac asleep.
///
/// It sizes itself. A web view in a scrolling column has no opinion about its own height, and
/// one guessed wrong is either a diagram with its feet cut off or an inch of blank page under
/// every one. So the page measures what mermaid drew and says so, once.
///
/// Every failure falls back to the source. A diagram that will not parse is still eleven lines
/// somebody wrote, and losing them to a blank box is worse than not drawing at all.
struct MermaidBlock: View {
    let source: String
    /// What the page reported, or the opening guess. Not zero: a web view given no height at all
    /// lays out at zero for one frame and the column jumps as each diagram lands.
    @State private var height: CGFloat = 140
    @State private var failed = false
    @Environment(\.colorScheme) private var scheme

    /// Past this and it is not a diagram any more, it is a scroll. Mermaid will happily draw a
    /// state machine four thousand points tall and a phone cannot use one.
    private static let ceiling: CGFloat = 1400

    var body: some View {
        if failed {
            fallback
        } else {
            MermaidWeb(source: source, dark: scheme == .dark, drawn: settle)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .fill(Palette.surfacePrimary)
                )
                .accessibilityLabel("Diagram")
                .accessibilityIdentifier("mermaid-block")
        }
    }

    /// The source, set as code. Deliberately the same shape a fence gets when nothing can draw
    /// it, so a diagram that fails looks like what it would have looked like anyway.
    private var fallback: some View {
        Text(source)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Palette.tileIdle)
            )
    }

    private func settle(_ reported: CGFloat?) {
        guard let reported, reported > 1 else {
            failed = true
            return
        }
        height = min(reported, Self.ceiling)
    }
}

/// The web view, and the four refusals that make it not a browser.
private struct MermaidWeb: UIViewRepresentable {
    let source: String
    let dark: Bool
    let drawn: (CGFloat?) -> Void

    func makeCoordinator() -> Sketcher { Sketcher(drawn: drawn) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: configured(with: context.coordinator))
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        // The column outside scrolls; this only ever scrolls sideways, for a diagram wider than
        // a phone. Vertical bounce inside a block that is exactly its own height reads as broken.
        web.scrollView.alwaysBounceVertical = false
        web.loadHTMLString(Self.page(source, dark: dark), baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.drawn = drawn
        // A theme change is a re-render, because mermaid bakes its colours into the SVG it made.
        guard context.coordinator.dark != dark else { return }
        context.coordinator.dark = dark
        context.coordinator.allow()
        web.loadHTMLString(Self.page(source, dark: dark), baseURL: nil)
    }

    private func configured(with pilot: Sketcher) -> WKWebViewConfiguration {
        let settings = WKWebViewConfiguration()
        settings.websiteDataStore = .nonPersistent()
        settings.dataDetectorTypes = []
        if let renderer = Self.renderer {
            settings.userContentController.addUserScript(
                WKUserScript(source: renderer, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
        // The same weak relay `ArtifactWeb` needs, and for the same measured reason: a content
        // controller keeps its handler for as long as the configuration lives, so registering the
        // coordinator directly is a cycle nothing breaks.
        settings.userContentController.add(Courier(pilot), name: "mermaid")
        return settings
    }

    /// The bundled renderer, read once. Nil if it is missing from the bundle, which is a build
    /// that did not copy it — and the honest answer to that is every diagram showing its source.
    private static let renderer: String? = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    /// One diagram, and the measurement that lets it size the block it sits in.
    ///
    /// The source goes in as the text of a `<pre>`, escaped, rather than into the script: a
    /// diagram is whatever somebody typed, and escaping it to survive being read as JavaScript is
    /// a bug waiting for the first quote mark.
    static func page(_ source: String, dark: Bool) -> String {
        """
        <!DOCTYPE html>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; padding: 0; background: transparent; }
          body { padding: 10px; -webkit-text-size-adjust: 100%; }
          #it { display: flex; justify-content: center; }
          svg { max-width: 100%; height: auto; }
        </style>
        <div id="it"><pre class="mermaid">\(escaped(source))</pre></div>
        <script>\(script(dark: dark))</script>
        """
    }

    /// Draw it, then say how tall it came out.
    ///
    /// A diagram that will not parse says nothing rather than drawing mermaid's own red error
    /// card, and zero is what the block reads as "show the source instead" — which is more use to
    /// somebody on a phone than a picture of a syntax error.
    private static func script(dark: Bool) -> String {
        """
        (function () {
          const say = (height) => window.webkit.messageHandlers.mermaid.postMessage(height);
          if (typeof mermaid === 'undefined') { say(0); return; }
          mermaid.initialize({
            startOnLoad: false,
            theme: \(dark ? "'dark'" : "'default'"),
            securityLevel: 'strict',
            fontFamily: '-apple-system, system-ui, sans-serif'
          });
          mermaid.run({ querySelector: '.mermaid' })
            .then(() => say(Math.ceil(document.body.getBoundingClientRect().height)))
            .catch(() => say(0));
        })();
        """
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// The one navigation this page is allowed, and the one number it may send.
@MainActor
private final class Sketcher: NSObject, WKNavigationDelegate {
    var drawn: (CGFloat?) -> Void
    var dark = false
    /// Set by the load that put the diagram on screen. Everything after it is the page trying to
    /// go somewhere, and the answer is no — there is nothing here to navigate to.
    private var arrived = false

    init(drawn: @escaping (CGFloat?) -> Void) { self.drawn = drawn }

    /// A deliberate reload — a theme change — is the one thing allowed to reset the gate.
    func allow() { arrived = false }

    func webView(
        _ web: WKWebView,
        decidePolicyFor action: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard !arrived else { return .cancel }
        arrived = true
        return .allow
    }

    func heard(_ message: WKScriptMessage) {
        guard let height = message.body as? NSNumber else { return }
        drawn(CGFloat(truncating: height))
    }
}

/// Holds the coordinator weakly, and holds nothing else — see `ArtifactWeb.Courier`.
private final class Courier: NSObject, WKScriptMessageHandler {
    private weak var pilot: Sketcher?

    init(_ pilot: Sketcher) { self.pilot = pilot }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated { pilot?.heard(message) }
    }
}
