//
//  ArisTrustTable.swift
//  Shared/Core (aris-agent, tests)
//
//  THE TRUST TABLE: the one data file the policy reads (ARCHITECTURE Part 2, Judgment). Each level (careful, standard,
//  free) gives, for each effect class and each provenance, one cell:
//    run              run it
//    runWithUndo      run it, its undo kept in the record
//    runWithUndoSaid  run it with its undo, and say aloud what was done
//    sayThenRun       say it first, a moment (`sayDelay` seconds) to stop it, then run
//    sendIfSpecified  the owner named the recipient and the content: sayThenRun; else readBackThenAsk
//    runIfSpecified   the owner named the recipient and the content: run at once; else readBackThenAsk
//    readBackThenAsk  read the whole action back, run on yes
//    ask              ask first
//    refuse           refuse and tell the owner
//  The never-list is not in the table: it is fixed (ArisNeverList). A grant (ArisStandingGrant) that matches turns a
//  cell of `grants.lifts` into `grants.becomes`, except at the levels in `grants.ignoredAt` and never for content.
//  The user may change cells in Settings (ArisTrustSettings keeps their changes); two rules hold whatever they writes: content
//  never causes an outward action (that cell is always refuse) and never a permanent one (that cell asks at most).
//  Three fixed rules sit on top of the cells, each only ever stricter and none of them Settings' to change (tenth VM
//  run): input put into an app (keys, text, a press, a choice, a command) by a call that is the content's asks, and so
//  does a call with an address content gave (ArisContentReach); a replace whose erased text couldn't be read asks every
//  time; a whole folder removed or moved is refused or asks on its own card (ArisBroadTarget).
//  Pure.
//

import Foundation

enum ArisTrustCell: String, CaseIterable, Codable, Sendable {
    case run, runWithUndo, runWithUndoSaid, sayThenRun, sendIfSpecified, runIfSpecified, readBackThenAsk, ask, refuse
}

struct ArisTrustTable: Equatable, Sendable {
    /// level → effect → provenance column → cell.
    var cells: [ArisTrustLevel: [ArisEffectClass: [ArisCallProvenance.Column: ArisTrustCell]]]
    var sayDelay: TimeInterval
    var grantLifts: Set<ArisTrustCell>
    var grantBecomes: ArisTrustCell
    var grantsIgnoredAt: Set<ArisTrustLevel>

