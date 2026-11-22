//
//  ArisDesktopSession+Erase.swift
//  aris-agent
//
//  The session's side of a replace (ArisDesktopErase): right before the text or the keys go, the field must still hold
//  (or have selected) exactly what the card showed would be erased, else nothing is done; a replace of everything
//  selects it first; and a typing, replace or erase that worked keeps its undo (ArisDesktopUndoLog), the erased text in
//  the undo store, so "되돌려" takes this change back and no older one.
//

import Foundation

extension ArisDesktopSession {
    /// Nil while the field holds what the decision read (or the call erases nothing); else nothing is done.
    func eraseHeld(_ look: ArisDesktopObservation, field: ArisDesktopElement?) -> ArisDesktopResult? {
        guard let erase = basis.erase else { return nil }
        let current = field.flatMap { ArisDesktopVerify.find($0, in: look) } ?? field ?? look.focusedElement
        guard !ArisDesktopErase.holds(card: erase.seen, now: erase.now(current)) else { return nil }
        turn.audit(["answer": "not done (what it would erase changed since it was decided)", "action": "desktop · \(target.name)", "brain": turn.brainName])
        return .failed(ArisDesktopErase.changedLine + "\n\n" + look.render())
    }

    /// A replace of everything: a select-all goes first.
    var selectsAllFirst: Bool { basis.erase?.scope == .whole && basis.erase?.replaces == true }

    /// The press's keys: a select-all first for an erase of everything whose keys don't select.
    func erasingKeys(_ keys: [String]) -> [String] {
        selectsAllFirst && !keys.contains(where: ArisDesktopBatch.isSelectAll) ? ["cmd+a"] + keys : keys
    }

    /// The type's select-all, in the background, read back: the field still has the focus and still holds what the card
    /// showed. What to tell the brain otherwise (nothing typed).
    func selectAllFirst(_ field: ArisDesktopElement, in look: ArisDesktopObservation) -> Result<(ArisDesktopObservation, ArisDesktopElement), ArisDesktopResult> {
        let sent = run(ArisPeekabooCommands.press(["cmd+a"], snapshot: look.peekaboo))
        turn.ledger.clearPendingSelectAll(window: look.window)
        guard sent?.dispatched == true, sent?.focusElsewhere != true, let again = lookAfter(look.window),
              let now = ArisDesktopVerify.find(field, in: again), again.isFocused(now), !again.focusIsSecure, !now.isSecure else {
            return .failure(.failed(Self.notTypedLead + " Couldn't select the text to replace in the background, so nothing was typed."))
        }
        if let refused = eraseHeld(again, field: now) { return .failure(refused) }
        return .success((again, now))
    }

    /// After a type or an erase that worked: its undo is kept, from the field's whole value right before (`before`) and
    /// as read back (`after`); a replace keeps what it erased in the undo store first. The line for the brain when the
    /// change can't be taken back; nil when it can (or nothing is kept: no folder, a value not read in full).
    @discardableResult
    func keepUndo(field: ArisDesktopElement, before: String?, after: ArisDesktopObservation, typing: Bool) -> String? {
        guard ArisDesktopUndoLog.folder != nil, let before, let bundle = target.bundle,
              let now = ArisDesktopVerify.find(field, in: after) ?? after.focusedElement, !now.rawCapped, let value = now.rawValue, value != before else { return nil }
        let recipe: ArisUndoRecipe?
        let replaced: Bool
        if typing, ArisApps.TextUndo.insertion(before: before, after: value) != nil {
            replaced = false
            recipe = ArisApps.TextUndo.recipe(app: target.name, bundle: bundle, role: now.role, label: now.label, before: before, after: value)
        } else {
            replaced = true
            guard let copy = ArisDesktopUndoLog.store?.keep(data: Data(before.utf8)) else {
                return "What it erased couldn't be kept, so this can't be undone: say so if you tell the user it was done."
            }
            recipe = ArisApps.TextUndo.replaced(app: target.name, bundle: bundle, role: now.role, label: now.label, before: before, after: value, copy: copy)
        }
        guard let recipe else { return nil }
        ArisDesktopUndoLog.add(app: target.name, summary: ArisDesktopUndoLog.summary(app: target.name, replaced: replaced, typed: typing), recipe: recipe)
        return nil
    }
}
