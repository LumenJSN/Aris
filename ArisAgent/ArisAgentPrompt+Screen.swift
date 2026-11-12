//
//  ArisAgentPrompt+Screen.swift
//  aris-agent
//
//  What a brain is told about seeing the screen now that the screenshot comes only with a request whose words point
//  at it (the owner, 2026-11-10; the app's ArisScreenNeed). The <images> section still says what came, when something did
//  (ArisAgentPrompt.images). This line is for the sealed brain of a conversation that saw the screen once: a later
//  request in it often comes without an image, and then it sees nothing new. It can still look at an app's window
//  itself with the desktop look (on its sealed list), or say what would send the screen. The open and gated brains
//  are told nothing about seeing the screen; the gated ones keep their own `screen`, `selection` and `tab` commands.
//

import Foundation

extension ArisAgentPrompt {
    /// Said to the sealed brain (never the hands-free one, which is told nothing about the screen).
    static let screenWhenShown = "The screen is in front of you only when an image of it came with the request (the <images> section " +
        "says so): a request without one shows you nothing new, so never describe the screen from an earlier image or guess what is on it. " +
        "When such a request needs the screen, look at the app in front with the desktop look above, or say in a few words that you'd " +
        "need to see it and that asking with \"화면 봐 줘\" or \"look at my screen\" sends it."
}
