//
//  ArisHandsPrompt.swift
//  aris-agent
//
//  The open Claude's system prompt with `arisCore2` on (ArisHandsFace; with it off the prompt is the shell form of
//  ArisAgentPrompt.system as ever, and nothing here runs). The model has no shell and no built-in tool, only Aris's
//  tools, each with its own schema: so it gets the prompt the API brains get for the same functions (the function
//  form: `aris` words for the generic tool, no shell-quoting lessons), with the web search it now has.
//

import Foundation

enum ArisHandsPrompt {
    static func system(task: Bool) -> String {
        ArisAgentPrompt.system(tools: ArisAPICatalog.generic, gated: true, task: task, functions: true, ownSearch: true) + "\n\n" + ArisMindSession.appTextRule
    }
}
