//
//  ArisAppsGrounding.swift
//  Shared/Core/Apps
//
//  A click names something that was read (tenth VM run, item 8: the model read a page three times, then asked to press
//  ‘the “역사” link in the 목차 (table of contents) sidebar’; the card went up, the press found nothing by that
//  description, and a second card asked for Cmd+F). The target of a model's click is an element of a read of that app in
//  this turn: its id as the read printed it ("e12"), or its exact name (with its role when the model gives one). A
//  description is refused before any card, with what to do instead. Nothing read, or nothing known of what was read,
//  refuses the same way: a miss is never less strict than a hit. Exactness is compared as a taught step's is
//  (ArisApps.Exact.normal: the words exactly, case included). Pure.
//

import Foundation

extension ArisApps {
    enum Grounding {
        /// One element as a read printed it.
        struct Seen: Equatable, Hashable, Sendable {
            var id: String
            var role: String
            var label: String
        }

        /// What a target names: an id, or a name with the role it was given with.
        struct Named: Equatable, Sendable {
            var id: String?
            var role: String?
            var label: String
        }

        /// The most of a target repeated in a refusal.
        static let quoted = 80

        private static let opening: Set<Character> = ["“", "\"", "‘", "'", "「", "『"]
        private static let closing: Set<Character> = ["”", "\"", "’", "'", "」", "』"]

        // MARK: - What a read printed

        /// The elements in a read's text: one per line of the shape ReadElement.line prints ("[e12] link “역사”",
        /// "[e30] textField “검색” = “고양이” (disabled)"). Any other line is nothing.
        static func lines(_ text: String) -> [Seen] {
            text.split(whereSeparator: \.isNewline).compactMap { line(String($0)) }
        }

        static func line(_ raw: String) -> Seen? {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            guard rest.hasPrefix("["), let close = rest.firstIndex(of: "]") else { return nil }
            let id = String(rest[rest.index(after: rest.startIndex)..<close])
            guard isId(id) else { return nil }
            rest = rest[rest.index(after: close)...].drop(while: { $0 == " " })
            for flag in [" (selected)", " (disabled)"] where rest.hasSuffix(flag) { rest = rest.dropLast(flag.count) }
            let role = String(rest.prefix(while: { $0 != " " }))
            guard !role.isEmpty, role.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
            rest = rest.dropFirst(role.count).drop(while: { $0 == " " })
            guard !rest.isEmpty else { return Seen(id: id, role: role, label: "") }
            // “label” or “label” = “value”; a line with only a value has no name.
            if rest.hasPrefix("= “") { return Seen(id: id, role: role, label: "") }
            guard rest.hasPrefix("“") else { return nil }
            let inside = rest.dropFirst()
            let end = inside.range(of: "” = “")?.lowerBound ?? (inside.hasSuffix("”") ? inside.index(before: inside.endIndex) : nil)
            guard let end else { return nil }
            return Seen(id: id, role: role, label: String(inside[..<end]))
        }

        /// An id as a read prints it: "e12" (a short id) or the engine's own ("elem_12").
        static func isId(_ text: String) -> Bool {
            let digits = text.hasPrefix("elem_") ? text.dropFirst(5) : text.hasPrefix("e") ? text.dropFirst(1) : Substring("")
            return !digits.isEmpty && digits.count <= 9 && digits.allSatisfy(\.isNumber)
        }

        private static func short(_ id: String) -> String { id.hasPrefix("elem_") ? "e" + id.dropFirst(5) : id }

