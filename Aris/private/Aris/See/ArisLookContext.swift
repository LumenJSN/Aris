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
    /// `rewrite`: the words ask to change what is selected (ArisDeixis.wantsRewrite). `typesOver`: they ask for text to
    /// go where the selection is, in a field (the look's writesHere with a selection).
    static func words(context: String, unread: String?, unselected: String?, pictured: Bool, rewrite: Bool, typesOver: Bool = false) -> String {
        let aside = pictured ? nil : unread
        let selection = rewrite ? unselected : nil
        return ([context] + [aside, selection, typesOver ? typeOverLine : nil].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: "\n")
    }

    /// The words ask for text to be typed or written in ("Type 'x' where I selected", "선택한 부분에 'x'라고 입력해 줘").
    static func asksToType(_ words: String) -> Bool {
        words.range(of: #"(?i)\b(type|write|enter|put)\b|입력|써\s?(줘|주)|적어|넣어"#, options: .regularExpression) != nil
    }

    /// Thirteenth VM run, Q2d1: "Type 'changed text' where I selected" was answered with only "changed text", nothing typed.
    static let typeOverLine = "The user asks for text to go into the app where the selection is: put it there with `aris-tools type \"<the text>\" --app \"<App>\"` " +
        "(it types over the selection, on a card that shows the text it erases). Don't answer with only the text."

    /// For the log: which of its own permissions aris-agent did without for this look.
    static func lacks(_ needs: [String]) -> String {
        needs.isEmpty ? "" : " (the helper lacks: \(needs.joined(separator: ", ")))"
    }
}
