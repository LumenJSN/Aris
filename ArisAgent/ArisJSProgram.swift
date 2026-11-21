//
//  ArisJSProgram.swift
//  aris-agent
//
//  A strict reader for the JavaScript Codex writes for computer use (cua_repl's js tool). Only code made of the
//  runtime's own calls with literal arguments is read; anything else (a loop, a template, a computed name, a call
//  inside an argument, a comment, any other function) is not, and then only the user may approve it. The runtime's API,
//  from ChatGPT.app's @oai/cua tinysky_alt/types.d.ts and @oai/cua-repl's instructions:
//
//      const app = await cua.getApp("Notes");   await app.click(3);   await app.typeText("hi", 5);
//
//  Every statement is one of `await <receiver>.<method>(<literals>);` or `const|let <name> = await <same>;`, where the
//  receiver is `cua` or a name bound by `cua.getApp("<app>")` earlier in the code.
//

import Foundation

/// A literal argument: the only values the code may pass.
indirect enum ArisJSValue: Equatable {
    case string(String)
    case number(String)
    case bool(Bool)
    case null
    case object([(key: String, value: ArisJSValue)])

    static func == (lhs: ArisJSValue, rhs: ArisJSValue) -> Bool { lhs.text == rhs.text }

    /// The value as JSON-like text, for the judge and the tests.
    var text: String {
        switch self {
        case .string(let value): return Self.quoted(value)
        case .number(let value): return value
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        case .object(let fields): return "{" + fields.map { Self.quoted($0.key) + ": " + $0.value.text }.joined(separator: ", ") + "}"
        }
    }

    /// Every string in it, keys included.
    var strings: [String] {
        switch self {
        case .string(let value): return [value]
        case .object(let fields): return fields.flatMap { [$0.key] + $0.value.strings }
        case .number, .bool, .null: return []
        }
    }

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes])) ?? Data()
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}

/// One call: the app it acts on (getApp's argument; nil for `cua` itself), the method, and its literal arguments.
struct ArisJSCall: Equatable {
    let app: String?
    let method: String
    let arguments: [ArisJSValue]
}

struct ArisJSProgram: Equatable {
    let calls: [ArisJSCall]

