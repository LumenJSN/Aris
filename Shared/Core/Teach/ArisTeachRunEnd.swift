//
//  ArisTeachRunEnd.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  What a replay's end says beyond its account (sixth VM run). Item 6a: a run that didn't do every step left its
//  "Doing “랩 메모”" tag ticked; only a run that did them all is done, any other end marks the tag as not done. Item 1:
//  a step that typed into an app and couldn't check what the field holds has no undo; the end says so, so a later
//  "되돌려" that can't take it back is no surprise. Pure.
//

import Foundation

enum ArisTeachRunEnd {
    /// Every step ran and worked.
    static func completed(_ outcome: ArisTeachReplay.Outcome) -> Bool {
        if case .done = outcome { return true }
        return false
    }

    /// The run's tag is marked as not done: any end but every step done, except his no on a card or a card nobody
    /// answered (the app takes the running tag away when a card ends without a yes) and a newer turn (this one's tags are gone).
    static func marksTagFailed(_ outcome: ArisTeachReplay.Outcome) -> Bool {
        switch outcome {
        case .done: return false
        case .partly: return true
        case .stopped(_, let end, _): return end != .declined && end != .unanswered && end != .stale
        }
    }

    /// The typing calls of a run that went in with no undo, by app (in order, each app once). Written from the run's
    /// queue, read after it.
    final class Unchecked: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String] = []

        init() {}

        /// One call's result: a typing that worked and has no undo names its app.
        func note(call name: String, result: ArisMindResult) {
            guard ArisTeachRunEnd.typing.contains(name), !result.isError, result.undo == nil else { return }
            let app = result.content?.source ?? ""
            lock.withLock { if !seen.contains(app) { seen.append(app) } }
        }

        var apps: [String] { lock.withLock { seen } }
    }

    /// The typing capability by its tool and capability names.
    static let typing: Set<String> = ["app_type", "app.type"]

    /// The account, with a line for typing that can't be undone.
    static func withUnchecked(_ account: String, apps: [String], english: Bool) -> String {
        guard !apps.isEmpty else { return account }
        let named = apps.filter { !$0.isEmpty }
        let line: String
        if english {
            line = named.isEmpty ? "What was typed couldn't be checked, so it can't be undone."
                : "What was typed into \(named.joined(separator: ", ")) couldn't be checked, so it can't be undone."
        } else {
            line = named.isEmpty ? "입력한 글은 확인하지 못해서 되돌릴 수 없어요."
                : "\(named.joined(separator: ", "))에 입력한 글은 확인하지 못해서 되돌릴 수 없어요."
        }
        return account + "\n" + line
    }
}
