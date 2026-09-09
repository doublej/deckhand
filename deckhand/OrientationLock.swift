import UIKit

/// The phone stops rotating while a clip is being recorded.
///
/// It is not a cosmetic lock. Portrait and landscape are two different screens here, and a
/// rotation swaps one for the other — which throws away the view holding the recorder, and
/// with it the clip being recorded. A phone put down, picked up or leaned over mid-sentence
/// would silently lose what was said.
@MainActor
enum OrientationLock {
    private(set) static var mask: UIInterfaceOrientationMask = .all

    /// Holds whatever the phone is showing right now.
    static func hold() {
        mask = current
        apply()
    }

    static func release() {
        mask = .all
        apply()
    }

    private static var current: UIInterfaceOrientationMask {
        switch scene?.interfaceOrientation {
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        case .portraitUpsideDown: .portraitUpsideDown
        default: .portrait
        }
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.first as? UIWindowScene
    }

    private static func apply() {
        scene?.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// The screen stays lit from the moment you start speaking until the words come back.
///
/// Not a convenience. The phone locking mid-sentence ends the recording, and locking during
/// the upload suspends the app with the clip still in flight — so what you said is lost after
/// you have already said it, which is the one failure this app cannot make good.
///
/// Counted rather than a flag: the recorder and the upload both hold it, and they hand over
/// with a gap of a frame or two. A plain bool would let the screen sleep in that gap.
@MainActor
enum Awake {
    private static var holds = 0

    static func hold() {
        holds += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release() {
        holds = max(0, holds - 1)
        UIApplication.shared.isIdleTimerDisabled = holds > 0
    }
}

/// The only reason this app has a delegate: UIKit asks it, not SwiftUI, which orientations a
/// window may take.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.mask }
    }
}
