// Tests for QA BUG-38 (the wake word never armed, and a spoken follow-up in an open conversation wasn't heard):
// each guard that holds the microphone back has a reason, logged once per change; a paused Spotify's open output
// stream (no meter reading) no longer counts as another app's sound; a missed "screen back" notice can't hold the
// microphone off for good.
import Foundation

func runQAWakeTests() {
    typealias A = ArisWakeArm
    check(A.blocker(A.State()) == nil, "BUG-38: nothing in the way: arm it")
    check(A.blocker(A.State(settingOn: false)) == .settingOff && A.blocker(A.State(settingOn: false, conversationOpen: true)) == nil,
          "BUG-38: the setting off holds the idle wake word, never a conversation's listening")
    check(A.blocker(A.State(idle: false)) == .busy && A.blocker(A.State(training: true)) == .training
          && A.blocker(A.State(listenerOpen: true)) == .listenerOpen && A.blocker(A.State(screenAway: true)) == .screenAway
          && A.blocker(A.State(permissionOK: false)) == .permission, "BUG-38: every guard has its reason")
    check(A.blocker(A.State(conversationOpen: true, otherAudio: true)) == .otherAudio && A.blocker(A.State(otherAudio: true)) == nil,
          "BUG-38: other audio holds only listening between turns")
    var log = A.Log()
    check(log.line(for: .screenAway) == "wake word not armed: the screen is locked or asleep" && log.line(for: .screenAway) == nil,
          "BUG-38: a reason is logged once, not on every try")
    check(log.line(for: .busy) == nil && log.line(for: .screenAway) != nil, "BUG-38: a turn under way isn't logged, and the reason again after it")
    check(log.line(for: nil) == nil && log.line(for: .otherAudio) != nil, "BUG-38: armed resets it")

    // The stuck state: Spotify running but paused keeps an output stream open; with no meter reading (System Audio
    // not granted: only zeros) that counted as another app's sound, so between turns never listened.
    let spotify = ArisOtherAudio.Process(pid: 900, bundle: "com.spotify.client", output: true, input: false)
    check(ArisOtherAudio.isPresent([spotify], ownPid: 1), "BUG-38: (the old rule) an open stream with no reading counts")
    check(!ArisOtherAudio.isPresent([spotify], ownPid: 1, pausedPlayers: ArisOtherAudio.pausedPlayers(nowPlaying: false)),
          "BUG-38: a paused Spotify (Now Playing says nothing plays) isn't another app's sound")
    check(ArisOtherAudio.isPresent([spotify], ownPid: 1, pausedPlayers: ArisOtherAudio.pausedPlayers(nowPlaying: true)),
          "BUG-38: a playing one still is")
    let zoom = ArisOtherAudio.Process(pid: 901, bundle: "us.zoom.xos", output: true, input: false)
    check(ArisOtherAudio.isPresent([spotify, zoom], ownPid: 1, pausedPlayers: ArisOtherAudio.pausedPlayers(nowPlaying: false)),
          "BUG-38: any other app's open stream still counts")
    check(ArisOtherAudio.isPresent([spotify], ownPid: 1, outputLevel: 0.2, pausedPlayers: ArisOtherAudio.pausedPlayers(nowPlaying: false)),
          "BUG-38: with a reading, the sound itself decides")
    let mic = ArisOtherAudio.Process(pid: 900, bundle: "com.spotify.client", output: false, input: true)
    check(ArisOtherAudio.isPresent([mic], ownPid: 1, pausedPlayers: ArisOtherAudio.musicPlayers), "BUG-38: recording always counts")

    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris")
    let wake = (try? String(contentsOf: root.appendingPathComponent("ArisController+Wake.swift"), encoding: .utf8)) ?? ""
    let controller = (try? String(contentsOf: root.appendingPathComponent("ArisController.swift"), encoding: .utf8)) ?? ""
    check(wake.contains("if screenAway, !Self.screenIsAwayNow()") && wake.contains("wakeArmLog.line(for: blocker)"),
          "BUG-38: the screen is asked directly, and the reason logged")
    check(controller.contains("screenAway = false\n"), "BUG-38: the talk key says the screen is on")
}