    /// The apps the code acts on, as it names them to getApp, each once.
    var apps: [String] {
        calls.filter { $0.method == "getApp" }.compactMap { $0.arguments.first?.strings.first }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Whether every call is getApp or one of an app's own methods: `cua`'s other reads (getState, listApps,
    /// listWindows) see across apps, so a call using them is never just its app's own screen.
    var staysInItsApps: Bool { calls.allSatisfy { $0.app != nil || $0.method == "getApp" } }

    /// The keys the code presses (pressKey's first argument).
    var keys: [String] { calls.filter { $0.app != nil && $0.method == "pressKey" }.compactMap { $0.arguments.first?.strings.first } }

    /// The text the code types into an app (typeText's text, setValue's value).
    var typedStrings: [String] {
        calls.compactMap { call -> String? in
            guard call.app != nil else { return nil }
            switch call.method {
            case "typeText": if case .string(let text)? = call.arguments.first { return text }
            case "setValue": if call.arguments.count > 1, case .string(let text) = call.arguments[1] { return text }
            default: break
            }
            return nil
        }
    }

    /// The labels it picks text by (selectText's text): in a chat app, what the code names as the conversation.
    var selections: [String] {
        calls.filter { $0.app != nil && $0.method == "selectText" && $0.arguments.count > 1 }.compactMap { $0.arguments[1].strings.first }
    }

    /// Whether the code sends what it typed: Return or Enter, a typed line break, or a click or secondary action after
    /// typing (a send button). In a chat app that is the outbound moment.
    var sends: Bool {
        var typed = false
        for call in calls where call.app != nil {
            switch call.method {
            case "typeText", "setValue":
                typed = true
                if call.arguments.flatMap(\.strings).contains(where: { $0.contains("\n") || $0.contains("\r") }) { return true }
            case "pressKey":
                if let key = call.arguments.first?.strings.first, ArisKeyCombo.read(key)?.key == "return" { return true }
            case "click", "performSecondaryAction":
                if typed { return true }
            default: break
            }
        }
        return false
    }

    /// Every literal string the code passes (the text it types, the keys, the labels), for the risky-word check.
    var strings: [String] { calls.flatMap { $0.arguments.flatMap(\.strings) } }

    /// `cua`'s own methods: finding an app and looking at what's open.
    static let cuaMethods: Set<String> = ["getApp", "getState", "listApps", "listWindows"]
    /// An app's methods that look or act on its UI (paste, which puts text on the user's clipboard, isn't one).
    static let appMethods: Set<String> = ["getAXState", "getAXStateAndScreenshot", "getScreenshot", "click", "drag", "scroll", "selectText",
                                          "setValue", "performSecondaryAction", "pressKey", "typeText"]
    /// What a name the code binds may look like: a lowercase letter, then letters and digits (so never `JSON`,
    /// `Object`, `$x` or `_x`), and none of the lowercase globals or words below.
    private static func bindable(_ name: String) -> Bool {
        name.range(of: "^[a-z][A-Za-z0-9]*$", options: .regularExpression) != nil && !globals.contains(name)
    }

    private static let globals: Set<String> = ["cua", "globalThis", "this", "require", "import", "eval", "nodeRepl", "process", "window", "self",
                                               "global", "module", "exports", "await", "async", "const", "let", "var", "new", "arguments",
                                               "undefined", "console", "fetch", "document", "navigator", "location", "setTimeout",
                                               "setInterval", "setImmediate", "clearTimeout", "clearInterval", "queueMicrotask",
                                               "structuredClone", "atob", "btoa", "escape", "unescape", "isNaN", "isFinite", "parseInt",
                                               "parseFloat", "encodeURI", "decodeURI", "encodeURIComponent", "decodeURIComponent", "crypto",
                                               "performance", "buffer", "constructor", "prototype", "of", "in", "if", "for", "while",
                                               "do", "return", "function", "class", "with", "delete", "typeof", "void", "yield", "true",
                                               "false", "null"]

    /// The code read as runtime calls with literal arguments; nil when any of it is anything else.
    static func read(_ code: String) -> ArisJSProgram? {
        guard let tokens = ArisJSTokens.read(code), !tokens.isEmpty else { return nil }
        var reader = Reader(tokens: tokens)
        var apps: [String: String] = [:]
        var bound: Set<String> = []
        var calls: [ArisJSCall] = []
        while !reader.atEnd {
            var binding: String?
            if reader.take(.word("const")) || reader.take(.word("let")) {
                guard case .word(let name)? = reader.next(), bindable(name), !bound.contains(name), reader.take(.symbol("=")) else { return nil }
                binding = name
            }
            guard reader.take(.word("await")), case .word(let receiver)? = reader.next(), reader.take(.symbol(".")),
                  case .word(let method)? = reader.next(), let arguments = reader.arguments() else { return nil }
            if receiver == "cua" {
                guard cuaMethods.contains(method) else { return nil }
                if method == "getApp" {
                    guard let binding, arguments.count == 1, case .string(let app) = arguments[0], !app.isEmpty else { return nil }
                    apps[binding] = app
                }
                calls.append(ArisJSCall(app: nil, method: method, arguments: arguments))
            } else {
                guard let app = apps[receiver], appMethods.contains(method) else { return nil }
                calls.append(ArisJSCall(app: app, method: method, arguments: arguments))
            }
            if let binding { bound.insert(binding) }
            _ = reader.take(.symbol(";"))
        }
        return ArisJSProgram(calls: calls)
    }

    private struct Reader {
        let tokens: [ArisJSTokens.Token]
        var index = 0

        var atEnd: Bool { index >= tokens.count }

        mutating func next() -> ArisJSTokens.Token? {
            guard index < tokens.count else { return nil }
            index += 1
            return tokens[index - 1]
        }

        mutating func take(_ token: ArisJSTokens.Token) -> Bool {
            guard index < tokens.count, tokens[index] == token else { return false }
            index += 1
            return true
        }

        /// `( value, value, … )`.
        mutating func arguments() -> [ArisJSValue]? {
            guard take(.symbol("(")) else { return nil }
            var values: [ArisJSValue] = []
            if take(.symbol(")")) { return values }
            repeat {
                guard let value = value(depth: 0) else { return nil }
                values.append(value)
            } while take(.symbol(","))
            return take(.symbol(")")) ? values : nil
        }

        /// A literal, or an object of literals (two levels at most: an option holding a point).
        mutating func value(depth: Int) -> ArisJSValue? {
            switch next() {
            case .string(let text)?: return .string(text)
            case .number(let text)?: return .number(text)
            case .word("true")?: return .bool(true)
            case .word("false")?: return .bool(false)
            case .word("null")?: return .null
            case .symbol("{")? where depth < 2:
                var fields: [(key: String, value: ArisJSValue)] = []
                if take(.symbol("}")) { return .object(fields) }
                repeat {
                    let key: String
                    switch next() {
                    case .word(let name)?: key = name
                    case .string(let name)?: key = name
                    default: return nil
                    }
                    guard take(.symbol(":")), let value = value(depth: depth + 1) else { return nil }
                    fields.append((key, value))
                } while take(.symbol(","))
                return take(.symbol("}")) ? .object(fields) : nil
            default: return nil
            }
        }
    }
}

/// The code as words, literals and a few marks; nil at anything else (a backtick, a bracket, an operator, a slash,
/// so no comments, templates, computed names or arithmetic).
enum ArisJSTokens {
    enum Token: Equatable {
        case word(String), string(String), number(String), symbol(String)
    }

    private static let symbols: Set<Character> = ["(", ")", "{", "}", ",", ";", ":", ".", "="]
    private static let hangulFillers: Set<UInt32> = [0x115F, 0x1160, 0x3164, 0xFFA0]

    /// A character that shows nothing: a format character (Cf), any default-ignorable code point, or a Hangul filler.
    static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .format || scalar.properties.isDefaultIgnorableCodePoint || hangulFillers.contains(scalar.value)
    }

    /// Whether one character (a grapheme cluster) carries a hidden scalar that isn't part of what it shows. An emoji's
    /// own joiners and selectors show nothing by themselves yet are the picture (a red heart, a family, Scotland's flag), so they pass:
    /// a zero-width joiner between two emoji, one variation selector right after a character that shows (one per
    /// character, so nothing can be smuggled in a run of them), and the short tag run of a subdivision flag. Every
    /// other hidden scalar (a bidi control, a zero-width space or joiner outside an emoji, a soft hyphen, a tag
    /// anywhere else) still counts (audit item 9: emoji in an MCP write were refused as hidden characters).
    static func hidesSomething(_ character: Character) -> Bool {
        let scalars = Array(character.unicodeScalars)
        return scalars.indices.contains { isHidden(scalars[$0]) && !partOfShownCharacter(scalars, $0) }
    }

    /// Text with any hidden scalar that isn't part of a shown character (hidesSomething).
    static func hidesSomething(_ text: String) -> Bool { text.contains(where: hidesSomething) }

    /// The scalars of `character` without the hidden ones that aren't part of what it shows.
    static func shownScalars(_ character: Character) -> [Unicode.Scalar] {
        let scalars = Array(character.unicodeScalars)
        return scalars.indices.filter { !isHidden(scalars[$0]) || partOfShownCharacter(scalars, $0) }.map { scalars[$0] }
    }

    private static let zeroWidthJoiner: UInt32 = 0x200D
    private static let cancelTag: UInt32 = 0xE007F
    private static let blackFlag: UInt32 = 0x1F3F4
    /// The longest subdivision code a flag's tags spell ("gbsct", "usca"): ISO 3166-2 codes are at most six.
    private static let maxFlagTags = 6

    private static func isVariationSelector(_ value: UInt32) -> Bool {
        (0xFE00...0xFE0F).contains(value) || (0xE0100...0xE01EF).contains(value)
    }

    private static func isEmojiScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmoji && !isHidden(scalar)
    }

