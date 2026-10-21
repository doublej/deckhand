import DeckhandKit
import SwiftUI

@main
struct DeckhandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @State private var live = LiveUpdates()

    var body: some Scene {
        WindowGroup {
            // No forced scheme: the rail paints its own dark ground, and a session page is
            // meant to be the phone's own light one. Forcing dark made both the same surface.
            RootView(model: model)
                .tint(Palette.tint)
                // The Mac drives the Lock Screen card, not the app: a backgrounded app has no
                // promise of running again soon. All this does is keep the Mac supplied with
                // the tokens that let it, for as long as the app is alive.
                .task {
                    // The archive's own tidying, done on the way in rather than on a timer: being
                    // opened is the only moment a phone app reliably gets, and the index is small
                    // enough that reading it costs nothing. It only ever drops clips that were
                    // actually said — see `ClipArchive.sweep`.
                    model.archive.sweep()
                    Touches.shared.begin { try? await model.settings.client()?.markPhoneInUse() }
                    live.begin { hex, kind, session in
                        try await model.settings.client()?
                            .register(pushToken: hex, kind: kind, session: session)
                    }
                    // The manager's messages, pushed while its panel is not on screen. A tap
                    // opens the chat it came from: the manager's panel, or a session's page.
                    Notifier.shared.begin(
                        register: { hex in
                            try await model.settings.client()?
                                .register(pushToken: hex, kind: "device", session: nil)
                        },
                        opened: { target in Task { await model.open(target) } },
                        showing: { $0 == .manager && model.manager.open }
                    )
                }
                // A tap on a Lock Screen card opens the session that card is about. The card
                // carries the id (`CardLink`); the phone has to find that session in a listing
                // it may not have fetched yet, which is every cold launch from the Lock Screen —
                // so the refresh comes first and the route second, or the rail would be asked to
                // push a session it is not yet holding and would quietly do nothing.
                //
                // `manager.route` rather than a second slot beside it: the rail already acts on
                // exactly this ask, from the manager, and a second way to say "open this session"
                // is a second place the answer can drift.
                //
                // Every other `deckhand://` link goes the same way — `DeepLink` holds the shapes.
                .onOpenURL { url in
                    guard let link = DeepLink(url) else { return }
                    Task { await model.follow(link) }
                }
        }
    }
}

/// Portrait is one session at a time. Landscape is the whole deck at once — and one swipe left
/// of either is the manager.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        // Outside the keyboard rule below, deliberately. The rail and the deck ignore the
        // keyboard because nothing on them is typed into; the manager panel is one long field
        // and has to rise for it, which it cannot do inside an ancestor that ignores it.
        ManagerShell(model: model) {
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height {
                    DeckView(model: model)
                } else {
                    SessionListView(model: model)
                }
            }
            .ignoresSafeArea(.keyboard)
        }
        // Set once, at the root, so every surface that renders markdown draws a mermaid fence
        // rather than printing it: a transcript, a briefing, a report a session left behind. The
        // seam is here because drawing one needs a web view and `Markdown` lives in DeckhandKit,
        // which has no UIKit in it on purpose.
        .diagrams { AnyView(MermaidBlock(source: $0)) }
    }
}

/// Tells the Mac the person is using the phone: on coming to the front, and on any touch at most
/// every `every` seconds. The Mac compares that with its own last keypress, so whichever was
/// touched last is where sessions reach the person.
///
/// Seen through a recogniser on each window that declines every touch it is shown. Declining is
/// the point: it is asked about all of them, sheets included, and can never take one away from
/// the view it was meant for.
@MainActor
final class Touches: NSObject, UIGestureRecognizerDelegate {
    static let shared = Touches()
    /// A stale stamp only delays the phone winning; a keypress at the Mac takes it back at once.
    private static let every: TimeInterval = 10
    private var last = Date.distantPast
    private var watched = Set<ObjectIdentifier>()
    private var tell: (@MainActor () async -> Void)?

    func begin(tell: @escaping @MainActor () async -> Void) {
        self.tell = tell
        NotificationCenter.default.addObserver(
            self, selector: #selector(cameToFront),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        cameToFront()
    }

    @objc private func cameToFront() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where watched.insert(ObjectIdentifier(window)).inserted {
                let seeing = UITapGestureRecognizer()
                seeing.cancelsTouchesInView = false
                seeing.delegate = self
                window.addGestureRecognizer(seeing)
            }
        }
        last = .distantPast
        touched()
    }

    private func touched() {
        guard let tell, Date.now.timeIntervalSince(last) >= Self.every else { return }
        last = .now
        Task { await tell() }
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touched()
        return false
    }
}
