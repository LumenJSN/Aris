//
//  ArisSettingsPath.swift
//  Aris
//
//  A place in Aris's settings as the settings window names it on this Mac (VM run, bug 4: replies pointed to
//  "Settings › 할 일" while the English window's sidebar said "To-dos"). Since option A the pages are four, and an old
//  page's name in a reply reads as the page that has its rows. The window's sidebar is English whenever the
//  UI is (ArisSettingsCopy), and a page's rows are English once that page is translated, so the names are read from
//  the same catalog the window reads: "설정 › 할 일 · 캘린더 › 미리 알림 접근" on a Korean Mac, "Settings › To-dos ·
//  Calendar › Reminders access" on an English one. The sentence around the
//  path is in the language of the request; the path is in the window's. Foundation only (tested).
//

import Foundation

enum ArisSettingsPath {
    /// "설정 › 앱 › 권한 › 미리 알림 접근", "Settings › To-dos …": the page, and a row by its Korean name with the part it
    /// is in (option A's pages are long: the part says where on the page). A row the index knows is named on the page
    /// that has it now, whatever page was asked for.
    static func path(_ page: ArisSettingsPage, _ row: String? = nil, english: Bool = ArisUIWords.english) -> String {
        let entry = row.flatMap { title in ArisSettingsIndex.entries.first { $0.title == title || $0.formerly.contains(title) } }
        let shown = entry?.page ?? page
        var parts = [ArisUIWords.text("설정", "Settings", english: english), pageName(shown, english: english)]
        if let part = entry?.part.title { parts.append(english ? ArisSettingsCopy.t(part) : part) }
        if let row { parts.append(english && ArisSettingsCopy.translatedPages.contains(shown) ? ArisSettingsCopy.t(entry?.title ?? row) : (entry?.title ?? row)) }
        return parts.joined(separator: " › ")
    }

    /// The page as the sidebar names it.
    static func pageName(_ page: ArisSettingsPage, english: Bool = ArisUIWords.english) -> String {
        english ? ArisSettingsCopy.t(page.title) : page.title
    }

    /// What pages were called before the four pages of option A (the 14 pages, and before those 노치 기능, 캘린더 and 할
    /// 일): a reply that still says one is pointed at the page that took its rows.
    static let former: [(title: String, page: ArisSettingsPage, part: String?)] = ArisSettingsFormerPage.allCases.map { ($0.title, $0.page, $0.part) }
        + [("노치 기능", .features, "look.music"), ("캘린더", .todo, "able.calendar"), ("할 일", .todo, "able.todo")]

    /// A former page named as its page and the part that took most of its rows ("Aris와 말하기 › AI · 모델").
    static func formerName(page: ArisSettingsPage, part: String?, english: Bool) -> String {
        guard let title = part.flatMap(ArisSettingsParts.part)?.title else { return pageName(page, english: english) }
        return pageName(page, english: english) + " › " + (english ? ArisSettingsCopy.t(title) : title)
    }

    /// Where the AI that answers and its key are set, as the window names it now: "설정 › Aris와 말하기 › AI · 모델",
    /// read from the part's own title (tenth VM run, item 12: the setup still said "Settings › AI services", a page
    /// the window no longer has).
    static func aiPage(english: Bool = ArisUIWords.english) -> String {
        let former = ArisSettingsFormerPage.ai
        let named = formerName(page: former.page, part: former.part, english: english)
        // Where the window's English can't be read (no compiled catalogue), its own English as last written; the tests
        // hold this equal to the catalogue's.
        let shown = english && named.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) ? aiPageEnglish : named
        return ArisUIWords.text("설정", "Settings", english: english) + " › " + shown
    }
    static let aiPageEnglish = "Talking to Aris › AI · Model"

    /// A reply with its settings paths named as the window names them: on an English Mac "설정 › 할 일" and
    /// "Settings > 할 일" (the agent and the AI write the pages' Korean names) read "Settings › To-dos · Calendar", and on
    /// either Mac a page's former name reads as the page that has its rows now ("설정 › 캘린더" → "설정 › 할 일 · 캘린더").
    /// Nothing else changes on a Korean Mac, or in a reply that names no page.
    static func shown(_ text: String, english: Bool = ArisUIWords.english) -> String {
        guard text.contains("설정") || text.contains("Settings") else { return text }
        var out = text
        // The longest name first, so "노치 · 사이드 노치" isn't taken for a shorter page's.
        // A former page's English name too ("Settings › AI services"), for replies written in English.
        let englishFormer = former.compactMap { item in ArisSettingsCopy.english(item.title).flatMap { $0 == item.title ? nil : (title: $0, page: item.page, part: item.part) } }
        let names = (ArisSettingsPage.allCases.map { (title: $0.title, page: $0, part: String?.none) } + former + englishFormer).sorted { $0.title.count > $1.title.count }
        for (title, page, part) in names {
            let named = part == nil ? pageName(page, english: english) : formerName(page: page, part: part, english: english)
            guard named != title else { continue }
            // Not the start of a longer name ("할 일" in "할 일 · 캘린더").
            let pattern = "(?:설정|Settings)(?:의)?\\s*[›>→]\\s*" + NSRegularExpression.escapedPattern(for: title) + "(?!\\s*·)"
            let lead = ArisUIWords.text("설정", "Settings", english: english)
            out = out.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: lead + " › " + named), options: .regularExpression)
        }
        return out
    }
}
