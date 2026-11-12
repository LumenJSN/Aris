//
//  ArisAskAdmission.swift
//  aris-agent
//
//  Whether a POST /ask may still start its turn once its images are decoded off the server queue: only while the
//  connection is still ready and the app hasn't closed it meanwhile. A turn that isn't admitted touches nothing (no
//  conversation flags, no fresh start, no brain).
//

import Foundation
import Network

enum ArisAskAdmission {
    static func proceeds(state: NWConnection.State, cancelled: Bool) -> Bool {
        guard !cancelled, case .ready = state else { return false }
        return true
    }
}

/// A flag set from one queue and read from another (the close handler sets it; handleAsk reads it).
final class ArisCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
