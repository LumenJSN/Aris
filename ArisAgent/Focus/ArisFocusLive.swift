//
//  ArisFocusLive.swift
//  aris-agent (jv-focus)
//
//  The live half of F4: the window a look reads (ArisLook.gather), read through Accessibility into a tree (bounded:
//  ArisFocusReader), with the app's focused element, where the pointer is and what was circled this turn; resolved
//  against the owner's words (ArisFocusResolver) and kept on the desk for the rest of the turn, where Judgment's
//  focus hook reads it (ArisTrustGate's world, with `arisCore2` on). Accessibility only: nothing here captures the
//  screen, asks macOS for a permission, moves the pointer or presses a key; without Accessibility nothing is read.
//

import ApplicationServices
import Foundation

/// The live source: an app's elements, each asked with a short timeout, several attributes in one round trip.
struct ArisFocusAXSource: ArisFocusElements {
    /// Seconds one element may take (a whole look stops at its clock: ArisFocusLive.limit).
    static let perCall: Float = 0.25
    private static let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute,
                                kAXDocumentAttribute, kAXURLAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXSelectedAttribute,
                                kAXFilenameAttribute] as [String]
    let budget: ArisAXBudget

    func read(_ element: AXUIElement) -> ArisFocusElementRead? {
        AXUIElementSetMessagingTimeout(element, Self.perCall)
        var raw: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, Self.names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw)
        budget.record(error)
        guard error == .success, let values = raw as? [AnyObject], values.count == Self.names.count else { return nil }
        let text = { (index: Int) -> String? in values[index] as? String }
        let role = text(0) ?? ""
        var read = ArisFocusElementRead(role: role, subrole: text(1), title: text(2), label: text(3), identifier: text(4))
        read.document = text(5)
        read.url = (values[6] as? URL)?.absoluteString ?? text(6)
        read.frame = Self.frame(values[7], values[8])
        read.selected = (values[9] as? NSNumber)?.boolValue ?? false
        read.filename = text(10)
        let secure = role == "AXSecureTextField" || read.subrole == "AXSecureTextField"
        // A password field's value is never asked for.
        if !secure {
            let value = ArisAX.copy(element, kAXValueAttribute as String)
            budget.record(value.error)
            read.value = value.value as? String
            if ArisAXNode.textEntryRoles.contains(role) || role == "AXWebArea" || role == "AXStaticText" {
                read.selectedText = ArisAX.string(element, kAXSelectedTextAttribute as String)
            }
            if ArisAXNode.textEntryRoles.contains(role) { read.editable = ArisAX.settable(element, kAXValueAttribute as String) }
        }
        return read
    }

    func children(_ element: AXUIElement) -> [AXUIElement] {
        let found = ArisAX.copy(element, kAXChildrenAttribute as String)
        budget.record(found.error)
        return found.value as? [AXUIElement] ?? []
    }

    func same(_ a: AXUIElement, _ b: AXUIElement) -> Bool { CFEqual(a, b) }

    /// AXSelectedChildren, and an outline's or table's AXSelectedRows: what Finder (and other lists) says is selected.
    func selectedChildren(_ element: AXUIElement, role: String) -> [AXUIElement] {
        var found: [AXUIElement] = []
        for name in [kAXSelectedChildrenAttribute as String] + (["AXOutline", "AXTable"].contains(role) ? [kAXSelectedRowsAttribute as String] : []) {
            let value = ArisAX.copy(element, name)
            budget.record(value.error)
            found += (value.value as? [AnyObject] ?? []).compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        }
        return found
    }

    static func frame(_ position: AnyObject, _ size: AnyObject) -> ArisFocusRect? {
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return ArisFocusRect(x: origin.x, y: origin.y, width: dimensions.width, height: dimensions.height)
    }
}

enum ArisFocusLive {
    /// A look's tree read stops after this long (the look itself has the app's ten seconds).
    static let limit: TimeInterval = 2.5

