import DeckhandKit
import Foundation
import Testing

/// Which runs of a turn become taps, and what each one opens.
@Suite("What a turn links")
struct LinksTests {
    private func links(in text: String) -> [String] {
        let out = Links.marked(text)
        return out.runs.compactMap { run in run.link.map { _ in String(out[run.range].characters) } }
    }

    private func link(of text: String) -> URL? {
        Links.marked(text).runs.compactMap(\.link).first
    }

    @Test("a dev server with no scheme is an address")
    func bareHosts() {
        #expect(links(in: "running on localhost:5173 now") == ["localhost:5173"])
        #expect(link(of: "at mac.local:4180/health")?.absoluteString == "http://mac.local:4180/health")
        #expect(links(in: "bound 0.0.0.0:4180 and 127.0.0.1:8080/x") == ["0.0.0.0:4180", "127.0.0.1:8080/x"])
    }

    @Test("a path to a file the Mac opens is a link to the Mac's copy")
    func paths() {
        #expect(links(in: "wrote ~/dev/x/shot.png and ./out/a.md, then /Users/jj/clip.MOV")
                == ["~/dev/x/shot.png", "./out/a.md", "/Users/jj/clip.MOV"])
        #expect(Links.macPath(of: link(of: "see docs/plan.md:12")!) == "docs/plan.md")
        #expect(Links.macPath(of: link(of: "see /tmp/a b.png")!) == "b.png")
    }

    @Test("source, and a path inside an address, are left alone")
    func notPaths() {
        #expect(links(in: "edited Sources/App.swift") == [])
        #expect(links(in: "https://x.com/shot.png") == ["https://x.com/shot.png"])
        #expect(Links.macPath(of: link(of: "https://x.com/shot.png")!) == nil)
    }

    @Test("a file address opens on the Mac too, and a closing backtick is not part of an address")
    func edges() {
        #expect(Links.macPath(of: link(of: "file:///Users/jj/a.png")!) == "/Users/jj/a.png")
        #expect(links(in: "`https://x.com/a`.") == ["https://x.com/a"])
    }
}
