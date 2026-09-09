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
