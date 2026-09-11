import Foundation
import Testing

@testable import DeckhandKit

/// A file as the daemon hands one over: the name is what the grouping reads, so nothing else
/// here matters to these tests.
private func made(_ name: String, at moment: Double = 0) -> Asset {
    Asset(path: "/tmp/session/\(name)", name: name, kind: "text", size: 1, modified: moment)
}

@Suite("Which section a file belongs under")
struct SuffixTests {
    @Test("an ordinary name is filed under its suffix, said the way the header says it")
    func ordinary() {
        #expect(made("shot.png").suffix == "PNG")
        #expect(made("notes.md").suffix == "MD")
    }

    @Test("case is not a difference, so one suffix is never two sections")
    func caseFolded() {
        // A camera roll writes .PNG and a screenshot writes .png. Two PNG headers in one list
        // is the bug this is here to stop.
        #expect(made("Shot.PNG").suffix == made("shot.png").suffix)
    }

    @Test("the last dot wins, so a double suffix is filed under the suffix that opens it")
    func doubleSuffix() {
        #expect(made("report.tar.gz").suffix == "GZ")
        #expect(made("client.d.ts").suffix == "TS")
    }

    @Test("a name with no suffix to read still gets a header")
    func nothingToRead() {
        // A leading dot is part of the name: .gitignore is a hidden file called gitignore, not a
        // file of type gitignore. A trailing dot leaves an empty string, which would have drawn
        // a header with no word in it.
        #expect(made("Justfile").suffix == Asset.noSuffix)
        #expect(made(".gitignore").suffix == Asset.noSuffix)
        #expect(made("archive.").suffix == Asset.noSuffix)
        // Never the empty string, whatever the name did.
        #expect(!Asset.noSuffix.isEmpty)
    }
}

@Suite("The sections of the Files tab")
struct GroupingTests {
    @Test("the biggest section comes first")
    func biggestFirst() {
        let sections = Asset.grouped([
            made("notes.md"), made("one.png"), made("two.png"), made("three.png"), made("clip.mov")
        ])
        #expect(sections.map(\.suffix) == ["PNG", "MD", "MOV"])
        #expect(sections.map(\.assets.count) == [3, 1, 1])
    }

    @Test("sections of the same size are ordered by suffix, so the list never reshuffles itself")
    func tiesAreStable() {
        // Grouping goes through a dictionary, whose order changes between launches. Without the
        // tie-break these three would swap places every time the tab was opened.
        let files = [made("a.mov"), made("b.md"), made("c.png")]
        let once = Asset.grouped(files).map(\.suffix)
        #expect(once == ["MD", "MOV", "PNG"])
        #expect(Asset.grouped(files.reversed()).map(\.suffix) == once)
    }

    @Test("inside a section the Mac's own order is kept")
    func orderKept() {
        // The daemon sorts newest first. Regrouping must not quietly re-sort by name.
        let section = Asset.grouped([
            made("newest.png", at: 300), made("older.png", at: 200), made("oldest.png", at: 100)
        ]).first
        #expect(section?.assets.map(\.name) == ["newest.png", "older.png", "oldest.png"])
    }

    @Test("files with no suffix are one section like any other")
    func nothingToReadGroups() {
        let sections = Asset.grouped([made("Justfile"), made(".gitignore"), made("notes.md")])
        #expect(sections.first?.suffix == Asset.noSuffix)
        #expect(sections.first?.assets.count == 2)
    }

    @Test("no files, no sections — the tab says its own empty line instead")
    func nothing() {
        #expect(Asset.grouped([]).isEmpty)
    }
}

@Suite("What a downloaded file is called on the phone")
struct FilenameTests {
    /// The name is off the wire and becomes a path component here, so these are the cases that
    /// decide where a download lands, not only what it is titled.
    private func named(_ name: String, path: String = "/tmp/session/report.md") -> Asset {
        Asset(path: path, name: name, kind: "text", size: 1, modified: 0)
    }

    @Test("a real name survives whole, which is the whole point of the share sheet")
    func real() {
        #expect(named("report.md").filename == "report.md")
        // A dotfile is a file called gitignore, the same reading `suffix` gives it.
        #expect(named(".gitignore").filename == ".gitignore")
    }

    @Test("a name carrying separators is cut to its last piece")
    func separators() {
        #expect(named("../../escape.md").filename == "escape.md")
        #expect(named("/etc/passwd").filename == "passwd")
    }

    @Test("a component naming a folder rather than a file falls through to the path")
    func folders() {
        #expect(named("..").filename == "report.md")
        #expect(named(".").filename == "report.md")
        #expect(named("/").filename == "report.md")
        #expect(named("").filename == "report.md")
    }

    @Test("nothing usable on either side still leaves a name to write")
    func nothing() {
        #expect(named("", path: "").filename == "file")
    }
}
