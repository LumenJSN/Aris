//
//  ArisAppNames.swift
//  aris-tools
//
//  An app by the name the user says or the Mac shows (QA BUG-13: "텍스트 편집기 2개 켜서 반반으로 나눠 줘" failed with
//  "Unable to find application named '텍스트 편집기'": `open -a` takes the app's file name, not its Korean one). The
//  names said aloud for Apple's apps, then the installed apps' shown (localized) names, read from LaunchServices by
//  aris-tools; any spacing or case. Pure, so the tests run it.
//

import Foundation

enum ArisAppNames {
    /// An installed app: its shown name (localized) and its file name without ".app".
    struct App: Equatable {
        let display: String
        let file: String
    }

    /// Names said aloud (Korean on a Korean Mac, and their usual variants) to the app's file name.
    static let aliases: [String: String] = [
        "텍스트 편집기": "TextEdit", "텍스트 편집": "TextEdit", "미리보기": "Preview", "메모": "Notes", "계산기": "Calculator",
        "캘린더": "Calendar", "달력": "Calendar", "지도": "Maps", "사진": "Photos", "메시지": "Messages", "음악": "Music",
        "미리 알림": "Reminders", "연락처": "Contacts", "시스템 설정": "System Settings", "터미널": "Terminal", "메일": "Mail",
        "단축어": "Shortcuts", "스티커": "Stickies", "파인더": "Finder", "사파리": "Safari",
    ]

    /// How names compare: composed, lowercased, without spaces.
    static func key(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased().filter { !$0.isWhitespace }
    }

    /// `--app` names exactly this app, by its shown or file name: as said, or as what was said resolves (an alias, another
    /// spacing, the other language's name: desk-imp-4, "달력" found Calendar, brought it forward, then failed as "no app
    /// is named exactly 달력"). Never an app whose name only contains it.
    static func isExactly(_ said: String, resolved: String?, localizedName: String?, fileName: String?) -> Bool {
        let names = [localizedName, fileName].compactMap { $0 }.map(key)
        let wanted = [said] + (resolved.map { [$0] } ?? [])
        return wanted.map(key).contains { !$0.isEmpty && names.contains($0) }
    }

    /// The app's file name for `name`: an alias, else an installed app whose shown or file name it is; nil for none.
    static func match(_ name: String, in installed: [App]) -> String? {
        let wanted = key(name)
        guard !wanted.isEmpty else { return nil }
        if let alias = aliases.first(where: { key($0.key) == wanted }) { return alias.value }
        return installed.first { key($0.display) == wanted || key($0.file) == wanted }?.file
    }

    /// What `open -a` is given for `name`: the app's file name when the name is known ("메모" → Notes), else the name as
    /// said (audit tools-9: `app` passed the Korean name on and the app was never found).
    static func openName(_ name: String, in installed: [App]) -> String {
        match(name, in: installed) ?? name
    }
}
