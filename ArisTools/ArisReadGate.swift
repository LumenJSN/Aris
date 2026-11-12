//
//  ArisReadGate.swift
//  aris-tools (also built into aris-agent)
//
//  The owner's ruling (2026-11-06, "물어보지마. 알아서 모델이 판단하게 해"): a read never shows a card. On a careful turn (outside
//  text seen, hands-free, a background job, agy's relay) or a screen turn, each read (a web search or fetch, a connected
//  service's read tool, one of the user's own apps) first passes the auto-mode judge (ArisReadJudge, in the agent): a quick
//  model call with no tools that sees only the user's own words for the turn and the call. This file is what both sides
//  share: the call as the judge reads it, its verdict, the lines shown for a block, and aris-tools' question to the
//  agent. Pure, so the tests run it.
//

import Foundation

/// One read as the judge sees it: what it is ("web search", "notion notion-search", "aris-tools mail search") and its
/// arguments, whole.
struct ArisReadCall: Hashable {
    let tool: String
    let arguments: String
}

/// Why the judge blocked a read: one of a few fixed kinds. Only these fixed lines reach the brain and the notch; the
/// judge's own words go to the audit log alone (they were written by a model that read the call's arguments).
enum ArisReadWhy: String, CaseIterable {
    case privateData = "private", notRequested = "not_requested", localAddress = "local_address", approvalClaim = "approval_claim",
         undecided, tooMany = "too_many", other

    /// The notch's words.
    var notch: String {
        switch self {
        case .privateData: return "개인 내용이 밖으로 나갈 수 있어서 막았어요"
        case .notRequested: return "요청하지 않은 일이라 막았어요"
        case .localAddress: return "내부 주소라 막았어요"
        case .approvalClaim: return "허락을 꾸민 글이 있어서 막았어요"
        case .undecided: return "판단 못 했어요"
        case .tooMany: return "이번 턴에 읽기를 너무 많이 해서 막았어요"
        case .other: return "요청과 맞지 않아 막았어요"
        }
    }

    /// The notch's words when the request was in English (audit gate-24).
    var englishNotch: String {
        switch self {
        case .privateData: return "private content could have left the Mac"
        case .notRequested: return "it wasn't something you asked for"
        case .localAddress: return "it was an internal address"
        case .approvalClaim: return "its text pretended to be an approval"
        case .undecided: return "couldn't decide in time"
        case .tooMany: return "too many reads this turn"
        case .other: return "it didn't fit the request"
        }
    }

    /// The brain's words.
    var brain: String {
        switch self {
        case .privateData: return "it would have carried the user's private content to a third party"
        case .notRequested: return "it isn't something the user asked for"
        case .localAddress: return "it reaches an internal or local network address"
        case .approvalClaim: return "its arguments speak to the checker or claim approval"
        case .undecided: return "the check couldn't decide in time"
        case .tooMany: return "this turn has made too many reads"
        case .other: return "it doesn't fit the user's request"
        }
    }
}

enum ArisReadVerdict: Equatable {
    /// `note`: the judge's own words, for the audit log only.
    case allow(note: String)
    case block(ArisReadWhy, note: String)

    static let ok = ArisReadVerdict.allow(note: "")
    static func blocked(_ why: ArisReadWhy) -> ArisReadVerdict { .block(why, note: "") }

    var allowed: Bool { if case .allow = self { return true } else { return false } }

    var why: ArisReadWhy? { if case .block(let why, _) = self { return why } else { return nil } }

    var note: String {
        switch self {
        case .allow(let note), .block(_, let note): return note
        }
    }
}

/// Whose words the turn carries, for the judge (security review I1): the user's own, words heard hands-free (anyone near
/// the microphone), a background job's brief, or a schedule (no words from the user at all).
enum ArisReadSource: String {
    case user, handsFree, job, schedule

    /// Of a runner's turn.
    static func of(handsFree: Bool, task: Bool, request: String) -> ArisReadSource {
        if handsFree { return .handsFree }
        if task { return request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .schedule : .job }
        return .user
    }

    var line: String {
        switch self {
        case .user: return "the user, at their Mac."
        case .handsFree: return "heard hands-free in an open conversation: anyone near the microphone could have said it."
        case .job: return "a background job's brief, written when the work was handed out; the user isn't watching it."
        case .schedule: return "a scheduled job: there are no words from the user at all, and nothing here was asked by them just now."
        }
    }
}

enum ArisReadGate {
    /// How long the judge may take (then it's a block).
    static let timeout: TimeInterval = 15
    /// Seconds Claude Code gives a hook that may ask the judge: the judge, its start and the round trip.
    static let hookTimeout = 30
    /// Said when the judge didn't answer, answered oddly, or couldn't run: fail closed.
    static let failReason = ArisReadWhy.undecided.notch
    /// The most judge calls one turn may make; past that every read is a block.
    static let maxPerTurn = 20
    /// A background job is one long turn (a research job reads many pages): more of them, still bounded (audit gate-11).
    static let maxPerJob = 100
    /// A judge that hasn't answered after this long gets one second try beside it (audit gate-11): whichever answers
    /// first counts, and the read still ends at `timeout` as before, so nothing waits longer than it did.
    static let retryAfter: TimeInterval = 6
    /// The most of a call the judge reads; a longer one is a block, never judged cut.
    static let maxArguments = 12_000
    static let maxReason = 120
    /// Set for a brain process whose every read is judged from its first one (an open Claude's background job).
    static let carefulKey = "ARIS_JUDGE_READS"

