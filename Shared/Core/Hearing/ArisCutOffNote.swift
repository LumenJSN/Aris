//
//  ArisCutOffNote.swift
//  Aris (Shared/Core, Foundation only)
//
//  A request sent at a plausible end and then cancelled (the user went on talking) stays in the brain's thread, so the
//  whole question that follows says the half one is not to be answered (ArisController+Endpoint, `cutOffNote`). Only
//  that turn's own requests carry it: the hearing that counted the cancel is kept until another turn listens, and a
//  typed turn never listens, so the count alone would follow the user into every later turn. The note is asked for after
//  the turn took (or cancelled) the early request, so a cancel made by that take counts too.
//

import Foundation

enum ArisCutOffNote {
    /// `cancelled`: requests the hearing cancelled. `hearingTurn`: the turn that hearing listened for. `turn`: the turn
    /// whose request this is.
    static func applies(cancelled: Int, hearingTurn: ArisTurnID?, turn: ArisTurnID?) -> Bool {
        guard cancelled > 0, let hearingTurn else { return false }
        return hearingTurn == turn
    }
}
