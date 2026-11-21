//
//  ArisController+PermissionWait.swift
//  Aris
//
//  A turn that waits on macOS's own permission dialog (a first calendar event, a first to-do) says so in the turn:
//  its step ("캘린더 허용 기다리는 중") and the feature's one line of why under it, until the dialog is answered (VM
//  run 2026-11-19, A2/A3: the reason went to a card that waits for the turn to end, so it was only logged and spoken).
//

import Foundation

extension ArisController {
    /// Shows the wait in the turn; false when no turn is working now (the permission layer puts its card up instead).
    func showPermissionWait(_ key: ArisPermissionKey, reason: String) -> Bool {
        guard session.phase == .thinking, session.question == nil else { return false }
        let step = ArisPermissionNotice.waitingStep(key.permission, english: ArisUIWords.english)
        setSession(session.waitingForPermission(step: step, reason: reason))
        return true
    }

    /// The dialog was answered: the turn goes on without the wait's line.
    func endPermissionWait() {
        guard session.waitingNote != nil else { return }
        setSession(session.permissionAnswered())
    }
}
