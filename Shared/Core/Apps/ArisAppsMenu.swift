//
//  ArisAppsMenu.swift
//  Shared/Core/Apps
//
//  An app's menu bar as data: every item with its path, whether it is enabled, its checkmark and its key equivalent,
//  as Accessibility reads it (AXMenuBar → AXMenuBarItem → AXMenu → AXMenuItem…). Every Mac app has one, so this is the
//  channel that reaches any app, and pressing an item by Accessibility works while the app stays in the background.
//  The tests use recorded trees in this shape (JSON). Pure.
//

import Foundation

extension ArisApps {
    struct MenuItem: Codable, Equatable, Sendable {
        var title: String
        var enabled: Bool = true
        /// A checkmark (or a mixed mark) beside it.
        var checked: Bool = false
        /// The key equivalent's character ("N", "s", a function-key glyph), when it has one.
        var key: String? = nil
        /// AXMenuItemCmdModifiers: 0 is ⌘ alone; +1 ⇧, +2 ⌥, +4 ⌃, +8 no ⌘.
        var modifiers: Int? = nil
        var items: [MenuItem]? = nil

        init(title: String, enabled: Bool = true, checked: Bool = false, key: String? = nil, modifiers: Int? = nil, items: [MenuItem]? = nil) {
            self.title = title
            self.enabled = enabled
            self.checked = checked
            self.key = key
            self.modifiers = modifiers
            self.items = items
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
            key = try container.decodeIfPresent(String.self, forKey: .key)
            modifiers = try container.decodeIfPresent(Int.self, forKey: .modifiers)
            items = try container.decodeIfPresent([MenuItem].self, forKey: .items)
        }

        /// The key equivalent as people write it ("⌘⇧N"), nil without one.
        var shortcut: String? {
            guard let key, !key.isEmpty else { return nil }
            let flags = modifiers ?? 0
            var text = ""
            if flags & 4 != 0 { text += "⌃" }
            if flags & 2 != 0 { text += "⌥" }
            if flags & 1 != 0 { text += "⇧" }
            if flags & 8 == 0 { text += "⌘" }
            return text + key.uppercased()
        }
    }

    struct MenuBar: Codable, Equatable, Sendable {
        /// The top menus (File, Edit…), each with its items; the Apple menu left out.
        var menus: [MenuItem]

        struct Entry: Equatable, Sendable {
            var path: [String]
            var item: MenuItem
        }

        /// Every item that does something (has no submenu), in menu order, with its full path.
        var leaves: [Entry] {
            var out: [Entry] = []
            func walk(_ item: MenuItem, _ path: [String]) {
                let here = path + [item.title]
                if let items = item.items, !items.isEmpty {
                    for child in items { walk(child, here) }
                } else if !path.isEmpty {
                    out.append(Entry(path: here, item: item))
                }
            }
            for menu in menus where !menu.title.isEmpty { walk(menu, []) }
            return out
        }

        /// The item at this path (titles compared as menuTitleKey does), nil when it isn't there.
        func item(at path: [String]) -> MenuItem? {
            var level = menus
            var found: MenuItem?
            for step in path {
                guard let next = level.first(where: { Self.titleKey($0.title) == Self.titleKey(step) }) else { return nil }
                found = next
                level = next.items ?? []
            }
            return found
        }

        /// How titles compare: no case, "..." as "…", spaces folded.
        static func titleKey(_ title: String) -> String {
            title.precomposedStringWithCanonicalMapping.lowercased().replacingOccurrences(of: "...", with: "…")
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }

        /// "File > Save As…" or "파일 › 다른 이름으로 저장…" into its steps.
        static func path(_ text: String) -> [String] {
            text.components(separatedBy: CharacterSet(charactersIn: ">›")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }
}
