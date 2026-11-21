//
//  ArisTrustSettings.swift
//  aris-agent
//
//  The owner's trust settings, data only (no UI in this branch): the one "how much Aris asks" level, the standing
//  grants, and his changes to the table's cells. Kept with the helper's other settings, ~/.config/aris/aris/trust.json
//  (0600 in a 0700 folder, ArisPrivateFile; a file that is a link or open to others counts for nothing). No capability
//  can reach it (the never-list holds Aris's folder and every `trust.` capability); the owner changes it by his own
//  words (ArisGrantLearning, through ArisTrustGate) or through POST /trust from the Aris app itself:
//    {"op": "list"}                                        -> {"level", "levels", "grants": [...], "table": {...}, "cells": [...]}
//    {"op": "level", "level": "careful"|"standard"|"free"}  -> the list
//    {"op": "add", "grant": {"capability"?, "effect"?, "target"?: {"kind", "pattern", "addresses"?}, "expires"?: seconds}}
//                                                          -> the list (400 for a grant that isn't well formed or safe)
//    {"op": "remove", "id": "<uuid>"}                      -> the list (404 for no such grant)
//    {"op": "cell", "level", "effect", "provenance", "cell"} -> the list (400 when the content rule forbids it)
//

import Foundation

struct ArisTrustSettings: Equatable, Codable {
    var level: ArisTrustLevel = .standard
    var grants: [ArisStandingGrant] = []
    /// level → effect → provenance → cell (ArisTrustTable.changed).
    var cells: [String: [String: [String: String]]] = [:]

    static func file(home: String) -> URL { ArisPrivateFile.folder(home: home).appendingPathComponent("trust.json") }

    /// The settings; the defaults when the file is missing, damaged, a link or open to others. Grants that aren't well
    /// formed or safe, or that have expired, are dropped.
    static func load(home: String, now: Date = Date()) -> ArisTrustSettings {
        guard let data = ArisPrivateFile.read(file(home: home)), var settings = try? ArisPrivateFile.decoder.decode(ArisTrustSettings.self, from: data) else {
            return ArisTrustSettings()
        }
        settings.grants = settings.grants.filter { $0.isWellFormed && $0.isSafe(home: home) && ($0.expires.map { $0 > now } ?? true) }
        return settings
    }

    func save(home: String) throws {
        try ArisPrivateFile.withLock(Self.file(home: home)) {
            try ArisPrivateFile.write(try ArisPrivateFile.encoder.encode(self), to: Self.file(home: home))
        }
    }

    var table: ArisTrustTable { ArisTrustTable.standard.changed(by: cells) }

    func context(home: String, now: Date = Date()) -> ArisTrustPolicy.Context {
        ArisTrustPolicy.Context(level: level, grants: grants, table: table, home: home, now: now)
    }

    /// The settings after one of the owner's sentences changed a grant.
    func applying(_ change: ArisGrantChange, home: String) -> ArisTrustSettings {
        var next = self
        next.grants = ArisGrantLearning.applied(change, to: grants, home: home).filter { $0.isSafe(home: home) }
        return next
    }
}

enum ArisTrustRoute {
    struct Reply: Equatable {
        let status: Int
        let body: Data
    }

