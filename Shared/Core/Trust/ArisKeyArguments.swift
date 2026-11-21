//
//  ArisKeyArguments.swift
//  Shared/Core (aris-agent, tests)
//
//  A capability call's key arguments, read from its JSON arguments or from an aris-tools call's words: who it goes
//  to, what it touches, which app, which command or address, what text it carries, and money. The names a schema
//  uses are matched loosely (to, recipients, cc; path, from, destination; app, bundle; command; url; text, body),
//  and a value's shape settles the ambiguous ones (a "to" that starts with / is a path). Pure.
//

import Foundation

enum ArisKeyArguments {
    static let recipientKeys: Set<String> = ["to", "cc", "bcc", "recipient", "recipients", "email", "emails", "phone", "number", "contact",
                                             "contacts", "chat", "channel", "user", "users", "who", "attendees", "invitees", "share_with", "sharewith"]
    static let pathKeys: Set<String> = ["path", "paths", "file", "files", "from", "source", "destination", "dest", "folder", "in", "cwd", "dir",
                                        "directory", "into", "target", "newpath", "new_path", "output"]
    /// Keys that always name a file or folder (the others in pathKeys only when the value looks like a path).
    static let strictPathKeys: Set<String> = ["path", "paths", "file", "files", "folder", "cwd", "dir", "directory", "newpath", "new_path",
                                              "destination", "dest", "output"]
    static let appKeys: Set<String> = ["app", "application", "bundle", "bundleid", "bundle_id", "appname", "app_name"]
    static let commandKeys: Set<String> = ["command", "cmd", "script", "shell"]
    static let urlKeys: Set<String> = ["url", "link", "href", "uri", "webhook"]
    static let bodyKeys: Set<String> = ["text", "body", "message", "content", "subject", "note", "markdown", "value", "caption", "comment", "title"]
    static let amountKeys: Set<String> = ["amount", "price", "total", "sum", "value_cents", "amount_cents"]
    static let payeeKeys: Set<String> = ["payee", "merchant", "beneficiary", "vendor"]
    /// Arguments that are a count, never money, by capability: `app.scroll`'s "amount" is lines (tenth VM run, item 6: a
    /// scroll was read as a payment with no payee and refused with the payment's words). Only what is listed here.
    static let countKeys: [String: Set<String>] = ["app.scroll": ["amount"]]

    /// The key arguments of JSON arguments. `capability`: its id, so a payment's recipient counts as its payee.
    static func extract(_ arguments: [String: Any], capability: String = "") -> [ArisKeyArgument] {
        let paying = ["pay", "payment", "purchase", "checkout", "transfer", "order"].contains { capability.lowercased().contains($0) }
        var found: [ArisKeyArgument] = []
        for key in arguments.keys.sorted() {
            let name = key.lowercased()
            if countKeys[capability]?.contains(name) == true { continue }
            for value in strings(arguments[key] as Any) where !value.isEmpty {
                if let kind = kind(of: name, value: value, paying: paying) { found.append(ArisKeyArgument(kind: kind, value: String(value.prefix(20_000)))) }
            }
            if let nested = arguments[key] as? [String: Any], !(bodyKeys.contains(name)) {
                found += extract(nested, capability: capability)
            }
        }
        var seen = Set<ArisKeyArgument>()
        return found.filter { seen.insert($0).inserted }
    }

    private static func kind(of name: String, value: String, paying: Bool) -> ArisKeyArgument.Kind? {
        let looksPath = value.hasPrefix("/") || value.hasPrefix("~/") || value == "~"
        let looksURL = value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://")
        if amountKeys.contains(name) { return .amount }
        if payeeKeys.contains(name) || (paying && recipientKeys.contains(name)) { return .payee }
        if commandKeys.contains(name) { return .command }
        if urlKeys.contains(name) || (looksURL && (recipientKeys.contains(name) || pathKeys.contains(name))) { return .url }
        if appKeys.contains(name) { return .app }
        if strictPathKeys.contains(name) || (pathKeys.contains(name) && looksPath) { return .path }
        if recipientKeys.contains(name) { return looksPath ? .path : .recipient }
        if bodyKeys.contains(name) { return .body }
        return nil
    }

    private static func strings(_ value: Any) -> [String] {
        switch value {
        case let text as String: return [text]
        case let list as [Any]: return list.flatMap(strings)
        case let number as NSNumber: return [number.stringValue]
        default: return []
        }
    }

    // MARK: - aris-tools words

    /// The key arguments of an aris-tools call's words (the old catalogue's commands as the registry wraps them).
    static func extract(argv: [String], stdin: String? = nil) -> [ArisKeyArgument] {
        guard let command = argv.first else { return [] }
        var found: [ArisKeyArgument] = []
        let rest = Array(argv.dropFirst())
        var index = 0
        var plain: [String] = []
        while index < rest.count {
            let word = rest[index]
            if word == "--app" || word == "--with", index + 1 < rest.count {
                found.append(ArisKeyArgument(kind: word == "--app" ? .app : .recipient, value: rest[index + 1]))
                index += 2
                continue
            }
            if word.hasPrefix("--") {
                index += word.contains("=") ? 1 : 2
                continue
            }
            plain.append(word)
            index += 1
        }
        switch command {
        case "message":
            if let to = plain.first { found.append(ArisKeyArgument(kind: .recipient, value: to)) }
            if plain.count > 1 { found.append(ArisKeyArgument(kind: .body, value: plain.dropFirst().joined(separator: " "))) }
        case "app", "new", "tile", "window":
            found += plain.filter { !["left", "right", "full", "center"].contains($0) }.map { ArisKeyArgument(kind: .app, value: $0) }
        case "link":
            found += plain.map { ArisKeyArgument(kind: .url, value: $0) }
        case "type", "clipboard", "note", "remember", "remind", "todo":
            let text = plain.filter { $0 != "set" && $0 != "add" }.joined(separator: " ")
            if !text.isEmpty { found.append(ArisKeyArgument(kind: .body, value: text)) }
        case "mcp":
            if plain.count >= 4, let data = plain[3].data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                found += extract(object, capability: plain[2])
            }
        default:
            found += plain.compactMap { word in
                if word.hasPrefix("/") || word.hasPrefix("~/") { return ArisKeyArgument(kind: .path, value: word) }
                if word.lowercased().hasPrefix("https://") || word.lowercased().hasPrefix("http://") { return ArisKeyArgument(kind: .url, value: word) }
                return nil
            }
        }
        if let stdin, !stdin.isEmpty { found.append(ArisKeyArgument(kind: .body, value: stdin)) }
        return found
    }
}
