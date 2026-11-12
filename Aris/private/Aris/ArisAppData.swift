//
//  ArisAppData.swift
//  Aris
//
//  What the app itself keeps, for 정보 › 데이터 (audit ④, mockup audit-4-settings-extra.html option C): which files
//  each 데이터 지우기 item means in the app's own container, and the 데이터 내보내기 JSON (history, memory, teammates).
//  Memory and the agent's logs live in ~/.config/aris, which the sandboxed app can't write: those go through the
//  agent's /data route (ArisDataRoute). Pure apart from the file removal, which is given the folders (tests use a temp
//  folder).
//

import Foundation

enum ArisAppData {
    /// The 데이터 지우기 list.
    enum Item: String, CaseIterable, Identifiable {
        case history, memory, words, clipboard, sprites, logs

        var id: Self { self }

        var title: String {
            switch self {
            case .history: "대화 기록"
            case .memory: "Aris가 기억하는 것"
            case .words: "받아쓰기 단어장 · 배운 단어"
            case .clipboard: "클립보드 기록"
            case .sprites: "캐릭터 그림 캐시"
            case .logs: "기록 파일(로그)"
            }
        }

        /// Whether (part of) it is in ~/.config/aris, so the agent removes it.
        var agentSide: Bool { self == .memory || self == .words || self == .logs }
    }

    struct Places {
        /// The container's Application Support and Caches.
        let support: URL
        let caches: URL
        let bundleId: String

        var arisFolder: URL { support.appendingPathComponent("Aris", isDirectory: true) }

        /// The app's files for `item` that exist now.
        func paths(for item: Item) -> [URL] {
            switch item {
            case .history: return files(named: { $0 == "history.json" || $0.hasPrefix("history.json.corrupt-") })
            case .clipboard: return files(named: { $0 == "clipboard.json" || $0.hasPrefix("clipboard.json.corrupt-") })
            case .logs: return files(named: { $0.contains(".jsonl") })
            case .sprites:
                let sprites = caches.appendingPathComponent(bundleId, isDirectory: true).appendingPathComponent("ArisSprites", isDirectory: true)
                return FileManager.default.fileExists(atPath: sprites.path) ? [sprites] : []
            case .memory, .words: return []
            }
        }

        private func files(named match: (String) -> Bool) -> [URL] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: arisFolder.path)) ?? []
            return names.filter(match).sorted().map { arisFolder.appendingPathComponent($0) }
        }

        /// Removes the app's files for `items`; the ones that couldn't be removed.
        func remove(_ items: [Item]) -> [URL] {
            items.flatMap(paths(for:)).filter { url in
                do { try FileManager.default.removeItem(at: url); return false } catch { return true }
            }
        }

        /// The app's own container folders, in the sandbox.
        static func current() -> Places? {
            let fm = FileManager.default
            guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                  let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
            return Places(support: support, caches: caches, bundleId: Bundle.main.bundleIdentifier ?? "com.lumenjsn.aris")
        }
    }

    // MARK: - 데이터 내보내기

    private struct ExportedTurn: Encodable {
        let date: String
        let heard: String
        let reply: String
        let file: String?
        let task: Bool
    }

    /// The export file: a header, then each part the owner picked (nil = not picked). `since` keeps only newer history.
    /// `extras`: the agent's "memoryDetails" and "work", written beside the memory when memory is picked.
    static func exportJSON(history: [ArisHistoryEntry]?, memory: String?, teammates: [Any]?, since: Date?, now: Date, extras: [String: Any]? = nil) -> Data {
        let stamp = ISO8601DateFormatter()
        var root: [String: Any] = ["app": "Aris", "exported": stamp.string(from: now), "version": 1]
        if let history {
            let kept = history.filter { since == nil || $0.date >= since! }.sorted { $0.date < $1.date }
            root["history"] = kept.map { entry -> [String: Any] in
                var row: [String: Any] = ["date": stamp.string(from: entry.date), "heard": entry.heard, "reply": entry.reply, "task": entry.isTask]
                if let file = entry.file { row["file"] = file }
                return row
            }
        }
        if let memory {
            root["memory"] = facts(memory)
            for key in ["memoryDetails", "work"] { if let part = extras?[key] { root[key] = part } }
        }
        if let teammates { root["teammates"] = teammates }
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    /// memory.md's "- fact (date)" lines as plain facts.
    static func facts(_ memory: String) -> [String] {
        memory.split(separator: "\n").map { line -> String in
            var text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("- ") { text.removeFirst(2) }
            return text
        }.filter { !$0.isEmpty }
    }

    /// "Aris 데이터 2026-11-04.json".
    static func fileName(_ base: String, ext: String, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(base) \(formatter.string(from: now)).\(ext)"
    }
}