    /// The window the look read, observed: its tree (only while aris-agent has Accessibility), the pointer, the regions.
    static func observe(app: ArisFocusApp, windowID: Int?, windowTitle: String?, regions: [ArisFocusRect], trusted: Bool) -> ArisFocusObservation {
        var observation = ArisFocusObservation(app: app, windowTitle: windowTitle, windowID: windowID, regions: regions)
        // Where the pointer is, read (Core Graphics, global points, top-left origin); nothing is moved.
        if let mouse = CGEvent(source: nil)?.location { observation.pointer = ArisFocusPoint(x: mouse.x, y: mouse.y) }
        guard trusted, let pid = app.pid, !ArisAX.unresponsive(pid: pid) else { return observation }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, ArisFocusAXSource.perCall)
        let window = windowID.flatMap { ArisAX.window(pid: pid, id: $0) } ?? ArisAX.element(element, kAXFocusedWindowAttribute as String)
        guard let window else { return observation }
        let budget = ArisAXBudget(limit: limit)
        let reader = ArisFocusReader(source: ArisFocusAXSource(budget: budget), exhausted: { budget.exhausted })
        let read = reader.tree(window, focused: ArisAX.focused(pid: pid))
        observation.tree = read.tree
        observation.cut = read.cut
        if observation.windowTitle == nil { observation.windowTitle = read.tree?.title }
        if observation.windowID == nil { observation.windowID = ArisAX.windowId(window) }
        return observation
    }

    /// The circled regions a /look request carries: `[[x, y, width, height], …]` in global points (at most eight).
    static func regions(_ raw: Any?) -> [ArisFocusRect] {
        guard let list = raw as? [[Any]] else { return [] }
        return list.prefix(8).compactMap { values in
            let numbers = values.compactMap { ($0 as? NSNumber)?.doubleValue }
            guard numbers.count == 4, numbers.allSatisfy(\.isFinite), numbers[2] > 0, numbers[3] > 0 else { return nil }
            return ArisFocusRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }
    }

    /// What /look adds to its reply for the app: the focus's kind and whether the answer is the text to type in place.
    static func reply(_ resolution: ArisFocusResolution?, words: String) -> [String: Any] {
        guard let focus = resolution?.focus else { return [:] }
        var body: [String: Any] = ["focusKind": focus.kind.rawValue, "writesHere": ArisFocusContext.writesInPlace(words, focus: focus)]
        if let landing = focus.landing { body["landing"] = landing.mode.rawValue }
        return body
    }
}

/// The turn's focus, kept for what else in the turn needs it (Judgment's focus hook); it goes stale after two minutes.
final class ArisFocusDesk: @unchecked Sendable {
    static let shared = ArisFocusDesk()
    static let freshFor: TimeInterval = 120

    private let lock = NSLock()
    private var kept: (resolution: ArisFocusResolution, words: String, at: Date)?

    /// `words`: the turn's words the resolution was made for (a resolved person counts in that turn only).
    func keep(_ resolution: ArisFocusResolution, words: String = "", at: Date = Date()) { lock.withLock { kept = (resolution, words, at) } }

    func latest(now: Date = Date()) -> ArisFocusResolution? {
        lock.withLock {
            guard let kept, now.timeIntervalSince(kept.at) < Self.freshFor else { return nil }
            return kept.resolution
        }
    }

    /// The World facts the trust tracker reads: the app in front and the focus object, while the focus is fresh.
    func worldFacts(now: Date = Date()) -> ArisWorldFacts {
        let fresh: (ArisFocusResolution, String)? = lock.withLock {
            guard let kept, now.timeIntervalSince(kept.at) < Self.freshFor else { return nil }
            return (kept.resolution, kept.words)
        }
        guard let (resolution, words) = fresh, let focus = resolution.focus,
              let object = ArisFocusContext.trustObject(resolution, words: words) else { return ArisWorldFacts() }
        return ArisWorldFacts(frontApp: focus.app.name, focus: object)
    }

    /// Judgment's world reads the desk (ArisCore2Trust.start; the gate runs only with `arisCore2` on).
    static func install(gate: ArisTrustGate = .shared, desk: ArisFocusDesk = .shared) {
        gate.world = { _ in desk.worldFacts() }
    }
}
