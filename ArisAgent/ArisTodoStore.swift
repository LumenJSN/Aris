//
//  ArisTodoStore.swift
//  aris-agent
//
//  What the notch app can't read itself (POST /todos): Canvas deadlines still to hand in (aris-tools canvas --json,
//  fetched at most every 10 minutes), the ones ticked off (aris/todos.json), and the old to-do file's items, which
//  the app imports into Reminders once. Your to-dos themselves are in Reminders (the app). One queue, so two
//  changes never race.
//

import Foundation

enum ArisTodoStore {
    private static let work = DispatchQueue(label: "com.lumenjsn.aris.todos")
    private static let canvasEvery: TimeInterval = 600
    private static var canvas: (at: Date, due: [ArisDue])?
    private static var file: URL { ArisAgentRunner.directory.appendingPathComponent("todos.json") }

    /// Applies `op` (list, hide, finish) and answers with what to show: JSON {todos, due}.
    static func handle(op: String, text: String?, id: String?, done: @escaping (Data) -> Void) {
        work.async {
            var list = load()
            let now = Date()
            var finished: String?
            switch op {
            case "hide": if let id { list = list.hidingDue(id) }
            case "finish":
                // The Canvas deadline those words name (hidden: nothing is handed in); the app does your own items.
                if let text, let due = ArisDueMatch.one(text, in: canvasDue(now: now)) {
                    list = list.hidingDue(due.id)
                    // Canvas titles are other people's words: the app only learns that a deadline was ticked.
                    finished = ArisTodoList.dueTicked
                }
            default: break
            }
            if op == "hide" || finished != nil { save(list) }
            let due = canvasDue(now: now).filter { !list.hiddenDue.contains($0.id) }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let todos = (try? encoder.encode(list.shown(now: now))) ?? Data("[]".utf8)
            let deadlines = (try? encoder.encode(due)) ?? Data("[]".utf8)
            let said = finished.flatMap { try? JSONSerialization.data(withJSONObject: [$0], options: .fragmentsAllowed) }
                .map { Data(",\"finished\":".utf8) + $0.dropFirst().dropLast() } ?? Data()
            done(Data("{\"todos\":".utf8) + todos + Data(",\"due\":".utf8) + deadlines + said + Data("}".utf8))
        }
    }

    private static func canvasDue(now: Date) -> [ArisDue] {
        if let canvas, now.timeIntervalSince(canvas.at) < canvasEvery { return canvas.due }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Whole, never cut at the look's 4,000 characters (a long term's list is longer).
        guard let output = ArisLook.dataOutput(ArisAgentRunner.toolsPath, ["canvas", "--json"], ArisAgentRunner.environment(), timeout: 20),
              let due = try? decoder.decode([ArisDue].self, from: Data(output.utf8)) else { return canvas?.due ?? [] }
        canvas = (now, due)
        return due
    }

    private static func load() -> ArisTodoList {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: file)).flatMap { try? decoder.decode(ArisTodoList.self, from: $0) } ?? ArisTodoList()
    }

    private static func save(_ list: ArisTodoList) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(list.pruned(now: Date())) else { return }
        do {
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            FileHandle.standardError.write(Data("aris-agent: couldn't save the to-do list: \(error.localizedDescription)\n".utf8))
        }
    }
}
