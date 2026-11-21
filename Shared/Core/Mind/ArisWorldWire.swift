//
//  ArisWorldWire.swift
//  Shared/Core (Aris app, aris-agent, tests)
//
//  The app's World as it reaches the helper (ARCHITECTURE Part 2: World and Judgment), on each conversation turn's
//  POST /ask (its `world` field, only while the helper says Core 2 is on): the app in front, the contacts the app may
//  already read (only with the Contacts permission already granted: Aris never asks for it here), and the apps'
//  nicknames it knows. The helper maps it into the trust gate's facts (ArisMindWorld.facts), so "엄마한테 보내 줘"
//  is grounded by the contact named 엄마, not only by the literal word. Nothing here is shown to a model, and nothing
//  private beyond names and addresses travels: never a window's title, the selection or the screen. Every value is
//  checked and cut on the way in (the helper takes it only from the Aris app itself). Pure.
//

import Foundation

enum ArisWorldWire {
    static let mostContacts = 3_000
    static let mostNames = 8
    static let mostApps = 400
    static let longest = 120

    struct Payload: Equatable, Sendable {
        var frontApp: String?
        var frontBundle: String?
        var contacts: [ArisWorldFacts.Contact] = []
        var apps: [String: [String]] = [:]
    }

    // MARK: - The app's side

    static func encode(_ payload: Payload) -> [String: Any] {
        var object: [String: Any] = [:]
        if let front = payload.frontApp { object["frontApp"] = front }
        if let bundle = payload.frontBundle { object["frontBundle"] = bundle }
        object["contacts"] = payload.contacts.prefix(mostContacts).map { contact -> [String: Any] in
            ["name": contact.name, "aliases": Array(contact.aliases.prefix(mostNames)), "addresses": Array(contact.addresses.prefix(mostNames))]
        }
        object["apps"] = Dictionary(payload.apps.prefix(mostApps).map { ($0.key, Array($0.value.prefix(mostNames))) }) { first, _ in first }
        return object
    }

    /// The app nicknames as the app's intent table has them (nickname → app), turned to app → nicknames.
    static func apps(fromAliases aliases: [String: String]) -> [String: [String]] {
        var apps: [String: [String]] = [:]
        for (nickname, app) in aliases.sorted(by: { $0.key < $1.key }) { apps[app, default: []].append(nickname) }
        return apps
    }

    // MARK: - The helper's side

    /// The payload, every value checked; nil for anything that isn't one.
    static func decode(_ raw: Any?) -> Payload? {
        guard let object = raw as? [String: Any] else { return nil }
        var payload = Payload()
        payload.frontApp = clean(object["frontApp"])
        payload.frontBundle = clean(object["frontBundle"])
        for item in ((object["contacts"] as? [Any]) ?? []).prefix(mostContacts) {
            guard let contact = item as? [String: Any], let name = clean(contact["name"]) else { continue }
            let aliases = ((contact["aliases"] as? [Any]) ?? []).prefix(mostNames).compactMap(clean)
            let addresses = ((contact["addresses"] as? [Any]) ?? []).prefix(mostNames).compactMap(clean)
            payload.contacts.append(ArisWorldFacts.Contact(name: name, aliases: aliases, addresses: addresses))
        }
        for (app, names) in ((object["apps"] as? [String: Any]) ?? [:]).prefix(mostApps) {
            guard let app = clean(app) else { continue }
            payload.apps[app] = ((names as? [Any]) ?? []).prefix(mostNames).compactMap(clean)
        }
        return payload
    }

    /// One plain value: a string, no control characters, trimmed, at most `longest` characters; nil when empty.
    static func clean(_ raw: Any?) -> String? {
        guard let text = raw as? String else { return nil }
        let plain = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !(0x202A...0x202E).contains($0.value)
                && !(0x2066...0x2069).contains($0.value) }.map(Character.init)).trimmingCharacters(in: .whitespaces)
        guard !plain.isEmpty, plain.count <= longest else { return nil }
        return plain
    }
}
