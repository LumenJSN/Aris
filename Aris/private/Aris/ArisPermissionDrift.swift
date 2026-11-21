//
//  ArisPermissionDrift.swift
//  Aris
//
//  An update can drop macOS permissions (a new signature, a moved app): nothing used to say so, and features just
//  stopped. At launch the permissions the enabled features need are compared with what was granted at the last
//  launch; one that was on then and is off now is said once, on the notice pill, with the button to its list in
//  System Settings (the fixes path every problem card uses). Foundation only (tested); ArisPermissionDriftLive reads
//  macOS and posts.
//

import Foundation

enum ArisPermissionDrift {
    /// What was granted at the last launch (the panes' raw values).
    static let lastGrantedKey = "arisGrantedPermissions"
    static let noticeKey = "permission-drift"

    /// The lists the features that are on need: hearing (microphone, speech recognition), the key taps (Input
    /// Monitoring), the app's own key handling (Accessibility), and the screen when Aris may look at it.
    static func needed(seesScreen: Bool) -> [ArisFix.Pane] {
        [.microphone, .speech, .accessibility, .listen] + (seesScreen ? [.screen] : [])
    }

    /// The needed lists that were granted at the last launch and are not now. No record from before (the first launch
    /// with this check): nothing is said, only recorded.
    static func lost(needed: [ArisFix.Pane], granted: Set<ArisFix.Pane>, before: [String]?) -> [ArisFix.Pane] {
        guard let before else { return [] }
        let had = Set(before)
        return needed.filter { had.contains($0.rawValue) && !granted.contains($0) }
    }

    /// What is kept for the next launch.
    static func record(_ granted: Set<ArisFix.Pane>) -> [String] { granted.map(\.rawValue).sorted() }

    /// The one card: which lists went off, and a button that opens each in turn.
    static func notice(lost: [ArisFix.Pane], english: Bool) -> ArisNotice? {
        guard let first = lost.first else { return nil }
        let names = lost.map { $0.permission(english: english) }.joined(separator: english ? ", " : ", ")
        let title = english ? "A permission was turned off" : "권한이 꺼졌어요"
        let body = english ? "macOS turned off \(names) for Aris, likely with the update. Turn it back on in System Settings."
            : "업데이트하면서 macOS가 Aris의 \(names) 권한을 껐어요. 시스템 설정에서 다시 켜 주세요."
        let fixes = lost.map(ArisFix.pane)
        return ArisNotice(key: noticeKey, kind: .problem, title: title, body: body,
                          actions: [ArisNoticeAction(title: ArisFixWords.title(.pane(first), english: english), primary: true, role: .fixes(fixes))])
    }
}
