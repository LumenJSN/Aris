// Tests for the two first-run window defects the VM run of 2026-11-10 found (qa/vm-run-1110/REPORT.md, bugs 5 and 6):
// the setup window stays the window behind every macOS prompt of the permission page (Terminal covered it under the
// second prompt), and opening Aris again while the setup is unfinished brings the setup forward instead of Settings.
// Which window comes forward, whether Aris is an app with a Dock icon, and when the setup takes the front back from
// another app are pure rules (ArisOnboardingFront); no window is shown and no app is activated here.
// Called from main.swift; uses its check().
import Foundation

func runVMSetupTests() {
    vmSetupFrontTests()
    vmSetupReopenTests()
    vmSetupPolicyTests()
    vmSetupTakerTests()
    vmSetupHoldTests()
    MainActor.assumeIsolated { vmSetupPromptingTests() }
    vmSetupWiringTests()
}

private func source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The lines of a source file that are code (a comment may name what the code no longer does).
private func code(_ path: String) -> String {
    source(path).split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

private let everyPhase: [ArisOnboardingPhase] = [.intro, .flight, .talk, .handoff, .setup, .finish, .closed]

// MARK: - Which window comes forward

private func vmSetupFrontTests() {
    typealias F = ArisOnboardingFront
    check(F.front(after: .opened(quiet: false, reopened: false), phase: .setup) == .guide,
          "vm setup: at the first launch the setup window comes forward with the keyboard")
    check(F.front(after: .opened(quiet: true, reopened: true), phase: .setup) == .guide,
          "vm setup: after Quit & Reopen the setup window comes forward with the keyboard")
    check(F.front(after: .opened(quiet: true, reopened: false), phase: .setup) == .guideQuietly,
          "vm setup: a quiet resume at a later launch shows the setup in front without taking the keyboard")
    check(F.front(after: .permission(.promptAnswered), phase: .setup) == .guide && F.front(after: .permission(.promptAnswered), phase: .handoff) == .guide,
          "vm setup: when a macOS prompt closes the setup window comes forward")
    check(F.front(after: .permission(.granted), phase: .setup) == .guide,
          "vm setup: back from System Settings with the permission on, the setup window comes forward")
    check(everyPhase.allSatisfy { F.front(after: .permission(.settingsOpened), phase: $0) == .nothing },
          "vm setup: sent to System Settings for a permission, nothing of Aris's comes forward over it")
    check([ArisOnboardingPhase.intro, .flight, .talk, .finish, .closed].allSatisfy { phase in
        F.front(after: .permission(.promptAnswered), phase: phase) == .nothing && F.front(after: .permission(.granted), phase: phase) == .nothing
    }, "vm setup: a prompt answered or a permission turned on moves nothing once the setup window is not showing")
    check([ArisOnboardingPhase.intro, .flight, .talk, .handoff, .setup].allSatisfy { F.front(after: .settingsClosed, phase: $0) == .guide },
          "vm setup: Aris's settings window closing during the setup brings the setup forward")
    check(F.front(after: .settingsClosed, phase: .finish) == .nothing && F.front(after: .settingsClosed, phase: .closed) == .nothing,
          "vm setup: Aris's settings window closing after the setup moves nothing")
}

private func vmSetupReopenTests() {
    typealias F = ArisOnboardingFront
    check([ArisOnboardingPhase.intro, .flight, .talk, .handoff, .setup].allSatisfy { F.front(after: .reopened, phase: $0) == .guide },
          "vm bug 6: opening Aris again while the setup is unfinished brings the setup forward, not Settings")
    check(F.front(after: .reopened, phase: .closed) == .settings, "vm bug 6: opening Aris again after the setup opens Settings, as before")
    check(F.front(after: .reopened, phase: .finish) == .settings,
          "vm bug 6: once Finish was pressed the setup is over: opening Aris again opens Settings")
    check(everyPhase.allSatisfy { F.front(after: .reopened, phase: $0) != .nothing && F.front(after: .reopened, phase: $0) != .guideQuietly },
          "vm bug 6: opening Aris again always brings one window forward with the keyboard")
}

// MARK: - A Dock icon and a menu bar of its own while a window is open

private func vmSetupPolicyTests() {
    typealias F = ArisOnboardingFront
    check(F.regularApp(guideWindow: true, settingsOpen: false),
          "vm bug 5: while the setup window is open Aris is an app with a Dock icon and its own menu bar (macOS hands the screen back to it after a prompt)")
    check(F.regularApp(guideWindow: false, settingsOpen: true) && F.regularApp(guideWindow: true, settingsOpen: true),
          "vm setup: the settings window keeps the Dock icon, with or without the setup")
    check(!F.regularApp(guideWindow: false, settingsOpen: false), "vm setup: with neither window open Aris is the menu-bar app it always was")
}

// MARK: - Who came to the front

private func vmSetupTakerTests() {
    typealias F = ArisOnboardingFront
    let own = "com.lumenjsn.aris"
    check(F.taker(bundleID: own, own: own, regular: true) == .aris && F.taker(bundleID: own, own: own, regular: false) == .aris,
          "vm bug 5: Aris coming to the front is Aris")
    check(F.taker(bundleID: "com.apple.systempreferences", own: own, regular: true) == .systemSettings
          && F.taker(bundleID: "com.apple.SystemSettings", own: own, regular: true) == .systemSettings,
          "vm bug 5: System Settings is told apart from every other app")
    check(F.taker(bundleID: "com.apple.Terminal", own: own, regular: true) == .app, "vm bug 5: Terminal is another app with windows of its own")
    check(F.taker(bundleID: "com.apple.UserNotificationCenter", own: own, regular: false) == .agent
          && F.taker(bundleID: "com.apple.SecurityAgent", own: own, regular: false) == .agent && F.taker(bundleID: nil, own: own, regular: false) == .agent,
          "vm bug 5: what puts up macOS's prompts and password windows has no Dock icon, and is not taken for an app")
    check(F.taker(bundleID: nil, own: nil, regular: true) == .app, "vm bug 5: an app with no bundle id is still another app")
}

// MARK: - Taking the front back

private func vmSetupHoldTests() {
    typealias F = ArisOnboardingFront
    check(F.holds(against: .app, phase: .setup, prompting: true, sinceForward: nil, held: 0),
          "vm bug 5: another app coming forward while macOS's prompts are being answered gives the front back to the setup")
    check(F.holds(against: .app, phase: .setup, prompting: true, sinceForward: 40, held: 0),
          "vm bug 5: however long the first prompt took to answer, the setup is behind the second one")
    check(F.holds(against: .app, phase: .setup, prompting: false, sinceForward: 0.4, held: 0) && F.holds(against: .app, phase: .handoff, prompting: false, sinceForward: 0, held: 0),
          "vm bug 5: another app coming forward a moment after the setup did (macOS handing the screen back late) gives the front back to the setup")
    check(!F.holds(against: .app, phase: .setup, prompting: false, sinceForward: F.settle, held: 0) && !F.holds(against: .app, phase: .setup, prompting: false, sinceForward: 30, held: 0),
          "vm bug 5: after that moment, switching to another app is the user's own doing and is left alone")
    check(!F.holds(against: .app, phase: .setup, prompting: false, sinceForward: nil, held: 0),
          "vm bug 5: a setup that never took the front (a quiet resume) takes nothing back")
    check(!F.holds(against: .app, phase: .setup, prompting: false, sinceForward: -1, held: 0), "vm bug 5: a clock running backwards holds nothing")
    for prompting in [true, false] {
        check(!F.holds(against: .systemSettings, phase: .setup, prompting: prompting, sinceForward: 0.1, held: 0),
              "vm bug 5: System Settings coming forward is never covered by the setup (prompting \(prompting))")
        check(!F.holds(against: .agent, phase: .setup, prompting: prompting, sinceForward: 0.1, held: 0),
              "vm bug 5: macOS's own prompt keeps the keyboard it took (prompting \(prompting))")
        check(!F.holds(against: .aris, phase: .setup, prompting: prompting, sinceForward: 0.1, held: 0),
              "vm bug 5: Aris coming forward needs nothing done (prompting \(prompting))")
    }
    check([ArisOnboardingPhase.intro, .flight, .talk, .finish, .closed].allSatisfy { !F.holds(against: .app, phase: $0, prompting: true, sinceForward: 0.1, held: 0) },
          "vm bug 5: only while the setup window shows; nothing takes the front in normal use")
    check(F.holds(against: .app, phase: .setup, prompting: true, sinceForward: 0.1, held: F.maxHolds - 1)
          && !F.holds(against: .app, phase: .setup, prompting: true, sinceForward: 0.1, held: F.maxHolds),
          "vm bug 5: it gives up after a few tries, so two apps never fight over the front")
    check(F.settle >= 1 && F.settle <= 3 && F.maxHolds >= 2 && F.maxHolds <= 6 && F.recheck > 0 && F.recheck < F.settle,
          "vm bug 5: the moment is a second or two, the tries a handful, and the second look falls inside the moment")
}

// MARK: - macOS's prompts in flight

@MainActor private func vmSetupPromptingTests() {
    var grants: [ArisOnboardingStep: ArisGrant] = [:]
    var asked: [ArisOnboardingStep] = []
    var answers: [CheckedContinuation<Void, Never>] = []
    let actions = ArisOnboardingModel.Actions(grant: { grants[$0] ?? .undecided },
                                              request: { step in
                                                  asked.append(step)
                                                  await withCheckedContinuation { answers.append($0) }
                                              },
                                              stop: { _ in }, talkKeys: { ["⌥", "Space"] })
    func turn() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    func answer(_ step: ArisOnboardingStep, _ grant: ArisGrant) {
        grants[step] = grant
        answers.removeFirst().resume()
        turn()
    }

    let model = ArisOnboardingModel(actions: actions)
    var came: [String] = []
    model.onAsked = { step, prompted in came.append("\(step.rawValue):\(prompted):\(model.prompting)") }
    model.begin()
    check(!model.prompting, "vm bug 5: before 허용 no macOS prompt is up")
    model.allow(.mic)
    turn()
    check(asked == [.mic] && model.prompting, "vm bug 5: the microphone's prompt is up")
    answer(.mic, .granted)
    check(asked == [.mic, .speech] && model.prompting && came == ["mic:true:true"],
          "vm bug 5: between the microphone's answer and the speech recognition prompt, macOS's prompts are still being answered")
    answer(.speech, .granted)
    check(!model.prompting && came == ["mic:true:true", "speech:true:true"], "vm bug 5: after the second answer no prompt is up")

    // Refused before: macOS won't ask twice, so the card's 허용 opens System Settings and no prompt is in flight.
    grants = [.mic: .denied, .speech: .denied]
    asked = []
    came = []
    let refused = ArisOnboardingModel(actions: actions)
    refused.onAsked = { step, prompted in came.append("\(step.rawValue):\(prompted):\(refused.prompting)") }
    refused.begin()
    refused.allow(.mic)
    turn()
    check(asked == [.mic] && !refused.prompting, "vm bug 5: a microphone refused before opens System Settings: no prompt is up to hold the front for")
    answers.removeFirst().resume()
    turn()
    answers.removeFirst().resume()
    turn()
    check(came == ["mic:false:false", "speech:false:false"], "vm bug 5: the setup is told System Settings was opened, not that a prompt was answered")

    // The microphone on, speech recognition still to ask: one prompt.
    grants = [.mic: .granted]
    asked = []
    came = []
    let half = ArisOnboardingModel(actions: actions)
    half.onAsked = { step, prompted in came.append("\(step.rawValue):\(prompted):\(half.prompting)") }
    half.begin()
    half.allow(.mic)
    turn()
    check(asked == [.speech] && half.prompting, "vm bug 5: with the microphone already on only the speech recognition prompt is up")
    answer(.speech, .granted)
    check(!half.prompting && came == ["speech:true:true"], "vm bug 5: and once it is answered none is")

    // 나중에 with the prompt still up: the page moves on to System Settings' cards, so nothing is held for the prompt.
    grants = [:]
    asked = []
    let putOff = ArisOnboardingModel(actions: actions)
    putOff.begin()
    putOff.allow(.mic)
    turn()
    check(putOff.prompting, "vm bug 5: the microphone's prompt is up again")
    putOff.later(.mic)
    check(!putOff.prompting && putOff.flow.active == .accessibility, "vm bug 5: 나중에 while macOS's prompt is up stops holding the front for it")
    putOff.later(.accessibility)
    check(!putOff.prompting, "vm bug 5: putting off a System Settings card changes nothing about prompts")
    answers.removeFirst().resume()
    turn()
    answers.removeFirst().resume()
    turn()
    check(!putOff.prompting && answers.isEmpty, "vm bug 5: and once the left-over prompts are answered none is in flight")

    // System Settings cards never count as a prompt.
    grants = [.mic: .granted, .speech: .granted]
    asked = []
    let settings = ArisOnboardingModel(actions: actions)
    settings.begin()
    settings.allow(.accessibility)
    turn()
    check(asked == [.accessibility] && !settings.prompting, "vm bug 5: Accessibility is turned on in System Settings: no macOS prompt, nothing held")
    answers.removeFirst().resume()
    turn()
}

// MARK: - The rules are the ones the app runs

private func vmSetupWiringTests() {
    let entry = code("Aris/private/App/ArisEntry.swift")
    let reopen = entry.components(separatedBy: "func applicationShouldHandleReopen").dropFirst().first?.components(separatedBy: "func applicationShouldTerminateAfterLastWindowClosed").first ?? ""
    let guideAt = reopen.range(of: "ArisOnboardingGuide.shared.openedAgain()")?.lowerBound, settingsAt = reopen.range(of: "ArisSettingsWindow.shared.show()")?.lowerBound
    check(guideAt != nil && settingsAt != nil && guideAt! < settingsAt!, "vm bug 6: a reopen asks the setup first, and opens Settings only when the setup does not take it")

    let guide = code("Aris/private/Aris/Onboarding/ArisOnboardingGuide.swift"), setup = code("Aris/private/Aris/Onboarding/ArisOnboardingGuide+Setup.swift")
    let front = code("Aris/private/Aris/Onboarding/ArisOnboardingGuide+Front.swift")
    check(front.contains("ArisOnboardingFront.front(after: .reopened, phase: phase)") && front.contains("ArisOnboardingFront.front(after: .settingsClosed, phase: phase)"),
          "vm bug 6: the reopen and the settings window closing go through the rule")
    let surface = guide.components(separatedBy: "func surface()").dropFirst().first?.components(separatedBy: "func attach(").first ?? ""
    check(surface.contains("window.bringForward()") && !surface.contains("window.makeKeyAndOrderFront(nil)"),
          "vm bug 6: brought forward, the setup window is in front of other apps' windows (it stayed behind Terminal's)")
    check(setup.contains("ArisOnboardingFront.front(after: .opened(quiet: quiet, reopened: reopened), phase: phase)")
          && front.contains("ArisOnboardingFront.front(after: .permission(event), phase: phase)"),
          "vm setup: opening and the permission moments go through the rule")
    check(front.contains("ArisOnboardingFront.holds(against:") && front.contains("model?.prompting") && front.contains("ArisOnboardingFront.regularApp(guideWindow:"),
          "vm bug 5: the guide takes the front back, and sets the Dock icon, by the rules")
    check(code("Aris/private/Aris/Onboarding/ArisOnboardingWatch.swift").contains("NSWorkspace.didActivateApplicationNotification"),
          "vm bug 5: the guide hears of another app coming to the front while it shows")
    check(setup.contains("applyPolicy()") && guide.contains("applyPolicy()"), "vm bug 5: the Dock icon follows the guide's windows as they open and close")

    let settings = code("Aris/components/Settings/ArisSettingsWindow.swift")
    let closing = settings.components(separatedBy: "func windowWillClose").dropFirst().first?.components(separatedBy: "func windowDidMiniaturize").first ?? ""
    check(closing.contains("ArisOnboardingGuide.shared.hasWindow ? .regular : .accessory") && !closing.contains("NSApp.setActivationPolicy(.accessory)"),
          "vm bug 6: closing Settings during the setup leaves Aris the app in front (it handed the screen to Terminal)")
    check(closing.contains("ArisOnboardingGuide.shared.settingsClosed()"), "vm bug 6: closing Settings tells the setup, which comes forward")
}
