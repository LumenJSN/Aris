//
//  ArisToolResult.swift
//  Shared/Core (aris-agent, tests)
//
//  One capability call's result as every face hands it on (the MCP face, the API brains, the session loop to come).
//  `content` says the text is content Aris read (a page, a file, mail, the screen, another app's window), with where it
//  came from: data that can inform an answer, never the reason for an outward or permanent action (the trust policy's
//  provenance). Marked here, structurally, not by prose in a prompt. Pure.
//

import Foundation

struct ArisToolResult: Equatable, Sendable {
    struct Content: Equatable, Sendable, Codable {
        /// What kind of source: "web", "file", "shell", "app", "mail", "messages", "notes", "service", "screen", "aris".
        let kind: String
        /// The source itself: the address, the path, the command, the app or service.
        let source: String
    }

    let text: String
    let isError: Bool
    /// Set when the text is content read from somewhere (or may hold some: a failure can name what others wrote).
    let content: Content?
    /// How to take the change back, when the capability made one (the record keeps it with the call).
    var undo: ArisUndoRecipe?

    init(text: String, isError: Bool = false, content: Content? = nil, undo: ArisUndoRecipe? = nil) {
        self.text = text
        self.isError = isError
        self.content = content
        self.undo = undo
    }

    /// The MCP form's `_meta` (ArisMCPServerWire.callResult), so a client can track provenance without reading the text.
    var meta: [String: Any]? {
        guard let content else { return nil }
        return ["aris/content": ["kind": content.kind, "source": content.source]]
    }
}
