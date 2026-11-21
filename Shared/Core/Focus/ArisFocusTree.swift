//
//  ArisFocusTree.swift
//  Shared/Core/Focus (aris-agent, app, tests)
//
//  An app's window as Accessibility shows it, as a plain value: one node per element with the few attributes focus
//  resolution needs (role, words, selection, document, frame, focused, selected, editable). The helper reads the real
//  tree into this shape (ArisAgent/Focus/ArisFocusLive.swift, bounded in nodes, depth and time); the tests write their
//  own trees. Roles are Accessibility's own strings ("AXTextArea"). A password field's value is never kept: the live
//  reader never asks for it and `words` would drop it anyway. Coordinates are Quartz global points (origin at the top
//  left of the main display), as Accessibility, CGEvent and the circle gesture give them. Foundation only.
//

import Foundation

struct ArisFocusPoint: Equatable, Sendable, Codable {
    var x: Double
    var y: Double
}

struct ArisFocusRect: Equatable, Sendable, Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var area: Double { max(0, width) * max(0, height) }
    var center: ArisFocusPoint { ArisFocusPoint(x: x + width / 2, y: y + height / 2) }

    func contains(_ point: ArisFocusPoint) -> Bool {
        point.x >= x && point.x < x + width && point.y >= y && point.y < y + height
    }

    /// The area both rectangles cover.
    func overlap(_ other: ArisFocusRect) -> Double {
        let left = max(x, other.x), right = min(x + width, other.x + other.width)
        let top = max(y, other.y), bottom = min(y + height, other.y + other.height)
        return right > left && bottom > top ? (right - left) * (bottom - top) : 0
    }

    /// How much of this rectangle lies inside `other`, 0 to 1 (a point-sized one: whether its centre does).
    func shareInside(_ other: ArisFocusRect) -> Double {
        guard area > 0 else { return other.contains(center) ? 1 : 0 }
        return overlap(other) / area
    }
}

/// One element of a window.
struct ArisAXNode: Equatable, Sendable, Codable {
    var role: String
    var subrole: String?
    var title: String?
    var value: String?
    /// AXDescription.
    var label: String?
    var identifier: String?
    /// AXSelectedText, for a text element with a selection.
    var selectedText: String?
    /// AXDocument: the file a window or editor shows (a file URL or a path).
    var document: String?
    /// AXURL: the page a web area shows, or the file an item of a file browser is (Finder's icons and rows).
    var url: String?
    /// AXFilename: the file name an item of a file browser shows (Finder's icon view).
    var filename: String?
    var frame: ArisFocusRect?
    /// This is the app's focused element.
    var focused = false
    /// AXSelected (a row, a cell, a tab).
    var selected = false
    /// Its value can be set (a field or editor that takes typing).
    var editable = false
    var children: [ArisAXNode] = []

