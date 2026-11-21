//
//  ArisTaughtRoute.swift
//  aris-agent
//
//  The taught procedures (F3, ArisTeachStore's taught.json) on the settings page: listed among 설정 › 기억 › 저장된 단계
//  with the saved desktop steps and the learned shortcuts, each with 이름 바꾸기 and 지우기, through POST /memory's ops
//  (fourth VM run: lessons he taught were nowhere in Settings, which said there were no saved steps):
//    {"op": "savedSteps"}                                -> the rows before it, then one row per taught procedure (key
//                                                           with `keyPrefix` and its id, its steps worded in both
//                                                           languages by ArisTeachCopy.step, the apps)
//    {"op": "savedStepsDelete", "key": "…"}              -> a key with `keyPrefix` deletes that procedure
//    {"op": "savedStepsRename", "key": "…", "name": "…"} -> renames it: {"renamed": bool, "taken": bool}; a name another
//                                                           procedure or a routine has is refused, never taken over
//  The settings' buttons are his own clicks in the app (POST /memory takes only the app itself), so no card is asked
//  as the spoken "이름 바꿔" / "지워" do. Foundation only (tested); the live access is `live(home:)`.
//

import Foundation

/// What the route may do with the taught procedures.
struct ArisTaughtAccess {
    var all: () -> [ArisTeachProcedure]
    /// True when that procedure was there and is gone.
    var remove: (UUID) -> Bool
    /// The routines' names (a procedure never takes one).
    var routineNames: () -> [String]
    /// Keeps the renamed procedure; false when it couldn't be written.
    var save: (ArisTeachProcedure) -> Bool
}

enum ArisTaughtRoute {
    /// Marks a row's key as a taught procedure's. Like ArisShortcutsRoute's, it starts with a space, which no saved
    /// steps' key does.
    static let keyPrefix = " taught:"

    /// `earlier`: the answer of the routes before this one for the same object (saved steps and learned shortcuts).
    static func handle(_ object: [String: Any], access: ArisTaughtAccess?,
                       earlier: () -> (status: Int, body: Data, audit: String?)) -> (status: Int, body: Data, audit: String?) {
        guard let access else { return earlier() }
        switch object["op"] as? String {
        case "savedSteps":
            let before = earlier()
            guard before.status == 200 else { return before }
            var body = (try? JSONSerialization.jsonObject(with: before.body)) as? [String: Any] ?? [:]
            body["recipes"] = (body["recipes"] as? [[String: Any]] ?? []) + rows(access.all())
            return (200, (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8), before.audit)
        case "savedStepsDelete":
            guard let id = id(object["key"]) else { return earlier() }
            let removed = access.remove(id)
            return ok(["removed": removed], audit: removed ? "teach: deleted one in Settings" : nil)
        case "savedStepsRename":
            guard let id = id(object["key"]) else { return (400, Data("{}".utf8), nil) }
            let name = ArisTeachNames.clean(object["name"] as? String ?? "")
            guard !ArisTeachNames.key(name).isEmpty else { return (400, Data("{}".utf8), nil) }
            let stored = access.all()
            guard let procedure = stored.first(where: { $0.id == id }) else { return ok(["renamed": false, "taken": false], audit: nil) }
            let wanted = ArisTeachNames.key(name)
            let taken = stored.contains { $0.id != id && ArisTeachNames.key($0.name) == wanted }
                || access.routineNames().contains { ArisTeachNames.key($0) == wanted }
            guard !taken else { return ok(["renamed": false, "taken": true], audit: nil) }
            let renamed = access.save(procedure.renamed(name, at: Date()))
            return ok(["renamed": renamed, "taken": false], audit: renamed ? "teach: renamed one in Settings" : nil)
        default:
            return earlier()
        }
    }

    /// The procedure a row's key names; nil for any other key.
    static func id(_ key: Any?) -> UUID? {
        guard let key = key as? String, key.hasPrefix(keyPrefix) else { return nil }
        return UUID(uuidString: String(key.dropFirst(keyPrefix.count)))
    }

    /// One row per procedure, the last taught first, in the saved steps' shape (ArisSavedStepsItem in the app). A rename
    /// keeps its row where it was (fifth VM run, M2: a renamed lesson jumped to the top): the order is when each was
    /// first taught, never when it was last changed.
    static func rows(_ procedures: [ArisTeachProcedure]) -> [[String: Any]] {
        procedures.enumerated().sorted { $0.element.created != $1.element.created ? $0.element.created > $1.element.created : $0.offset > $1.offset }
            .map(\.element).map { procedure in
            let apps = Array(NSOrderedSet(array: procedure.steps.map(\.app))).compactMap { $0 as? String }
            return ["key": keyPrefix + procedure.id.uuidString, "request": procedure.name, "saved": ISO8601DateFormatter().string(from: procedure.changed),
                    "outside": false, "taught": true,
                    "steps": procedure.steps.map { ArisTeachCopy.step($0, in: procedure, english: false) },
                    "stepsEn": procedure.steps.map { ArisTeachCopy.step($0, in: procedure, english: true) },
                    "apps": apps.joined(separator: ", ")]
        }
    }

    /// The taught store as it is on this Mac.
    static func live(home: String) -> ArisTaughtAccess {
        let file = ArisTeachStore.file(home: home)
        return ArisTaughtAccess(
            all: { ArisTeachStore.load(file: file) },
            remove: { id in (try? ArisTeachStore.remove(id: id, file: file)) != nil },
            routineNames: { ArisRoutineStore.load(file: ArisRoutineStore.file(home: home)).map(\.name) },
            save: { procedure in (try? ArisTeachStore.save(procedure, file: file)) != nil })
    }

    private static func ok(_ object: [String: Any], audit: String?) -> (status: Int, body: Data, audit: String?) {
        (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8), audit)
    }
}
