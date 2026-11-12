//
//  ArisOnboardingBrainHelp.swift
//  Aris
//
//  What the guide's AI page lets a Mac with no AI do about it (VM run 2026-11-11, section 2.4): the three AI cards were
//  grey, did nothing when clicked, and their one line of help had nothing to act on; "Check again" showed nothing when
//  pressed. Each card's Terminal command can now be copied, its line says what to do afterwards, and a press of Check
//  again says that it checked and what it found. Pure, so the tests run it.
//

import Foundation

extension ArisOnboardingBrainRows {
    /// The command the row's help names, as typed in Terminal; nil for the API key row (it has its own form).
    static func command(_ brain: ArisBrain) -> String? {
        switch brain {
        case .claude: "claude"
        case .codex: "codex login"
        case .antigravity: "agy"
        case .api: nil
        }
    }

    /// Whether a click on the row copies its command: an AI that isn't set up here and is set up in Terminal.
    static func copiesCommand(_ row: Row) -> Bool { row.state == .missing && command(row.brain) != nil }

    /// What a press of Check again found.
    enum Checked: Equatable {
        /// aris-agent didn't answer: nothing is known.
        case unreachable
        /// It answered: no AI is set up on this Mac (not `none`: the page holds an optional of this).
        case nothing
        /// These are set up now and were not at the last look.
        case found([ArisBrain])
        /// Nothing changed; these are set up.
        case same([ArisBrain])
    }

    /// `answered`: the agent answered this press. `before`, `after`: which AIs were set up at the last look and now.
    static func checked(answered: Bool, before: [ArisBrain: Bool]?, after: [ArisBrain: Bool]?) -> Checked {
        guard answered, let after, !after.isEmpty else { return .unreachable }
        let ready = ArisBrainChoice.order.filter { after[$0] == true }
        guard !ready.isEmpty else { return .nothing }
        // With no look before this one, nothing can be called new.
        guard let before else { return .same(ready) }
        let new = ready.filter { before[$0] != true }
        return new.isEmpty ? .same(ready) : .found(new)
    }

    /// "Checking…" stays at least this long, so a press is seen to do something (the agent answers in a few ms).
    static let checkingShown: Duration = .milliseconds(600)
    /// "Copied" stays this long on a row.
    static let copiedShown: Duration = .seconds(2)
}

// MARK: - The page's words

extension ArisSetupWords {
    /// After a row's "install it, then sign in" line: what to do next on this page.
    static func thenCheckAgain(english: Bool = english) -> String { say("그런 다음 다시 확인을 눌러 주세요.", "After that, press Check again.", english) }

    static func copyCommand(_ command: String, english: Bool = english) -> String { say("“\(command)” 복사", "Copy “\(command)”", english) }
    static func copied(english: Bool = english) -> String { say("복사했어요", "Copied", english) }
    static func copyHint(english: Bool = english) -> String { say("터미널에 붙여 넣을 명령을 복사해요.", "Copies the command to paste into Terminal.", english) }

    /// What a press of Check again found. `names`: the AIs' names as the rows show them.
    static func checked(_ result: ArisOnboardingBrainRows.Checked, names: (ArisBrain) -> String, english: Bool = english) -> String {
        switch result {
        case .unreachable:
            return say("지금은 확인하지 못했어요. Aris의 도우미가 답하지 않았어요. 잠시 뒤에 다시 눌러 주세요.",
                       "I couldn't check just now: Aris's helper didn't answer. Press it again in a moment.", english)
        case .nothing:
            return say("방금 확인했어요. 아직 이 Mac에 준비된 AI가 없어요.", "Checked just now: no AI is set up on this Mac yet.", english)
        case .found(let brains):
            let list = brains.map(names).joined(separator: ", ")
            return say("방금 확인했어요. 새로 준비된 AI: \(list)", "Checked just now. Newly ready: \(list)", english)
        case .same(let brains):
            let list = brains.map(names).joined(separator: ", ")
            return say("방금 확인했어요. 달라진 건 없어요. 준비된 AI: \(list)", "Checked just now: nothing new. Ready: \(list)", english)
        }
    }
}
