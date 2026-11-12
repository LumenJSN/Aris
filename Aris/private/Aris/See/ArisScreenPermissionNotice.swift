//
//  ArisScreenPermissionNotice.swift
//  Aris
//
//  The Screen Recording lines (plan D2, permission flow steps 3–5), shared by the circle gesture and the per-turn
//  screenshot so the user sees each at most once per launch, whichever path asks first:
//  - "화면을 보려면 화면 기록 권한이 필요해요" with 허용하기, which opens the guide (the only place Aris asks macOS);
//  - once the guide has been opened this launch and the grant still reads false (macOS needs a relaunch for it),
//    "Aris를 다시 열면 화면을 볼 수 있어요" with 다시 열기.
//  Pure, so the tests run it.
//

import Foundation

@MainActor
enum ArisScreenPermissionNotice {
    enum Line: Equatable {
        case permission, relaunch

        var text: String {
            switch self {
            case .permission: ArisScreenPermissionNotice.text
            case .relaunch: ArisUIWords.text("Aris를 다시 열면 화면을 볼 수 있어요", "Reopen Aris and I can see the screen")
            }
        }

        var action: String {
            switch self {
            case .permission: ArisScreenPermissionNotice.action
            case .relaunch: ArisUIWords.text("다시 열기", "Reopen")
            }
        }
    }

    nonisolated static var text: String { ArisUIWords.text("화면을 보려면 화면 기록 권한이 필요해요", "I need Screen Recording to see the screen") }
    nonisolated static var action: String { ArisUIWords.text("허용하기", "Allow") }

    private static var shownPermission = false
    private static var shownRelaunch = false
    private static var openedGuide = false

    /// The user opened the Screen Recording guide this launch.
    static func guideOpened() {
        openedGuide = true
    }

    /// The line to show now that a turn or a circle found no grant, or nil (each shows once per launch).
    static func next() -> Line? {
        if openedGuide {
            guard !shownRelaunch else { return nil }
            shownRelaunch = true
            return .relaunch
        }
        guard !shownPermission else { return nil }
        shownPermission = true
        return .permission
    }
}