    static func handle(_ object: [String: Any], home: String, now: Date = Date(), audit: (String) -> Void = { _ in }) -> Reply {
        var settings = ArisTrustSettings.load(home: home, now: now)
        let op = object["op"] as? String ?? ""
        switch op {
        case "list":
            return listing(settings)
        case "level":
            guard let level = (object["level"] as? String).flatMap(ArisTrustLevel.init(rawValue:)) else { return refuse(400, op, audit) }
            settings.level = level
        case "add":
            guard let grant = grant(from: object["grant"], now: now), grant.isWellFormed, grant.isSafe(home: home) else { return refuse(400, op, audit) }
            settings.grants.append(grant)
        case "remove":
            guard let id = (object["id"] as? String).flatMap(UUID.init(uuidString:)), settings.grants.contains(where: { $0.id == id }) else {
                return refuse(404, op, audit)
            }
            settings.grants.removeAll { $0.id == id }
        case "cell":
            guard let level = (object["level"] as? String).flatMap(ArisTrustLevel.init(rawValue:)),
                  let effect = (object["effect"] as? String).flatMap(ArisEffectClass.init(rawValue:)), ArisTrustTable.rows.contains(effect),
                  let column = (object["provenance"] as? String).flatMap(ArisCallProvenance.Column.init(rawValue:)),
                  let cell = (object["cell"] as? String).flatMap(ArisTrustCell.init(rawValue:)),
                  ArisTrustTable.allowed(cell, effect: effect, column: column) else { return refuse(400, op, audit) }
            settings.cells[level.rawValue, default: [:]][effect.rawValue, default: [:]][column.rawValue] = cell.rawValue
        default:
            return refuse(400, String(op.prefix(32)), audit)
        }
        do { try settings.save(home: home) } catch { return Reply(status: 500, body: Data(#"{"error":"couldn't save"}"#.utf8)) }
        audit(line(["trust": op, "level": settings.level.rawValue, "grants": String(settings.grants.count)]))
        return listing(settings)
    }

    static func grant(from value: Any?, now: Date) -> ArisStandingGrant? {
        guard let object = value as? [String: Any] else { return nil }
        let capability = object["capability"] as? String
        let effect = (object["effect"] as? String).flatMap(ArisEffectClass.init(rawValue:))
        if object["effect"] != nil && effect == nil { return nil }
        var target: ArisStandingGrant.Target?
        if let raw = object["target"] as? [String: Any] {
            guard let kind = (raw["kind"] as? String).flatMap(ArisKeyArgument.Kind.init(rawValue:)), let pattern = raw["pattern"] as? String else { return nil }
            target = .init(kind: kind, pattern: pattern, addresses: (raw["addresses"] as? [String] ?? []).filter { $0.count <= 200 }.prefix(10).map { $0 })
        }
        let expires = (object["expires"] as? NSNumber).map { now.addingTimeInterval(min(max($0.doubleValue, 60), 365 * 86_400)) }
        return ArisStandingGrant(capability: capability, effect: effect, target: target, expires: expires, created: now, words: "설정에서 추가")
    }

    static func listing(_ settings: ArisTrustSettings) -> Reply {
        let formatter = ISO8601DateFormatter()
        let grants: [[String: Any]] = settings.grants.map { grant in
            var row: [String: Any] = ["id": grant.id.uuidString, "created": formatter.string(from: grant.created)]
            if let capability = grant.capability { row["capability"] = capability }
            if let effect = grant.effect { row["effect"] = effect.rawValue }
            if let target = grant.target { row["target"] = ["kind": target.kind.rawValue, "pattern": target.pattern, "addresses": target.addresses] }
            if let expires = grant.expires { row["expires"] = formatter.string(from: expires) }
            if let words = grant.words { row["words"] = words }
            return row
        }
        let table = settings.table
        var cells: [String: Any] = [:]
        for level in ArisTrustLevel.allCases {
            var rows: [String: Any] = [:]
            for effect in ArisTrustTable.rows {
                rows[effect.rawValue] = Dictionary(uniqueKeysWithValues: ArisCallProvenance.Column.allCases.map { ($0.rawValue, table.cell(level, effect, $0).rawValue) })
            }
            cells[level.rawValue] = rows
        }
        let body: [String: Any] = ["level": settings.level.rawValue, "levels": ArisTrustLevel.allCases.map(\.rawValue), "grants": grants,
                                   "table": cells, "cells": ArisTrustCell.allCases.map(\.rawValue)]
        return Reply(status: 200, body: (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8))
    }

    private static func refuse(_ status: Int, _ op: String, _ audit: (String) -> Void) -> Reply {
        audit(line(["trust": op, "answer": "refused"]))
        return Reply(status: status, body: Data("{}".utf8))
    }

    private static func line(_ fields: [String: String]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }
}
