//
//  ArisFleetResolver.swift
//  Shared/Core (app, aris-agent, tests)
//
//  Which session a spoken reference means: one, several ("all of them", "막힌 애들 다"), or a short question back when
//  more than one fits. In order: the session's id; "all"; its number ("3번", "삼번", "number three"); then filters
//  that narrow the live sessions together: the tool ("코덱스", "claude"), the stuck ones ("막힌 애", "the stuck one"),
//  the folder (its name, a part of it, or its name said in Hangul: "아리스 하는 애", "the one in altswitch"), what it
//  works on ("the one fixing the tests", "테스트 고치는 애", from its first request and its title), "the last one" (the
//  newest), "that one" (the one waiting on the user, when there is one). Gone sessions are never chosen. Pure.
//

import Foundation

enum ArisFleetResolution: Equatable {
    case one(ArisFleetSession)
    /// The reference names several on purpose ("all of them").
    case several([ArisFleetSession])
    /// More than one fits: the question to ask the owner, and the ones it is between.
    case ask(String, [ArisFleetSession])
    /// None fits: the line to say.
    case none(String)
}

enum ArisFleetResolver {
    static func resolve(_ reference: String, in fleet: ArisFleet, home: String, english: Bool) -> ArisFleetResolution {
        let live = fleet.live
        let raw = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !live.isEmpty else { return .none(english ? "No coding session is running right now." : "지금 돌고 있는 코딩 세션이 없어요.") }
        if let exact = live.first(where: { $0.id == raw }) { return .one(exact) }
        if raw.hasPrefix("/") || raw.hasPrefix("~/") {
            let path = ((raw.hasPrefix("~") ? home + raw.dropFirst() : raw) as NSString).standardizingPath
            let found = live.filter { ($0.folder as NSString).standardizingPath == path }
            if found.count == 1 { return .one(found[0]) }
            if found.count > 1 { return .ask(question(found, home: home, english: english), found) }
        }
        let text = raw.lowercased().precomposedStringWithCanonicalMapping
        let tokens = ArisFleetWords.tokens(raw)
        let wantsAll = has(text, tokens, all)
        if !wantsAll, let number = ArisFleetWords.number(in: raw) {
            guard let session = fleet.numbered(number) else {
                return .none(english ? "There's no session number \(number) right now. " + listLine(live, home: home, english: true)
                                     : "지금 \(number)번 세션은 없어요. " + listLine(live, home: home, english: false))
            }
            return .one(session)
        }
        var candidates = live
        var narrowed = false
        if let tool = tool(text) {
            candidates = candidates.filter { $0.tool == tool }
            narrowed = true
        }
        if has(text, tokens, permission) {
            candidates = candidates.filter { $0.state == .waitingPermission }
            narrowed = true
        } else if has(text, tokens, failure) {
            candidates = candidates.filter { $0.state == .failed }
            narrowed = true
        } else if has(text, tokens, stuck) {
            candidates = candidates.filter { $0.state.needsUser }
            narrowed = true
        } else if has(text, tokens, finished) {
            candidates = candidates.filter { $0.state == .idle && $0.lastMessage != nil }
            narrowed = true
        }
        let content = tokens.filter { !ArisFleetWords.stopwords.contains($0) && !isMarker($0, text) }
        let byFolder = folderMatches(content, among: candidates, home: home)
        if !byFolder.isEmpty {
            candidates = byFolder
            narrowed = true
        } else {
            let byWork = workMatches(content, among: candidates)
            if !byWork.isEmpty {
                candidates = byWork
                narrowed = true
            } else if !content.isEmpty, !wantsAll, !narrowedByDeixis(text, tokens), candidates.count > 0, !narrowed {
                return .none(english ? "No session fits \"\(raw)\". " + listLine(live, home: home, english: true)
                                     : "‘\(raw)’에 맞는 세션이 없어요. " + listLine(live, home: home, english: false))
            }
        }
        if has(text, tokens, last) {
            let newest = candidates.max { $0.startedAt < $1.startedAt }
            if has(text, tokens, finished), let done = candidates.max(by: { $0.lastActive < $1.lastActive }) { return .one(done) }
            return newest.map { .one($0) } ?? .none(english ? "No session fits that." : "그런 세션이 없어요.")
        }
        if wantsAll { return candidates.isEmpty ? .none(english ? "No session fits that." : "그런 세션이 없어요.") : .several(candidates) }
        if !narrowed, narrowedByDeixis(text, tokens) {
            let waiting = candidates.filter { $0.state.needsUser }
            if waiting.count == 1 { return .one(waiting[0]) }
            if waiting.count > 1 { candidates = waiting }
        }
        switch candidates.count {
        case 0:
            return .none(english ? "No session fits that. " + listLine(live, home: home, english: true)
                                 : "그런 세션이 없어요. " + listLine(live, home: home, english: false))
        case 1:
            return .one(candidates[0])
        default:
            return .ask(question(candidates, home: home, english: english), candidates)
        }
    }

    // MARK: - Words

    static let all = ["다들", "전부", "모두", "모든", "다", "전체", "각자", "all", "everyone", "everybody", "every", "each"]
    static let stuck = ["막힌", "막혔", "막혀", "멈춘", "멈췄", "멈춰", "기다리는", "기다리고", "기다려", "대기", "문제", "stuck", "blocked", "waiting",
                        "asking", "needs"]
    static let permission = ["권한", "허락", "승인", "permission", "approval"]
    static let failure = ["실패", "에러", "오류", "터진", "죽은", "failed", "error", "crashed", "broke"]
    static let finished = ["끝난", "끝낸", "끝났", "끝냈", "다한", "finished", "done", "completed"]
    static let last = ["마지막", "최근", "방금", "막", "이번", "제일 최근", "last", "latest", "newest", "recent"]
    static let deixis = ["그거", "그것", "걔", "쟤", "얘", "저거", "이거", "그놈", "that", "this", "it"]

