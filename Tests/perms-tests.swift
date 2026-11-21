// jv-perms: the setup shows only the permission cards the chosen features need and walks them as before; the
// permission cards under the notch (why before macOS asks, a refusal once with its pane, a reopen offer); the
// Automation check that never asks; the links agree with ArisFix's; aris-tools never raises macOS's Accessibility alert.
// The model itself is tested with `swift test` (Tests/ArisCoreTests/ArisPermissionsTests.swift).
import Foundation

private func permsSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func permsSetupCardTests() {
    let all = ArisSetupCards.chosen(dictation: true, circleGesture: true, wakeWord: true)
    check(ArisSetupCards.cards(for: all) == [.mic, .accessibility], "perms setup: every feature on shows two cards (Screen Recording waits for the first circle)")
    let defaults = ArisSetupCards.chosen(dictation: true, circleGesture: true, wakeWord: false)
    check(ArisSetupCards.cards(for: defaults) == [.mic, .accessibility], "perms setup: the default switches (circle gesture on) show no Screen Recording card")
    for dictation in [false, true] {
        for wake in [false, true] {
            for circle in [false, true] {
                let cards = ArisSetupCards.cards(for: ArisSetupCards.chosen(dictation: dictation, circleGesture: circle, wakeWord: wake))
                check(cards == [.mic, .accessibility], "perms setup: never a Screen Recording card (dictation \(dictation), wake \(wake), circle \(circle))")
            }
        }
    }
    check(ArisSetupCards.cards(for: [.screenPicture]) == [.screen], "perms setup: the card is still there for a feature that asks in the setup")
    check(permsSource("Aris/private/Aris/Gesture/ArisGesturePermissionChip.swift").contains("ArisPermissionCenter.shared.openPane(.screenRecording)"),
          "perms gesture: the circle's 허용하기 opens the pane through the permission center (watched, relaunch offered once)")
    check(ArisSetupCards.cards(for: [.talk]) == [.mic], "perms setup: talking alone needs only the microphone card")
    check(ArisSetupCards.cards(for: []) == [], "perms setup: nothing chosen, no card")
    check(ArisSetupCards.card(for: .inputMonitoring) == nil && ArisSetupCards.card(for: .fullDiskAccess) == nil,
          "perms setup: what has no card is asked when a feature needs it")
}

private func permsSetupFlowTests() {
    var flow = ArisSetupFlow(page: .permissions, cards: [.mic, .accessibility])
    let none: [ArisPermissionCard: Bool] = [:]
    flow.begin(granted: none)
    check(flow.active == .mic, "perms flow: the first shown card opens")
    check(!flow.continueShown(granted: none), "perms flow: 계속 waits for the shown cards")
    check(flow.continueShown(granted: [.mic: true, .accessibility: true]), "perms flow: 계속 once the shown cards are on (no screen card)")
    check(abs(flow.progress(granted: [.mic: true]) - 0.5 / Double(ArisSetupPage.allCases.count)) < 1e-9,
          "perms flow: the rail counts the shown cards only")
    flow.putOff(.mic)
    check(flow.active == .accessibility, "perms flow: 나중에 opens the next shown card")
    flow.putOff(.accessibility)
    check(flow.active == nil && flow.allDecided(granted: none), "perms flow: never opens a card the setup does not show")
    check(ArisSetupFlow(cards: [.screen, .mic]).cards == [.mic, .screen], "perms flow: cards keep the page's order")
    check(ArisSetupFlow().cards == ArisPermissionCard.allCases, "perms flow: the default is every card, as before")
    var empty = ArisSetupFlow(cards: [])
    empty.begin(granted: none)
    check(empty.active == nil && empty.continueShown(granted: none), "perms flow: no cards, nothing to wait for")
}

