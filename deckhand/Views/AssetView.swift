import AVKit
import DeckhandKit
import SwiftUI

/// One file, open. Three kinds and three ways of showing them: an image fits the sheet, text
/// scrolls and can be selected, a video gets a player.
///
/// The bytes are fetched when the sheet appears and released when it closes. Nothing about a
/// 30 MB clip should outlive the screen looking at it.
struct AssetView: View {
    @Bindable var model: AppModel
    let session: Session
    let asset: Asset
    @State private var data: Data?
    @State private var failed: String?
    @State private var playing: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surfaceGround)
                .navigationTitle(asset.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }.tint(Palette.tint)
                    }
                }
        }
        .task { await load() }
        .onDisappear { discard() }
    }

    @ViewBuilder private var content: some View {
        if let failed {
            message(failed)
        } else if let data {
            shown(data)
        } else {
            ProgressView().controlSize(.regular)
        }
    }

    @ViewBuilder private func shown(_ data: Data) -> some View {
        switch asset.sort {
        case .image: picture(data)
        case .video: film
        case .text: writing(data)
        }
    }

    @ViewBuilder private func picture(_ data: Data) -> some View {
        if let image = UIImage(data: data) {
            // Zoomable, because half of what a session makes is a screenshot of something
            // small in the corner of something large.
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }
        } else {
            message("Not an image this phone can draw")
        }
    }

    @ViewBuilder private var film: some View {
        if let playing {
            VideoPlayer(player: AVPlayer(url: playing))
        } else {
            message("Could not stage the clip for playback")
        }
    }

    private func writing(_ data: Data) -> some View {
        ScrollView {
            Text(String(bytes: data, encoding: .utf8) ?? "Not text this phone can read")
                .font(Typography.mono)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.medium)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textSecondary)
            .padding(Spacing.large)
    }

    private func load() async {
        do {
            let bytes = try await model.contents(of: asset, in: session)
            data = bytes
            // AVPlayer wants a URL, and it picks its reader off the extension — the same rule
            // the clips going the other way live under.
            if asset.sort == .video { playing = try stage(bytes) }
        } catch {
            failed = "The Mac could not hand that over"
        }
    }

    private func stage(_ bytes: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((asset.name as NSString).pathExtension)
        try bytes.write(to: url)
        return url
    }

    private func discard() {
        if let playing { try? FileManager.default.removeItem(at: playing) }
        data = nil
    }
}
