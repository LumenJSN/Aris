//
//  ArisAIMenuHighlight.swift
//  Aris
//
//  The one highlighted row of an open AI 서비스 dropdown. A menu opens with its chosen item highlighted; ↓ and ↑ move
//  the highlight (wrapping) and the list scrolls to it; the pointer's moving puts it on the row under the pointer.
//  There is one highlight, never the keyboard's and the pointer's side by side (upgrade VM run 2026-11-11, bug 8: the
//  keyboard's left the visible rows while the pointer's stayed lit). Foundation only (tested).
//

import Foundation

struct ArisAIMenuHighlight: Equatable, Sendable {
    /// The highlighted item's id; nil: none.
    var id: String?
    /// Rises each time a key moved the highlight: the list scrolls to the row then. The pointer's own moves never
    /// scroll (its row is in view already).
    var keyMoves = 0
    /// Where the pointer was when a key last moved the highlight. The list scrolls under a pointer that rests, and
    /// the row that slides under it must not take the highlight back; nil once the pointer has moved.
    var pointerAtKey: CGPoint?

    /// The items a key can stop at: every one that can be picked, the foot's too, in the order they are drawn.
    static func stops(_ menu: ArisAIMenu) -> [String] {
        (menu.items + menu.foot).filter { !$0.disabled }.map(\.id)
    }

    /// A menu just opened: its chosen item, when it can be picked.
    static func opening(_ menu: ArisAIMenu) -> ArisAIMenuHighlight {
        ArisAIMenuHighlight(id: menu.items.first { $0.checked && !$0.disabled }?.id)
    }

    /// ↓ (`step` 1) or ↑ (-1): the next item, wrapping. With none highlighted (or one the search took away), the
    /// first or the last. `pointer`: where the pointer is now.
    func moved(_ step: Int, in menu: ArisAIMenu, pointer: CGPoint) -> ArisAIMenuHighlight {
        let stops = Self.stops(menu)
        guard !stops.isEmpty else { return self }
        let at = id.flatMap(stops.firstIndex)
        let next = at.map { ($0 + step + stops.count) % stops.count } ?? (step > 0 ? 0 : stops.count - 1)
        return ArisAIMenuHighlight(id: stops[next], keyMoves: keyMoves + 1, pointerAtKey: pointer)
    }

    /// A letter typed while the list has the keyboard: the next item after the highlighted one whose title starts
    /// with it (wrapping; a Hangul consonant matches a title's first consonant), as a macOS menu does. `said`: the
    /// title as it is drawn. Nothing starts with it: the highlight stays.
    func typed(_ text: String, in menu: ArisAIMenu, said: (String) -> String = { $0 }, pointer: CGPoint) -> ArisAIMenuHighlight {
        let needle = ArisSettingsIndex.normalized(text)
        let items = (menu.items + menu.foot).filter { !$0.disabled }
        guard !needle.isEmpty, !items.isEmpty else { return self }
        let start = id.flatMap { current in items.firstIndex { $0.id == current } }.map { $0 + 1 } ?? 0
        let order = (0..<items.count).map { items[(start + $0) % items.count] }
        guard let hit = order.first(where: { item in
            let title = said(item.title)
            return ArisSettingsIndex.normalized(title).hasPrefix(needle) || ArisSettingsIndex.initials(title).hasPrefix(needle)
        }) else { return self }
        return ArisAIMenuHighlight(id: hit.id, keyMoves: keyMoves + 1, pointerAtKey: pointer)
    }

    /// The pointer is over `item`, at `pointer`: that row is the highlight, unless the pointer hasn't moved since a key
    /// moved it, or the item can't be picked.
    func hovered(_ item: String, pointer: CGPoint, in menu: ArisAIMenu) -> ArisAIMenuHighlight {
        guard pointer != pointerAtKey, Self.stops(menu).contains(item) else { return self }
        return ArisAIMenuHighlight(id: item, keyMoves: keyMoves)
    }

    /// The pointer left `item`, and is now at `pointer`: when that row was the highlight and the pointer really moved,
    /// nothing is highlighted (as a menu does when the pointer leaves it).
    func unhovered(_ item: String, pointer: CGPoint) -> ArisAIMenuHighlight {
        guard pointer != pointerAtKey, id == item else { return self }
        return ArisAIMenuHighlight(keyMoves: keyMoves)
    }
}

/// Which edges of the menu's scrolling list hide more rows. The list fades at such an edge, but a fade over a blank
/// stretch (a separator, the gap above a group's title) shows nothing: the 생각 list ended in an empty strip above its
/// foot with its API entries out of sight and no sign that it scrolls. So each such edge also carries a small still
/// chevron, as macOS's own long menus do. Foundation only (tested).
enum ArisAIMenuEdges {
    /// `listHeight`: every row; `visible`: what the panel shows of it; `offset`: the list's top in its scroller (0,
    /// then negative as it scrolls).
    static func more(listHeight: CGFloat, visible: CGFloat, offset: CGFloat) -> (above: Bool, below: Bool) {
        guard listHeight > visible + 1 else { return (false, false) }
        return (offset < -2, visible - offset < listHeight - 2)
    }
}
