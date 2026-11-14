//
//  ArisDataExport.swift
//  aris-agent
//
//  What the data export (설정 › 정보 › 데이터 › 내보내기, POST /data {"op": "export"}) adds to memory.md's lines:
//  each memory with where it came from (said, learned, a tool, imported, and from which AI), its mark (an imported
//  instruction) and the whole text of a long imported line; and the work memory, every episode and lesson as stored
//  (Aris's own record: never a tool's output). Foundation only (tested).
//

import Foundation

enum ArisDataExport {
    /// {"memoryDetails": [...], "work": {"on", "episodes", "lessons"}} for the export's reply.
    static func extras(memory: ArisMemoryStore) -> [String: Any] {
        let extras = memory.importExtras()
        let details = memory.all().reversed().map { record -> [String: Any] in
            var row: [String: Any] = ["text": record.text, "kind": record.kind.rawValue, "source": record.source.rawValue,
                                      "date": ArisMemoryText.day(record.turnAt), "confidence": record.confidence]
            if !record.subject.isEmpty { row["subject"] = record.subject }
            if let extra = extras[record.id] {
                if let via = extra.via { row["via"] = via }
                if let mark = extra.mark { row["mark"] = mark }
                if let detail = extra.detail { row["detail"] = detail }
            }
            return row
        }
        let work = ArisWorkStore(memory: memory)
        let stamp = ISO8601DateFormatter()
        let episodes = work.episodes(tainted: true, limit: ArisWorkStore.capacity).map { episode -> [String: Any] in
            ["id": episode.name, "at": stamp.string(from: episode.at), "kind": episode.kind.rawValue, "asked": episode.asked, "brain": episode.brain,
             "steps": episode.steps.map { "\($0.line) [\($0.status)]" }, "made": episode.made.map { ["kind": $0.kind, "value": $0.value] },
             "outcome": episode.outcome.rawValue, "taint": episode.taint.mark, "title": episode.title, "teammate": episode.teammate,
             "place": episode.place, "result": episode.result]
        }
        let lessons = work.lessons(expired: true).map { lesson -> [String: Any] in
            ["id": lesson.name, "kind": lesson.kind.rawValue, "key": lesson.key, "asked": lesson.asked, "works": lesson.works.map(\.line),
             "fails": lesson.fails.map(\.line), "basedOn": lesson.evidence.map { "E\($0)" }, "confidence": lesson.confidence,
             "expired": lesson.expired, "learnedWhereOutsideTextWasRead": lesson.outside]
        }
        // The people and project pages: summary, names and the timeline with each entry's source.
        let pages = memory.entities().map { entity -> [String: Any] in
            ["name": entity.name, "kind": entity.kind.rawValue, "summary": entity.summary, "aliases": entity.aliases,
             "timeline": memory.timeline(of: entity.id).map { ["date": ArisMemoryText.day($0.at), "text": $0.text, "source": $0.source.rawValue] }]
        }
        return ["memoryDetails": details, "people": pages, "work": ["on": work.isOn, "episodes": episodes, "lessons": lessons] as [String: Any]]
    }
}
