//
//  ArisWakeDown.swift
//  Aris
//
//  The wake word's microphone that won't work (2026-11-18 audit: after its third failed check it stayed closed until
//  Aris was relaunched, and nobody was told). It now keeps trying, at most ten minutes apart (ArisWakeArm.pause), starts
//  again from its shortest pause on the events that usually fix it (a route change, the Mac waking, the permission
//  given, another app letting the microphone go), and once it has been down for two minutes the user is told, once,
//  on the notice pill. Pure (tested).
//

import Foundation

struct ArisWakeDown: Equatable {
    /// Down this long (seconds) before the user is told.
    static let tellAfter: Double = 120

    /// When the microphone first failed in this run of failures (uptime seconds); nil while it works.
    private(set) var since: Double?
    /// The user was told about this run of failures.
    private(set) var told = false

    var isDown: Bool { since != nil }

    /// An open or a check failed at `now`.
    mutating func failed(at now: Double) {
        if since == nil { since = now }
    }

    /// The microphone opened and a check listened: the next failure is a new run, told again if it lasts.
    mutating func worked() {
        since = nil
        told = false
    }

    /// True once per run of failures, when it has lasted `tellAfter`.
    mutating func shouldTell(at now: Double) -> Bool {
        guard let since, !told, now - since >= Self.tellAfter else { return false }
        told = true
        return true
    }

    /// The notice's words.
    static func title(english: Bool) -> String {
        ArisUIWords.text("이름을 불러도 못 듣고 있어요", "Aris can't hear its name right now", english: english)
    }

    static func body(english: Bool) -> String {
        ArisUIWords.text("마이크를 열지 못하고 있어요. 계속 다시 시도할게요. 말하기 단축키로는 그대로 부를 수 있어요.",
                         "The microphone won't open for the wake word. Aris keeps trying; the talk shortcut still works.", english: english)
    }
}
