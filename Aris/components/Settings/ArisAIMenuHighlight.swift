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

/// The settings window's menus and the controls that open them, to the measured numbers (the measured
/// menu content, items, radio items, separators and labels, its settings
/// page's select button, and its language dialog). Numbers only, Foundation only (tested); the views in
/// ArisAIServicesMenu, ArisSettingsDropdown and ArisSettingsSheets draw with them.
enum ArisMenuLook {
    /// `0xRRGGBB` at an alpha.
    struct Shade: Equatable, Sendable {
        let hex: UInt32
        let alpha: Double
        init(_ hex: UInt32, _ alpha: Double = 1) {
            self.hex = hex
            self.alpha = alpha
        }
    }

    /// A shade for each appearance.
    struct Pair: Equatable, Sendable {
        let light: Shade
        let dark: Shade
        func pick(_ dark: Bool) -> Shade { dark ? self.dark : light }
    }

    /// A CSS box-shadow: offset, blur, spread, its colour, and whether it is inset.
    struct Shadow: Equatable, Sendable {
        let y: CGFloat
        let blur: CGFloat
        let spread: CGFloat
        let shade: Shade
        var inset = false
    }

    // MARK: The panel (DropdownMenuContent)

    /// `rounded-2xl`, `p-2`, a 1-pt border.
    static let radius: CGFloat = 16
    static let inset: CGFloat = 8
    /// `shadow-2xl shadow-black/10`: 0 25 50 −12 at black .1, in both appearances.
    static let shadow = Shadow(y: 25, blur: 50, spread: -12, shade: Shade(0x000000, 0.1))
    /// From its button: `sideOffset 4` (the AI 서비스 page's select), the primitive's 8 (a settings row's).
    static let pageGap: CGFloat = 4
    static let settingsGap: CGFloat = 8
    /// A settings row's menu: `min-w-[220px]`, at most 320 tall, its right edge on the button's (`align end`), kept
    /// 12 from the window's edges (`collisionPadding 12`). The page's: as wide as its button, at most 300 tall.
    static let settingsMinWidth: CGFloat = 220
    static let settingsMaxHeight: CGFloat = 320
    static let pageMaxHeight: CGFloat = 300
    static let edge: CGFloat = 12
    /// It is there at once and gone at once: the panel's animate-in / animate-out classes have no rule in the measured
    /// stylesheets, so nothing plays.
    static let animates = false

    // MARK: Items

    /// `rounded-lg px-3 py-2.5 text-sm font-medium`, hover gray-100 / white 10%, disabled at .4.
    static let rowRadius: CGFloat = 8
    static let rowPaddingH: CGFloat = 12
    static let rowPaddingV: CGFloat = 10
    static let rowFont: CGFloat = 14
    static let rowHover = Pair(light: Shade(0xf3f4f6), dark: Shade(0xffffff, 0.1))
    static let disabledOpacity = 0.4
    /// An AI 서비스 item's check: `h-4 w-4` in the accent.
    static let checkBox: CGFloat = 16
    /// A settings row's chosen item (RadioItem checked): no check, a left-to-right sheen and four shades.
    static let radioEdge = Pair(light: Shade(0xe6f5ff, 0.08), dark: Shade(0x8c96aa, 0.05))
    static let radioMiddle = Pair(light: Shade(0xffffff, 0.2), dark: Shade(0xffffff, 0.08))
    static let radioShadowsLight = [
        Shadow(y: 2, blur: 2, spread: 0, shade: Shade(0x000000, 0.05), inset: true),
        Shadow(y: -2, blur: 2, spread: 0, shade: Shade(0xffffff, 0.5), inset: true),
        Shadow(y: 4, blur: 2, spread: -2, shade: Shade(0x1e1e1e, 0.15)),
        Shadow(y: 0, blur: 1.6, spread: 4, shade: Shade(0xd2ebff, 0.2), inset: true),
    ]
    static let radioShadowsDark = [
        Shadow(y: 1, blur: 3, spread: 0, shade: Shade(0x000000, 0.8), inset: true),
        Shadow(y: -1.3, blur: 0.5, spread: 0, shade: Shade(0xffffff, 0.4), inset: true),
        Shadow(y: 4, blur: 2, spread: -2, shade: Shade(0x000000, 0.3)),
        Shadow(y: 1.5, blur: 2, spread: 1.5, shade: Shade(0xffffff, 0.24), inset: true),
    ]

    // MARK: Separator and group label

    /// `my-1.5 h-px`, edge to edge, gray-200 / white 10%.
    static let separatorMargin: CGFloat = 6
    static let separator = Pair(light: Shade(0xe5e7eb), dark: Shade(0xffffff, 0.1))
    /// `px-3 py-2 text-xs font-semibold uppercase tracking-wider` (.05 em), gray-500 / gray-400.
    static let labelFont: CGFloat = 12
    static let labelTracking = 0.05
    static let labelPaddingH: CGFloat = 12
    static let labelPaddingV: CGFloat = 8
    static let label = Pair(light: Shade(0x6a7282), dark: Shade(0x99a1af))

    // MARK: A settings row's select (the settings page's select button)

