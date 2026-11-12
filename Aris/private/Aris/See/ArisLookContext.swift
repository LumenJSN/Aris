//
//  ArisLookContext.swift
//  Aris
//
//  What goes to the AI with a question about the screen, put together from aris-agent's look and from whether the
//  app's own picture of the screen goes with the turn. The picture is the screen read: with it in hand the AI is never
//  told the screen couldn't be read, whatever aris-agent itself may do (VM bug 1: every answer ended with "Screen
//  Recording isn't allowed" while its description of the screen was right). Without it, the look's own line says what
//  was missing and which row to switch on. aris-agent's missing Accessibility is said only when the words ask to
//  change what is selected, never under every answer. The lines are the agent's (ArisScreenRead). Pure.
//

import Foundation

enum ArisLookContext {
    /// `context`: what the look found. `unread`: its line for when the front window's words didn't come. `unselected`:
    /// its line for when a selection couldn't be read. `pictured`: the app's screenshot goes with this turn.
    /// `rewrite`: the words ask to change what is selected (ArisDeixis.wantsRewrite).
    static func words(context: String, unread: String?, unselected: String?, pictured: Bool, rewrite: Bool) -> String {
        let aside = pictured ? nil : unread
        let selection = rewrite ? unselected : nil
        return ([context] + [aside, selection].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: "\n")
    }

    /// For the log: which of its own permissions aris-agent did without for this look.
    static func lacks(_ needs: [String]) -> String {
        needs.isEmpty ? "" : " (the helper lacks: \(needs.joined(separator: ", ")))"
    }
}
