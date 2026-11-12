//
//  ArisCircleHint.swift
//  Aris
//
//  The one line Settings shows under "동그라미로 가리키기" (and the screen row beside it): how to draw a circle,
//  naming the gesture's key ("⌥⇧를 누른 채 …", ArisGestureKey), with 을/를 matched to how the key's name ends.
//  Pure, so the tests run it.
//

import Foundation

enum ArisCircleHint {
    /// Said when no key is named.
    static let fallbackKey = "말하기 단축키"
    static let action = "누른 채 화면에 동그라미를 그리면 그 부분을 같이 봐요"

    private static let modifierSymbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "⇪", "🌐"]
    /// Key words whose Korean reading ends in a consonant: 리턴, 탭, 홈, 페이지 업/다운, 업, 다운 (스페이스, 엔터 … take 를).
    private static let closedWords: Set<String> = ["return", "tab", "home", "pageup", "pagedown", "up", "down"]
    /// Letters read with a final consonant: 엘, 엠, 엔, 알.
    private static let closedLetters: Set<Character> = ["l", "m", "n", "r"]
    /// Digits read with a final consonant: 영, 일, 삼, 육, 칠, 팔.
    private static let closedDigits: Set<Character> = ["0", "1", "3", "6", "7", "8"]

    /// The hint for a key as shortcuts are written ("⌥⇧", "⌥Space"), or the setting's name when none is given.
    static func text(shortcut: String?) -> String {
        guard let name = shortcut.flatMap(keyName) else { return "\(fallbackKey)를 \(action)" }
        return "\(name)\(objectParticle(after: name)) \(action)"
    }

    /// "⌥Space" → "⌥ Space": the modifier symbols, then a space, then the key. Nil for an empty shortcut.
    static func keyName(_ shortcut: String) -> String? {
        let trimmed = shortcut.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let modifiers = String(trimmed.prefix { modifierSymbols.contains($0) })
        let key = trimmed.dropFirst(modifiers.count).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return modifiers }
        return modifiers.isEmpty ? key : "\(modifiers) \(key)"
    }

    /// 을 after a name read with a final consonant, else 를.
    static func objectParticle(after name: String) -> String {
        closesWithConsonant(name) ? "을" : "를"
    }

    private static func closesWithConsonant(_ name: String) -> Bool {
        let word = name.split(separator: " ").last.map(String.init) ?? name
        guard let last = word.last else { return false }
        if let scalar = last.unicodeScalars.first, (0xAC00...0xD7A3).contains(scalar.value) {
            return (scalar.value - 0xAC00) % 28 != 0
        }
        if closedDigits.contains(last) { return true }
        if last.isNumber { return false }
        let lower = word.lowercased()
        if word.count == 1 { return closedLetters.contains(Character(lower)) }
        return closedWords.contains(lower)
    }
}
