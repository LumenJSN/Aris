//
//  ArisOverlayCensus.swift
//  Aris
//
//  Every full-screen overlay a turn puts up (the ink, the window-pick surfaces) while it is up, so whatever ends the
//  turn (Esc, a timeout, an error, the turn's end) can put away anything left (QA BUG-44: after an Esc, pick surfaces on
//  three displays and an ink panel stayed on screen over every app).
//

import Foundation

@MainActor
enum ArisOverlayCensus {
    private static var open: [ObjectIdentifier: () -> Void] = [:]

    /// An overlay went up; `close` puts it away.
    static func shown(_ owner: AnyObject, close: @escaping () -> Void) {
        open[ObjectIdentifier(owner)] = close
    }

    /// It was put away.
    static func closed(_ owner: AnyObject) {
        open[ObjectIdentifier(owner)] = nil
    }

    static var count: Int { open.count }

    /// Puts away every overlay still up; how many there were.
    @discardableResult
    static func closeAll() -> Int {
        let left = open
        open = [:]
        left.values.forEach { $0() }
        return left.count
    }
}
