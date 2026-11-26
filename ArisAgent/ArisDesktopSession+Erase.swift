//
//  ArisDesktopSession+Erase.swift
//  aris-agent
//
//  The session's side of a replace (ArisDesktopErase): right before the text or the keys go, the field must still hold
//  (or have selected) exactly what the card showed would be erased, else nothing is done; a replace of everything
//  selects it first, and types only once Accessibility shows all of it selected; after the typing the field must hold
//  just the new text, else what was typed is taken out again and the step fails (seventeenth VM run, R1k: resumed after
//  a pause with System Settings in front, the select-all didn't take, the text went in after the old and was told as
//  done). An erase of everything is held to the same rule: its delete goes only over all of the field selected, and
//  the field must be empty after it, else what it took is put back and the step fails. A typing, replace or erase that
//  worked keeps its undo (ArisDesktopUndoLog), the erased text in the undo store, so "되돌려" takes this change back and
//  no older one.
//

import Foundation

extension ArisDesktopSession {
    /// Nil while the field holds what the decision read (or the call erases nothing); else nothing is done.
    func eraseHeld(_ look: ArisDesktopObservation, field: ArisDesktopElement?) -> ArisDesktopResult? {
        guard let erase = basis.erase else { return nil }
        let current = field.flatMap { ArisDesktopVerify.find($0, in: look) } ?? field ?? look.focusedElement
        guard !ArisDesktopErase.holds(card: erase.seen, now: erase.now(current)) else { return nil }
        turn.audit(["answer": "not done (what it would erase changed since it was decided)", "action": "desktop · \(target.name)", "brain": turn.brainName])
        turn.ledger.noteFieldChanged()
        return .failed(ArisDesktopErase.changedLine + "\n\n" + look.render())
    }

    /// A replace of everything: a select-all goes first.
    var selectsAllFirst: Bool { basis.erase?.scope == .whole && basis.erase?.replaces == true }

    /// The press's keys: a select-all first for an erase of everything whose keys don't select.
    func erasingKeys(_ keys: [String]) -> [String] {
        selectsAllFirst && !keys.contains(where: ArisDesktopBatch.isSelectAll) ? ["cmd+a"] + keys : keys
    }

    /// How the select-all of a replace or an erase of everything went.
    enum SelectAll {
        /// All of it is selected (or the field doesn't tell its selection: the field is checked after, unreplaced and
        /// unerased).
        case selected(ArisDesktopObservation, ArisDesktopElement)
        /// The keys went (or, for an erase, couldn't reach the window in the background), but Accessibility shows only
        /// part of it selected (R1k: a background cmd+a with another app in front): nothing typed or deleted; the window
        /// brought forward on the user's card is the next way.
        case missed(ArisDesktopObservation, ArisDesktopElement)
        /// What to tell the brain (nothing typed or deleted).
        case refused(ArisDesktopResult)
    }

    /// The select-all of a type (or, `erasing`, of a press that deletes everything), in the background, read back: the
    /// field still has the focus, still holds what the card showed, and has all of it selected. It runs again with the
    /// step after a pause (ArisDesktopEngine+Lock runs the step from its start), never taken from before it.
    func selectAllFirst(_ field: ArisDesktopElement, in look: ArisDesktopObservation, erasing: Bool = false) -> SelectAll {
        let sent = run(ArisPeekabooCommands.press(["cmd+a"], snapshot: look.peekaboo))
        turn.ledger.clearPendingSelectAll(window: look.window)
        // An erase's keys that can't reach the window in the background go forward, as the press's own keys do.
        if erasing, sent?.focusElsewhere == true { return .missed(look, field) }
        guard sent?.dispatched == true, sent?.focusElsewhere != true, let again = lookAfter(look.window),
              let now = ArisDesktopVerify.find(field, in: again), again.isFocused(now), !again.focusIsSecure, !now.isSecure else {
            return .refused(.failed(erasing ? ArisDesktopErase.notErasedLead + " Couldn't select the text to erase in the background, so nothing was deleted."
                                    : Self.notTypedLead + " Couldn't select the text to replace in the background, so nothing was typed."))
        }
        if let refused = eraseHeld(again, field: now) { return .refused(refused) }
        if ArisDesktopErase.coversAll(now) == false {
            turn.audit(["answer": "select-all didn't take in the background (selection \(now.selectedRange?.shown ?? "?"))",
                        "action": "desktop \(erasing ? "press" : "type") · \(target.name)", "brain": turn.brainName])
            return .missed(again, now)
        }
        return .selected(again, now)
    }

