//
//  ArisUndoSaid.swift
//  Shared/Core/Trust
//
//  A change that ran on the owner's word with its undo kept (the trust table's "run, undo kept") is said as that
//  (eleventh VM run, item 7: "초안.txt 휴지통에 버려 줘" ran with no card, which is the table's row, and the reply said
//  only "휴지통으로 옮겼어요": nothing told him it could be taken back). The call's result, which only the model reads,
//  ends with one line that holds the model to saying so. Only for the changes he may not expect to be undoable and that
//  matter when wrong (a file moved, renamed or put in the Trash, an event added), and only when an undo was really
//  kept. Pure.
//

import Foundation

enum ArisUndoSaid {
    static let capabilities: Set<String> = ["aris.file_trash", "aris.file_rename", "aris.file_move", "aris.add_event"]

    static let note = "This was done with an undo kept. Tell the owner in one short sentence what was done and that it can be undone "
        + "(Korean: “…했어요. 되돌릴 수 있어요.”; English: “Done. You can undo it.”)."

    /// The result's text for the model. `canUndo`: the call left an undo (its own recipe, or the activity log's entry).
    static func text(_ text: String, capability: String, canUndo: Bool) -> String {
        guard canUndo, capabilities.contains(capability.lowercased()) else { return text }
        return text + "\n" + note
    }
}
