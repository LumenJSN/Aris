//
//  ArisPermissionNotice.swift
//  Aris
//
//  The card under the notch for a permission decision (ArisPermissions.require), made of the existing notice:
//  before macOS asks, the feature's one sentence of why; when it is off, that sentence and one button to its pane;
//  when a switch is on but needs Aris reopened, one button for that. One card per permission (its key), so a second
//  ask replaces the first instead of piling up. Pure.
//

import Foundation

enum ArisPermissionNotice {
    static func key(_ key: ArisPermissionKey) -> String { "permission:\(key)" }

    /// The reopen card's body, under the permission's name.
    static let relaunchBody = (korean: "켜졌어요. Aris를 다시 열면 바로 써요.", english: "It's on. Reopen Aris to use it.")

    /// How long a card that only says why stays up (macOS's own dialog is the thing to answer).
    static let reasonShowsFor: TimeInterval = 8
    /// The relaunch offer goes by itself too (fourteenth VM run: "Input Monitoring · Reopen Aris" stayed under the closed
    /// notch for an hour); the Reopen button stays in Settings › Permissions.
    static let relaunchShowsFor: TimeInterval = 30

    /// The permission's name as System Settings shows it on this macOS where Aris knows the list's name.
    static func title(_ permission: ArisPermission, english: Bool) -> String {
        switch permission {
        case .accessibility: ArisFix.Pane.accessibility.title(english: english)
        case .screenRecording: ArisFix.Pane.screen.title(english: english)
        default: permission.title(english: english)
        }
    }

    /// The card a reading's change takes down: the permission's own (its "it is off" card, or the reason card left
    /// over from the ask) once it is on. A stale "Calendars is off" stayed up after the switch was on and caught clicks
    /// on the notch (VM run 2026-11-19, A2).
    static func withdrawn(by change: ArisPermissionChange) -> String? {
        if case .granted(let permission) = change { return key(permission) }
        return nil
    }

    /// The turn's step while macOS's own dialog for `permission` is up (the turn waits for the answer).
    static func waitingStep(_ permission: ArisPermission, english: Bool) -> String {
        let name = title(permission, english: english)
        return ArisUIWords.text("\(name) 허용 기다리는 중", "Waiting for \(name) access", english: english)
    }

    /// The card for `decision`; nil for one that goes ahead with nothing to say.
    static func notice(for decision: ArisPermissionDecision, english: Bool) -> ArisNotice? {
        switch decision {
        case .proceed, .doWithout:
            return nil
        case .prompt(let key, let reason), .openPane(let key, _, let reason), .proceedAfterSaying(let key, let reason):
            return ArisNotice(key: Self.key(key), kind: .system, title: title(key.permission, english: english), body: reason,
                              showsFor: reasonShowsFor)
        case .tellOff(let key, _, let reason):
            let off = ArisUIWords.text("\(ArisJosa.attach(title(key.permission, english: false), "이", "가")) 꺼져 있어요.",
                                       "\(title(key.permission, english: true)) is off.", english: english)
            let open = ArisUIWords.text("설정 열기", "Open Settings", english: english)
            return ArisNotice(key: Self.key(key), kind: .problem, title: off, body: reason,
                              actions: [ArisNoticeAction(title: open, primary: true, role: .permissionPane(key.permission))])
        case .offerRelaunch(let key):
            // The title names the permission, so the body doesn't again: under the closed notch the pill shows title and
            // body on one line, and it is read whole (ArisNoticePillFit.readWhole). Fourth VM run: "Input Monitoring
            // Input Monitoring is on. R…" until it was clicked.
            let name = title(key.permission, english: english)
            let body = ArisUIWords.text(relaunchBody.korean, relaunchBody.english, english: english)
            let reopen = ArisUIWords.text("다시 열기", "Reopen", english: english)
            return ArisNotice(key: Self.key(key), kind: .system, title: name, body: body,
                              actions: [ArisNoticeAction(title: reopen, primary: true, role: .relaunchApp)], showsFor: relaunchShowsFor)
        }
    }
}
