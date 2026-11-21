// jv-world: one world store with one observer per source (ARCHITECTURE.md 3.5), one interruption policy, the
// brief's conditions, the deadline of a to-do without a time, and the closed notch fed by deduplicated snapshots.
// ArisWorld, the controller and the notch need AppKit and can't be compiled here: the pure parts are run, the notices'
// mapping onto the policy is run on the real ArisNoticeRoute, and the wiring is checked in the sources.
import Foundation

private func worldSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func worldPolicyTests() {
    typealias I = ArisInterruption
    let job = I.Want(kind: .jobDone, spoken: true)
    check(I.decide(job, I.Moment()) == .speak, "world policy: a job's result is said at a free moment (the baseline)")
    check(I.decide(job, I.Moment(userSpeaking: true)) == .hold(.userStopsSpeaking), "world policy: nothing starts over the user's voice")
    check(I.decide(job, I.Moment(arisSpeaking: true)) == .hold(.arisStopsSpeaking), "world policy: nothing starts over Aris's own voice")
    check(I.decide(job, I.Moment(screenAway: true)) == .hold(.unlock), "world policy: a locked screen holds it for the unlock")
    check(I.decide(job, I.Moment(inCall: true)) == .hold(.callEnds), "world policy: a job's result waits for the call to end")
    check(I.decide(I.Want(kind: .timer, urgency: .high), I.Moment(inCall: true)) == .show, "world policy: a timer shows in a call, quietly")
    check(I.decide(I.Want(kind: .teammateAsks, needsAnswer: true, spoken: true), I.Moment(inCall: true)) == .show,
          "world policy: a question waiting for the user shows in a call, quietly")
    check(I.decide(job, I.Moment(mayMakeSound: false)) == .show, "world policy: muted or quiet hours keep it to the pill (the baseline)")
    check(I.decide(job, I.Moment(otherAudio: true, headphones: true)) == .speak, "world policy: music and headphones change nothing for a job")
}

private func worldNoticeMappingTests() {
    let now = Date()
    let due = ArisDue(id: "d", course: "CSC263", title: "PS3", at: now.addingTimeInterval(3_600), url: nil)
    check(ArisNoticeRoute.want(ArisNoticeRoute.deadline(due, .hoursBefore, now: now, english: false), spoken: false)
            == ArisInterruption.Want(kind: .deadline, urgency: .high), "world mapping: a deadline 3 h off is urgent")
    check(ArisNoticeRoute.want(ArisNoticeRoute.deadline(due, .dayBefore, now: now, english: false), spoken: false).urgency == .normal,
          "world mapping: a deadline a day off is not")
    check(ArisNoticeRoute.want(ArisNoticeRoute.timer(title: "t", text: "x"), spoken: false).kind == .timer, "world mapping: a timer")
    check(ArisNoticeRoute.want(ArisNoticeRoute.teammateAsks(title: "t", said: "s", english: false), spoken: true)
            == ArisInterruption.Want(kind: .teammateAsks, needsAnswer: true, spoken: true), "world mapping: a teammate's question waits on the user")
    check(ArisNoticeRoute.want(ArisNoticeRoute.announcement(title: "t", text: "x", kind: .done), spoken: true).kind == .jobDone,
          "world mapping: a job done")
    check(ArisNoticeRoute.want(ArisNoticeRoute.helperDown(english: false), spoken: false).kind == .problem, "world mapping: a problem")
    check(ArisNoticeRoute.want(ArisNotice(key: ArisUpdateWords.key, kind: .system, title: "u", body: ""), spoken: false)
            == ArisInterruption.Want(kind: .update, urgency: .low), "world mapping: an update can wait")
    check(ArisNoticeRoute.updateKey == ArisUpdateWords.key, "world mapping: the update's key is the updater's")
    check(ArisNoticeRoute.want(ArisNotice(kind: .system, title: "n", body: ""), spoken: true).kind == .news, "world mapping: Aris's own news")
}