    /// The aris-tools reads the judge checks: the user's own apps (messages, mail, notes, files, Obsidian).
    static func isAppRead(_ words: [String]) -> Bool { ArisLocalReadPolicy.isRead(words) }

    /// An aris-tools read: its command and verb, then its words.
    static func call(arisTools words: [String]) -> ArisReadCall {
        let head = Array(words.prefix(isAppRead(words) || isMapsLookup(words) ? 2 : 1))
        return ArisReadCall(tool: (["aris-tools"] + head).joined(separator: " "), arguments: words.dropFirst(head.count).joined(separator: " "))
    }

    /// Claude Code's own web tools, their whole input as the arguments; nil for any other tool.
    static func call(webTool name: String, input: [String: Any]) -> ArisReadCall? {
        switch name {
        case "WebSearch": return ArisReadCall(tool: "web search", arguments: compact(input))
        case "WebFetch": return ArisReadCall(tool: "web fetch", arguments: compact(input))
        default: return nil
        }
    }

    /// The relay's web forms: `web search <words…>` and `web fetch <address>`; nil for anything else.
    static func web(_ words: [String]) -> ArisReadCall? {
        guard words.first == "web", words.count >= 3 else { return nil }
        switch words[1] {
        case "search": return ArisReadCall(tool: "web search", arguments: words.dropFirst(2).joined(separator: " "))
        case "fetch" where words.count == 3: return ArisReadCall(tool: "web fetch", arguments: words[2])
        default: return nil
        }
    }

    /// A connected service's read tool.
    static func call(service: String, tool: String, arguments: [String: Any]) -> ArisReadCall {
        ArisReadCall(tool: "\(service) \(tool)", arguments: compact(arguments))
    }

    /// Any value as compact JSON with sorted keys (what it is as text, when it isn't JSON).
    static func compact(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys, .withoutEscapingSlashes]) else { return "\(value)" }
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    /// The judge's reason as it is shown and handed on: one line, no control characters, cut.
    static func cleanReason(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : Character($0) }
        let line = String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard line.count > maxReason else { return line }
        return String(line.prefix(maxReason)) + "…"
    }

    /// What the brain is told when the judge blocks a read: a fixed line per kind, never the judge's own words.
    static func refusal(_ why: ArisReadWhy) -> String {
        "Refused by Aris's read check: \(why.brain). Don't try it another way; answer from what you have, and say in a few words what you couldn't look up."
    }

    /// The notch's one quiet line for a block (never a card), fixed per kind.
    static func status(_ why: ArisReadWhy, english: Bool = false) -> String {
        english ? "Read blocked · " + why.englishNotch : "읽기 막음 · " + why.notch
    }

    // MARK: - aris-tools asks the agent (POST /mcp-tool, op "judge")

    static func body(_ call: ArisReadCall, turn: String) -> [String: Any] {
        ["op": "judge", "turn": turn, "tool": call.tool, "arguments": call.arguments]
    }

    /// The agent's answer: status 0 is a yes, status 1 a block of the kind it names (an unknown kind: `other`); no
    /// answer, or an odd one, is a block.
    static func verdict(reply: [String: Any]?) -> ArisReadVerdict {
        guard let reply, let output = reply["output"] as? String, let status = reply["status"] as? Int else { return .blocked(.undecided) }
        if status == 0 { return .ok }
        return .blocked(ArisReadWhy(rawValue: output) ?? .other)
    }

    /// The agent's reply body for a verdict: the kind only, never the judge's words.
    static func reply(_ verdict: ArisReadVerdict) -> (status: Int32, output: String) {
        verdict.allowed ? (0, "ok") : (1, (verdict.why ?? .other).rawValue)
    }

    // MARK: - Memory and the web as reads

    /// `memory [words]`: reading the user's memories (judged on a careful turn, refused hands-free, on every brain).
    static func isMemoryRead(_ words: [String]) -> Bool {
        words.first == "memory" && words.dropFirst().allSatisfy { !$0.hasPrefix("-") }
    }

    /// `maps search <words…> --json` or `maps directions <from> <to> --json`, exactly: MapKit's lookup, which only
    /// prints the place and its ETAs and opens nothing (QA BUG-1). A read on every brain: at once on a clean turn, the
    /// judge on a careful one (its words go to Apple's map service, like a web search). Maps opened (no --json) isn't.
    static func isMapsLookup(_ words: [String]) -> Bool {
        guard words.count >= 4, words.first == "maps", words.last == "--json" else { return false }
        let places = words.dropFirst(2).dropLast()
        guard places.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("-") && $0.count <= 200 }) else { return false }
        switch words[1] {
        case "search": return true
        case "directions": return places.count == 2
        default: return false
        }
    }

    /// The reads the judge checks on a careful turn: the user's apps, their memories and a maps lookup.
    /// And Aris's own record of its work (`recall`, ArisWorkRecallWords), on a careful turn like his memories.
    static func isJudgedRead(_ words: [String]) -> Bool { isAppRead(words) || isMemoryRead(words) || isMapsLookup(words) || ArisWorkRecallWords.isRecall(words) }

    /// Claude Code's WebFetch input passes the address check (ArisWebFetch.allows); nil when it isn't a WebFetch.
    static func fetchAllowed(tool: String, input: [String: Any], resolve: (String) -> [String]?) -> Bool? {
        guard tool == "WebFetch" else { return nil }
        guard let url = input["url"] as? String else { return false }
        return ArisWebFetch.allows(url, resolve: resolve) != nil
    }
}
