//
//  ArisFocusReader.swift
//  aris-agent (jv-focus)
//
//  Reads a window's Accessibility tree into the plain shape focus resolution works on (ArisAXNode), within bounds: at
//  most `mostNodes` elements, `deepest` levels, `perNode` children of one element, a value cut to `valueLimit`, and a
//  clock (ArisAXBudget): a slow or hung app gives what was read so far, marked cut. A password field's value is never
//  asked for, and dropped if a source gives it anyway. The elements come from a source (the live one asks
//  Accessibility, ArisFocusLive; the tests give their own), so this part runs in the tests. Foundation only.
//

import Foundation

/// One element's attributes, as a source answers them.
struct ArisFocusElementRead: Equatable {
    var role: String
    var subrole: String?
    var title: String?
    var value: String?
    var label: String?
    var identifier: String?
    var selectedText: String?
    var document: String?
    var url: String?
    /// AXFilename (a file browser's item).
    var filename: String?
    var frame: ArisFocusRect?
    var selected = false
    var editable = false
}

protocol ArisFocusElements {
    associatedtype Element
    /// The element's attributes (`secureKnown`: its role says it is a password field, so its value is not asked); nil
    /// when the app didn't answer in time.
    func read(_ element: Element) -> ArisFocusElementRead?
    func children(_ element: Element) -> [Element]
    /// Whether two references are the same element (the app's focused element against each one read).
    func same(_ a: Element, _ b: Element) -> Bool
    /// The children a list-like element says are selected (AXSelectedChildren, an outline's AXSelectedRows): Finder's
    /// icon view marks its selection there, not always with AXSelected on each item. `role`: the element's.
    func selectedChildren(_ element: Element, role: String) -> [Element]
}

extension ArisFocusElements {
    func selectedChildren(_ element: Element, role: String) -> [Element] { [] }
}

struct ArisFocusReader<Source: ArisFocusElements> {
    static var mostNodes: Int { 900 }
    static var deepest: Int { 30 }
    static var perNode: Int { 200 }
    static var valueLimit: Int { 4_000 }

    let source: Source
    /// True once the time is up or the app stopped answering.
    let exhausted: () -> Bool

    /// The window's tree, and whether the read stopped at a bound.
    func tree(_ window: Source.Element, focused: Source.Element?) -> (tree: ArisAXNode?, cut: Bool) {
        var count = 0, cut = false
        func visit(_ element: Source.Element, depth: Int) -> ArisAXNode? {
            guard count < Self.mostNodes, !exhausted() else { cut = true; return nil }
            guard let read = source.read(element) else { cut = true; return nil }
            count += 1
            let secure = read.role == "AXSecureTextField" || read.subrole == "AXSecureTextField"
            var node = ArisAXNode(read.role, subrole: read.subrole, title: read.title, value: secure ? nil : read.value.map(Self.short),
                                  label: read.label, identifier: read.identifier, selectedText: secure ? nil : read.selectedText.map(Self.short),
                                  document: read.document, url: read.url, filename: read.filename, frame: read.frame,
                                  focused: focused.map { source.same($0, element) } ?? false, selected: read.selected, editable: read.editable)
            guard depth < Self.deepest else { cut = true; return node }
            let children = source.children(element)
            if children.count > Self.perNode { cut = true }
            let chosen = Self.selectionHolders.contains(read.role) ? source.selectedChildren(element, role: read.role) : []
            for child in children.prefix(Self.perNode) {
                guard var inner = visit(child, depth: depth + 1) else { if count >= Self.mostNodes || exhausted() { break } else { continue } }
                if !inner.selected, chosen.contains(where: { source.same($0, child) }) { inner.selected = true }
                node.children.append(inner)
            }
            return node
        }
        let tree = visit(window, depth: 0)
        return (tree, cut)
    }

    /// The roles whose selected children are asked for: lists, outlines, tables, collections and the plain group
    /// Finder's icon view is.
    static var selectionHolders: Set<String> { ArisAXNode.listRoles.union(["AXGroup"]) }

    static func short(_ text: String) -> String { text.count > valueLimit ? String(text.prefix(valueLimit)) : text }
}
