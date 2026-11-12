//
//  ArisWhyPrompt.swift
//  aris-agent
//
//  What every AI is told about "왜 그렇게 했어?". Aris answers that question itself, from its own record of the turn
//  (ArisWhyDesk), so an AI never has to. But a why-question said another way still reaches the AI, and an AI asked why
//  will make up a likely-sounding reason: which rule put a card up, why something was refused, which AI answered.
//  It can't know any of that. This line keeps it to what it does know and tells the user how to get the record.
//  Foundation only (tested).
//

import Foundation

enum ArisWhyPrompt {
    /// The words the user can say to get the record, as the rule names them.
    static let korean = "왜 그렇게 했어?"
    static let english = "why did you do that?"

    static let rule = """
        When the user asks why you did, asked about or refused something a moment ago
        - Say only what you know yourself from this conversation: what you were asked, what you ran and what came back. \
        Never invent a reason for the rest: why a confirm card came up, why Aris refused or stopped something, which \
        AI answered or took over, or what Aris read or did. You can't see those; Aris keeps its own record of them.
        - Then say, in a few words, that asking “\(korean)” (or “\(english)”) right after a turn gets that record from \
        Aris itself.
        """

    /// The rule as a part to put after a prompt's last part.
    static let part = "\n\n" + rule
}
