//
//  ArisSetupBrainKey.swift
//  Aris
//
//  AI 고르기 on a Mac with no AI (the owner's pick 3-A, 2026-11-11; qa/design-1111/onboarding-mock.html choice 3): the one
//  thing that can be finished inside the window comes first. The key field is open at the top (paste, 저장); under it
//  the AIs someone may already use, each as one line with its Terminal command, copied by a click, and 다시 확인. The
//  page's own way on says what it does: "AI 없이 계속" while nothing can answer, 계속 once something can. A saved key
//  goes the way Settings › AI services sends it (to the helper once, which checks its shape and keeps it in the
//  Keychain) and is then tried the way Settings tries it (the helper's short check): a key that doesn't answer is said
//  now, not at the first question. The rules and the words, pure, so the tests run them; ArisBrainPage draws them.
//

import Foundation

extension ArisOnboardingBrainRows {
    /// The page's two faces: the key first (it opened with no AI set up, and stays so for this visit, so a saved key
    /// or a found AI changes its rows in place), or the list to pick from.
    enum Layout: Equatable { case keyFirst, pick }

    /// `startedEmpty`: at some point of this setup the helper said no AI is set up here.
    static func layout(ready: [ArisBrain: Bool]?, startedEmpty: Bool) -> Layout {
        startedEmpty || heading(ready: ready) == .none ? .keyFirst : .pick
    }

    /// The AIs set up through their own tool in Terminal, in the user's order: the lines under the key field.
    static var terminalBrains: [ArisBrain] { ArisBrainChoice.order.filter { command($0) != nil } }

    /// What the page's way on does.
    enum Onward: Equatable {
        /// Nothing can answer: the setup goes on without an AI, and the button says so.
        case withoutAI
        case next
    }

    /// Without an AI when the helper said, for every one of them, that none is set up, or when the only one set up is
    /// a key whose check has just failed. Not known yet is never "without".
    static func onward(ready: [ArisBrain: Bool]?, keyTrouble: Bool = false) -> Onward {
        ArisBrainChoice.noneReady(ready) || (keyTrouble && !canAnswer(ready: ready, keyTrouble: true)) ? .withoutAI : .next
    }

    /// The helper's check of a key just saved, as Settings reads it: only a check that failed with something to say
    /// is trouble (a check that could not run says nothing).
    static func keyTestTrouble(ok: Bool, message: String) -> String? { !ok && !message.isEmpty ? message : nil }

    /// Whether the page may say an AI can answer: one is set up, and it is not only the key whose check just failed.
    static func canAnswer(ready: [ArisBrain: Bool]?, keyTrouble: Bool) -> Bool {
        guard let ready else { return false }
        return ArisBrainChoice.order.contains { ready[$0] == true && !(keyTrouble && $0 == .api) }
    }

    /// The rows as the page shows them: a key that is saved but did not answer is "saved", never "answers by default".
    static func shown(_ rows: [Row], keyTrouble: Bool) -> [Row] {
        rows.map { $0.brain == .api && $0.state == .chosen && keyTrouble ? Row(brain: .api, state: .ready, recommended: $0.recommended) : $0 }
    }
}

// MARK: - The page's words

extension ArisSetupWords {
    /// The heading over the key field: nothing can answer yet, or (after a key is saved or an AI found) something can.
    static func brainKeyTitle(anyReady: Bool, english: Bool = english) -> String {
        anyReady ? say("이제 답할 수 있어요", "An AI can answer now", english) : say("아직 답할 AI가 없어요", "No AI can answer yet", english)
    }
    static func brainKeyLead(anyReady: Bool, english: Bool = english) -> String {
        anyReady ? say("나중에 설정 › AI 서비스에서 바꿀 수 있어요.", "You can change it later in Settings › AI services.", english)
            : say("키를 붙여 넣으면 바로 쓸 수 있어요.", "Paste a key and it works right away.", english)
    }
    /// Over the lines of AIs that are set up in Terminal.
    static func brainExisting(english: Bool = english) -> String {
        say("쓰던 AI가 있으면 터미널에서 한 번만 실행해 주세요", "Already use one of these? Run it once in Terminal", english)
    }
    static func brainCopy(english: Bool = english) -> String { say("명령 복사", "Copy command", english) }
    static func brainWithoutAI(english: Bool = english) -> String { say("AI 없이 계속", "Continue without an AI", english) }

    /// The helper refused the key. Its own words are Korean; another language gets the guide's line.
    static func keyRefused(_ said: String, english: Bool = english) -> String { english ? ArisOnboardingCopy.brainKeyFailed : said }

    /// The key was saved and the helper's check of it failed. `said`: the helper's own (Korean) reason.
    static func keyNotWorking(_ said: String, english: Bool = english) -> String {
        say("키는 저장했는데, 이 키로는 답을 받지 못했어요. \(said)", "The key is saved, but it didn't answer when I tried it. Check it and paste it again.", english)
    }
}
