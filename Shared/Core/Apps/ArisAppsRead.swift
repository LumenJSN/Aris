//
//  ArisAppsRead.swift
//  Shared/Core/Apps
//
//  app.read: an app's window as structured text the model can refer to. The engine's look (its `ui_elements`, each
//  with an id, role, label, value and frame) becomes one line per element with a short id ("e12"), roles and labels
//  kept; a part of it can be asked for (the focused field, the selection, the document, a list or table, the visible
//  conversation of a chat app); the text is bounded and says where to continue. app.type/click/select/scroll name
//  elements by these ids, or by a description matched against the last read. Pure.
//

import Foundation

extension ArisApps {
    struct ReadElement: Equatable, Sendable {
        var id: String
        var role: String
        var label: String
        var value: String?
        var enabled = true
        var actionable = false
        var selected = false
        var selectionLength = 0
        /// The selected text's range in `value` (UTF-16), when the engine gave one.
        var selectionRange: (location: Int, length: Int)?
        var frame: (x: Double, y: Double, width: Double, height: Double)?
        var identifier: String?

        static func == (lhs: ReadElement, rhs: ReadElement) -> Bool {
            lhs.id == rhs.id && lhs.role == rhs.role && lhs.label == rhs.label && lhs.value == rhs.value && lhs.enabled == rhs.enabled
                && lhs.actionable == rhs.actionable && lhs.selected == rhs.selected
        }

        /// The short id the model uses: the engine's "elem_12" as "e12".
        var shortId: String { id.hasPrefix("elem_") ? "e" + id.dropFirst(5) : id }

        /// From the engine's element dictionary.
        init?(_ json: JSON) {
            guard let id = json["id"]?.string else { return nil }
            self.id = id
            role = json["role"]?.string ?? "other"
            label = json["label"]?.string ?? ""
            value = json["value"]?.string
            enabled = json["is_enabled"]?.bool ?? true
            actionable = json["is_actionable"]?.bool ?? false
            selected = json["is_selected"]?.bool ?? false
            selectionLength = json["selected_text_range"]?["length"]?.int ?? 0
            if let location = json["selected_text_range"]?["location"]?.int, let length = json["selected_text_range"]?["length"]?.int {
                selectionRange = (location, length)
            }
            identifier = json["identifier"]?.string
            if let bounds = json["bounds"], let x = bounds["x"]?.number, let y = bounds["y"]?.number {
                frame = (x, y, bounds["width"]?.number ?? 0, bounds["height"]?.number ?? 0)
            }
        }

        init(id: String, role: String, label: String, value: String? = nil, actionable: Bool = false, frame: (Double, Double, Double, Double)? = nil) {
            self.id = id
            self.role = role
            self.label = label
            self.value = value
            self.actionable = actionable
            self.frame = frame.map { (x: $0.0, y: $0.1, width: $0.2, height: $0.3) }
        }

        static let textRoles: Set<String> = ["textField", "textArea", "searchField", "comboBox", "secureTextField"]

        /// The selected text of a field holding `value`, by its range (UTF-16): "" when nothing is selected; nil when it
        /// can't be told (no range, or a range that isn't inside the text as read).
        static func selected(in value: String?, range: (location: Int, length: Int)?) -> String? {
            guard let range, range.location >= 0, range.length >= 0 else { return nil }
            if range.length == 0 { return "" }
            let units = Array((value ?? "").utf16)
            guard range.location + range.length <= units.count else { return nil }
            return String(utf16CodeUnits: Array(units[range.location..<(range.location + range.length)]), count: range.length)
        }
        var isText: Bool { Self.textRoles.contains(role) }

        /// One line: "[e12] button “Send”", "[e4] textArea “Message” = “hi”" (secure fields never show a value).
        func line(valueLimit: Int = 300) -> String {
            var text = "[\(shortId)] \(role)"
            // A static text's words are its value: shown as its label, as the engine does.
            let label = self.label.isEmpty && role == "staticText" ? (value ?? "") : self.label
            if !label.isEmpty { text += " “\(label.prefix(160))”" }
            if let value, !value.isEmpty, role != "secureTextField", value != label {
                let shown = value.count > valueLimit ? String(value.prefix(valueLimit)) + "…" : value
                text += " = “\(shown.replacingOccurrences(of: "\n", with: "⏎"))”"
            }
            if !enabled { text += " (disabled)" }
            if selected { text += " (selected)" }
            return text
        }
    }

    enum Read {
        enum Part: String, CaseIterable, Sendable {
            case all, focused, selection, document, list, table, conversation, controls
        }

        struct Page: Equatable, Sendable {
            var text: String
            var shown: Int
            var total: Int
            /// Where to continue (`offset`), nil when everything was shown.
            var next: Int?
        }

        /// The elements of one part of the window, in reading order (top to bottom, left to right).
        static func pick(_ part: Part, from elements: [ReadElement], focusedFrame: (Double, Double)? = nil) -> [ReadElement] {
            let ordered = readingOrder(elements)
            switch part {
            case .all: return ordered
            case .controls: return ordered.filter { $0.actionable || $0.isText }
            case .focused:
                guard let focusedFrame, let index = ordered.firstIndex(where: { $0.frame.map { abs($0.x - focusedFrame.0) < 1 && abs($0.y - focusedFrame.1) < 1 } ?? false })
                else { return ordered.filter(\.isText).prefix(1).map { $0 } }
                return Array(ordered[max(0, index - 6)...min(ordered.count - 1, index + 6)])
            case .selection: return ordered.filter { $0.selected || $0.selectionLength > 0 }
            case .document: return ordered.filter { ["textArea", "webArea", "staticText", "heading", "link"].contains($0.role) && !($0.value ?? $0.label).isEmpty }
            case .list:
                let rows = ordered.filter { ["row", "cell", "outlineRow", "listItem"].contains($0.role) }
                return rows.isEmpty ? ordered.filter { $0.role == "staticText" } : rows
            case .table: return ordered.filter { ["table", "row", "cell", "column", "header", "staticText", "textField"].contains($0.role) }
            case .conversation: return conversation(ordered)
            }
        }

