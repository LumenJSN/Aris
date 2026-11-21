//
//  ArisAPICatalog.swift
//  aris-agent
//
//  aris-tools as function calls for the API brains (cleanroom spec 14, §3.4): a few typed functions that small models
//  call reliably (a timer, the weather, a message…), and the generic `aris(args)` that keeps the whole tool surface.
//  Every call becomes an aris-tools argv, then one shell-quoted command that ArisCommandPolicy.words reads back to the
//  same argv, so it goes through the very same risk gate as Codex's commands: no second policy. A turn heard hands-free
//  is offered only the sealed subset (whose argv can satisfy ArisSealedTools).
//

import Foundation

struct ArisAPICatalogEntry: @unchecked Sendable {
    let function: ArisAPIFunction
    /// In the sealed subset (every argv it makes may pass ArisSealedTools; the driver checks each call anyway).
    let sealed: Bool
    /// The aris-tools words for these arguments; nil when they aren't what the schema says.
    let argv: ([String: Any]) -> [String]?
    /// The text aris-tools reads on stdin (a desktop type or set-value: never in argv).
    var stdin: (([String: Any]) -> String?)? = nil
}

enum ArisAPICatalog {
    static let generic = "aris"

    /// A string argument (a number is taken as its digits; anything else is wrong).
    static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): return number.stringValue
        default: return nil
        }
    }

    static func whole(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == number.doubleValue.rounded() {
            return number.intValue
        }
        return (value as? String).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// The typed functions, in the order offered: the capability registry's (ArisCapabilities.functions), the one source.
    static var entries: [ArisAPICatalogEntry] { ArisCapabilities.functions }

    static func entry(_ name: String) -> ArisAPICatalogEntry? { entries.first { $0.function.name == name } }

    /// The functions a turn is offered: all, or the sealed subset.
    static func functions(sealed: Bool) -> [ArisAPIFunction] {
        entries.filter { !sealed || $0.sealed }.map(\.function)
    }

    static func names(sealed: Bool) -> Set<String> { Set(functions(sealed: sealed).map(\.name)) }

    /// The text a call's aris-tools reads on stdin; nil for a call that takes none.
    static func stdin(name: String, arguments: String) -> String? {
        guard let entry = entry(name), let make = entry.stdin, arguments.utf8.count <= 200_000, let object = ArisAPIDialects.jsonObject(arguments),
              let text = make(object), text.utf8.count <= 131_072, !text.contains("\0") else { return nil }
        return text
    }

    /// The argv for a call: nil for an unknown function or arguments that aren't a JSON object of the right shape.
    static func argv(name: String, arguments: String) -> [String]? {
        guard let entry = entry(name), arguments.utf8.count <= 64_000, let object = ArisAPIDialects.jsonObject(arguments),
              let words = entry.argv(object), !words.isEmpty, words.count <= 64 else { return nil }
        // Every word plain text: a NUL or a carriage return could hide something from a reader of the card.
        guard words.allSatisfy({ !$0.contains("\0") && !$0.contains("\r") && $0.count <= 20_000 }) else { return nil }
        return words
    }

    // MARK: - argv ⇄ command

    private static let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:=+,@%-")

    /// One word as the shell (and ArisCommandPolicy.words) reads it back unchanged: as it is when plain, else in single
    /// quotes, a single quote inside written as '"'"'.
    static func quote(_ word: String) -> String {
        if !word.isEmpty, word.unicodeScalars.allSatisfy(plain.contains) { return word }
        return "'" + word.replacingOccurrences(of: "'", with: #"'"'"'"#) + "'"
    }

    /// The command the risk gate judges and the card shows, for `argv` run by aris-tools at `tools`.
    static func command(tools: String, argv: [String]) -> String {
        ([tools] + argv).map(quote).joined(separator: " ")
    }
}
