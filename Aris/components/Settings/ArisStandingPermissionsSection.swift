//
//  ArisStandingPermissionsSection.swift
//  Aris
//
//  컴퓨터 제어 → 묻지 않고 하는 일: how a standing permission aris-agent learned (three yeses in a row, then "앞으로
//  이건 그냥 할까?" → 응) is named on its row. The rows, each with 취소, are the page's (ArisSettingsBuilder).
//

import Foundation

enum ArisStandingPermissionText {
    private static let titles = ["message": "메시지 보내기", "trash": "휴지통으로 옮기기", "remind": "미리 알림", "note": "메모",
                                 "event": "일정 추가", "notion-calendar-create-events": "Notion 일정 만들기",
                                 "notion-calendar-update-events": "Notion 일정 바꾸기", "notion-create-pages": "Notion 페이지 만들기",
                                 "notion-update-page": "Notion 페이지 고치기", "notion-create-comment": "Notion 댓글"]

    /// The kind's name, with any folded switch after it ("Notion 일정 만들기 (+notify)").
    static func title(_ permission: ArisStandingPermission) -> String {
        let parts = permission.kind.components(separatedBy: "+")
        let base = titles[parts[0]] ?? parts[0]
        return parts.count > 1 ? "\(base) (+\(parts.dropFirst().joined(separator: ", +")))" : base
    }

    /// The target in full (it is what the permission covers), then where it goes through.
    static func desc(_ permission: ArisStandingPermission) -> String {
        "대상: \(permission.target)" + (permission.app.isEmpty ? "" : " · \(permission.app)")
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "message": return "message"
        case "trash": return "trash"
        case _ where kind.hasPrefix("notion-calendar"): return "calendar"
        case _ where kind.hasPrefix("notion-"): return "doc.text"
        default: return "checkmark.shield"
        }
    }
}