        /// Top to bottom, then left to right (the engine lists breadth first); elements without a frame keep their place last.
        static func readingOrder(_ elements: [ReadElement]) -> [ReadElement] {
            let placed = elements.filter { $0.frame != nil }.sorted { a, b in
                let ay = a.frame!.y, by = b.frame!.y
                if abs(ay - by) > 4 { return ay < by }
                return a.frame!.x < b.frame!.x
            }
            return placed + elements.filter { $0.frame == nil }
        }

        /// A chat app's visible conversation: the words right of the sidebar (the left quarter of the window) and above
        /// the field you write in, top to bottom.
        static func conversation(_ ordered: [ReadElement]) -> [ReadElement] {
            let framed = ordered.filter { $0.frame != nil }
            guard let left = framed.map({ $0.frame!.x }).min(), let right = framed.map({ $0.frame!.x + $0.frame!.width }).max() else {
                return ordered.filter { $0.role == "staticText" }
            }
            let width = right - left
            let field = framed.filter { $0.isText && $0.role != "secureTextField" }.max { $0.frame!.y < $1.frame!.y }
            let bottom = field?.frame?.y ?? .greatestFiniteMagnitude
            return framed.filter { element in
                ["staticText", "textArea", "link", "image", "group"].contains(element.role) && !(element.value ?? element.label).isEmpty
                    && element.frame!.x >= left + width * 0.25 && element.frame!.y < bottom && element.id != field?.id
            } + (field.map { [$0] } ?? [])
        }

        /// The lines from `offset`, as many as fit in `limit` characters.
        static func page(_ elements: [ReadElement], offset: Int = 0, limit: Int = 6_000) -> Page {
            let start = max(0, min(offset, elements.count))
            var lines: [String] = [], used = 0, index = start
            while index < elements.count {
                let line = elements[index].line()
                if used + line.count + 1 > limit, !lines.isEmpty { break }
                lines.append(line)
                used += line.count + 1
                index += 1
            }
            return Page(text: lines.joined(separator: "\n"), shown: lines.count, total: elements.count, next: index < elements.count ? index : nil)
        }

        // MARK: - Naming an element

        enum Located: Equatable, Sendable {
            case one(ReadElement)
            case several([ReadElement])
            case none
        }

        /// The element a target names: a short id ("e12"), the engine's id, or a description ("보내기 버튼", "the message
        /// field") matched on label, value, identifier and role.
        static func locate(_ target: String, in elements: [ReadElement], prefer roles: Set<String> = []) -> Located {
            let trimmed = target.trimmingCharacters(in: .whitespaces)
            if let exact = elements.first(where: { $0.shortId == trimmed || $0.id == trimmed }) { return .one(exact) }
            // Exactly an element's name as a read printed it (ArisAppsGrounding), before any description is scored: one is
            // that element, several are asked about, never picked among.
            let named = exactly(trimmed, in: elements)
            if named.count == 1 { return .one(named[0]) }
            if named.count > 1 {
                let preferred = named.filter { roles.contains($0.role) }
                return preferred.count == 1 ? .one(preferred[0]) : .several(Array((preferred.isEmpty ? named : preferred).prefix(4)))
            }
            let words = Lexicon.units(trimmed)
            guard !words.isEmpty else { return .none }
            let roleWords: [String: Set<String>] = [
                "button": ["button", "버튼"], "textField": ["field", "칸", "입력", "입력창", "필드", "box"], "textArea": ["field", "칸", "입력창", "editor", "본문"],
                "searchField": ["search", "검색", "검색창"], "checkBox": ["checkbox", "체크박스", "체크"], "link": ["link", "링크"],
                "row": ["row", "줄", "행", "item", "항목"], "tab": ["tab", "탭"], "popUpButton": ["menu", "popup", "메뉴"],
            ]
            let asked = Set(words.flatMap(Lexicon.meanings))
            let scored = elements.map { element -> (ReadElement, Double) in
                let named = Lexicon.terms([element.label, element.value ?? "", element.identifier ?? ""].joined(separator: " "))
                let meanings = Set(named.flatMap(Lexicon.meanings))
                var score = 0.0
                for word in words {
                    if named.contains(word) { score += 1 }
                    else if !Lexicon.meanings(word).isDisjoint(with: meanings) { score += 0.8 }
                    else if named.contains(where: { $0.count >= 2 && ($0.hasPrefix(word) || word.hasPrefix($0)) }) { score += 0.5 }
                    else if roleWords[element.role]?.contains(word) == true { score += 0.4 }
                }
                if !asked.isEmpty, asked.isSubset(of: meanings) { score += 0.3 }
                if roles.contains(element.role) { score += 0.3 }
                if !element.enabled { score -= 0.3 }
                return (element, score / Double(words.count))
            }.filter { $0.1 >= 0.5 }.sorted { $0.1 > $1.1 }
            guard let best = scored.first else { return .none }
            let close = scored.filter { $0.1 >= best.1 - 0.1 }
            return close.count == 1 ? .one(best.0) : .several(close.prefix(4).map(\.0))
        }
    }
}
