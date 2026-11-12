//
//  ArisAIKeyChoice.swift
//  Aris
//
//  When a thinking AI picked on the AI services page becomes the brain (second upgrade run, bug 2). The page said
//  "Until it can be used, DeepSeek thinks" for a Groq pick with no key, but saving a made-up Groq key made Groq the
//  brain at once, and the next question failed. A pick becomes the brain only once it can answer: its tool installed,
//  or its key answered once (a check or a turn). A key saved for a pick is saved without making it the brain; a key
//  for the brain that answers now replaces that brain's key, as before. Pure, so the tests run it.
//

import Foundation

enum ArisAIKeyChoice {
    /// Whether a pick that lacks this waits (the working brain goes on answering): a key, a tool, or a key that has
    /// never answered.
    static func waits(_ lack: ArisAILack) -> Bool { lack == .key || lack == .install || lack == .check }

    /// Whether saving a key for `holder` (an API provider's id) makes it the brain now. `pending`: the pick that waits
    /// ("api:groq"); `think`: the brain the page shows as chosen. Only when it is already the brain, not only picked.
    static func activatesOnSave(holder: String, pending: String?, think: String) -> Bool {
        let mine = "api:" + holder
        return pending != mine && think == mine
    }
}
