//
//  ArisAgentClient+TypeHere.swift
//  Aris
//
//  The quick path's write at a caret (ArisTypeHere) and the undo of it: the helper types only where nothing is selected
//  and hands back the mark of what it added; "되돌려" sends that mark back and only that text is taken out.
//

import Foundation

extension ArisAgentClient {
    private static let typeHereURL = URL(string: "http://127.0.0.1:23351/insert")!
    private static let typeHereUndoURL = URL(string: "http://127.0.0.1:23351/insert-undo")!

    struct TypedHere: Equatable {
        /// The app it went into, and the mark that finds the added text again (nil: it can't be taken back by Aris).
        let app: String?
        let undo: String?
    }

    enum TypeHereResult: Equatable {
        case typed(TypedHere)
        /// Something was selected (or couldn't be read) when it came to type: nothing typed.
        case notAtCaret
        case failed(String)
    }

    /// `text` typed at the caret of the look's field (`target`), never over a selection.
    static func typeAtCaret(_ text: String, target: String) async -> TypeHereResult {
        guard let token = ClaudeHookToken.load() else { return .failed("Aris's helper isn't running") }
        var request = URLRequest(url: typeHereURL, timeoutInterval: fieldWriteTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(["text": text, "target": target, "caretOnly": true]))
        guard let (data, response) = try? await ArisNoStore.session.data(for: request) else { return .failed("Aris's helper didn't answer") }
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if reply["notAtCaret"] as? Bool == true { return .notAtCaret }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .failed((reply["error"] as? String) ?? "it couldn't be typed") }
        return .typed(TypedHere(app: reply["app"] as? String, undo: reply["undo"] as? String))
    }

    /// Takes out the text a caret write added. Nil when it was, else why not.
    static func undoTyped(_ typed: TypedHere) async -> String? {
        guard let app = typed.app, let undo = typed.undo else { return "Aris can't find that text again" }
        guard let token = ClaudeHookToken.load() else { return "Aris's helper isn't running" }
        var request = URLRequest(url: typeHereUndoURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(["app": app, "undo": undo]))
        guard let (data, response) = try? await ArisNoStore.session.data(for: request) else { return "Aris's helper didn't answer" }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String ?? "it couldn't be taken back"
        }
        return nil
    }
}

extension ArisAgentClient {
    private static let asideReadyURL = URL(string: "http://127.0.0.1:23351/aside-ready")!

    /// Whether Aside's command-line tool is on this Mac; nil when the helper didn't say (then nothing is held back).
    static func asideInstalled() async -> Bool? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: asideReadyURL, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified([:]))
        guard let (data, response) = try? await ArisNoStore.session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["installed"] as? Bool
    }
}

/// The last text the quick path typed at a caret, for "되돌려" (kept for this app run only).
@MainActor
final class ArisTypedHereLog {
    static let shared = ArisTypedHereLog()
    private(set) var last: (typed: ArisAgentClient.TypedHere, at: Date)?

    func note(_ typed: ArisAgentClient.TypedHere, at: Date = Date()) { last = (typed, at) }

    /// The last write when it is newer than `newest` (the newest other change) and within `reach`; nil otherwise.
    func latest(newerThan newest: Date?, since reach: Date) -> ArisAgentClient.TypedHere? {
        guard let last, last.at >= reach, last.at >= (newest ?? .distantPast) else { return nil }
        return last.typed
    }

    func clear() { last = nil }
}