    private static func partOfShownCharacter(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        let value = scalars[index].value
        if isVariationSelector(value) {
            // One selector, right after a scalar that shows and that the selector belongs to: the text/emoji ones
            // after an emoji, the ideographic ones after an ideograph, the others after a non-ASCII character. A
            // selector after a plain letter shows nothing and could carry a hidden byte, so it still counts.
            guard index > 0, !isHidden(scalars[index - 1]) else { return false }
            let base = scalars[index - 1]
            switch value {
            case 0xFE0E, 0xFE0F: return base.properties.isEmoji
            case 0xE0100...0xE01EF: return base.properties.isIdeographic
            default: return !base.isASCII
            }
        }
        if value == zeroWidthJoiner {
            // Between two emoji (the one before may carry its selector or skin tone).
            guard index > 0, index + 1 < scalars.count, isEmojiScalar(scalars[index + 1]) else { return false }
            var before = index - 1
            if isVariationSelector(scalars[before].value), before > 0 { before -= 1 }
            return isEmojiScalar(scalars[before])
        }
        if (0xE0020...0xE007F).contains(value) {
            // A subdivision flag: the black flag, two to six tag letters or digits, the cancel tag, and nothing else.
            guard scalars.first?.value == blackFlag, scalars.last?.value == cancelTag else { return false }
            let tags = scalars.dropFirst().dropLast()
            guard (2...maxFlagTags).contains(tags.count) else { return false }
            return tags.allSatisfy { (0xE0061...0xE007A).contains($0.value) || (0xE0030...0xE0039).contains($0.value) }
        }
        return false
    }

