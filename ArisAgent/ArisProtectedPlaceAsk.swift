//
//  ArisProtectedPlaceAsk.swift
//  aris-agent
//
//  "도큐멘트 폴더 통째로 지워 줘", "~/Downloads 비워 줘", "delete my Desktop folder": a protected place asked to go as a
//  whole (thirteenth VM run, D1–D5b: the brain asked whether to trash Documents, suggested a wording that was then
//  refused, and said it had no way to list Downloads). The gate refuses any such call anyway (ArisBroadTarget); this
//  answers the request itself, before any AI, with one plain sentence that says what can be done instead. Only words
//  that are wholly such a request are taken (an allowlist of their words): anything else in them ("바탕화면에 있는
//  임시폴더13 폴더 지워 줘", a file's name) goes to the AI as before. Pure.
//

import Foundation

enum ArisProtectedPlaceAsk {
    enum Place: String, Equatable { case home, desktop, documents, downloads }
    /// The folder goes (deleted, trashed, moved), or what it holds does (emptied).
    enum Kind: Equatable { case whole, empty }

    struct Asked: Equatable {
        let place: Place
        let kind: Kind
    }

    /// The place a word names (its particle taken off); `needsFolder`: only with "폴더"/"folder" beside it (문서, 홈 are
    /// also ordinary words).
    private static func place(_ token: String) -> (Place, needsFolder: Bool)? {
        let names: [(String, Place, Bool)] = [
            ("도큐멘트", .documents, false), ("다큐먼트", .documents, false), ("documents", .documents, false), ("~/documents", .documents, false),
            ("문서", .documents, true), ("바탕화면", .desktop, false), ("데스크탑", .desktop, false), ("데스크톱", .desktop, false),
            ("desktop", .desktop, false), ("~/desktop", .desktop, false), ("다운로드", .downloads, false), ("downloads", .downloads, false),
            ("~/downloads", .downloads, false), ("홈", .home, true), ("home", .home, true), ("~", .home, false), ("~/", .home, false),
        ]
        let bare = strip(token)
        return names.first { $0.0 == bare }.map { ($0.1, $0.2) }
    }

    private static let particles = ["에서", "으로", "에는", "을", "를", "은", "는", "이", "가", "도", "만", "의", "에", "로"]

    private static func strip(_ token: String) -> String {
        for particle in particles where token.count > particle.count && token.hasSuffix(particle) {
            let rest = String(token.dropLast(particle.count))
            // "다운로드" ends in 드, never a particle; only a known word loses one.
            if ["도큐멘트", "다큐먼트", "문서", "바탕화면", "데스크탑", "데스크톱", "다운로드", "홈", "폴더", "자체", "휴지통", "안", "거", "것", "파일", "파일들"].contains(rest) { return rest }
        }
        return token
    }

    private static let folderWords: Set<String> = ["폴더", "folder"]
    private static let wholeVerbs = ["지워", "지우", "삭제", "휴지통", "버려", "버리", "옮겨", "옮기", "넣어", "없애"]
    private static let emptyVerbs = ["비워", "비우"]
    private static let englishWhole: Set<String> = ["delete", "trash", "remove", "erase", "wipe", "move", "bin"]
    private static let englishEmpty: Set<String> = ["empty", "clear"]
    /// Words that may stand beside them and change nothing: endings, "통째로", "전부", "please", "my", "the"…
    private static let fillers: Set<String> = [
        "줘", "주세요", "줄래", "해", "해줘", "해라", "좀", "그냥", "아니", "통째로", "통째", "전체", "전체를", "자체", "전부", "다", "모두", "싹", "완전히",
        "안", "안에", "안의", "있는", "거", "것", "파일", "파일들", "내", "제", "please", "my", "the", "whole", "entire", "all", "everything", "in", "itself",
        "to", "put", "throw", "away", "out", "of", "folder's", "contents", "files", "can", "you", "could",
    ]
    /// Words that make it a request about what is inside (emptying), not the folder itself.
    private static let insideWords: Set<String> = ["안", "안에", "안의", "있는", "거", "것", "파일", "파일들", "everything", "contents", "files", "all"]

    /// The request, when it is wholly one to delete, move or empty a protected place.
    static func parse(_ request: String) -> Asked? {
        let words = request.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.!?·'\"’“”")))
            .filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 14 else { return nil }
        var found: (Place, Bool)?
        var folder = false, whole = false, empty = false, inside = false
        for word in words {
            let bare = strip(word)
            if let named = place(word) {
                guard found == nil || found?.0 == named.0 else { return nil }
                found = named
            } else if folderWords.contains(bare) {
                folder = true
            } else if wholeVerbs.contains(where: bare.hasPrefix) || englishWhole.contains(bare) {
                whole = true
            } else if emptyVerbs.contains(where: bare.hasPrefix) || englishEmpty.contains(bare) {
                empty = true
            } else if fillers.contains(bare) || fillers.contains(word) {
                if insideWords.contains(bare) || insideWords.contains(word) { inside = true }
            } else {
                return nil
            }
        }
        guard let (place, needsFolder) = found, !needsFolder || folder, whole || empty else { return nil }
        return Asked(place: place, kind: empty || inside ? .empty : .whole)
    }

    /// The one sentence: what isn't done, and what can be.
    static func reply(_ asked: Asked, korean: Bool) -> String {
        let name: String
        switch asked.place {
        case .home: name = korean ? "홈" : "home"
        case .desktop: name = korean ? "바탕화면" : "Desktop"
        case .documents: name = korean ? "문서" : "Documents"
        case .downloads: name = korean ? "다운로드" : "Downloads"
        }
        switch (asked.kind, korean) {
        case (.whole, true): return "\(name) 폴더는 통째로 지우거나 옮기지 않으니, 지울 파일을 말씀해 주시면 그 파일만 휴지통으로 옮길게요."
        case (.empty, true): return "\(name) 폴더를 통째로 비우지는 않으니, 지울 파일을 골라 말씀해 주시면 그 파일들만 휴지통으로 옮길게요."
        case (.whole, false): return "I don't delete or move your whole \(name) folder, but tell me which files in it to remove and I'll move just those to the Trash."
        case (.empty, false): return "I don't empty your whole \(name) folder at once, but pick the files you want gone and I'll move just those to the Trash."
        }
    }

    /// main.swift's answer for a plain main turn; nil to go on as before.
    static func answer(_ request: String, fromApp: Bool, handsFree: Bool, plain: Bool) -> String? {
        guard fromApp, !handsFree, plain, let asked = parse(request) else { return nil }
        let korean = ArisMemoryText.isKorean(request) || !request.contains(where: \.isLetter)
        ArisCore2Trust.writeAudit(ArisTrustGate.line(["action": "refused here: a protected place as a whole (\(asked.place.rawValue))", "risk": "spoken"]), "local")
        return reply(asked, korean: korean)
    }
}
