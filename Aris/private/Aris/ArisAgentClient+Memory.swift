//
//  ArisAgentClient+Memory.swift
//  Aris
//
//  설정 › 기억 talks to aris-agent's POST /memory: the agent owns memory.sqlite (the sandboxed app can't open it);
//  the app lists, deletes one, deletes all and flips 자동으로 기억하기. Only the Aris app itself is answered (ArisPeer).
//

import Foundation

extension ArisAgentClient {
    private static let memoryURL = URL(string: "http://127.0.0.1:23351/memory")!

    /// The memories, the switches, and what waits for the user (held items, conflicts), the people and project pages and
    /// the weekly tidy-up's changes; nil when the agent didn't answer (the list says so, rather than looking empty).
    static func memories() async -> ArisMemoryPage? {
        guard let data = await memoryCall(["op": "list"]) else { return nil }
        return try? JSONDecoder().decode(ArisMemoryPage.self, from: data)
    }

    /// 확인할 것 › 넣기 / 버리기. True when the agent did it.
    static func keepHeldMemory(id: String) async -> Bool { await memoryFlag(["op": "heldKeep", "id": id], "kept") }
    static func dropHeldMemory(id: String) async -> Bool { await memoryFlag(["op": "heldDrop", "id": id], "dropped") }

    /// A conflict settled: `keep` is the memory that is right now, or "both".
    static func settleMemoryConflict(id: String, keep: String) async -> Bool { await memoryFlag(["op": "conflictKeep", "id": id, "keep": keep], "settled") }

    /// A person's or project's page removed (its memories stay).
    static func forgetMemoryEntity(id: String) async -> Bool { await memoryFlag(["op": "entityDelete", "id": id], "removed") }

    /// The weekly tidy-up's change taken back.
    static func undoMemoryChange(id: Int) async -> Bool { await memoryFlag(["op": "changeUndo", "id": id], "undone") }

    /// 매주 정리하기 as the agent now has it; nil when it didn't answer.
    static func setConsolidateMemory(_ on: Bool) async -> Bool? {
        guard let data = await memoryCall(["op": "consolidate", "on": on]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["consolidate"] as? Bool
    }

    /// The answer's `key` is true.
    private static func memoryFlag(_ body: [String: Any], _ key: String) async -> Bool {
        guard let data = await memoryCall(body), let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return reply[key] as? Bool == true
    }

    /// True when the agent removed it.
    static func forgetMemory(id: String) async -> Bool {
        guard let data = await memoryCall(["op": "delete", "id": id]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return body["removed"] as? Bool == true
    }

    /// The user's 확인: the memory counts as sure. True when the agent had it.
    static func confirmMemory(id: String) async -> Bool {
        guard let data = await memoryCall(["op": "confirm", "id": id]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return body["confirmed"] as? Bool == true
    }

    static func forgetAllMemories() async -> Bool {
        await memoryCall(["op": "clear", "confirm": "모두"]) != nil
    }

    /// The switch as the agent now has it; nil when it didn't answer.
    static func setAutoMemory(_ on: Bool) async -> Bool? {
        guard let data = await memoryCall(["op": "auto", "on": on]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["auto"] as? Bool
    }

    // MARK: 일하면서 배운 것 (the agent's work memory: ArisWorkRoute)

    /// The lessons, how many episodes there are and the switch; nil when the agent didn't answer.
    static func workMemory() async -> (lessons: [ArisWorkLessonItem], episodes: Int, on: Bool)? {
        guard let data = await memoryCall(["op": "work"]) else { return nil }
        struct Reply: Decodable { let lessons: [ArisWorkLessonItem]; let episodes: Int; let on: Bool }
        return (try? JSONDecoder().decode(Reply.self, from: data)).map { ($0.lessons, $0.episodes, $0.on) }
    }

    /// The switch as the agent now has it; nil when it didn't answer.
    static func setWorkMemory(_ on: Bool) async -> Bool? {
        guard let data = await memoryCall(["op": "workOn", "on": on]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["on"] as? Bool
    }

    static func forgetWorkLesson(id: Int) async -> Bool {
        guard let data = await memoryCall(["op": "workDelete", "id": id]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return body["removed"] as? Bool == true
    }

    static func forgetAllWork() async -> Bool {
        await memoryCall(["op": "workClear", "confirm": "모두"]) != nil
    }

    // MARK: 저장된 단계 (the agent's saved desktop steps: ArisSavedStepsRoute)

    /// The saved requests, newest first; nil when the agent didn't answer.
    static func savedSteps() async -> [ArisSavedStepsItem]? {
        guard let data = await memoryCall(["op": "savedSteps"]) else { return nil }
        struct Reply: Decodable { let recipes: [ArisSavedStepsItem] }
        return (try? JSONDecoder().decode(Reply.self, from: data))?.recipes
    }

    static func forgetSavedSteps(key: String) async -> Bool {
        guard let data = await memoryCall(["op": "savedStepsDelete", "key": key]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return body["removed"] as? Bool == true
    }

    // MARK: 다른 AI에서 가져오기 (ArisImportRoute)

    /// The request to copy into the other AI, in the UI's language; nil when the agent didn't answer.
    static func importPrompt(english: Bool) async -> String? {
        guard let data = await memoryCall(["op": "importPrompt"]), let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body[english ? "en" : "ko"] as? String
    }

    /// The agent's reading of a paste: every line with what Aris makes of it. The text never goes to an AI.
    static func importPreview(_ text: String) async -> (lines: [ArisImportRow], unreadable: [String], complete: Bool?)? {
        guard let data = await memoryCall(["op": "importPreview", "text": text], timeout: 20) else { return nil }
        struct Reply: Decodable { let lines: [ArisImportRow]; let unreadable: [String]; let complete: Bool? }
        return (try? JSONDecoder().decode(Reply.self, from: data)).map { ($0.lines, $0.unreadable, $0.complete) }
    }

    /// Writes the chosen lines in one go; what was written, with the batch that 되돌리기 names.
    static func importApply(source: String, lines: [[String: String]]) async -> ArisImportReceipt? {
        guard let data = await memoryCall(["op": "importApply", "source": source, "lines": lines], timeout: 60) else { return nil }
        return try? JSONDecoder().decode(ArisImportReceipt.self, from: data)
    }

    /// True when exactly that batch was taken back.
    static func importUndo(batch: String) async -> Bool {
        guard let data = await memoryCall(["op": "importUndo", "batch": batch], timeout: 20),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return body["found"] as? Bool == true
    }

    /// The body of a 200 answer; nil for anything else.
    private static func memoryCall(_ body: [String: Any], timeout: TimeInterval = 5) async -> Data? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: memoryURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