    /// After a replace of everything was typed: the field must hold just the new text. Otherwise it is never told as
    /// done (R1k: the text went in after the old, and the undo called it an insertion): what was typed is taken out
    /// again and read back, the step fails, and the brain is told to say so plainly. Nil when it replaced, or when the
    /// field doesn't give its whole value (nothing to check it by).
    func unreplaced(_ text: String, field: ArisDesktopElement, before: String, after: ArisDesktopObservation) -> ArisDesktopResult? {
        guard selectsAllFirst, let now = ArisDesktopVerify.find(field, in: after), !now.rawCapped, let value = now.rawValue,
              !ArisDesktopErase.replacedWhole(value, with: text) else { return nil }
        let back = takeBack(now, before: before, value: value, in: after)
        turn.audit(["answer": "not replaced (\(back.restored ? "taken back" : "couldn't be taken back"))", "action": "desktop type · \(target.name)",
                    "brain": turn.brainName])
        // Left in the field: kept for Aris's undo like any typing, so "되돌려" takes it out.
        if !back.restored { keepUndo(field: field, before: before, after: back.look ?? after, typing: true) }
        return .failed(ArisDesktopErase.notReplacedLine(restored: back.restored, why: back.why) + "\n\n" + (back.look ?? after).render())
    }

    /// After the delete of an erase of everything: the field must be empty (what the erase card promised). Otherwise it
    /// is never told as done (a delete over only part of it, or over the caret): anything it took is put back and read
    /// back, the step fails with NOT ERASED, and the brain is told to say so plainly; what can't be put back is kept for
    /// Aris's undo. Nil when it is empty, or when the field doesn't give its whole value (nothing to check it by).
    func unerased(field: ArisDesktopElement, before: String, after: ArisDesktopObservation) -> ArisDesktopResult? {
        guard selectsAllFirst, let now = ArisDesktopVerify.find(field, in: after) ?? after.focusedElement, !now.rawCapped, let value = now.rawValue,
              !ArisDesktopErase.replacedWhole(value, with: "") else { return nil }
        let unchanged = value.precomposedStringWithCanonicalMapping == before.precomposedStringWithCanonicalMapping
        let back = unchanged ? (restored: true, look: Optional(after), why: String?.none) : takeBack(now, before: before, value: value, in: after)
        turn.audit(["answer": "not erased (\(unchanged ? "nothing changed" : back.restored ? "put back" : "couldn't be put back"))", "action": "desktop press · \(target.name)",
                    "brain": turn.brainName])
        if !back.restored { keepUndo(field: field, before: before, after: back.look ?? after, typing: false) }
        return .failed(ArisDesktopErase.notErasedLine(restored: back.restored, why: back.why) + "\n\n" + (back.look ?? after).render())
    }

    /// The field put back to `before`: text added beside it is taken out the way Aris's undo does it (that range only,
    /// so nothing else in the document changes); anything else gets its old value set. Read back either way.
    func takeBack(_ field: ArisDesktopElement, before: String, value: String,
                          in after: ArisDesktopObservation) -> (restored: Bool, look: ArisDesktopObservation?, why: String?) {
        var why: String?
        if let bundle = target.bundle,
           case .textInserted(_, let element, _)? = ArisApps.TextUndo.recipe(app: target.name, bundle: bundle, role: field.role, label: field.label,
                                                                            before: before, after: value) {
            do { try ArisDesktopUndoLog.perform(target.name, element, "") } catch let error as ArisUndoError { why = error.message } catch { why = String(describing: error) }
        } else {
            _ = run(ArisPeekabooCommands.setValue(before, element: field.id, snapshot: after.peekaboo))
        }
        guard let again = lookAfter(after.window) else { return (false, nil, why ?? "the window couldn't be read back") }
        let read = ArisDesktopVerify.find(field, in: again).flatMap { $0.rawCapped ? nil : $0.rawValue }
        let restored = read?.precomposedStringWithCanonicalMapping == before.precomposedStringWithCanonicalMapping
        return (restored, again, restored ? nil : why ?? "the field doesn't read as it did")
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
