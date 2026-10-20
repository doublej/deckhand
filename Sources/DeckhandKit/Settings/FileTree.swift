import Foundation

/// The files tab seen as folders: what is directly in one folder, and the folders under it.
///
/// Built from the same flat list the Mac sends, so it is an arrangement and never a second
/// listing — whatever the suffix and connected-folder choices already narrowed it to is what it
/// arranges, which is how "drill into a folder, then by extension" and "by extension, then into a
/// folder" are the same two taps either way round.
///
/// **A folder holding nothing but one other folder is not a stop.** A render folder sits at
/// `out/2026-10-20/frames/`, and three taps through two empty levels to reach it is the thing a
/// tree on a phone gets wrong. Such a chain is one row, named `out/2026-10-20/frames`.
public struct FileTree: Equatable, Sendable {
    public struct Folder: Hashable, Identifiable, Sendable {
        public let path: String
        /// Relative to the folder being shown; more than one component where a chain collapsed.
        public let name: String
        /// Every file anywhere under it.
        public let count: Int
        public var id: String { path }
    }

    /// One step of the way back up: a folder's own name and where it is.
    public struct Crumb: Hashable, Identifiable, Sendable {
        public let name: String
        public let path: String
        public var id: String { path }
    }

    /// The folder every file is under — where browsing starts.
    public let root: String
    public let here: String
    public let folders: [Folder]
    public let files: [Asset]

    /// `location` is where the person has drilled to; anything outside the list's own root
    /// (a choice above narrowed the list away from it) starts again at the root.
    public init(_ assets: [Asset], at location: String? = nil) {
        let root = Self.common(assets.map(\.folder))
        let here = location.flatMap { Self.under($0, root) ? $0 : nil } ?? root
        self.root = root
        self.here = here
        files = assets.filter { $0.folder == here }
        folders = Self.children(of: here, in: assets)
    }

    /// One folder up, or nil at the top — where a swipe back goes.
    public var above: String? {
        here == root ? nil : trail.dropLast().last?.path
    }

    /// From the root down to here, each one tappable.
    public var trail: [Crumb] {
        let below = here.dropFirst(root.count).split(separator: "/").map(String.init)
        var path = Self.base(root)
        return [Crumb(name: (root as NSString).lastPathComponent, path: root)] + below.map { name in
            path += "/" + name
            return Crumb(name: name, path: path)
        }
    }

    /// The folders directly under `here`, newest first, each one's empty chain collapsed.
    private static func children(of here: String, in assets: [Asset]) -> [Folder] {
        var newest: [String: Double] = [:]
        for asset in assets {
            if let next = step(asset, below: here) { newest[next] = max(newest[next] ?? 0, asset.modified) }
        }
        return newest.sorted { $0.value > $1.value }.map { path, _ in
            var deepest = path
            while !assets.contains(where: { $0.folder == deepest }),
                  let only = only(child: deepest, in: assets) {
                deepest = only
            }
            return Folder(path: deepest, name: String(deepest.dropFirst(base(here).count + 1)),
                          count: assets.filter { under($0.folder, path) }.count)
        }
    }

    /// The single folder directly under `path`, or nil where there are none or several.
    private static func only(child path: String, in assets: [Asset]) -> String? {
        let next = Set(assets.compactMap { step($0, below: path) })
        return next.count == 1 ? next.first : nil
    }

    /// The folder directly under `path` that this file is somewhere inside, or nil if it is not below it.
    private static func step(_ asset: Asset, below path: String) -> String? {
        guard asset.folder != path, under(asset.folder, path) else { return nil }
        let base = base(path)
        return base + "/" + asset.folder.dropFirst(base.count + 1).prefix { $0 != "/" }
    }

    /// What a child's path is built on: "/" contributes nothing, or every child would start "//".
    private static func base(_ path: String) -> String { path == "/" ? "" : path }

    /// Whether `path` is `folder` or anywhere inside it, by whole components.
    static func under(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/")
    }

    /// The deepest folder all of these are in.
    static func common(_ folders: [String]) -> String {
        guard var shared = folders.first?.split(separator: "/", omittingEmptySubsequences: false) else {
            return ""
        }
        for folder in folders.dropFirst() {
            let parts = folder.split(separator: "/", omittingEmptySubsequences: false)
            shared = Array(zip(shared, parts).prefix { $0 == $1 }.map(\.0))
        }
        let joined = shared.joined(separator: "/")
        return joined.isEmpty ? "/" : joined
    }
}