private func worldWiringTests() {
    let wake = worldSource("Aris/private/Aris/ArisController+Wake.swift")
    check(!wake.contains("com.apple.screenIsLocked") && wake.contains("ArisWorld.shared.subscribe([.screen])"),
          "world wiring: the wake word hears the lock and sleep from ArisWorld")
    check(!wake.contains("ArisMicWatch {") && wake.contains("change == .audioDevices"),
          "world wiring: the wake word hears device changes from ArisWorld")
    let brief = worldSource("Aris/private/Aris/ArisController+Brief.swift")
    check(!brief.contains("DistributedNotificationCenter") && brief.contains("ArisBriefCheck.step("),
          "world wiring: the brief comes on the world's unlock and asks ArisBriefCheck")
    let entry = worldSource("Aris/private/App/ArisEntry.swift")
    check(!entry.contains("com.apple.screenIsLocked") && entry.contains("ArisWorld.shared.subscribe([.screen])"),
          "world wiring: the notch windows hear the lock from ArisWorld")
    let pill = worldSource("Aris/private/Aris/Dictation/ArisDictationPillCenter.swift")
    check(!pill.contains("didActivateApplicationNotification") && !pill.contains("com.apple.screenIsLocked")
            && !pill.contains("didChangeScreenParametersNotification"), "world wiring: the dictation pill hears the front app, displays and lock from ArisWorld")
    let rest = worldSource("Aris/private/Aris/ArisWakeRestLive.swift")
    check(!rest.contains("ArisMicWatch {") && !rest.contains("didChangeScreenParametersNotification"),
          "world wiring: the wake word's rest hears devices and displays from ArisWorld")
    let center = worldSource("Aris/private/Aris/Notice/ArisNoticeCenter.swift")
    check(!center.contains("didChangeScreenParametersNotification"), "world wiring: the notice pill hears displays from ArisWorld")
    let teammate = worldSource("Aris/private/Aris/ArisController+Teammate.swift")
    check(!teammate.contains("ClaudeStore.shared.onEvent =") && teammate.contains("subscribe([.claude])"),
          "world wiring: the teammate watch hears hook events from ArisWorld, which holds the store's one slot")
    let controller = worldSource("Aris/private/Aris/ArisController.swift")
    check(controller.contains("frontApp: ArisWorld.shared.snapshot.frontApp?.name"), "world wiring: a turn's context reads the front app from the snapshot")
    check(controller.contains("ArisWorld.shared.start(aris: self)"), "world wiring: the world starts with the controller")
    let notice = worldSource("Aris/private/Aris/Notice/ArisController+Notice.swift")
    check(notice.contains("if case .hold = now") && notice.contains("decision.comesUp else { return nil }")
            && notice.contains("decision == .speak { await self.sayNews(said) }"),
          "world wiring: notify waits on the policy outside the line and says the line only when it says speak")
    let voice = worldSource("Aris/private/Aris/ArisController+Conversation.swift")
    check(voice.contains("ArisWorld.shared.heardVoice(talking)"), "world wiring: the user's voice reaches the world outside a conversation too")
    let todos = worldSource("Aris/private/Aris/ArisTodoModel.swift")
    check(todos.contains("ArisDeadlineDate.mayAlert(") && todos.contains("ArisDeadlineDate.deadline("),
          "world wiring: a to-do's deadline alert reads ArisDeadlineDate")
}

private func worldNotchTests() {
    let root = worldSource("Aris/private/Notch/ArisNotchRoot.swift")
    check(!root.contains("ClaudeStore.shared"), "notch cpu: the root no longer observes ClaudeStore (each hook event re-evaluated it)")
    check(!root.contains("@Default("), "notch cpu: the root reads no preference through @Default")
    let vnotch = worldSource("Aris/private/Notch/ArisNotchRoot+VNotch.swift")
    check(!vnotch.contains("UserDefaults.standard"), "notch cpu: starMayRest reads the closed rest from the snapshot")
    let behaviour = worldSource("Aris/private/Notch/ArisNotchRoot+Behaviour.swift")
    check(!behaviour.contains("root.claude.") && behaviour.contains("root.claudeFeed.current.approvals"),
          "notch cpu: the approvals' animation reads the deduplicated snapshot")
    let feeds = worldSource("Aris/private/Aris/ArisNotchFeeds.swift")
    check(feeds.contains("if next != self.current { self.current = next }"), "notch cpu: the snapshots publish only a change")
    for key in ["enableGestures", "closeGestureEnabled", "enableHorizontalMediaGestures", "gestureSensitivity", "enableHaptics",
                "openNotchOnHover", "minimumHoverDuration", "shelfEnabled", "sneakPeekStyles", "cornerRadiusScaling", "arisMuted",
                "arisRestStar", "arisClosedRestRaw"] {
        check(feeds.contains("Defaults.publisher(.\(key)") && feeds.contains("Defaults[.\(key)]"), "notch cpu: \(key) is watched and read")
    }
}

func runWorldTests() {
    worldPolicyTests()
    worldNoticeMappingTests()
    worldWiringTests()
    worldNotchTests()
}
