import DeckhandKit
import SwiftUI
import WebKit

/// The page itself, and the only web view in this app.
///
/// UIKit because there is no SwiftUI web view to target: `WebView` arrived after iOS 18, which
/// is this app's floor, and none of what makes this safe is reachable from it anyway — a
/// navigation policy, a user script at document start, a message handler and a non-persistent
/// data store are all `WKWebViewConfiguration` and `WKNavigationDelegate`.
///
/// Everything here is a refusal, and each one is its own line of defence rather than a
/// restatement of the last:
///
/// - The CSP (`ArtifactPage.armoured`) stops the page reaching the network at all.
/// - `decidePolicyFor` stops it leaving the page it was loaded as, whatever the CSP allows
///   inside the document: an anchor to another document, `location =`, a meta refresh.
/// - The non-persistent store means nothing it writes outlives the screen.
/// - No back-forward gestures, no link preview, no data detectors: there is no browser here,
///   so there must be nothing that behaves like one.
///
/// The page is loaded once, in `makeUIView`. A reload is a navigation and this view refuses
/// those, so there is nowhere else it could honestly happen.
struct ArtifactWeb: UIViewRepresentable {
    let artifact: Artifact
    /// The HTML as the agent wrote it. Armoured on the way in, never before.
    let html: String
    /// What the person answered, as the JSON text `JSON.stringify` made of it.
    let respond: (String) -> Void
    let close: () -> Void

    func makeCoordinator() -> Pilot { Pilot(respond: respond, close: close) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: configured(with: context.coordinator))
        web.navigationDelegate = context.coordinator
        // A swipe that goes back is a browser's gesture, and there is nowhere back to.
        web.allowsBackForwardNavigationGestures = false
        // A long press on a link showing a preview of where it goes: it goes nowhere, and the
        // preview is a second screen over this one.
        web.allowsLinkPreview = false
        // `isInspectable` is left alone on purpose. Off is the release default, and setting it
        // anywhere would either turn Safari's inspector on in a shipped build or take away the
        // one way to find out why a demo page is not drawing.
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.loadHTMLString(ArtifactPage.armoured(html), baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        // The closures are rebuilt on every SwiftUI pass; the web view and the coordinator are
        // not. Without this the page would be answering into the first render's state.
        context.coordinator.respond = respond
        context.coordinator.close = close
    }

    private func configured(with pilot: Pilot) -> WKWebViewConfiguration {
        let settings = WKWebViewConfiguration()
        // Nothing the page stores survives it: no cookies, no local storage, no cache shared
        // with the next artifact or with anything else on the phone.
        settings.websiteDataStore = .nonPersistent()
        // A phone number or an address in the prose becoming a tappable callout is navigation
        // under another name, and every tap on one would be a way off this page.
        settings.dataDetectorTypes = []
        settings.userContentController.addUserScript(
            WKUserScript(source: ArtifactPage.bridge(for: artifact),
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true)
        )
        // A relay, and this is the leak the whole file exists around: a user content controller
        // retains its message handler for as long as the configuration lives, and the
        // configuration lives as long as the web view. A handler that holds the web view — or
        // anything holding it — back is then a cycle nothing breaks, and the page, its store
        // and its JavaScript context stay alive after the screen is gone. The relay holds the
        // coordinator weakly, so the only strong chain runs one way.
        settings.userContentController.add(Relay(pilot), name: ArtifactPage.handlerName)
        return settings
    }
}

/// The one navigation this page is allowed, and the two messages it may send.
@MainActor
final class Pilot: NSObject, WKNavigationDelegate {
    var respond: (String) -> Void
    var close: () -> Void
    /// Set by the load that put the page on the screen. Everything after it is something the
    /// page decided to do, and the answer to all of it is no.
    private var arrived = false

    init(respond: @escaping (String) -> Void, close: @escaping () -> Void) {
        self.respond = respond
        self.close = close
    }

    /// One page, and it is the one we handed over.
    ///
    /// `.cancel`, never a new screen: a page that tries to leave is refused where it stands,
    /// and nothing about the view it is in changes. The async form of this delegate method
    /// rather than the completion handler, so there is no way to return without answering.
    ///
    /// Measured against a real WKWebView before this was trusted, because the whole thing rests
    /// on the count: `loadHTMLString(_:baseURL: nil)` asks **once**, for `about:blank`. Were it
    /// two, this flag would be cancelling the page it is meant to be showing and the screen
    /// would be blank with nothing in the log. What a page then tries — `location.href`, a
    /// tapped link, `location.reload()` — each arrive here as one more and are refused, and the
    /// page stays exactly as it was. A form post never reaches this at all: the policy's
    /// `form-action 'none'` stops it a layer earlier.
    func webView(
        _ web: WKWebView,
        decidePolicyFor action: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard !arrived else { return .cancel }
        arrived = true
        return .allow
    }

    /// `window.deckhand`'s two messages. Anything else — a page probing what else the handler
    /// will take — is dropped without a word.
    func heard(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else {
            return
        }
        switch kind {
        case "respond":
            if let json = body["json"] as? String { respond(json) }
        case "close":
            close()
        default:
            break
        }
    }
}

/// Holds the coordinator weakly, and holds nothing else.
///
/// The only reason this type exists is that `WKUserContentController.add(_:name:)` takes its
/// handler strongly and never lets go of it. Registering the coordinator directly would work
/// and would also outlive the screen.
///
/// Measured, both ways, with a handler that holds its web view back: registered directly,
/// neither is ever released — no deinit, ever. Behind this relay, the handler goes the moment
/// the web view does. The relay itself is what the controller keeps, and it can be kept for as
/// long as WebKit likes, because a weak reference is the whole of what it owns.
final class Relay: NSObject, WKScriptMessageHandler {
    private weak var pilot: Pilot?

    init(_ pilot: Pilot) { self.pilot = pilot }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated { pilot?.heard(message) }
    }
}