        /// The app and elements of an app.read's result (the outcome's JSON); nil for a read that failed and for
        /// anything that isn't one.
        static func read(_ result: String) -> (app: String, elements: [Seen])? {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(result.utf8))) as? [String: Any], object["ok"] as? Bool == true,
                  let data = object["data"] as? [String: Any], let app = data["app"] as? String, !app.isEmpty,
                  let text = data["text"] as? String else { return nil }
            return (app, lines(text))
        }

        // MARK: - What a target names

        /// A target as a call gives it: "e12", "[e12]", a read's whole line ("[e12] link “역사”": its id), a name
        /// ("역사", "“역사”", a taught step's "=역사"), or a role and a name ("link “역사”", "link 역사": `roles` are the
        /// roles that count, the ones read).
        static func named(_ target: String, roles: Set<String> = []) -> Named {
            var text = Exact.parse(target).text.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
                let id = String(text[text.index(after: text.startIndex)..<close])
                if isId(id) { return Named(id: short(id), role: nil, label: "") }
            }
            if isId(text) { return Named(id: short(text), role: nil, label: "") }
            var role: String?
            if let space = text.firstIndex(of: " "), roles.contains(String(text[..<space])) {
                role = String(text[..<space])
                text = String(text[text.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            }
            if text.count >= 2, let first = text.first, let last = text.last, opening.contains(first), closing.contains(last) {
                text = String(text.dropFirst().dropLast())
            }
            return Named(id: nil, role: role, label: text)
        }

        /// The read elements a target names: by its id, else by exactly its name (and role).
        static func matches(_ target: String, in seen: [Seen]) -> [Seen] {
            let named = named(target, roles: Set(seen.map(\.role)))
            if let id = named.id { return seen.filter { short($0.id) == id } }
            let wanted = Exact.normal(named.label)
            guard !wanted.isEmpty else { return [] }
            return seen.filter { Exact.normal($0.label) == wanted && (named.role == nil || named.role == $0.role) }
        }

        // MARK: - The check

        /// Why a click of `target` in `app` isn't pressed; nil when it names an element that was read. `seen`: what
        /// this turn's reads of that app showed (nil: none, or not known).
        static func check(target: String, app: String, seen: [Seen]?) -> String? {
            guard let seen, !seen.isEmpty else { return readFirst(target: target, app: app, read: false) }
            return matches(target, in: seen).isEmpty ? readFirst(target: target, app: app, read: true) : nil
        }

        /// The refusal: nothing was pressed, and how to name the element. Read by the AI, never spoken.
        static func readFirst(target: String, app: String, read: Bool) -> String {
            let said = target.count > quoted ? String(target.prefix(quoted)) + "…" : target
            let lead = read ? "‘\(said)’ isn't an element that was read from \(app) in this turn" : "\(app) hasn't been read in this turn"
            return "Nothing was pressed: \(lead). Read \(app) first (its part \"controls\" lists what can be pressed, and `find` narrows a long page to a word), "
                + "then name the element by its id (like e12) or its exact name from that read. Never describe it."
        }
    }
}

extension ArisApps.Read {
    /// The elements whose name or value holds `query` (case and width ignored); all of them when nothing is asked for.
    /// A long page read for one word ("역사") is its few lines, not three pages.
    static func matching(_ query: String?, in elements: [ArisApps.ReadElement]) -> [ArisApps.ReadElement] {
        guard let wanted = query?.trimmingCharacters(in: .whitespacesAndNewlines), !wanted.isEmpty else { return elements }
        return elements.filter { element in
            [element.label, element.value ?? ""].contains { $0.range(of: wanted, options: [.caseInsensitive, .widthInsensitive]) != nil }
        }
    }

    /// The elements a target names exactly, as a read printed them: by exactly its name (with its role when given).
    static func exactly(_ target: String, in elements: [ArisApps.ReadElement]) -> [ArisApps.ReadElement] {
        let named = ArisApps.Grounding.named(target, roles: Set(elements.map(\.role)))
        if let id = named.id { return elements.filter { $0.shortId == id } }
        let wanted = ArisApps.Exact.normal(named.label)
        guard !wanted.isEmpty else { return [] }
        return elements.filter { element in
            let shown = element.label.isEmpty && element.role == "staticText" ? element.value ?? "" : element.label
            return ArisApps.Exact.normal(shown) == wanted && (named.role == nil || named.role == element.role)
        }
    }
}
