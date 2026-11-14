//
//  ArisMemoryReviewRoute.swift
//  aris-agent
//
//  POST /memory, the parts of 설정 › 기억 that memory v2 added (only the Aris app itself: ArisPeer, in main.swift):
//  what waits for the user (held items, conflicts), the people and project pages, and the weekly tidy-up's switch and
//  changes. The ops are listed on ArisMemoryRoute. A memory's words never go into the audit line.
//  Foundation only (tested).
//

import Foundation

enum ArisMemoryReviewRoute {
    /// The lists `{"op": "list"}` adds beside the memories.
    static func lists(_ store: ArisMemoryStore, now: Date = Date()) -> [String: Any] {
        let memories = store.all()
        let held = store.held().map { item -> [String: Any] in
            ["id": item.id, "kind": item.kind, "text": item.text, "source": item.source.rawValue, "label": item.source.label(korean: true),
             "why": ArisMemoryGate.reason(item.family, korean: true), "whyEn": ArisMemoryGate.reason(item.family, korean: false), "at": item.at.timeIntervalSince1970]
        }
        let side = { (r: ArisMemoryRecord) -> [String: Any] in
            ["id": r.id, "text": r.line, "source": r.source.rawValue, "label": r.source.label(korean: true), "said": r.turnAt.timeIntervalSince1970]
        }
        let conflicts = store.conflicts().map { c -> [String: Any] in ["id": c.id, "first": side(c.first), "second": side(c.second)] }
        let entities = store.entities().map { e -> [String: Any] in
            ["id": e.id, "kind": e.kind.rawValue, "name": e.name, "summary": e.summary, "entries": store.timeline(of: e.id).count,
             "open": ArisEntities.openItems(e, memories: memories, now: now).count, "aliases": e.aliases]
        }
        let changes = store.changes().map { c -> [String: Any] in
            ["id": c.id, "name": c.name, "before": c.before, "after": c.after, "at": c.at.timeIntervalSince1970, "evidence": c.evidence]
        }
        return ["held": held, "conflicts": conflicts, "entities": entities, "changes": changes]
    }

    /// Nil for any op that isn't one of these.
    static func handle(_ object: [String: Any], store: ArisMemoryStore) -> (status: Int, body: Data, audit: String?)? {
        let id = (object["id"] as? String).flatMap { $0.isEmpty || $0.count > 64 ? nil : $0 }
        switch object["op"] as? String {
        case "heldKeep":
            guard let id else { return bad() }
            let kept: Bool
            switch store.keepHeld(id: id) {
            case .memory(let outcome)?:
                if case .added = outcome { kept = true } else if case .updated = outcome { kept = true } else if case .duplicate = outcome { kept = true } else { kept = false }
            case .lesson(let payload)?: kept = ArisWorkStore(memory: store).saveReviewed(payload: payload) != nil
            case nil: kept = false
            }
            return ok(["kept": kept], audit: kept ? "memory: kept a held item" : nil)
        case "heldDrop":
            guard let id else { return bad() }
            let dropped = store.dropHeld(id: id)
            return ok(["dropped": dropped], audit: dropped ? "memory: dropped a held item" : nil)
        case "conflictKeep":
            guard let id, let keep = object["keep"] as? String, !keep.isEmpty, keep.count <= 64 else { return bad() }
            let settled = store.resolveConflict(id: id, keep: keep == "both" ? nil : keep)
            return ok(["settled": settled], audit: settled ? "memory: settled a conflict" : nil)
        case "entityDelete":
            guard let id else { return bad() }
            let removed = store.deleteEntity(id: id)
            return ok(["removed": removed], audit: removed ? "memory: removed a page" : nil)
        case "changeUndo":
            guard let number = object["id"] as? Int else { return bad() }
            let undone = store.undoChange(id: number)
            return ok(["undone": undone], audit: undone ? "memory: undid a tidy-up change" : nil)
        case "consolidate":
            guard let on = object["on"] as? Bool else { return bad() }
            store.consolidates = on
            return ok(["consolidate": store.consolidates], audit: "memory: weekly tidy-up \(on ? "on" : "off")")
        default:
            return nil
        }
    }

    private static func ok(_ object: [String: Any], audit: String?) -> (status: Int, body: Data, audit: String?) {
        (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8), audit)
    }

    private static func bad() -> (status: Int, body: Data, audit: String?) { (400, Data("{}".utf8), nil) }
}
