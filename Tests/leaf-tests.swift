// Acceptance tests for the clean-room small leaves: swipes, app icons, AppleScript (cleanroom-specs/05, 14).
import AppKit
import Foundation

func runLeafTestsBlocking() {
    panTests()
    appIconTests()
    final class Done: @unchecked Sendable { var value = false }
    let done = Done()
    Task {
        await appleScriptTests()
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private func panTests() {
    typealias T0 = ArisPanTracker
    var down = ArisPanTracker(direction: .down, threshold: 4)
    check(down.move(2) == nil && down.move(0.1) == nil, "swipe: below the threshold nothing is reported; |Δ| ≤ 0.2 is noise")
    let began = down.move(3)
    check(began?.0 == 5 && began?.1 == .began, "swipe: it begins once the total reaches the threshold")
    let changed = down.move(10)
    check(changed?.0 == 15 && changed?.1 == .changed, "swipe: then reports the running total")
    let reset = down.move(-1)
    check(reset?.0 == 0 && reset?.1 == .changed, "swipe: moving against the direction starts over (.changed 0 once begun)")
    _ = down.move(6)
    let ended = down.end()
    check(ended?.0 == 6 && ended?.1 == .ended && down.end() == nil && !down.began, "swipe: ends once with the total, then starts afresh")
    var never = ArisPanTracker(direction: .down, threshold: 4)
    check(never.move(1) == nil && never.move(-3) == nil, "swipe: a reversal before it began reports nothing")
    let quiet = never.end()
    check(quiet?.0 == 0 && quiet?.1 == .ended, "swipe: a scroll that never began ends with 0")
    var up = ArisPanTracker(direction: .up, threshold: 4)
    check(up.move(5) == nil && up.move(-6)?.0 == 6, "swipe: an up swipe reports a positive distance to the up handler")
    var left = ArisPanTracker(direction: .left, threshold: 4)
    let leftBegan = left.move(-4), leftMore = left.move(-1)
    check(leftBegan?.0 == 4 && leftBegan?.1 == .began && leftMore?.0 == 5, "swipe: a left swipe reports positive distances to the left handler")
    check(T0.dragDistance(12, direction: .down, threshold: 4) == 12 && T0.dragDistance(-12, direction: .up, threshold: 4) == 12
          && T0.dragDistance(-9, direction: .left, threshold: 4) == 9 && T0.dragDistance(9, direction: .right, threshold: 4) == 9,
          "drag: the distance along the direction, positive")
    check(T0.dragDistance(3, direction: .down, threshold: 4) == nil && T0.dragDistance(-12, direction: .down, threshold: 4) == nil,
          "drag: nothing below the threshold or against the direction")

    typealias T = ArisPanTracker
    check(T.scrollDelta(dx: 1, dy: 10, precise: true, invertedFromDevice: true, normalize: true, vertical: true) == 10,
          "scroll: natural scrolling, fingers down -> positive")
    check(T.scrollDelta(dx: 1, dy: -10, precise: true, invertedFromDevice: false, normalize: true, vertical: true) == 10,
          "scroll: classic scrolling is flipped to follow the fingers when normalising")
    check(T.scrollDelta(dx: 1, dy: -10, precise: true, invertedFromDevice: false, normalize: false, vertical: true) == -10,
          "scroll: without normalising, deltas are taken as they come")
    check(T.scrollDelta(dx: 7, dy: 10, precise: true, invertedFromDevice: true, normalize: true, vertical: true) == nil
          && T.scrollDelta(dx: 6, dy: 9, precise: true, invertedFromDevice: true, normalize: true, vertical: true) == 9,
          "scroll: the axis must dominate by 1.5×")
    check(T.scrollDelta(dx: 2, dy: 0, precise: false, invertedFromDevice: true, normalize: true, vertical: false) == 16,
          "scroll: mouse-wheel deltas count 8×")
}

private func appIconTests() {
    let n = ArisAppIcon.normalized
    check(n(" com.spotify.client \n") == "com.spotify.client", "app icon: ids are trimmed")
    check(n("com.apple.WebKit.WebContent") == "com.apple.Safari" && n("com.apple.Safari.SafeBrowsing") == "com.apple.Safari",
          "app icon: WebKit and Safari helpers map to Safari")
    check(n("com.apple.SafariTechnologyPreview.WebContent") == "com.apple.SafariTechnologyPreview", "app icon: Technology Preview helpers")
    check(n("com.google.Chrome.helper.renderer") == "com.google.Chrome" && n("com.brave.Browser.Helper") == "com.brave.Browser",
          "app icon: an id is cut before its helper component")
    check(n("com.example.helperapp") == "com.example.helperapp" && n("com.apple.Music") == "com.apple.Music", "app icon: other ids stay")
    typealias App = ArisAppIcon.RunningApp
    let apps = [App(bundleID: "com.x.App.helper", bundleURL: URL(fileURLWithPath: "/a"), isRegular: false, isTerminated: false, pid: 10),
                App(bundleID: "com.x.App", bundleURL: URL(fileURLWithPath: "/b"), isRegular: true, isTerminated: false, pid: 40),
                App(bundleID: "com.x.App", bundleURL: URL(fileURLWithPath: "/c"), isRegular: true, isTerminated: false, pid: 20),
                App(bundleID: "com.x.App", bundleURL: URL(fileURLWithPath: "/d"), isRegular: true, isTerminated: true, pid: 5)]
    check(ArisAppIcon.pick(apps, for: "com.x.App")?.path == "/c", "app icon: a running app, regular first, then the lowest pid")
    check(ArisAppIcon.pick(apps, for: "com.y") == nil, "app icon: none running -> nil")
    check(appIconAsNSImage(for: "com.example.does-not-exist") == nil, "app icon: as artwork, an unknown app is nil (the placeholder shows)")
    check(appIconAsNSImage(for: "com.apple.finder")?.size == NSSize(width: 256, height: 256), "app icon: as artwork, sized 256 × 256")
}

private func appleScriptTests() async {
    let result = try? await ArisAppleScript.run("return 40 + 2")
    check(result == "42", "applescript: runs out of process (osascript) and returns the result as text")
    do {
        _ = try await ArisAppleScript.run("error \"nope\" number 7")
        check(false, "applescript: a script error throws")
    } catch let error as ArisAppleScriptError {
        check(error.message == "nope" && error.number == 7, "applescript: a script error throws with its message")
    } catch {
        check(false, "applescript: unexpected error type")
    }
}
