//
//  ArisDesktopHoldPlan.swift
//  aris-tools
//
//  What `window …` asks the agent before it moves a window (ArisDesktopHold): inside a brain's turn, that turn's turn
//  at the keys and pointer (its credential); in the agent's own work that already holds them (a learned shortcut's
//  replay, a window arrangement: the agent passes the id it holds them as), the agent's word that it does. Anything
//  else, a cleared environment or a terminal, fails closed: nothing is moved (security review 10, L8). Pure (tested).
//

import Foundation

enum ArisDesktopHoldPlan: Equatable {
    /// Ask with this turn's credential.
    case turn(String)
    /// Ask the agent to confirm it holds the keys and pointer as this id.
    case held(String)
    /// Nothing is asked and nothing is moved, for this reason.
    case refuse(String)

    /// The environment key the agent's own work passes its lock id in (ArisDesktopLock.heldKey: the same name).
    static let heldKey = "ARIS_DESKTOP_HELD"

    static let noTurnLine = "aris-tools window moves a window only inside an Aris turn or Aris's own replay, and none was found, so nothing was moved."

    static func plan(environment: [String: String], read: (String) -> String?) -> ArisDesktopHoldPlan {
        if let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = read(path), !turn.isEmpty { return .turn(turn) }
        if let held = environment[heldKey], isHeldId(held) { return .held(held) }
        return .refuse(noTurnLine)
    }

    /// The shape of the agent's own one-off lock ids (ArisDesktopLock.oneOff): "shortcut:" or "arrange:" and a UUID.
    static func isHeldId(_ id: String) -> Bool {
        guard let colon = id.firstIndex(of: ":") else { return false }
        return ["shortcut", "arrange"].contains(String(id[..<colon])) && UUID(uuidString: String(id[id.index(after: colon)...])) != nil
    }
}
