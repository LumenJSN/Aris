//
//  ArisAppsHands+TypeCheck.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  app.type's read-back: the field it typed into, found again in a fresh look, and what it holds now. The undo of a
//  typing is made only from this (never from what was sent), so a field that can't be found again leaves the typing
//  without one.
//
//  Sixth VM run, item 1: after File › New the typing went into the new document but was never verified, so it had no
//  undo ("(Typed into an app: TextEdit) can't be undone"). The earlier fix (82a72bf3) made the typing read the new
//  window afresh before it typed, and that held: the text went where it should. What failed was the read after it.
//  It took the field by the engine's element id from the look before the typing ("elem_N", only a place in that one
//  look's walk), or else by role and label. A brand-new document's first change gives its window more to show (its
//  title bar's "Edited", the autosave of a never-saved document), so the next look's walk numbers its elements anew:
//  the old id named another element, the first match was not the text area, and nothing was verified. The first look
//  right after that change can also come back with nothing while TextEdit is busy with it. Now the field is found
//  again by what it is (its role, then its identifier or label, then where it is), never by a look's id alone, and the
//  read-back looks again for a moment until the field shows the text.
//

import Foundation

extension ArisAppsHands {
    /// The field `element` (from an earlier look) in `fresh`: an element of the same role, then the same identifier
    /// when it has one, else the same label; among several, the one where it was. Never another role, and never by
    /// the earlier look's element id alone.
    static func sameField(_ element: ArisApps.ReadElement, in fresh: [ArisApps.ReadElement]) -> ArisApps.ReadElement? {
        let sameRole = fresh.filter { $0.role == element.role }
        var pool: [ArisApps.ReadElement]
        if let identifier = element.identifier, !identifier.isEmpty {
            pool = sameRole.filter { $0.identifier == identifier }
        } else {
            pool = sameRole.filter { $0.label == element.label }
        }
        if pool.isEmpty, element.identifier?.isEmpty == false { pool = sameRole.filter { $0.label == element.label && ($0.identifier ?? "").isEmpty } }
        guard pool.count > 1 else { return pool.first }
        // Several alike: the one at the same place (a document's text area doesn't move when it is typed into).
        guard let was = element.frame else { return pool.first { $0.id == element.id } }
        return pool.min { distance($0.frame, was) < distance($1.frame, was) }
    }

    private static func distance(_ frame: (x: Double, y: Double, width: Double, height: Double)?, _ was: (x: Double, y: Double, width: Double, height: Double)) -> Double {
        guard let frame else { return .infinity }
        return abs(frame.x - was.x) + abs(frame.y - was.y) + abs(frame.width - was.width) + abs(frame.height - was.height)
    }

    /// The typed field as it is now: looked at again (for up to `readBackSeconds`) until `settled` holds for what it
    /// shows, or it shows the same twice; nil when the field was never found again.
    func readBack(_ target: Target, _ window: WindowInfo, field element: ArisApps.ReadElement, context: Context,
                  settled: (String) -> Bool) -> (element: ArisApps.ReadElement, value: String)? {
        let end = Date().addingTimeInterval(readBackSeconds)
        var last: (element: ArisApps.ReadElement, value: String)?
        while true {
            if let fresh = look(target, window, context: context).0, let found = Self.sameField(element, in: fresh.elements),
               let value = found.value ?? (found.isText ? "" : nil) {
                // Read twice the same without the text: that is what it holds.
                let same = last?.value == value
                last = (found, value)
                if settled(value) || same { return last }
            }
            if Date() >= end { return last }
            Thread.sleep(forTimeInterval: 0.15)
        }
    }

    /// What app.type says when the field it typed into couldn't be read back: what stays (the text, without an undo).
    static let unreadAfterTyping = "the text went in, but the field couldn't be read back, so this typing can't be undone"
}
