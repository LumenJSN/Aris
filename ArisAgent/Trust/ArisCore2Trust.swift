//
//  ArisCore2Trust.swift
//  aris-agent
//
//  The helper's few touch points with Judgment and Record, each one line in main.swift: start-up (the record's audit
//  writer, the why-desk's record lines, pruning), POST /trust (the settings' data route), the trust cards' answers on
//  POST /confirm, and the record's part of POST /activity, /undo and /undo-folder. With `arisCore2` off every one of
//  them steps aside and the old path answers as before.
//

import Foundation

enum ArisCore2Trust {
    /// actions.log's writer (main.swift passes ArisAgentRunner.writeAudit): a line and its key.
    nonisolated(unsafe) static var writeAudit: (String, String) -> Void = { _, _ in }

    static func start(home: String, audit: @escaping (String, String) -> Void) {
        writeAudit = audit
        ArisRecord.audit = { audit($0, "record") }
        ArisWhyDesk.recordLines = { from, to in ArisRecordRoutes.why(session: nil, from: from, to: to, home: home) }
        // Judgment's focus hook reads the turn's focus (jv-focus); the gate itself runs only with the switch on.
        ArisFocusDesk.install()
        // The app sends its switches with its first request, after the helper started, so Core 2's live parts start
        // when the switch is heard on, not only at launch (fourth VM run, D7: they never started, so the undo of a
        // replay's typing had no performer and failed with "isn't available in this helper yet").
        ArisSwitchEffects.core2On = { startLive(home: home) }
        guard ArisTrustSwitch.isOn() else { return }
        startLive(home: home)
    }

    private static let started = ArisLocked(false)

    /// Core 2's live parts, once: the browser's page for the gate's card (decision 2), the Mind's undo performers and
    /// World, and the record's pruning.
    static func startLive(home: String) {
        guard started.withLock({ was in
            defer { was = true }
            return !was
        }) else { return }
        ArisBrowserLive.install()
        ArisMindLive.start()
        ArisRecordJournal.prune(home: home)
        ArisUndoStore(home: home).prune()
    }

    static func statusLine(_ status: Int) -> String {
        switch status {
        case 200: "200 OK"
        case 400: "400 Bad Request"
        case 403: "403 Forbidden"
        case 404: "404 Not Found"
        case 409: "409 Conflict"
        default: "500 Internal Server Error"
        }
    }

    /// POST /trust (the Aris app itself only: main.swift checks that first).
    static func settings(_ object: [String: Any], home: String) -> (status: String, body: Data) {
        let reply = ArisTrustRoute.handle(object, home: home, audit: { writeAudit($0, "trust") })
        return (statusLine(reply.status), reply.body)
    }

    /// POST /confirm for a trust card; nil when the card isn't the trust gate's (or the switch is off). A yes counts only
    /// for the card exactly as made (the app sends back what it showed).
    static func confirm(_ object: [String: Any], id: String, allow: Bool) -> String? {
        guard ArisTrustSwitch.isOn(), ArisTrustGate.shared.owns(id) else { return nil }
        guard !allow || ArisTrustGate.shared.shown(id, detail: object["detail"] as? String, full: object["full"] as? String) else {
            writeAudit(ArisTrustGate.line(["answer": "refused (the card shown isn't the card made)", "question": id]), "confirm")
            return statusLine(403)
        }
        _ = ArisTrustGate.shared.answer(id, allow: allow, always: object["always"] as? Bool == true, unanswered: !allow && object["unanswered"] as? Bool == true)
        return statusLine(200)
    }

    /// The record's rows added to POST /activity's (the log's body as aris-tools gave it).
    static func activity(_ body: Data, today: Bool, home: String) -> Data {
        ArisTrustSwitch.isOn() ? ArisRecordRoutes.activity(logBody: body, today: today, home: home) : body
    }

    /// POST /undo answered from the record (off the server queue; `reply` on any queue); false when it is the old path's.
    static func undo(_ object: [String: Any], home: String, reply: @escaping (String, Data) -> Void) -> Bool {
        guard ArisTrustSwitch.isOn(), object["confirmed"] as? Bool != true else { return false }
        let id = object["id"] as? String
        if let id, UUID(uuidString: id) == nil { return false }
        let state = ArisRecordJournal.state(home: home)
        let known = id.map { id in state.calls.contains { $0.id == id.lowercased() } } ?? true
        guard known else { return false }
        let logLatest = ArisRecordRoutes.logLatest()
        if id == nil, ArisRecordRoutes.undo(id: nil, home: home, logLatest: logLatest, dryRun: true) == nil { return false }
        let unit = object["unit"] as? Bool == true
        DispatchQueue.global(qos: .userInitiated).async {
            guard let answer = ArisRecordRoutes.undo(id: id, unit: unit, home: home, logLatest: logLatest) else {
                return reply(statusLine(500), Data(#"{"error":"nothing to undo"}"#.utf8))
            }
            writeAudit(ArisTrustGate.line(["action": "undo (record)", "risk": "spoken", "exit": String(answer.status)]), "app")
            reply(statusLine(answer.status), Data(answer.body.utf8))
        }
        return true
    }

    /// POST /undo-folder for a record entry; nil when it is the old path's.
    static func undoFolder(_ id: String?, home: String) -> String? {
        guard ArisTrustSwitch.isOn() else { return nil }
        return ArisRecordRoutes.folder(ofEntry: id, home: home)
    }
}
