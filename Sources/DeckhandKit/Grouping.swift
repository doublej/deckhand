import Foundation

// How the Files tab is carved up. Here rather than in the view because every interesting part of
// it is a string edge case — a dotfile, a double suffix, a name with no dot in it at all — and
// DeckhandKit is the half of the app `just test` can reach.

public extension Asset {
    /// The header a file with nothing to read a suffix off is filed under.
    ///
    /// It has a space in it on purpose. Every other header is one uppercased word taken off the
    /// end of a name, and no name can produce a word with a space in it, so this one can never
    /// collide with a real suffix and quietly swallow somebody's files.
    static let noSuffix = "NO SUFFIX"

    /// What this file is filed under, uppercased the way the headers are: PNG, MD, MOV.
    ///
    /// Four decisions, each of them a name a real session has actually written:
    ///
    /// - **Uppercased**, so `Shot.PNG` off the camera roll and `shot.png` off a screenshot are
    ///   one section and not two sections with the same name in them.
    /// - **The last dot wins**, so `report.tar.gz` is GZ. The alternative is a list of the double
    ///   suffixes that mean something together — `.tar.gz`, `.d.ts`, `.min.js` — and that list is
    ///   never finished. The last suffix is the one that decides what opens the file, which is
    ///   the only question this tab is asked.
    /// - **A leading dot is part of the name, not a suffix**: `.gitignore` is a file called
    ///   gitignore that happens to be hidden, and there is no such thing as a gitignore *type*.
    ///   It goes under ``noSuffix`` next to `Justfile`, which is where it reads correctly.
    /// - **A trailing dot leaves nothing**: `archive.` is filed under ``noSuffix`` rather than
    ///   under the empty string, which would have drawn a header with no word in it.
    var suffix: String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return Self.noSuffix }
        let tail = name[name.index(after: dot)...]
        return tail.isEmpty ? Self.noSuffix : tail.uppercased()
    }

    /// One section of the Files tab: a suffix, and every file carrying it.
    struct Group: Identifiable, Sendable {
        public let suffix: String
        public let assets: [Asset]

        public var id: String { suffix }
    }

    /// The tab's sections, the biggest first.
    ///
    /// Ties are broken on the suffix alphabetically, and that is not tidiness. Three sections of
    /// two files each would otherwise come back in whatever order the dictionary happened to hand
    /// them over in, which changes between launches — so the list would appear to reshuffle itself
    /// every time the tab was opened, for no reason anybody looking at it could see.
    ///
    /// Inside a section the order is left exactly as it arrived, because it is already the right
    /// one: the Mac sorts these newest first, and which file the session just wrote is the thing
    /// a file list is opened to find out.
    static func grouped(_ assets: [Asset]) -> [Group] {
        Dictionary(grouping: assets, by: \.suffix)
            .map { Group(suffix: $0.key, assets: $0.value) }
            .sorted {
                $0.assets.count == $1.assets.count
                    ? $0.suffix < $1.suffix
                    : $0.assets.count > $1.assets.count
            }
    }
}
