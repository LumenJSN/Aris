//
//  ArisScreenAccess+Live.swift
//  aris-agent
//
//  The agent's one answer to "may aris-agent record the screen now?", asked with its own aris-tools: for the card
//  under an answer (ArisWidgetPick), the app's question (/permissions screenAccess) and computer use's --ocr and
//  click-at (ArisDesktopLiveAccess). All three used to ask this process itself, which keeps saying "off" after the user
//  has switched aris-agent on (VM bug 1).
//

import Foundation

extension ArisScreenAccess {
    /// Unknown counts as not allowed: nothing is captured on a guess.
    static var now: Bool {
        allowed(tools: ArisAgentRunner.toolsPath, environment: ArisAgentRunner.environment()) == true
    }
}

extension ArisWidgetPick.Access {
    /// As macOS has it now; neither check asks for anything.
    static var now: Self { Self(disk: ArisLocalReadPolicy.hasDiskAccess(), screen: ArisScreenAccess.now) }
}
