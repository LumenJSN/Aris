// Tests for the security review's follow-ups to the QA fixes (qa-followup): maps lookups taint and, after outside
// text, ask when their words aren't the user's (M1); a panel field takes the keyboard only after a press (M7); a Claude
// card's hover arm never pretends to have the keyboard (LOW).
import AppKit
import Foundation

func runQAFollowupTests() {
    qaFollowupPanelPressTests()
    qaFollowupCardArmTests()
}

// MARK: - M7: only a press takes the keyboard

private func qaFollowupPanelPressTests() {
    let own: pid_t = 10, weChat: pid_t = 20
    var focus = ArisPanelFocus()
    check(focus.responder(takesKeys: true, frontmost: weChat, own: own) == .dropCaret && !focus.editing && !focus.canBecomeKey(armed: false),
          "M7: a field that becomes first responder on its own takes nothing and loses its caret")
    check(focus.pressed(onField: true, frontmost: weChat, own: own) == .takeKey && focus.responder(takesKeys: true, frontmost: own, own: own) == .none,
          "M7: after a press, the field becoming first responder is the press's own")
    check(focus.responder(takesKeys: false) == .giveBack(weChat), "M7: and letting go gives the keyboard back")
}

// MARK: - LOW: a Claude card's hover arm never pretends to have the keyboard

private func qaFollowupCardArmTests() {
    MainActor.assumeIsolated {
        check(KeyboardTextInput.arm(byHotkey: false, arisActive: false) == .init(makeKey: false, activate: false),
              "LOW: hovering a Claude card while another app is active takes nothing (its Y/N would go to that app)")
        check(KeyboardTextInput.arm(byHotkey: false, arisActive: true) == .init(makeKey: true, activate: false),
              "LOW: hovering while Aris is active: the card's keys work as before")
        check(KeyboardTextInput.arm(byHotkey: true, arisActive: false) == .init(makeKey: true, activate: true),
              "LOW: the answer hotkey (the user's own press) brings Aris forward so Y/N really reach the card")
        check(!KeyboardTextInput.answersCardKey(arisActive: false) && KeyboardTextInput.answersCardKey(arisActive: true),
              "LOW: a card key counts only while Aris is the active app")
    }
}