private func permsNoticeTests() {
    let mic = ArisPermissionKey(.microphone)
    let ax = ArisPermissionKey(.accessibility)
    let screen = ArisPermissionKey(.screenRecording)
    check(ArisPermissionNotice.notice(for: .proceed, english: false) == nil && ArisPermissionNotice.notice(for: .doWithout(mic), english: false) == nil,
          "perms notice: going ahead, or doing without after being told, puts nothing up")
    let reason = ArisPermissionFeature.talk.reason(english: false)
    let why = ArisPermissionNotice.notice(for: .prompt(mic, reason: reason), english: false)
    check(why?.kind == .system && why?.body == reason && why?.actions.isEmpty == true && why?.key == "permission:microphone",
          "perms notice: before macOS asks, the reason alone, keyed by the permission")
    let off = ArisPermissionNotice.notice(for: .tellOff(ax, link: ArisPermission.accessibility.paneLink, reason: ArisPermissionFeature.appControl.reason(english: true)), english: true)
    check(off?.kind == .problem && off?.actions.first?.role == .permissionPane(.accessibility) && off?.actions.first?.primary == true,
          "perms notice: a refusal is a problem card with one button to its pane")
    check(off?.title.contains(ArisFix.Pane.accessibility.title(english: true)) == true, "perms notice: the list's name as this macOS shows it")
    let reopen = ArisPermissionNotice.notice(for: .offerRelaunch(screen), english: false)
    check(reopen?.actions.map(\.role) == [.relaunchApp], "perms notice: a switch that needs a relaunch offers one button")
    if let off {
        check(ArisNoticeRoute.want(off, spoken: false).kind == .problem, "perms notice: the interruption policy sees a refusal as a problem")
    }
}

private func permsLinkTests() {
    for pane in ArisFix.Pane.allCases {
        let match = ArisPermission.allCases.first { $0.anchor == pane.anchor }
        check(match != nil, "perms links: ArisFix's \(pane.rawValue) list is one of the model's")
        if let match { check(match.paneLink == pane.link, "perms links: \(pane.rawValue) opens the same pane from both") }
    }
}

private func permsAutomationTests() {
    check(ArisAutomationAccess.state(status: 0) == .granted, "perms automation: noErr is granted")
    check(ArisAutomationAccess.state(status: -1743) == .denied, "perms automation: errAEEventNotPermitted is denied")
    check(ArisAutomationAccess.state(status: -1744) == .notAsked, "perms automation: would need consent is not asked")
    check(ArisAutomationAccess.state(status: -600) == .unknown, "perms automation: an app that isn't running can't be told")
    let source = permsSource("Shared/ArisAutomationAccess.swift")
    check(source.contains("typeWildCard, typeWildCard, false)") && !source.contains("typeWildCard, true)"),
          "perms automation: the check never asks the user")
}

private func permsNoRepeatPromptTests() {
    for file in ["ArisTools/ArisWindows.swift", "ArisTools/main.swift", "ArisAgent/ArisHelperAccess.swift"] {
        check(!permsSource(file).contains("kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true"),
              "perms prompts: \(file) never raises macOS's Accessibility alert")
    }
    let center = permsSource("Aris/private/Aris/Permissions/ArisPermissionCenter.swift")
    check(center.contains("ArisController.shared.notify(card)"), "perms center: its cards go through notify (the interruption policy)")
    check(center.contains("didBecomeActiveNotification"), "perms center: re-reads when Aris comes to the front")
    let entry = permsSource("Aris/private/App/ArisEntry.swift")
    check(entry.contains("ArisPermissionCenter.shared.start()"), "perms center: started at launch (it only reads)")
    check(!center.contains("checker.prompt(") || center.components(separatedBy: "checker.prompt(").count == 2,
          "perms center: macOS's dialog is raised in one place only, from require")
}

func runPermsTests() {
    permsSetupCardTests()
    permsSetupFlowTests()
    permsNoticeTests()
    permsLinkTests()
    permsAutomationTests()
    permsNoRepeatPromptTests()
}