    static func read(_ code: String) -> [Token]? {
        var tokens: [Token] = []
        var characters = Array(code)[...]
        while let character = characters.first {
            if character.isWhitespace || character.isNewline {
                characters = characters.dropFirst()
            } else if symbols.contains(character) {
                tokens.append(.symbol(String(character)))
                characters = characters.dropFirst()
            } else if character == "\"" || character == "'" {
                guard let (text, rest) = string(characters.dropFirst(), quote: character) else { return nil }
                tokens.append(.string(text))
                characters = rest
            } else if character.isASCII, character.isNumber || character == "-" {
                let number = String(characters.prefix { $0.isASCII && ($0.isNumber || $0 == "." || $0 == "-") })
                guard number.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
                tokens.append(.number(number))
                characters = characters.dropFirst(number.count)
            } else if character.isASCII, character.isLetter || character == "_" || character == "$" {
                let word = String(characters.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "$") })
                tokens.append(.word(word))
                characters = characters.dropFirst(word.count)
            } else {
                return nil
            }
        }
        return tokens
    }

    /// A quoted string up to its closing quote; only \\, \', \", \n and \t escapes, and no line break inside.
    private static func string(_ characters: ArraySlice<Character>, quote: Character) -> (String, ArraySlice<Character>)? {
        var text = ""
        var rest = characters
        while let character = rest.first {
            rest = rest.dropFirst()
            switch character {
            case quote: return (text, rest)
            case "\n", "\r", "\r\n", "\u{2028}", "\u{2029}": return nil
            case "\\":
                guard let escaped = rest.first else { return nil }
                rest = rest.dropFirst()
                switch escaped {
                case "\\", "'", "\"": text.append(escaped)
                case "n": text.append("\n")
                case "t": text.append("\t")
                default: return nil
                }
            default:
                // Invisible characters (format and default-ignorable ones: bidi controls, zero-width marks, soft hyphens,
                // Hangul fillers, tags) could make what's shown differ from what's typed. An emoji's own joiners and
                // selectors are part of what it shows (hidesSomething).
                guard !ArisJSTokens.hidesSomething(character) else { return nil }
                text.append(character)
            }
        }
        return nil
    }
}

