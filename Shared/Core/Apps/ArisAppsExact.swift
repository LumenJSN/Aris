//
//  ArisAppsExact.swift
//  Shared/Core/Apps
//
//  Finding exactly what a taught step pressed (fourth VM run, D5: "Format › Wrap to Page" was taught; in a document
//  where that item read "Wrap to Window" the replay pressed it, un-wrapped the document and said it was done). A
//  taught menu step names its item by its exact titles, and by its key equivalent when it had one; a taught press names
//  its control by its exact label. When that exact item or control isn't there now, nothing is pressed: the step
//  fails and says what the app shows instead. A description the model gives is still matched as before.
//  Security review of the fix: exactness is never a second argument beside the target (one that the trust gate didn't
//  rate could have pressed "Pay now" under a target of "Cancel"). It is a mark on the one value that is both rated and
//  pressed: `=` before the label or the menu path, and the menu item's key equivalent in brackets after it
//  ("=Format › Make Plain Text [cmd+shift+t]"). Whoever writes the mark, what is rated is exactly what is pressed.
//  Pure.
//

import Foundation

extension ArisApps {
    enum Exact {
        /// A target or command as a call gives it: the label or path it names, whether it must be found exactly (the
        /// `=` mark of a taught step), and the key equivalent a menu item must have.
        struct Named: Equatable, Sendable {
            let text: String
            let exact: Bool
            let key: String?
        }

        static let mark = "="

        static func parse(_ said: String) -> Named {
            let trimmed = said.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(mark) else { return Named(text: trimmed, exact: false, key: nil) }
            var text = String(trimmed.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
            var key: String?
            if let open = text.range(of: " [", options: .backwards), text.hasSuffix("]") {
                let inside = String(text[open.upperBound..<text.index(before: text.endIndex)])
                if !inside.isEmpty, inside.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" }) {
                    key = inside.lowercased()
                    text = String(text[..<open.lowerBound])
                }
            }
            return Named(text: text, exact: true, key: key)
        }

        /// A taught step's target or command, marked to be found exactly.
        static func marked(_ text: String, key: String? = nil) -> String {
            mark + text + (key.map { $0.isEmpty ? "" : " [\($0)]" } ?? "")
        }

        /// Arguments no call may carry: exactness travels only as the mark on the value that is rated (an `exact` or
        /// `key` beside it would be pressed without being judged).
        static let refusedArguments = ["exact", "key"]

        /// A title or label as it is compared: its words exactly, case included; only the spaces around it, "..." for
        /// "…" and Unicode's composed form don't count.
        static func normal(_ text: String) -> String {
            text.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "...", with: "…")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：")))
        }

        /// A menu item's key equivalent as people write it ("⌘⇧N") in the keys a lesson records ("cmd+shift+n").
        static func keys(shortcut: String) -> String {
            var parts: [String] = []
            var rest = Substring(shortcut)
            let marks: [(Character, String)] = [("⌘", "cmd"), ("⌃", "ctrl"), ("⌥", "opt"), ("⇧", "shift")]
            while let first = rest.first, let mark = marks.first(where: { $0.0 == first }) {
                parts.append(mark.1)
                rest = rest.dropFirst()
            }
            let order = ["cmd", "ctrl", "opt", "shift"]
            return (order.filter(parts.contains) + [rest.lowercased()]).joined(separator: "+")
        }

        enum Menu: Equatable, Sendable {
            case found(Command)
            /// Why nothing was pressed, in the app layer's words.
            case missing(String)
        }

        /// The menu command at exactly `path` ("Format › Wrap to Page"), with key equivalent `key` when one is given.
        static func menu(_ path: String, key: String?, in commands: [Command], app: String) -> Menu {
            let wanted = MenuBar.path(path).map(normal)
            guard let last = wanted.last else { return .missing("that menu item isn't there now in \(app)") }
            let menuCommands = commands.filter { $0.channel == .menu && $0.path != nil }
            if let hit = menuCommands.first(where: { ($0.path ?? []).map(normal) == wanted }) {
                if let key, !key.isEmpty, (hit.keys.map(keys(shortcut:)) ?? "") != key {
                    return .missing("that menu item has another key now in \(app) (\(hit.keys ?? "none")), so it wasn't pressed")
                }
                return .found(hit)
            }
            // What the same menu holds instead: its item most like the one taught.
            let parent = Array(wanted.dropLast())
            let siblings = menuCommands.filter { Array(($0.path ?? []).map(normal).dropLast()) == parent }
            let near = siblings.map { ($0, Commands.score(last, $0)) }.filter { $0.1 >= 0.3 }.max { $0.1 < $1.1 }?.0
            if let near { return .missing("that menu item isn't there now (\(app) shows ‘\(near.title)’ instead)") }
            return .missing("that menu item isn't there now in \(app)")
        }

        /// The elements whose label (or id, or value) is exactly `label`; `prefer`: the roles that win a tie.
        static func controls(_ label: String, in elements: [ReadElement], prefer roles: Set<String> = []) -> Read.Located {
            let wanted = normal(label)
            guard !wanted.isEmpty else { return .none }
            let hits = elements.filter { element in
                [element.label, element.identifier ?? "", element.role == "staticText" ? element.value ?? "" : ""].contains { normal($0) == wanted }
            }
            guard !hits.isEmpty else { return .none }
            if hits.count == 1 { return .one(hits[0]) }
            let preferred = hits.filter { roles.contains($0.role) }
            if preferred.count == 1 { return .one(preferred[0]) }
            return .several(Array((preferred.isEmpty ? hits : preferred).prefix(4)))
        }

        /// The labelled control most like `label` (the most words in common, at least one): what the app shows instead,
        /// said, never pressed.
        static func nearest(_ label: String, in elements: [ReadElement]) -> ReadElement? {
            let wanted = Set(normal(label).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let scored = elements.filter { !$0.label.isEmpty && $0.role != "staticText" && $0.role != "textArea" }.map { element -> (ReadElement, Int) in
                let words = Set(normal(element.label).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                return (element, words.intersection(wanted).count)
            }.filter { $0.1 > 0 }
            return scored.max { $0.1 < $1.1 }?.0
        }

        /// Why a control taught as `label` isn't pressed: it isn't there, and what the app shows that is most like it.
        static func missingControl(_ label: String, near: ReadElement?, app: String) -> String {
            guard let near, !near.label.isEmpty else { return "that control isn't there now in \(app) (nothing labelled ‘\(label)’)" }
            return "that control isn't there now (\(app) shows ‘\(near.label)’ instead)"
        }
    }
}
