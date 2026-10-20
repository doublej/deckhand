import DeckhandKit
import SwiftUI

/// The project's header picture, behind a session page's title — where the agent working in the
/// project made one (`.deckhand/header.jpg`; `daemon/…/projects/header.py`). Nothing at all where
/// it did not, which is the usual case.
///
/// It costs no height: it fills whatever the strip in front of it already takes, plus the status
/// bar above, and dissolves into the page's ground so the title and the meter read over it on
/// either surface.
struct ProjectBanner: View {
    let model: AppModel
    let session: Session
    @State private var banner: UIImage?

    var body: some View {
        Group {
            if let banner {
                Color.clear
                    .overlay { Image(uiImage: banner).resizable().scaledToFill() }
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [Palette.surfaceGround.opacity(0.35), Palette.surfaceGround],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .ignoresSafeArea(edges: .top)
                    .accessibilityHidden(true)
            } else {
                Color.clear
            }
        }
        .task(id: session.sessionId) {
            let data = try? await model.settings.client()?.header(of: session.sessionId)
            banner = data.flatMap { $0 }.flatMap(UIImage.init(data:))
        }
    }
}
