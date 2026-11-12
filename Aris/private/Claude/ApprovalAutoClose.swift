//
//  ApprovalAutoClose.swift
//  Aris
//
//  Whether a display's notch closes once the last Claude card is answered.
//  Every display shares one tab selection, and the first notch to close resets it,
//  so each display also remembers whether it opened for the card itself.
//

enum ApprovalAutoClose {
    static func shouldClose(isOpen: Bool, hovering: Bool, openedForApproval: Bool, showingClaude: Bool) -> Bool {
        isOpen && !hovering && (openedForApproval || showingClaude)
    }
}
