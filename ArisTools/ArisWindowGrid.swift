//
//  ArisWindowGrid.swift
//  aris-tools
//
//  Laying several windows out in a grid ("Word 4개 켜서 4등분": four windows in a 2x2 grid),
//  and reading key chords ("cmd+shift+t") for the keys tool. Pure, so it is tested without a
//  screen or a keyboard; only ArisKeyLayout.current reads the keyboard layout in use.
//

import Carbon
import CoreGraphics
import Foundation

enum ArisWindowGrid {
    struct Grid: Equatable {
        let rows: Int
        let columns: Int
    }

    /// The most cells a grid may have (beyond that windows are too small to use).
    private static let largest = 16

    /// "2x2", "3x1" (rows x columns); nil for anything else.
    static func grid(named name: String) -> Grid? {
        let parts = name.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0, parts[0] * parts[1] <= largest else { return nil }
        return Grid(rows: parts[0], columns: parts[1])
    }

    /// Side by side up to three, then rows of up to three.
    static func grid(for count: Int) -> Grid {
        switch count {
        case ...3: return Grid(rows: 1, columns: max(1, count))
        case 4: return Grid(rows: 2, columns: 2)
        case 5...6: return Grid(rows: 2, columns: 3)
        default: return Grid(rows: 3, columns: 3)
        }
    }

    /// One frame per window (at most one per cell), in reading order from the top left. `area` is in
    /// screen coordinates, which grow upward. Every cell is the same size in whole points, inside `area` (QA BUG-14: two
    /// halves came out 845 and 816 high).
    static func frames(count: Int, grid: Grid, in area: CGRect) -> [CGRect] {
        let left = area.minX.rounded(.up), bottom = area.minY.rounded(.up)
        let width = ((area.maxX.rounded(.down) - left) / CGFloat(grid.columns)).rounded(.down)
        let height = ((area.maxY.rounded(.down) - bottom) / CGFloat(grid.rows)).rounded(.down)
        return (0..<min(count, grid.rows * grid.columns)).map { index in
            let row = index / grid.columns, column = index % grid.columns
            return CGRect(x: left + CGFloat(column) * width, y: bottom + CGFloat(grid.rows - 1 - row) * height,
                          width: width, height: height)
        }
    }
}

/// A key and its modifiers. A character key is the one that types that character on the keyboard layout in use (audit
/// desk-10: by fixed QWERTY positions, `cmd+a` pressed ⌘Q on AZERTY and quit the app, and ⌘V was ⌘K on Dvorak); with
/// Korean input on, that is the Latin layout behind it, so the key is the same as before. A named key (return, tab,
/// the arrows) sits in the same place on every layout.
struct ArisKeyChord: Equatable {
    let key: CGKeyCode
    let command: Bool
    let shift: Bool
    let option: Bool
    let control: Bool

    /// The keys that are the same on every layout.
    private static let named: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    /// The character keys by their place on a US keyboard: used only when the layout in use can't be read or doesn't
    /// have the character.
    private static let ansi: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "`": 50,
    ]

    /// "cmd+shift+t", "ctrl+opt+space", "return"; nil for a key it doesn't know. `layout`: the characters the layout in
    /// use types, to their key codes, without and with ⌘ held (ArisKeyLayout.current); none given, the US places.
    static func parse(_ text: String, layout: (_ command: Bool) -> [String: CGKeyCode] = { _ in [:] }) -> ArisKeyChord? {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last, !last.isEmpty else { return nil }
        let modifiers = Set(parts.dropLast())
        let known: Set<String> = ["cmd", "command", "shift", "opt", "option", "alt", "ctrl", "control"]
        guard modifiers.isSubset(of: known) else { return nil }
        let command = !modifiers.isDisjoint(with: ["cmd", "command"])
        guard let key = named[last] ?? layout(command)[last] ?? ansi[last] else { return nil }
        return ArisKeyChord(key: key, command: command, shift: modifiers.contains("shift"),
                            option: !modifiers.isDisjoint(with: ["opt", "option", "alt"]),
                            control: !modifiers.isDisjoint(with: ["ctrl", "control"]))
    }

    var flags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        if option { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        return flags
    }
}

/// Which key types which character on the keyboard layout in use.
enum ArisKeyLayout {
    /// The keys that type characters (the main block; return, tab and space are named keys).
    static let characterKeys: [CGKeyCode] = (0...50).filter { ![36, 48, 49].contains($0) }.map { CGKeyCode($0) }

    /// Characters to key codes, read from a layout one key at a time. `typed`: what a key types (nil for nothing); the
    /// first key that types a character keeps it. Pure.
    static func map(_ typed: (CGKeyCode) -> String?) -> [String: CGKeyCode] {
        var map: [String: CGKeyCode] = [:]
        for code in characterKeys {
            guard let character = typed(code)?.lowercased(), !character.isEmpty, map[character] == nil else { continue }
            map[character] = code
        }
        return map
    }

    /// The layout in use: the current Latin (ASCII-capable) one, which is also what a shortcut goes by while Korean
    /// input is on. `command`: with ⌘ held (a "Dvorak – QWERTY ⌘" layout types QWERTY then). Empty when it can't be read,
    /// or off the main thread (the input-source calls are main-thread only): the US places are used then.
    static func current(command: Bool) -> [String: CGKeyCode] {
        guard Thread.isMainThread, let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let modifiers = command ? UInt32(cmdKey >> 8) & 0xFF : 0
        let keyboard = UInt32(LMGetKbdType())
        return data.withUnsafeBytes { raw -> [String: CGKeyCode] in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return [:] }
            return map { code in
                var dead: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers, keyboard, OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                            &dead, characters.count, &length, &characters)
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: characters, count: length)
            }
        }
    }
}
