//
//  ArisSettingsPath.swift
//  Aris
//
//  A place in Aris's settings as the settings window names it on this Mac (VM run, bug 4: replies pointed to
//  "Settings › 할 일" while the English window's sidebar said "To-dos"). The window's sidebar is English whenever the
//  UI is (ArisSettingsCopy), and a page's rows are English once that page is translated, so the names are read from
//  the same catalog the window reads: "설정 › 할 일 · 캘린더 › 미리 알림 접근" on a Korean Mac, "Settings › To-dos ·
//  Calendar › Reminders access" on an English one. The sentence around the
//  path is in the language of the request; the path is in the window's. Foundation only (tested).
//

import Foundation

enum ArisSettingsPath {
    /// "설정 › 할 일", "Settings › To-dos › …": the page, and a row on it by its Korean name.
    static func path(_ page: ArisSettingsPage, _ row: String? = nil, english: Bool = ArisUIWords.english) -> String {
        var parts = [ArisUIWords.text("설정", "Settings", english: english), pageName(page, english: english)]
        if let row { parts.append(english && ArisSettingsCopy.translatedPages.contains(page) ? ArisSettingsCopy.t(row) : row) }
        return parts.joined(separator: " › ")
    }

    /// The page as the sidebar names it.
    static func pageName(_ page: ArisSettingsPage, english: Bool = ArisUIWords.english) -> String {
        english ? ArisSettingsCopy.t(page.title) : page.title
    }

    /// What pages were called before the sidebar became 14 pages (할 일 and 캘린더 merged, 모양 moved into 일반, 노치 기능
    /// renamed): a reply that still says one is pointed at the page that took its rows.
    static let former: [(title: String, page: ArisSettingsPage)] = [("노치 기능", .features), ("캘린더", .todo), ("할 일", .todo), ("모양", .general)]

    /// A reply with its settings paths named as the window names them: on an English Mac "설정 › 할 일" and
    /// "Settings > 할 일" (the agent and the AI write the pages' Korean names) read "Settings › To-dos · Calendar", and on
    /// either Mac a page's former name reads as the page that has its rows now ("설정 › 캘린더" → "설정 › 할 일 · 캘린더").
    /// Nothing else changes on a Korean Mac, or in a reply that names no page.
    static func shown(_ text: String, english: Bool = ArisUIWords.english) -> String {
        guard text.contains("설정") || text.contains("Settings") else { return text }
        var out = text
        // The longest name first, so "노치 · 사이드 노치" isn't taken for a shorter page's.
        let names = (ArisSettingsPage.allCases.map { (title: $0.title, page: $0) } + former).sorted { $0.title.count > $1.title.count }
        for (title, page) in names {
            let named = pageName(page, english: english)
            guard named != title else { continue }
            // Not the start of a longer name ("할 일" in "할 일 · 캘린더").
            let pattern = "(?:설정|Settings)(?:의)?\\s*[›>→]\\s*" + NSRegularExpression.escapedPattern(for: title) + "(?!\\s*·)"
            let lead = ArisUIWords.text("설정", "Settings", english: english)
            out = out.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: lead + " › " + named), options: .regularExpression)
        }
        return out
    }
}
