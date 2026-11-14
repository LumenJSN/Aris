//
//  ArisDesktopObservation.swift
//  aris-agent
//
//  One look at one window (`peekaboo see --window-id`), as Aris keeps it and as a brain reads it: Aris's own short
//  snapshot id (its refs are `@<id>:e<N>`), Peekaboo's snapshot id (never shown), the app and the exact window, the
//  elements after the privacy filter, and any text marks read from the screen. Rendered compactly: one line per
//  control or piece of text, generic containers and the window's own buttons left out. Pure.
//

import CoreGraphics
import Foundation

struct ArisDesktopObservation {
    /// Aris's id (refs are `@<snapshot>:e<N>`).
    let snapshot: String
    /// Peekaboo's `ps1_…` id: what Aris acts with, never shown.
    let peekaboo: String
    let target: ArisDesktopTarget
    let window: Int
    let title: String
    let elements: [ArisDesktopElement]
    /// Text read from the screen (Apple Vision), `@<snapshot>:t<N>`, with boxes in screen points.
    var marks: [ArisDesktopElement] = []
    let focused: CGRect?
    /// The focused element's AX role as Peekaboo read it (AXSecureTextField: a password field has the focus).
    var focusedRole: String? = nil
    let isDialog: Bool
    /// The privacy filter hid something, and where (a sidebar of the user's places: no text is read there either).
    let hidden: Bool
    var hiddenRegions: [CGRect] = []
    /// Why this isn't the window the brain asked about (the front one couldn't be read: its parent).
    var note: String? = nil
    var taken = Date()
    /// The window's frame (global points) when the look was taken: positions are compared relative to it, so a window
    /// that only moved isn't a changed control (I4).
    var frame: CGRect? = nil
    /// Peekaboo listed more elements than were kept (ArisDesktopEnvelope.elementsTruncated).
    var truncated = false

    /// Where an element sits inside the window (its top-left, window-relative when the frame is known).
    func position(of element: ArisDesktopElement) -> CGPoint {
        CGPoint(x: element.bounds.minX - (frame?.minX ?? 0), y: element.bounds.minY - (frame?.minY ?? 0))
    }

    /// Which of System Settings' tiers the pane this look shows is in (ArisSettingsPane).
    var settingsPane: ArisSettingsPane { ArisSettingsPane.of(self) }

    /// The element that has the focus, if the look shows one.
    var focusedElement: ArisDesktopElement? { elements.first(where: isFocused) }

    /// A password field has the focus (its role, or the focused element's) (I6).
    var focusIsSecure: Bool { focusedRole == "AXSecureTextField" || focusedElement?.isSecure == true }

    /// The field a send would carry in a sending app (I1, re-review 4): `element` itself when it takes text; for a control
    /// (a send button) the message field nearest it; else the focused one, else the window's only one. A search field is
    /// never the message field.
    func composer(for element: ArisDesktopElement?) -> ArisDesktopElement? {
        if let element, element.isTextEntry { return elements.first { $0.id == element.id } ?? element }
        let fields = elements.filter { $0.isTextEntry && !$0.isSearch }
        if let element, element.bounds.width > 0 {
            return fields.min { Self.distance($0, element) < Self.distance($1, element) }
        }
        if let focused = focusedElement, focused.isTextEntry, !focused.isSearch { return focused }
        return fields.count == 1 ? fields[0] : nil
    }

    /// The gap between two controls' frames (points; 0 when they touch or overlap).
    static func distance(_ one: ArisDesktopElement, _ other: ArisDesktopElement) -> CGFloat {
        let dx = max(0, max(one.bounds.minX - other.bounds.maxX, other.bounds.minX - one.bounds.maxX))
        let dy = max(0, max(one.bounds.minY - other.bounds.maxY, other.bounds.minY - one.bounds.maxY))
        return hypot(dx, dy)
    }

    /// Any text the window shows besides `field` (a chat's messages, its title rows): what a field that can't be read is
    /// confirmed from.
    func showsText(besides field: ArisDesktopElement?) -> Bool {
        shown.contains { $0.id != field?.id && (!$0.label.isEmpty || !($0.rawValue ?? "").isEmpty) && !Self.windowButtons.contains($0.label) }
    }

    /// The element a ref names in this observation.
    func element(_ ref: ArisDesktopRef) -> ArisDesktopElement? {
        ref.mark ? marks.first { $0.number == ref.element } : elements.first { $0.number == ref.element }
    }

    /// The element with this Peekaboo id.
    func element(id: String) -> ArisDesktopElement? { elements.first { $0.id == id } }

    func ref(_ element: ArisDesktopElement) -> String {
        "@\(snapshot):\(element.id.hasPrefix("ocr_") ? "t" : "e")\(element.number ?? 0)"
    }

    /// Whether the field is the window's focused element.
    func isFocused(_ element: ArisDesktopElement) -> Bool {
        guard let focused else { return false }
        return abs(focused.minX - element.bounds.minX) < 2 && abs(focused.minY - element.bounds.minY) < 2
            && abs(focused.width - element.bounds.width) < 2 && abs(focused.height - element.bounds.height) < 2
    }

    // MARK: - What a brain reads

    /// Containers and window chrome a brain never needs (a scroll area stays: it is what scroll acts on).
    static let generic: Set<String> = ["group", "cell", "outline row", "column", "split group", "toolbar", "row", "close button", "minimize button",
                                       "full screen button", "zoom button", "text field"]
    static let windowButtons: Set<String> = ["close button", "minimize button", "full screen button", "zoom button"]