    private static func has(_ text: String, _ tokens: [String], _ words: [String]) -> Bool {
        words.contains { word in word.contains(" ") ? text.contains(word) : tokens.contains(word) || tokens.contains { $0.hasPrefix(word) && ArisFleetWords.isHangul(word) && word.count >= 2 } }
    }

    private static func narrowedByDeixis(_ text: String, _ tokens: [String]) -> Bool { has(text, tokens, deixis) }

    /// A word that is one of the markers above (so it isn't taken for a folder or a topic).
    private static func isMarker(_ token: String, _ text: String) -> Bool {
        let markers = all + stuck + permission + failure + finished + last + deixis + toolWords.keys.map { $0 }
        return markers.contains { token == $0 || (ArisFleetWords.isHangul($0) && $0.count >= 2 && token.hasPrefix($0)) }
            || ArisFleetWords.number(in: token) != nil
    }

    static let toolWords: [String: ArisFleetTool] = ["클로드": .claudeCode, "클코": .claudeCode, "claude": .claudeCode, "코덱스": .codex, "codex": .codex,
                                                    "제미나이": .gemini, "재미나이": .gemini, "gemini": .gemini]

    private static func tool(_ text: String) -> ArisFleetTool? {
        let named = Set(toolWords.filter { text.contains($0.key) }.map(\.value))
        return named.count == 1 ? named.first : nil
    }

    // MARK: - Folder and work

    /// The sessions whose folder a word names: the whole name first, then one of its parts ("aris-jv-world": aris, jv,
    /// world), then a name that holds the word; Hangul words by their sound.
    static func folderMatches(_ words: [String], among sessions: [ArisFleetSession], home: String) -> [ArisFleetSession] {
        guard !words.isEmpty else { return [] }
        func name(_ session: ArisFleetSession) -> String { session.project(home: home).lowercased() }
        func parts(_ session: ArisFleetSession) -> [String] { name(session).split { "-_. ".contains($0) }.map(String.init) }
        let joined = words.joined(separator: "-"), glued = words.joined()
        if case let whole = sessions.filter({ name($0) == joined || name($0) == glued }), !whole.isEmpty { return whole }
        let tiers: [(String, ArisFleetSession) -> Bool] = [
            { word, session in name(session) == word },
            { word, session in parts(session).contains(word) },
            { word, session in word.count >= 3 && !ArisFleetWords.isHangul(word) && name(session).contains(word) },
            { word, session in
                guard ArisFleetWords.isHangul(word), word.count >= 2 else { return false }
                return ArisFleetWords.soundsAlike(word, name(session)) || parts(session).contains { ArisFleetWords.soundsAlike(word, $0) }
            },
        ]
        for tier in tiers {
            let scored = sessions.map { session in (session, words.filter { tier($0, session) }.count) }
            let best = scored.map(\.1).max() ?? 0
            if best > 0 { return scored.filter { $0.1 == best }.map(\.0) }
        }
        return []
    }

    /// The sessions whose first request or title has the most of the words (in either language), when one has more.
    static func workMatches(_ words: [String], among sessions: [ArisFleetSession]) -> [ArisFleetSession] {
        let wanted = words.filter { $0.count >= (ArisFleetWords.isHangul($0) ? 2 : 3) }
        guard !wanted.isEmpty else { return [] }
        let scored = sessions.map { session -> (ArisFleetSession, Int) in
            let text = [session.firstRequest, session.title?.text].compactMap { $0 }.joined(separator: " ").lowercased()
            let score = wanted.filter { word in
                ArisFleetWords.stems(word).contains { stem in
                    text.contains(stem) || (ArisFleetWords.meanings[stem] ?? []).contains { text.contains($0) }
                        || ArisFleetWords.meanings.contains { korean, english in english.contains { stem.hasPrefix($0) } && text.contains(korean) }
                }
            }.count
            return (session, score)
        }
        let best = scored.map(\.1).max() ?? 0
        guard best > 0 else { return [] }
        return scored.filter { $0.1 == best }.map(\.0)
    }

    // MARK: - What is said

    /// One session as said in a question or a line: "3번 aris-jv-world".
    static func label(_ session: ArisFleetSession, home: String, english: Bool) -> String {
        english ? "number \(session.number) (\(session.project(home: home)))" : "\(session.number)번 \(session.project(home: home))"
    }

    static func question(_ sessions: [ArisFleetSession], home: String, english: Bool) -> String {
        let shown = sessions.prefix(4).map { label($0, home: home, english: english) }
        let more = sessions.count > 4 ? (english ? " and \(sessions.count - 4) more" : " 외 \(sessions.count - 4)개") : ""
        return english ? "Which one: " + shown.joined(separator: ", ") + more + "?"
            : shown.joined(separator: ", ") + more + " 중 어느 쪽이요?"
    }

    private static func listLine(_ live: [ArisFleetSession], home: String, english: Bool) -> String {
        let shown = live.prefix(5).map { label($0, home: home, english: english) }.joined(separator: ", ")
        return english ? "Running: \(shown)." : "지금 있는 건 \(shown)이에요."
    }
}
