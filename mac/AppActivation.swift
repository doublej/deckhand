import AppKit

/// Bringing Deckhand to the front. Copied from utt (`swift/utt/Utt/App/AppActivation.swift`),
/// measurements and all, because this is the same kind of app with the same problem.
///
/// macOS 14 made activation *cooperative*: `NSApplication.activate()` only works if the
/// currently-active app yielded to us, and `NSApplication.h` says so outright — "no
/// guarantee that the app will be activated at all". Nothing yields to a menu bar app, so
/// `NSApp.activate()` is a silent no-op and the window opens behind everything.
///
/// Measured on macOS 26 (accessory app, another app frontmost, repeated runs):
///
/// | call                                                | fronts? |
/// |-----------------------------------------------------|---------|
/// | `makeKeyAndOrderFront` alone                         | no      |
/// | `NSApp.activate()`                                   | no      |
/// | `NSApp.activate(ignoringOtherApps: true)`            | yes     |
/// | `NSWorkspace.openApplication(self, activates: true)` | yes     |
///
/// So: take the fast path, then verify and escalate. `ignoringOtherApps:` is marked
/// `API_TO_BE_DEPRECATED`, which is why the LaunchServices path — the same request `open -a`
/// makes, and it reuses the running instance rather than spawning one — backs it up.
@MainActor
enum AppActivation {
    static func front() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            guard !isFrontmost else { return }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
        }
    }

    private static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
    }
}