    /// `px-4 py-1.5 rounded-lg gap-2 text-xs font-medium`, a 1-pt border: 16 + 12 + 2 = 30 tall. No press scale and
    /// no look of its own while open.
    static let selectPaddingH: CGFloat = 16
    static let selectHeight: CGFloat = 30
    static let selectRadius: CGFloat = 8
    static let selectFont: CGFloat = 12
    static let selectGap: CGFloat = 8
    /// ChevronsUpDown `h-3.5 w-3.5`.
    static let selectIcon: CGFloat = 14
    static let selectText = Pair(light: Shade(0x364153), dark: Shade(0xe5e7eb))
    static let selectTextHover = Pair(light: Shade(0x101828), dark: Shade(0xffffff))
    static let selectChevron = Pair(light: Shade(0x4a5565), dark: Shade(0x99a1af))
    static let selectBorder = Pair(light: Shade(0x000000, 0.04), dark: Shade(0xffffff, 0.04))
    static let selectBorderHover = Pair(light: Shade(0x000000, 0.08), dark: Shade(0xffffff, 0.08))
    /// `bg-gradient-to-b`: white → black 2%, white 8% → white 1%.
    static let selectFillTop = Pair(light: Shade(0xffffff), dark: Shade(0xffffff, 0.08))
    static let selectFillBottom = Pair(light: Shade(0x000000, 0.02), dark: Shade(0xffffff, 0.01))
    /// Aris's own guard: the widest a row's select grows before its choice is cut (the measured button has none).
    static let selectMaxWidth: CGFloat = 280

    // MARK: The language sheet (the measured language dialog)

    /// `max-w-[340px] rounded-2xl border`, white / the dark modal; `shadow-lg` light, the dark modal shadow dark;
    /// behind it black at .5 / .75. It opens and closes at once (no animate rule, as the menu).
    static let sheetWidth: CGFloat = 340
    static let sheetRadius: CGFloat = 16
    static let sheetFill = Pair(light: Shade(0xffffff), dark: Shade(0x1a1b1e))
    static let sheetBorder = Pair(light: Shade(0xe5e7eb), dark: Shade(0xdfe2e8, 0x12 / 255.0))
    static let sheetBackdrop = Pair(light: Shade(0x000000, 0.5), dark: Shade(0x000000, 0.75))
    static let sheetShadowsLight = [Shadow(y: 10, blur: 15, spread: -3, shade: Shade(0x000000, 0.1)), Shadow(y: 4, blur: 6, spread: -4, shade: Shade(0x000000, 0.1))]
    static let sheetShadowsDark = [Shadow(y: 24, blur: 64, spread: -20, shade: Shade(0x000000, 0xd1 / 255.0))]
    /// `max-h-[70vh]`.
    static let sheetMaxHeightShare: CGFloat = 0.7
    /// Head `px-5 pt-5 pb-4`: title 14/600, its line 12 `mt-0.5`, `mb-3` to the search.
    static let sheetPadding: CGFloat = 20
    static let sheetHeadBottom: CGFloat = 16
    static let sheetTitleFont: CGFloat = 14
    static let sheetLineFont: CGFloat = 12
    static let sheetLineGap: CGFloat = 2
    static let sheetSearchGap: CGFloat = 12
    /// Search `pl-9 pr-3 py-2 text-xs rounded-lg`, a 14-pt glass 12 in: 16 + 16 + 2 = 34 tall.
    static let searchHeight: CGFloat = 34
    static let searchRadius: CGFloat = 8
    static let searchFont: CGFloat = 12
    static let searchLeading: CGFloat = 36
    static let searchIcon: CGFloat = 14
    static let searchIconInset: CGFloat = 12
    static let searchFill = Pair(light: Shade(0xf9fafb), dark: Shade(0x1f2024))
    static let searchBorder = Pair(light: Shade(0xe5e7eb), dark: Shade(0xdfe2e8, 0x11 / 255.0))
    /// "N selected": `px-5 py-1 text-[10px] uppercase tracking-wider font-medium`.
    static let countFont: CGFloat = 10
    static let countPaddingV: CGFloat = 4
    /// List `px-3 py-2 space-y-0.5`; a row `px-3 py-2.5 rounded-lg gap-3`, its name 12/500 and its own name 10.
    static let listPaddingH: CGFloat = 12
    static let listPaddingV: CGFloat = 8
    static let listSpacing: CGFloat = 2
    static let optionGap: CGFloat = 12
    static let optionNameFont: CGFloat = 12
    static let optionNativeFont: CGFloat = 10
    static let optionOn = Pair(light: Shade(0xf3f4f6), dark: Shade(0xffffff, 0.1))
    static let optionHover = Pair(light: Shade(0xf9fafb), dark: Shade(0xffffff, 0.05))
    /// The box: `w-4 h-4 rounded`, on black 10% / white 20% with a black 20% / white 30% line and an inset shade, off
    /// a gray-300 / white 20% line (gray-400 / white 30% under the pointer); a `w-2.5` check in gray-700 / white.
    static let box: CGFloat = 16
    static let boxRadius: CGFloat = 4
    static let boxCheck: CGFloat = 10
    static let boxOnFill = Pair(light: Shade(0x000000, 0.1), dark: Shade(0xffffff, 0.2))
    static let boxOnBorder = Pair(light: Shade(0x000000, 0.2), dark: Shade(0xffffff, 0.3))
    static let boxOffBorder = Pair(light: Shade(0xd1d5dc), dark: Shade(0xffffff, 0.2))
    static let boxOffBorderHover = Pair(light: Shade(0x99a1af), dark: Shade(0xffffff, 0.3))
    static let boxShadeLight = [Shadow(y: 1, blur: 2, spread: 0, shade: Shade(0x000000, 0.1), inset: true), Shadow(y: -1, blur: 1, spread: 0, shade: Shade(0xffffff, 0.6), inset: true)]
    static let boxShadeDark = [Shadow(y: 1, blur: 2, spread: 0, shade: Shade(0x000000, 0.4), inset: true), Shadow(y: -1, blur: 1, spread: 0, shade: Shade(0xffffff, 0.2), inset: true)]
    static let boxCheckInk = Pair(light: Shade(0x364153), dark: Shade(0xffffff))
}
