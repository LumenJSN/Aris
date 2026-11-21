//
//  ArisTypeHereRoutes.swift
//  aris-agent
//
//  The app's own writes into a field its look read (/insert with a "target"), and the undo of one it typed at a caret
//  (/insert-undo): the text it added is found again by its mark (ArisApps.TextUndo) and only that range is taken out
//  (twelfth VM run, S3u: "방금 거 되돌려 줘" after the quick path typed said "되돌릴 게 없어요").
//

import Foundation
import Network

enum ArisTypeHereRoutes {
    static let paths: Set<String> = ["/insert-undo"]

    /// /insert with a look's field token. `caretOnly`: the quick path's write (only at a caret); its reply carries the
    /// undo mark of what it added.
    static func writeField(_ text: String, token: String, caretOnly: Bool, on connection: NWConnection) {
        DispatchQueue.global(qos: .userInitiated).async {
            let written = ArisFieldTargetLive.write(text, token: token, caretOnly: caretOnly)
            var reply: [String: Any] = written.outcome.failure.map(ArisInsertRefusal.reply) ?? ["confirmed": true]
            if let undo = written.undo, let app = written.app { reply["undo"] = undo; reply["app"] = app }
            if written.outcome.failure == ArisFieldWrite.notAtCaret { reply["notAtCaret"] = true }
            let body = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8)
            queue.async { respond(connection, written.outcome.failure == nil ? "200 OK" : "500 Internal Server Error", body) }
        }
    }

    static func handle(_ path: String, _ object: [String: Any], on connection: NWConnection) {
        guard path == "/insert-undo", let app = object["app"] as? String, let element = object["undo"] as? String,
              app.count <= 200, element.count <= 20_000, ArisApps.TextUndo.mark(element) != nil else {
            return respond(connection, "400 Bad Request", Data())
        }
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": "undo: text typed in \(app)", "risk": "spoken"]), key: "local")
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do { try ArisAppsTextUndoLive.remove(app: app, element: element) } catch let error as ArisUndoError { failure = error.message } catch {
                failure = String(describing: error)
            }
            let body = (try? JSONSerialization.data(withJSONObject: failure.map { ["error": $0] } ?? ["undone": true])) ?? Data("{}".utf8)
            queue.async { respond(connection, failure == nil ? "200 OK" : "500 Internal Server Error", body) }
        }
    }
}
