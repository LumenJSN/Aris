//
//  ArisController+Continuity.swift
//  Aris
//
//  The one check every way into a turn makes (the talk key, the wake word, a typed request): past the 대화 이어가기
//  setting since the last answer, the conversation ends and the turn starts a new one; otherwise it carries on with
//  its thread and recent turns (ArisContinuity has the whole rule).
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    func endConversationIfLongAgo() {
        let gap = lastTurnAt.map { Double((ContinuousClock.now - $0).components.seconds) }
        guard let why = ArisContinuity.startsFresh(secondsSinceLastAnswer: gap, windowMinutes: Defaults[.arisConversationMinutes]) else { return }
        log.notice("a new conversation (\(why.rawValue, privacy: .public))")
        endConversation()
    }
}