    /// The table as the user set it, 2026-11-18.
    static let defaultJSON = #"""
    {
      "version": 1,
      "sayDelay": 4,
      "grants": {"lifts": ["sayThenRun", "sendIfSpecified", "runIfSpecified", "readBackThenAsk", "ask"], "becomes": "run", "ignoredAt": ["careful"]},
      "levels": {
        "standard": {
          "observe":           {"ownerSaid": "run",             "ownerEarlier": "run",             "ownStep": "run",         "content": "run"},
          "change-reversible": {"ownerSaid": "runWithUndo",     "ownerEarlier": "runWithUndo",     "ownStep": "runWithUndo", "content": "runWithUndoSaid"},
          "change-permanent":  {"ownerSaid": "sayThenRun",      "ownerEarlier": "sayThenRun",      "ownStep": "ask",         "content": "ask"},
          "outward":           {"ownerSaid": "sendIfSpecified", "ownerEarlier": "sendIfSpecified", "ownStep": "ask",         "content": "refuse"}
        },
        "careful": {
          "observe":           {"ownerSaid": "run",             "ownerEarlier": "run",             "ownStep": "run",         "content": "run"},
          "change-reversible": {"ownerSaid": "runWithUndo",     "ownerEarlier": "runWithUndo",     "ownStep": "runWithUndo", "content": "runWithUndoSaid"},
          "change-permanent":  {"ownerSaid": "ask",             "ownerEarlier": "ask",             "ownStep": "ask",         "content": "ask"},
          "outward":           {"ownerSaid": "readBackThenAsk", "ownerEarlier": "readBackThenAsk", "ownStep": "ask",         "content": "refuse"}
        },
        "free": {
          "observe":           {"ownerSaid": "run",             "ownerEarlier": "run",             "ownStep": "run",         "content": "run"},
          "change-reversible": {"ownerSaid": "runWithUndo",     "ownerEarlier": "runWithUndo",     "ownStep": "runWithUndo", "content": "runWithUndoSaid"},
          "change-permanent":  {"ownerSaid": "run",             "ownerEarlier": "run",             "ownStep": "sayThenRun",  "content": "ask"},
          "outward":           {"ownerSaid": "runIfSpecified",  "ownerEarlier": "runIfSpecified",  "ownStep": "ask",         "content": "refuse"}
        }
      }
    }
    """#

    static let standard: ArisTrustTable = parse(Data(defaultJSON.utf8))!

    /// The effects the table has rows for (the never-list is fixed, not a row).
    static let rows: [ArisEffectClass] = [.observe, .changeReversible, .changePermanent, .outward]

    func cell(_ level: ArisTrustLevel, _ effect: ArisEffectClass, _ column: ArisCallProvenance.Column) -> ArisTrustCell {
        guard effect != .never else { return .refuse }
        return cells[level]?[effect]?[column] ?? .ask
    }

    /// Whether a cell may stand where the user put it: content never causes an outward action, nor a permanent one without
    /// the owner's yes.
    static func allowed(_ cell: ArisTrustCell, effect: ArisEffectClass, column: ArisCallProvenance.Column) -> Bool {
        guard column == .content else { return true }
        switch effect {
        case .outward, .never: return cell == .refuse
        case .changePermanent: return [.ask, .readBackThenAsk, .refuse].contains(cell)
        case .observe, .changeReversible: return true
        }
    }

    /// A table read from JSON (the shape of `defaultJSON`); nil when it is malformed, misses a cell, or breaks the
    /// content rule anywhere.
    static func parse(_ data: Data) -> ArisTrustTable? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let levels = object["levels"] as? [String: Any] else { return nil }
        var cells: [ArisTrustLevel: [ArisEffectClass: [ArisCallProvenance.Column: ArisTrustCell]]] = [:]
        for level in ArisTrustLevel.allCases {
            guard let rows = levels[level.rawValue] as? [String: Any] else { return nil }
            for effect in Self.rows {
                guard let row = rows[effect.rawValue] as? [String: String] else { return nil }
                for column in ArisCallProvenance.Column.allCases {
                    guard let raw = row[column.rawValue], let cell = ArisTrustCell(rawValue: raw), allowed(cell, effect: effect, column: column) else { return nil }
                    cells[level, default: [:]][effect, default: [:]][column] = cell
                }
            }
        }
        let grants = object["grants"] as? [String: Any] ?? [:]
        let lifts = Set((grants["lifts"] as? [String] ?? []).compactMap(ArisTrustCell.init(rawValue:)))
        let becomes = (grants["becomes"] as? String).flatMap(ArisTrustCell.init(rawValue:)) ?? .run
        let ignored = Set((grants["ignoredAt"] as? [String] ?? []).compactMap(ArisTrustLevel.init(rawValue:)))
        let delay = (object["sayDelay"] as? NSNumber)?.doubleValue ?? 4
        guard (0...30).contains(delay), [.run, .runWithUndo, .sayThenRun].contains(becomes) else { return nil }
        return ArisTrustTable(cells: cells, sayDelay: delay, grantLifts: lifts, grantBecomes: becomes, grantsIgnoredAt: ignored)
    }

    /// The user's changes on top: `[level: [effect: [column: cell]]]` as Settings stores them. A change the content rule
    /// forbids, or that names no real level, effect, column or cell, is dropped (the rest still applies).
    func changed(by overrides: [String: [String: [String: String]]]) -> ArisTrustTable {
        var table = self
        for (levelName, rows) in overrides {
            guard let level = ArisTrustLevel(rawValue: levelName) else { continue }
            for (effectName, row) in rows {
                guard let effect = ArisEffectClass(rawValue: effectName), Self.rows.contains(effect) else { continue }
                for (columnName, cellName) in row {
                    guard let column = ArisCallProvenance.Column(rawValue: columnName), let cell = ArisTrustCell(rawValue: cellName),
                          Self.allowed(cell, effect: effect, column: column) else { continue }
                    table.cells[level, default: [:]][effect, default: [:]][column] = cell
                }
            }
        }
        return table
    }
}