    /// The elements a brain sees: everything but generic containers with nothing to say and the window's own buttons.
    var shown: [ArisDesktopElement] {
        elements.filter { element in
            if Self.windowButtons.contains(element.label) { return false }
            if element.role == "group" || (element.role == "other" && Self.generic.contains(element.label)) { return (element.value ?? "").isEmpty == false }
            return true
        }
    }

    /// A tree too poor to act on: almost nothing a brain could press or type into.
    var isPoor: Bool {
        let acting = shown.filter { $0.actionable || ["button", "textField", "textArea", "checkbox", "radioButton", "popUpButton", "comboBox", "slider", "link", "menuButton"].contains($0.role) }
        return acting.count <= 1 && marks.isEmpty
    }

    static let poorLine = "This window shows almost nothing to accessibility (a canvas or a custom-drawn view). `desktop see --app \"<App>\" --ocr` " +
        "adds the text on screen as @…:tN marks with their boxes (click one), or `desktop click-at --app \"<App>\" --target \"<what>\"` " +
        "has Aris look at the window and click it."

    /// The same with no brain that can look at a picture set up: the text on screen only.
    static let poorLineTextOnly = "This window shows almost nothing to accessibility (a canvas or a custom-drawn view). `desktop see --app \"<App>\" --ocr` " +
        "adds the text on screen as @…:tN marks with their boxes (click one)."

    /// The controls (and text marks) whose name or value holds every one of `words` (any case), the first `max` of
    /// them; and how many there were in all. A huge window's listing, cut down to what the brain looks for.
    func matching(_ words: String, max: Int) -> (elements: [ArisDesktopElement], marks: [ArisDesktopElement], total: Int) {
        let wanted = words.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let holds = { (element: ArisDesktopElement) -> Bool in
            let said = (element.label + " " + (element.value ?? "")).lowercased()
            return !wanted.isEmpty && wanted.allSatisfy(said.contains)
        }
        let elements = shown.filter(holds), marks = self.marks.filter(holds)
        let kept = Array(elements.prefix(max))
        return (kept, Array(marks.prefix(Swift.max(0, max - kept.count))), elements.count + marks.count)
    }

    /// `poor`: what a poor tree says next, when not the default (the user picked another engine: ArisDesktopFallback).
    /// `find`: only the controls holding these words, at most `max` (`see --find`); the refs are the look's own.
    func render(limit: Int = 30_000, poor: String? = nil, find: String? = nil, max: Int = ArisDesktopObservation.findMax) -> String {
        var lines = ["\(target.name) · window \(window) “\(title)”\(isDialog ? " (a dialog)" : "") · see \(snapshot)"]
        if let note { lines.append(note) }
        let found = find.map { matching($0, max: max) }
        if let found, let find {
            lines.append("Only the controls holding “\(ArisDesktopCard.shown(find))”: \(min(found.total, max)) of \(found.total) shown (the window has \(shown.count + marks.count) in all).")
        }
        for element in found?.elements ?? shown {
            var line = "\(ref(element)) \(element.role)"
            if !element.label.isEmpty { line += " “\(ArisDesktopCard.shown(String(element.label.prefix(160))))”" }
            if let value = element.value, !value.isEmpty, value != element.label { line += " value=“\(ArisDesktopCard.shown(value))”" }
            if element.role == "textField" || element.role == "textArea", (element.value ?? "").isEmpty { line += " (empty)" }
            if isFocused(element) { line += " (focused)" }
            if !element.enabled { line += " (disabled)" }
            lines.append(line)
        }
        for mark in found?.marks ?? marks {
            let box = mark.bounds
            let round = { (value: CGFloat) in Int(value.rounded()) }
            lines.append("\(ref(mark)) text “\(ArisDesktopCard.shown(mark.label))” at \(round(box.minX)),\(round(box.minY)) \(round(box.width))×\(round(box.height))")
        }
        if hidden { lines.append(ArisDesktopPrivacy.hiddenLine) }
        if isPoor, found == nil { lines.append(poor ?? Self.poorLine.replacingOccurrences(of: "<App>", with: target.name)) }
        let text = lines.joined(separator: "\n")
        return text.count > limit ? String(text.prefix(limit)) + "\n(cut: the window has more)" : text
    }

    /// How many controls `see --find` lists when no --max is given.
    static let findMax = 40

    // MARK: - Making one

    /// Aris's short ids: `s` and five letters or digits.
    static func newId() -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return "s" + String((0..<5).map { _ in alphabet.randomElement()! })
    }

    /// The observation for a `see` envelope (nil when it isn't one), filtered for privacy.
    static func make(_ envelope: ArisDesktopEnvelope, target: ArisDesktopTarget, window: Int, identity: ArisDesktopIdentity,
                     id: String = newId()) -> ArisDesktopObservation? {
        guard envelope.success, let peekaboo = envelope.snapshotId else { return nil }
        let (elements, hidden, regions) = ArisDesktopPrivacy.filter(envelope.elements, identity)
        return ArisDesktopObservation(snapshot: id, peekaboo: peekaboo, target: target, window: envelope.windowId ?? window,
                                      title: ArisDesktopPrivacy.redact(envelope.windowTitle ?? "", identity), elements: elements,
                                      focused: envelope.focusedFrame, focusedRole: envelope.focusedRole, isDialog: envelope.isDialog, hidden: hidden,
                                      hiddenRegions: regions, truncated: envelope.elementsTruncated)
    }
}
