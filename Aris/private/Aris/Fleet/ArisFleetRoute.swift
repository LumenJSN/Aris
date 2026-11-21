//
//  ArisFleetRoute.swift
//  Aris
//
//  The fleet's ops on POST /aris/sessions (the shared token, like the rest of that route):
//  {"op": "fleet", "listing": [rows], "complete": bool}: the helper's look at Claude Code's own list goes in, and the
//    fleet comes out (ArisFleet's JSON, each session marked `answerable` when a card for its exact pending request
//    waits in the notch).
//  {"op": "deny", "session": id, "fingerprint": f}: a "no" to that very request's card. Only ever a no: any token
//    holder (a Claude Code session included) can reach this route, so no answer that lets something run is taken
//    here. An allow is the owner's yes on Aris's own card, applied in the app (ArisFleetGrant).
//  Foundation only (tested).
//

import Foundation

enum ArisFleetRoute {
    /// Rows taken from one look at most.
    static let mostRows = 64

    @MainActor
    static func answer(_ body: [String: Any], store: ClaudeStore, fleet: ArisFleetStore, now: Date) -> Data {
        let json: [String: Any]
        switch body["op"] as? String {
        case "fleet":
            if let rows = body["listing"] as? [[String: Any]] {
                fleet.listed(rows.prefix(mostRows).compactMap(listing), complete: body["complete"] as? Bool == true, at: now)
            }
            let marked = fleet.withCards(store.approvals)
            let object = (try? JSONSerialization.jsonObject(with: marked.json)) ?? [:]
            json = ["ok": true, "fleet": object]
        case "deny":
            guard let id = body["session"] as? String, let fingerprint = body["fingerprint"] as? String,
                  let card = store.approvals.first(where: { $0.sessionId == id && $0.fleetFingerprint == fingerprint }) else {
                json = ["ok": false, "message": "no such request waits"]
                break
            }
            guard case .tool = card.kind else {
                json = ["ok": false, "message": "not a permission request"]
                break
            }
            store.decide(card.id, .deny)
            json = ["ok": true]
        default:
            json = ["ok": false, "message": "unknown op"]
        }
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
    }

    /// One row of Claude Code's list as the helper sends it; each value checked for its shape.
    static func listing(_ row: [String: Any]) -> ArisFleetListing? {
        guard let session = row["session"] as? String, !session.isEmpty, session.count <= 100,
              let pid = (row["pid"] as? NSNumber)?.int32Value, pid > 1, let cwd = row["cwd"] as? String, cwd.hasPrefix("/"), cwd.count <= 1_024 else { return nil }
        var listing = ArisFleetListing(session: session, pid: pid, cwd: cwd)
        listing.started = (row["started"] as? Double).map { Date(timeIntervalSince1970: $0) }
        listing.title = (row["title"] as? String).map { String($0.prefix(120)) }
        listing.background = row["background"] as? Bool == true
        listing.status = (row["status"] as? String).flatMap { ["busy", "idle", "waiting"].contains($0) ? $0 : nil }
        listing.branch = (row["branch"] as? String).map { String($0.prefix(120)) }
        if let reach = row["reach"] as? [String: Any], let kind = (reach["kind"] as? String).flatMap(ArisFleetReach.Kind.init(rawValue:)) {
            listing.reach = ArisFleetReach(kind: kind, app: (reach["app"] as? String).map { String($0.prefix(60)) })
        }
        return listing
    }
}
