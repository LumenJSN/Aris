//
//  ArisTeachMenuKeys.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  A shortcut the owner pressed while he showed Aris something, told as the menu command it chose (third VM run, D1:
//  ⌘N in TextEdit was saved as "TextEdit에서 ⌘N 누르기"; the step is File › New, which also works when the keys
//  change): the app's menu bar item whose key equivalent is exactly those keys. The live observer reads the menu bar's
//  items through Accessibility (AXMenuItemCmdChar, AXMenuItemCmdModifiers); a shortcut no item has stays a key. Pure.
//

import Foundation

enum ArisTeachMenuKeys {
    /// One menu bar command with a key equivalent, as Accessibility gives it.
    struct Item: Equatable, Sendable {
        /// "File", "New".
        let path: [String]
        /// AXMenuItemCmdChar ("N", "s", "⌫").
        let character: String
        /// AXMenuItemCmdModifiers: 0 is ⌘ alone; +1 ⇧, +2 ⌥, +4 ⌃, +8 no ⌘.
        let modifiers: Int
        var enabled = true
    }

    /// The keys as the recorder writes them ("cmd+shift+n") for an item's equivalent; nil when it has none.
    static func keys(_ item: Item) -> String? {
        let character = item.character.trimmingCharacters(in: .whitespaces)
        guard !character.isEmpty else { return nil }
        var parts: [String] = []
        if item.modifiers & 8 == 0 { parts.append("cmd") }
        if item.modifiers & 4 != 0 { parts.append("ctrl") }
        if item.modifiers & 2 != 0 { parts.append("opt") }
        // A capital letter as its equivalent doesn't mean ⇧ by itself (AppKit shows "N" for ⌘N); only the flag does.
        if item.modifiers & 1 != 0 { parts.append("shift") }
        return (parts + [character.lowercased()]).joined(separator: "+")
    }

    /// The command `keys` chose among `items`: the one enabled item with exactly that equivalent; when none is enabled,
    /// the one item that has it at all; nil when none has it, or when several do (then the key is kept as it was
    /// pressed). The menus are read once, as the app is attached, and an item's enabled state then is no guide to
    /// later (sixth VM run, item 7b: Edit › Find › Use Selection for Find, greyed out with nothing selected at that read,
    /// was saved as "press ⌘E").
    static func command(for keys: String, in items: [Item]) -> [String]? {
        let wanted = ArisTeachGeneralise.normalisedKeys(keys)
        guard wanted.contains("+") else { return nil }
        let matches = items.filter { !$0.path.isEmpty && $0.path.allSatisfy { !$0.isEmpty } && Self.keys($0).map(ArisTeachGeneralise.normalisedKeys) == wanted }
        let enabled = matches.filter(\.enabled)
        return only(enabled) ?? (enabled.isEmpty ? only(matches) : nil)
    }

    /// The path when every item names the same one.
    private static func only(_ matches: [Item]) -> [String]? {
        let paths = Set(matches.map { $0.path.joined(separator: "\u{1F}") })
        guard paths.count == 1, let first = matches.first else { return nil }
        return first.path
    }
}
