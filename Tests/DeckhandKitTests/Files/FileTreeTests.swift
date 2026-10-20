import Foundation
import Testing

@testable import DeckhandKit

/// The files tab as folders: where browsing starts, what one level shows, and the way back up.
@Suite struct FileTreeTests {
    private func file(_ path: String, _ modified: Double = 1) -> Asset {
        Asset(path: path, name: (path as NSString).lastPathComponent, kind: "image", size: 1, modified: modified)
    }

    @Test("browsing starts where every file is under, and a chain of empty folders is one row")
    func startsAtTheCommonFolderAndCollapsesChains() {
        let files = [file("/p/shot.png", 3), file("/p/out/2026/frames/a.png", 2),
                     file("/p/out/2026/frames/b.png", 1), file("/p/docs/x.md", 5)]
        let tree = FileTree(files)
        #expect(tree.root == "/p")
        #expect(tree.files.map(\.name) == ["shot.png"])
        #expect(tree.folders.map(\.name) == ["docs", "out/2026/frames"])
        #expect(tree.folders.map(\.count) == [1, 2])
    }

    @Test("drilling in shows that folder, and the trail leads back up by name")
    func drillsAndLeadsBack() {
        let files = [file("/p/a/b/one.png"), file("/p/a/two.png"), file("/p/c.png")]
        let tree = FileTree(files, at: "/p/a/b")
        #expect(tree.files.map(\.name) == ["one.png"])
        #expect(tree.trail.map(\.name) == ["p", "a", "b"])
        #expect(tree.trail.map(\.path) == ["/p", "/p/a", "/p/a/b"])
        #expect(tree.above == "/p/a")
        #expect(FileTree(files, at: "/p/a").above == "/p")
        #expect(FileTree(files).above == nil)
    }

    @Test("a place the narrowed list no longer reaches starts again at its root")
    func fallsBackToTheRoot() {
        let tree = FileTree([file("/q/x.png"), file("/q/y/z.png")], at: "/p/a")
        #expect(tree.here == "/q")
        #expect(FileTree([]).folders.isEmpty)
        let apart = FileTree([file("/tmp/r/a.png"), file("/Users/jj/b.png")], at: "/tmp/r")
        #expect(apart.root == "/" && apart.files.map(\.name) == ["a.png"])
        #expect(apart.trail.map(\.path) == ["/", "/tmp", "/tmp/r"])
        #expect(FileTree([file("/tmp/r/a.png"), file("/Users/jj/b.png")]).folders.map(\.name).sorted()
            == ["Users/jj", "tmp/r"])
        #expect(FileTree.under("/p/ab", "/p/a") == false)
    }
}
