//
//  ArisKnownPlaces.swift
//  Shared/Core/Apps (aris-agent, tests, swift test)
//
//  The folders everyone calls by a name ("다운로드 폴더", "Downloads", "바탕화면", "홈"), and a path as it is said
//  ("~/Downloads"), made into the real path on this Mac (tenth VM run, item 2: "다운로드 폴더 열어 줘" became
//  `~/Downloads` unresolved, then an invented /Users/me/Downloads, then five key presses in Finder). The home folder is
//  the helper's to know, never the model's to guess: a name or "~" is resolved here, and a path under a user folder
//  that isn't on this Mac is refused with the way to say it. An allowlist: a word that is no place's name is no place.
//  Pure (what exists is asked through `exists`).
//

import Foundation

enum ArisKnownPlaces {
    struct Place: Equatable, Sendable {
        /// The id a capability takes ("downloads").
        var id: String
        /// Its path from the home folder ("Downloads"; "" the home itself); nil when it isn't under home.
        var underHome: String?
        /// Its path when it isn't under home ("/Applications").
        var absolute: String?
        /// What it is called, folded (ArisKnownPlaces.fold): Korean and English.
        var names: [String]
    }

    static let all: [Place] = [
        Place(id: "home", underHome: "", absolute: nil, names: ["홈", "홈디렉토리", "사용자", "home", "~"]),
        Place(id: "desktop", underHome: "Desktop", absolute: nil, names: ["바탕화면", "데스크탑", "데스크톱", "desktop"]),
        Place(id: "documents", underHome: "Documents", absolute: nil, names: ["문서", "도큐먼트", "documents", "document", "docs"]),
        Place(id: "downloads", underHome: "Downloads", absolute: nil, names: ["다운로드", "다운로드함", "내려받기", "downloads", "download"]),
        Place(id: "pictures", underHome: "Pictures", absolute: nil, names: ["사진", "그림", "pictures", "picture", "photos"]),
        Place(id: "music", underHome: "Music", absolute: nil, names: ["음악", "music"]),
        Place(id: "movies", underHome: "Movies", absolute: nil, names: ["동영상", "영화", "비디오", "movies", "movie", "videos"]),
        Place(id: "applications", underHome: nil, absolute: "/Applications", names: ["응용프로그램", "애플리케이션", "어플리케이션", "앱", "applications", "application", "apps"]),
        Place(id: "trash", underHome: ".Trash", absolute: nil, names: ["휴지통", "trash", "bin"]),
    ]

    /// The ids, for a capability's schema.
    static var ids: [String] { all.map(\.id) }

    /// Letters and digits only, lowercased, the word for a folder taken off the end ("다운로드 폴더", "Downloads folder").
    static func fold(_ raw: String) -> String {
        var text = raw.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "~" || text == "~/" { return "~" }
        for word in [" 폴더", " 디렉토리", " folder", " directory"] where text.hasSuffix(word) { text = String(text.dropLast(word.count)); break }
        if text.hasPrefix("the ") { text = String(text.dropFirst(4)) }
        if text.hasPrefix("my ") { text = String(text.dropFirst(3)) }
        if text.hasPrefix("내 ") { text = String(text.dropFirst(2)) }
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    /// The place a name means, exactly (never a path, never a word inside a longer one).
    static func named(_ said: String) -> Place? {
        let wanted = fold(said)
        guard !wanted.isEmpty else { return nil }
        return all.first { $0.id == wanted || $0.names.contains(wanted) }
    }

    static func path(_ place: Place, home: String) -> String {
        if let absolute = place.absolute { return absolute }
        let under = place.underHome ?? ""
        return under.isEmpty ? home : (home as NSString).appendingPathComponent(under)
    }

    enum Resolved: Equatable, Sendable {
        /// The real path.
        case path(String)
        /// A path under /Users/<name> where no such user folder is on this Mac (an invented home).
        case noSuchUser(String)
        /// Neither a known place's name nor a path from / or ~.
        case unknown
    }

    /// `said`: a known place's name alone, "~", "~/…", or an absolute path. `exists`: whether a folder is on this Mac.
    static func resolve(_ said: String, home: String, exists: (String) -> Bool) -> Resolved {
        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unknown }
        if text == "~" { return .path(home) }
        if text.hasPrefix("~/") { return .path((home as NSString).appendingPathComponent(String(text.dropFirst(2)))) }
        if text.hasPrefix("/") {
            let parts = (text as NSString).standardizingPath.split(separator: "/").map(String.init)
            if parts.count >= 2, parts[0] == "Users" {
                let user = "/Users/" + parts[1]
                if user != home, !home.hasPrefix(user + "/"), !exists(user) { return .noSuchUser(parts[1]) }
            }
            return .path(text)
        }
        // A place's name alone. Never a name with a rest ("Desktop/a.command"): what is judged is the path as written.
        guard let place = named(text) else { return .unknown }
        return .path(path(place, home: home))
    }

    /// What the model is told when a path is under a user folder that isn't here: the way to say it, and the real home.
    static func noSuchUserLine(_ user: String, home: String) -> String {
        "there is no user folder /Users/\(user) on this Mac, so nothing was opened. Never make up a home path: the owner's home is \(home); "
            + "name a place (\(ids.joined(separator: ", "))) or write the path from ~ (for example ~/Downloads)."
    }

    static let unknownLine = "that is neither a known place (\(ids.joined(separator: ", "))) nor a path from / or ~"
}