/// A key as pressKey names it, read the same however it's written: modifiers (cmd, opt, ctrl, shift, by any alias or
/// symbol, in any order, joined by +, - or spaces) and one key.
struct ArisKeyCombo: Equatable {
    let modifiers: Set<String>
    let key: String

    private static let modifierAliases: [String: String] = [
        "cmd": "cmd", "command": "cmd", "meta": "cmd", "super": "cmd", "⌘": "cmd", "opt": "opt", "option": "opt", "alt": "opt", "⌥": "opt",
        "ctrl": "ctrl", "control": "ctrl", "⌃": "ctrl", "shift": "shift", "⇧": "shift",
    ]
    private static let keyAliases: [String: String] = [
        "esc": "escape", "escape": "escape", "⎋": "escape", "return": "return", "enter": "return", "↩": "return", "⏎": "return",
        "delete": "delete", "backspace": "delete", "⌫": "delete", "tab": "tab", "⇥": "tab", "up": "up", "arrowup": "up", "↑": "up",
        "down": "down", "arrowdown": "down", "↓": "down", "left": "left", "arrowleft": "left", "←": "left", "right": "right",
        "arrowright": "right", "→": "right", "home": "home", "end": "end", "pageup": "pageup", "page_up": "pageup", "pagedown": "pagedown",
        "page_down": "pagedown",
    ]
    private static let symbols: Set<Character> = ["⌘", "⌥", "⌃", "⇧", "⎋", "↩", "⏎", "⌫", "⇥", "↑", "↓", "←", "→"]

    /// Nil when it isn't exactly one key with known modifiers.
    static func read(_ text: String) -> ArisKeyCombo? {
        var parts: [String] = []
        var word = ""
        for character in text.lowercased() {
            if character == "+" || character == "-" || character.isWhitespace {
                if !word.isEmpty { parts.append(word) }
                word = ""
            } else if symbols.contains(character) {
                if !word.isEmpty { parts.append(word) }
                parts.append(String(character))
                word = ""
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty { parts.append(word) }
        var modifiers: Set<String> = []
        var keys: [String] = []
        for part in parts {
            if let modifier = modifierAliases[part] { modifiers.insert(modifier) } else { keys.append(keyAliases[part] ?? part) }
        }
        guard keys.count == 1, let key = keys.first, key.count == 1 || keyAliases.values.contains(key) else { return nil }
        return ArisKeyCombo(modifiers: modifiers, key: key)
    }

    private static let editing: Set<String> = ["a", "c", "v", "x", "z", "s", "b", "i", "u", "f", "n", "t"]
    private static let moving: Set<String> = ["tab", "up", "down", "left", "right", "home", "end", "pageup", "pagedown"]

    /// The keys main Aris may let code press: moving around (Tab, shift+Tab, arrows, Home/End/PageUp/PageDown), Escape
    /// alone, Return (a new line in a document; in a chat app it's the send, decided apart), and cmd with
    /// a/c/v/x/z/s/b/i/u/f/n/t or shift+z. Anything else is the user's.
    /// The same, plus Notes' own cmd+shift+L (Format › Checklist) in Notes.
    func isAllowed(in bundle: String?) -> Bool {
        isAllowed || (bundle == "com.apple.Notes" && modifiers == ["cmd", "shift"] && key == "l")
    }

    var isAllowed: Bool {
        switch (modifiers, key) {
        case ([], let key) where Self.moving.contains(key) || key == "escape" || key == "return": return true
        case (["shift"], "tab"): return true
        case (["cmd"], let key) where Self.editing.contains(key): return true
        case (["cmd", "shift"], "z"): return true
        default: return false
        }
    }
}
