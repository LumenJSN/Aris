//
//  ArisNotchPresence.swift
//  Aris
//
//  Whether any notch is open right now, recorded by ArisNotchModel's open/close, so a turn can tell (before it
//  starts listening) whether the open notch shows the previous answer (plan D3 focus). Pure, so the tests run it.
//

import Foundation

final class ArisNotchPresence: @unchecked Sendable {
    static let shared = ArisNotchPresence()

    private let lock = NSLock()
    private var open: Set<ObjectIdentifier> = []

    func set(open isOpen: Bool, for notch: AnyObject) {
        lock.withLock {
            if isOpen { open.insert(ObjectIdentifier(notch)) } else { open.remove(ObjectIdentifier(notch)) }
        }
    }

    var isOpen: Bool { lock.withLock { !open.isEmpty } }
}