    init(_ role: String, subrole: String? = nil, title: String? = nil, value: String? = nil, label: String? = nil,
         identifier: String? = nil, selectedText: String? = nil, document: String? = nil, url: String? = nil,
         filename: String? = nil, frame: ArisFocusRect? = nil, focused: Bool = false, selected: Bool = false, editable: Bool = false,
         children: [ArisAXNode] = []) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.value = value
        self.label = label
        self.identifier = identifier
        self.selectedText = selectedText
        self.document = document
        self.url = url
        self.filename = filename
        self.frame = frame
        self.focused = focused
        self.selected = selected
        self.editable = editable
        self.children = children
    }

    // MARK: - Roles

    static let textEntryRoles: Set<String> = ["AXTextArea", "AXTextField", "AXSearchField", "AXComboBox"]
    static let singleLineRoles: Set<String> = ["AXTextField", "AXSearchField", "AXComboBox"]
    static let rowRoles: Set<String> = ["AXRow", "AXCell", "AXOutlineRow"]
    static let listRoles: Set<String> = ["AXOutline", "AXTable", "AXList", "AXBrowser", "AXCollection"]

    var isSecure: Bool { role == "AXSecureTextField" || subrole == "AXSecureTextField" }
    var isTextEntry: Bool { !isSecure && Self.textEntryRoles.contains(role) }
    var isSingleLine: Bool { Self.singleLineRoles.contains(role) }
    var isRow: Bool { Self.rowRoles.contains(role) }
    /// The file this element is, by its AXURL (a file URL), as a path.
    var filePath: String? {
        guard let url, url.hasPrefix("file:"), let parsed = URL(string: url), parsed.isFileURL else { return nil }
        return parsed.path
    }
    /// It names a file of a file browser (its AXURL is a file, or it has an AXFilename).
    var isFileItem: Bool { filePath != nil || !(filename ?? "").isEmpty }

    /// What the element says, each piece once: its title, its value (never a password field's), its description.
    var words: [String] {
        let pieces = isSecure ? [title, label] : [title, value, label]
        var seen: [String] = []
        for piece in pieces.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !piece.isEmpty && !seen.contains(piece) {
            seen.append(piece)
        }
        return seen
    }

    // MARK: - Walking

    /// Every node with its index path from this one, depth first, this one first.
    func walk(_ path: [Int] = [], _ visit: (ArisAXNode, [Int]) -> Void) {
        visit(self, path)
        for (index, child) in children.enumerated() { child.walk(path + [index], visit) }
    }

    func node(at path: [Int]) -> ArisAXNode? {
        var current = self
        for index in path {
            guard current.children.indices.contains(index) else { return nil }
            current = current.children[index]
        }
        return current
    }

    /// The nodes from this one down to `path`, this one first.
    func chain(to path: [Int]) -> [ArisAXNode] {
        var current = self, nodes = [self]
        for index in path {
            guard current.children.indices.contains(index) else { break }
            current = current.children[index]
            nodes.append(current)
        }
        return nodes
    }

    func paths(where match: (ArisAXNode) -> Bool) -> [[Int]] {
        var found: [[Int]] = []
        walk { node, path in if match(node) { found.append(path) } }
        return found
    }

    func firstPath(where match: (ArisAXNode) -> Bool) -> [Int]? { paths(where: match).first }

    /// The deepest node whose frame holds the point (the window itself only when nothing inside it does).
    func deepestPath(at point: ArisFocusPoint) -> [Int]? {
        guard frame?.contains(point) ?? true else { return nil }
        for (index, child) in children.enumerated().reversed() {
            if child.frame?.contains(point) == true, let inner = child.deepestPath(at: point) { return [index] + inner }
        }
        // A child without a frame (a group Accessibility didn't place) is looked through.
        for (index, child) in children.enumerated() where child.frame == nil {
            if let inner = child.deepestPath(at: point), !inner.isEmpty || !child.words.isEmpty { return [index] + inner }
        }
        return frame == nil ? nil : []
    }

    /// The words of this node and everything in it, in tree order, each line once, cut at `limit` characters.
    func text(limit: Int = 4_000) -> String {
        var lines: [String] = [], used = 0
        walk { node, _ in
            guard used < limit else { return }
            for piece in node.words where lines.last != piece && !(lines.last ?? "").contains(piece) {
                lines.append(piece)
                used += piece.count + 1
            }
        }
        let joined = lines.joined(separator: "\n")
        return joined.count > limit ? String(joined.prefix(limit)) + "…" : joined
    }

    /// The nodes with words whose frames lie mostly inside `rect` (`share` of their area), outermost first: a node
    /// counted keeps its children out, so each word comes once.
    func paths(inside rect: ArisFocusRect, share: Double = 0.5) -> [[Int]] {
        var found: [[Int]] = []
        func visit(_ node: ArisAXNode, _ path: [Int]) {
            if let frame = node.frame, frame.shareInside(rect) >= share, !node.text(limit: 1).isEmpty, node.role != "AXWindow" {
                found.append(path)
                return
            }
            if let frame = node.frame, frame.overlap(rect) == 0, frame.area > 0 { return }
            for (index, child) in node.children.enumerated() { visit(child, path + [index]) }
        }
        visit(self, [])
        return found
    }
}
