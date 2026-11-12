// Tests for the owner's ①B (mockups/new-features.html §1, option B): while the talk key is held or the circle mode is on,
// a click on a window picks it (a light yellow wash over the whole window) and a second click lets it go; the picked
// windows go with the question as image chips. Called from main.swift; uses its check().
import AppKit
import Foundation

func runWindowPickTests() {
    windowPickArmingTests()
    windowPickToggleTests()
    windowPickHitTests()
    windowPickPrivacyTests()
    windowPickGeometryTests()
    windowPickWashTests()
    windowPickMergeTests()
    windowPickShotTests()
    windowPickSessionCapTests()
}

private func pickHit(_ id: UInt32, bundle: String? = "com.apple.Safari", frame: CGRect = CGRect(x: 0, y: 0, width: 400, height: 300),
                     app: String? = "Safari", title: String? = "Canvas") -> ArisWindowHit {
    ArisWindowHit(id: id, pid: Int32(id) + 100, app: app, title: title, frame: frame, samples: 1, hitCenter: true, bundleId: bundle)
}

// MARK: - When picking is on

private func windowPickArmingTests() {
    check(ArisWindowPick.arms(gestureKey: false, committed: true, handsFree: false),
          "pick: the talk key held past the commit window picks (⌥ Space 누른 채)")
    check(!ArisWindowPick.arms(gestureKey: false, committed: true, handsFree: true),
          "pick: a talk-key tap (hands-free voice) doesn't pick, so clicks reach the apps")
    check(ArisWindowPick.arms(gestureKey: true, committed: true, handsFree: false)
          && ArisWindowPick.arms(gestureKey: true, committed: true, handsFree: true),
          "pick: the circle mode picks held and hands-free (동그라미 모드)")
    check(!ArisWindowPick.arms(gestureKey: true, committed: false, handsFree: false)
          && !ArisWindowPick.arms(gestureKey: false, committed: false, handsFree: false),
          "pick: nothing picks before the press commits")
}

// MARK: - Toggle

private func windowPickToggleTests() {
    var s = ArisWindowPickState()
    check(s.toggle(pickHit(1), otherShots: 0, voicedMs: 0, at: 0, display: 1) == .ignored && s.picks.isEmpty,
          "pick: a click before arming does nothing")
    s.arm()
    guard case .added(let first) = s.toggle(pickHit(1), otherShots: 0, voicedMs: 120, at: 10, display: 1) else {
        return check(false, "pick: a click on a window picks it")
    }
    check(first.hit.id == 1 && first.voicedMs == 120 && first.at == 10 && first.display == 1 && s.ids == [1],
          "pick: a click on a window picks it, with the voiced time for its [img N] marker")
    _ = s.toggle(pickHit(2), otherShots: 0, voicedMs: 300, at: 20, display: 1)
    _ = s.toggle(pickHit(3), otherShots: 0, voicedMs: 500, at: 30, display: 2)
    check(s.ids == [1, 2, 3], "pick: picks keep the order they were made in")
    check(s.toggle(pickHit(2), otherShots: 0, voicedMs: 0, at: 40, display: 1) == .removed(pickHit(2)) && s.ids == [1, 3],
          "pick: a second click on a picked window lets it go")
    let moved = pickHit(3, frame: CGRect(x: 50, y: 50, width: 200, height: 200))
    check(s.toggle(moved, otherShots: 0, voicedMs: 0, at: 50, display: 1) == .removed(moved) && s.ids == [1],
          "pick: a window is matched by its id, so one that moved still lets go")
    check(s.toggle(nil, otherShots: 0, voicedMs: 0, at: 60, display: 1) == .ignored && s.ids == [1],
          "pick: a click on the desktop (no window) does nothing")
    check(s.drop(window: 1) && s.ids.isEmpty && !s.drop(window: 1), "pick: a pick whose capture failed is dropped once")
    _ = s.toggle(pickHit(5), otherShots: 0, voicedMs: 0, at: 70, display: 1)
    s.disarm()
    check(s.toggle(pickHit(6), otherShots: 0, voicedMs: 0, at: 80, display: 1) == .ignored && s.ids == [5],
          "pick: disarmed (a talk-key tap went hands-free), clicks do nothing and the picks stay for the turn")
    s.reset()
    check(s.ids.isEmpty && !s.armed, "pick: reset forgets everything")

    // The cap: 8 shots in all, circles included.
    var full = ArisWindowPickState()
    full.arm()
    for id in 1...8 { _ = full.toggle(pickHit(UInt32(id)), otherShots: 0, voicedMs: 0, at: Double(id), display: 1) }
    check(full.ids.count == 8 && full.toggle(pickHit(9), otherShots: 0, voicedMs: 0, at: 9, display: 1) == .full(pickHit(9))
          && full.ids.count == 8, "pick: the 9th window is refused with the 8/8 capsule (the shot cap is 8)")
    check(full.toggle(pickHit(4), otherShots: 0, voicedMs: 0, at: 10, display: 1) == .removed(pickHit(4)) && full.ids.count == 7,
          "pick: at the cap a picked window can still be let go")
    var mixed = ArisWindowPickState()
    mixed.arm()
    _ = mixed.toggle(pickHit(1), otherShots: 6, voicedMs: 0, at: 1, display: 1)
    _ = mixed.toggle(pickHit(2), otherShots: 6, voicedMs: 0, at: 2, display: 1)
    check(mixed.ids == [1, 2], "pick: circled shots and picks share the cap (6 circles + 2 picks)")
    check(mixed.toggle(pickHit(3), otherShots: 6, voicedMs: 0, at: 3, display: 1) == .full(pickHit(3)),
          "pick: 6 circles + 2 picks is the cap: a third pick is refused")
}

// MARK: - Hit-testing

private func windowPickHitTests() {
    func window(_ n: Int, pid: Int32, _ r: CGRect, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
        [kCGWindowNumber as String: n, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
         kCGWindowAlpha as String: alpha, kCGWindowOwnerName as String: "App\(pid)", kCGWindowName as String: "W\(n)",
         kCGWindowBounds as String: r.dictionaryRepresentation]
    }
    let windows = [
        window(1, pid: 1, CGRect(x: 0, y: 0, width: 3000, height: 2000)),          // Aris's own pick overlay
        window(2, pid: 2, CGRect(x: 0, y: 0, width: 3000, height: 25), layer: 24), // menu bar
        window(3, pid: 3, CGRect(x: 0, y: 0, width: 3000, height: 2000), alpha: 0), // invisible
        window(4, pid: 4, CGRect(x: 600, y: 150, width: 300, height: 170)),         // a note in front
        window(5, pid: 5, CGRect(x: 30, y: 60, width: 1000, height: 400)),          // a browser behind it
    ]
    let bundle: (Int32) -> String? = { $0 == 4 ? "com.apple.Notes" : $0 == 5 ? "com.apple.Safari" : nil }
    check(ArisWindowAtPoint.front(at: CGPoint(x: 700, y: 200), windows: windows, ownPid: 1, bundle: bundle)?.id == 4,
          "pick hit: the frontmost window under the click, never Aris's own overlay")
    check(ArisWindowAtPoint.front(at: CGPoint(x: 100, y: 100), windows: windows, ownPid: 1, bundle: bundle)?.id == 5
          && ArisWindowAtPoint.front(at: CGPoint(x: 100, y: 100), windows: windows, ownPid: 1, bundle: bundle)?.bundleId == "com.apple.Safari",
          "pick hit: where the front window doesn't reach, the one behind it, with its bundle id")
    check(ArisWindowAtPoint.front(at: CGPoint(x: 2500, y: 1500), windows: windows, ownPid: 1, bundle: bundle) == nil,
          "pick hit: the desktop (only invisible or other-layer windows) is no window")
    check(ArisWindowAtPoint.front(at: CGPoint(x: 2500, y: 10), windows: windows, ownPid: 1, bundle: bundle) == nil,
          "pick hit: the menu bar is never picked")
}

// MARK: - Privacy

private func windowPickPrivacyTests() {
    var s = ArisWindowPickState()
    s.arm()
    let passwords = pickHit(70, bundle: "com.apple.Passwords", app: "Passwords")
    check(s.toggle(passwords, otherShots: 0, voicedMs: 0, at: 0, display: 1) == .refused(passwords) && s.ids.isEmpty,
          "pick privacy: a password app's window is refused (the red refusal), never picked")
    let helper = pickHit(80, bundle: "com.1password.1password.helper")
    check(s.toggle(helper, otherShots: 0, voicedMs: 0, at: 0, display: 1) == .refused(helper),
          "pick privacy: a helper inside a private app is refused too")
    let unknown = pickHit(90, bundle: nil)
    check(s.toggle(unknown, otherShots: 0, voicedMs: 0, at: 0, display: 1) == .refused(unknown) && s.ids.isEmpty,
          "pick privacy: a window whose owner can't be resolved is refused (fail closed)")
    var full = ArisWindowPickState()
    full.arm()
    for id in 1...8 { _ = full.toggle(pickHit(UInt32(id)), otherShots: 0, voicedMs: 0, at: 0, display: 1) }
    check(full.toggle(passwords, otherShots: 0, voicedMs: 0, at: 0, display: 1) == .refused(passwords),
          "pick privacy: at the cap a private window still gets the privacy refusal, not 8/8")
    check(ArisWindowPick.mayCapture(bundleId: "com.apple.Safari", pid: 5, ownPid: 1, ownBundleId: "com.lumenjsn.aris")
          && !ArisWindowPick.mayCapture(bundleId: "com.apple.Passwords", pid: 5, ownPid: 1, ownBundleId: "com.lumenjsn.aris")
          && !ArisWindowPick.mayCapture(bundleId: nil, pid: 5, ownPid: 1, ownBundleId: "com.lumenjsn.aris")
          && !ArisWindowPick.mayCapture(bundleId: "com.lumenjsn.aris", pid: 9, ownPid: 1, ownBundleId: "com.lumenjsn.aris")
          && !ArisWindowPick.mayCapture(bundleId: "com.apple.Safari", pid: 1, ownPid: 1, ownBundleId: "com.lumenjsn.aris"),
          "pick privacy: at capture the window's owner is checked again: never a private app, an unknown owner or Aris")
    check(!ArisWindowPick.listens(setting: true, permission: true, secureInput: true)
          && !ArisWindowPick.listens(setting: true, permission: false, secureInput: false)
          && !ArisWindowPick.listens(setting: false, permission: true, secureInput: false)
          && ArisWindowPick.listens(setting: true, permission: true, secureInput: false),
          "pick privacy: no picking under secure input, without the Screen Recording grant or with 동그라미로 가리키기 off")
}

// MARK: - Geometry

private func windowPickGeometryTests() {
    // Primary 1512×982 at the origin; a second display above-right of it in Cocoa space.
    let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let second = CGRect(x: 1512, y: 300, width: 1920, height: 1080)
    check(ArisWindowPickGeometry.quartz(CGPoint(x: 100, y: 900), primaryHeight: primary.height) == CGPoint(x: 100, y: 82),
          "pick geometry: a Cocoa click becomes a Quartz (top-left) point for the window list")
    check(ArisWindowPickGeometry.quartzBounds(ofCocoa: second, primaryHeight: primary.height)
          == CGRect(x: 1512, y: 982 - 1380, width: 1920, height: 1080),
          "pick geometry: a display's Cocoa frame as Quartz bounds")
    let display = ArisWindowPickGeometry.quartzBounds(ofCocoa: primary, primaryHeight: primary.height)
    check(ArisWindowPickGeometry.local(CGRect(x: 36, y: 64, width: 540, height: 372), display: display)
          == CGRect(x: 36, y: 64, width: 540, height: 372),
          "pick geometry: on the primary display a window's Quartz frame is its panel-local rect")
    let other = ArisWindowPickGeometry.quartzBounds(ofCocoa: second, primaryHeight: primary.height)
    check(ArisWindowPickGeometry.local(CGRect(x: 1600, y: -300, width: 400, height: 300), display: other)
          == CGRect(x: 88, y: 98, width: 400, height: 300),
          "pick geometry: on another display, relative to that display's top-left")
    check(ArisWindowPickGeometry.local(CGRect(x: 36, y: 64, width: 540, height: 372), display: other) == nil,
          "pick geometry: a window on another display gets no wash here")
    let straddling = ArisWindowPickGeometry.local(CGRect(x: 1400, y: 100, width: 300, height: 200), display: display)
    check(straddling == CGRect(x: 1400, y: 100, width: 300, height: 200),
          "pick geometry: a window across two displays is washed whole on each (not clipped: its corners stay round)")
}

// MARK: - The wash (ink E, option B)

private func windowPickWashTests() {
    typealias W = ArisWindowPickWash
    check(W.fillAlpha == 0.13 && W.ringAlpha == 0.34 && W.ringWidth == 2 && W.hoverAlpha == 0.28 && W.hoverWidth == 1.5,
          "pick wash: B's values, a .13 yellow wash with a 2 pt ring at ink E's .34; hover a 1.5 pt ring at .28")
    check(W.color == ArisInkRenderer.markerColor, "pick wash: ink E's yellow, rgb(255,214,10)")
    check(W.reveal(ageMs: 0) == 0 && W.reveal(ageMs: W.sweepMs) == 1 && W.reveal(ageMs: 5000) == 1
          && W.reveal(ageMs: 100) > 0.5 && W.reveal(ageMs: 100) < 1,
          "pick wash: one sweep from the left over 340 ms, ease-out (.23,1,.32,1), then it stays")
    check(W.fade(sinceMs: 0) == 1 && W.fade(sinceMs: W.fadeMs) == 0 && W.fade(sinceMs: 90) > 0 && W.fade(sinceMs: 90) < 1,
          "pick wash: a let-go wash fades out over 180 ms")
    check(W.hover(sinceMs: 0, on: true) == 0 && W.hover(sinceMs: W.hoverMs, on: true) == 1
          && W.hover(sinceMs: 0, on: false) == 1 && W.hover(sinceMs: W.hoverMs, on: false) == 0,
          "pick wash: the hover ring comes and goes over 160 ms")
    check(W.settled(ageMs: W.sweepMs) && !W.settled(ageMs: W.sweepMs - 1),
          "pick wash: once swept it is still: nothing repeats or blinks")
    check(W.cornerRadius(macOSMajor: 26) == 16 && W.cornerRadius(macOSMajor: 15) == 10,
          "pick wash: corners follow the system's window corners")
}

// MARK: - Into the turn

private func pickShot(_ badge: Int, voiced: Double = 0, at: Double = 0) -> ArisGestureShot {
    ArisGestureShot(badge: badge, app: "App", title: "T", jpeg: Data([1]), thumb: Data([2]), voicedMsAtCapture: voiced,
                    capturedAtMs: at, display: 1)
}

private func windowPickMergeTests() {
    check(ArisWindowPickMerge.badges(taken: [], count: 3) == [1, 2, 3], "pick merge: picks alone are numbered 1, 2, 3")
    check(ArisWindowPickMerge.badges(taken: [1, 2], count: 2) == [3, 4], "pick merge: picks follow the circles' numbers")
    check(ArisWindowPickMerge.badges(taken: [1, 3], count: 2) == [2, 4], "pick merge: picks take the free numbers, never a circle's")
    check(ArisWindowPickMerge.badges(taken: [1, 2, 3, 4, 5, 6], count: 4) == [7, 8], "pick merge: never past 8 in all")

    let speech = (startedAtMs: 0.0, endedAtMs: 4000.0, totalVoicedMs: 3000.0)
    let picksOnly = ArisWindowPickMerge.merge(nil, picks: [pickShot(1), pickShot(2)], speech: speech)
    check(picksOnly?.shots.map(\.badge) == [1, 2] && picksOnly?.references.isEmpty == true && picksOnly?.speech?.totalVoicedMs == 3000
          && picksOnly?.images().map(\.name) == ["gesture-screenshot-1.jpg", "gesture-screenshot-2.jpg"]
          && picksOnly?.images().allSatisfy({ $0.kind == .gesture }) == true,
          "pick merge: the picked windows go as numbered shots with the speech window, no screenshot")
    let drawn = ArisGestureResult(shots: [], references: [Data([9])], speech: speech, handsFree: false)
    let noRefs = ArisWindowPickMerge.merge(drawn, picks: [pickShot(1)], speech: nil)
    check(noRefs?.references.isEmpty == true && noRefs?.shots.count == 1,
          "pick merge: with picks and no circled shot only the picked windows go (the drawing of the screen is dropped)")
    let circled = ArisGestureResult(shots: [pickShot(1)], references: [Data([9])], speech: speech, handsFree: true)
    let both = ArisWindowPickMerge.merge(circled, picks: [pickShot(2)], speech: nil)
    check(both?.shots.map(\.badge) == [1, 2] && both?.references.count == 1 && both?.handsFree == true,
          "pick merge: circles keep their drawing reference and numbers; picks join them")
    let many = ArisGestureResult(shots: (1...6).map { pickShot($0) }, references: [], speech: speech, handsFree: false)
    check(ArisWindowPickMerge.merge(many, picks: (7...9).map { pickShot($0) }, speech: nil)?.shots.count == 8,
          "pick merge: 8 shots at most, whatever raced")
    check(ArisWindowPickMerge.merge(nil, picks: [], speech: speech) == nil && ArisWindowPickMerge.merge(drawn, picks: [], speech: nil)?.references.count == 1,
          "pick merge: no picks leaves the drawing as it was; nothing at all is no drawing")
    let turn = ArisGestureTurn(result: picksOnly)
    check(turn?.hasShots == true && turn?.display("이거 봐 줘").contains("[img 1]") == true,
          "pick merge: the picks become the question's image chips")
}

private func windowPickShotTests() {
    let size = CGSize(width: 1200, height: 800)
    guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                              space: ArisInkRenderer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return check(false, "pick shot: test image")
    }
    // Something with detail, so the JPEG clears the blank floor.
    for i in 0..<400 {
        ctx.setFillColor(CGColor(srgbRed: CGFloat(i % 7) / 7, green: CGFloat(i % 11) / 11, blue: CGFloat(i % 13) / 13, alpha: 1))
        ctx.fill(CGRect(x: (i * 37) % 1200, y: (i * 53) % 800, width: 30 + i % 40, height: 20 + i % 30))
    }
    let window = ctx.makeImage()!
    let shot = ArisWindowPickShots.compose(window: window, badge: 3)
    let thumb = shot.flatMap { NSImage(data: $0.thumb) }
    check(shot != nil && shot!.jpeg.starts(with: [0xFF, 0xD8]) && thumb != nil && (thumb?.size.width ?? 0) <= 640,
          "pick shot: the window as JPEG with its number, and a PNG thumb at most 640 wide for the chip")
    let blank = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: ArisInkRenderer.sRGB,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    blank.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    blank.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
    check(ArisWindowPickShots.compose(window: blank.makeImage()!, badge: 1) == nil, "pick shot: a black window (nothing came) is no shot")
    let huge = CGContext(data: nil, width: 5000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0, space: ArisInkRenderer.sRGB,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    huge.draw(window, in: CGRect(x: 0, y: 0, width: 5000, height: 1000))
    let big = ArisWindowPickShots.compose(window: huge.makeImage()!, badge: 1)
    let bigImage = big.flatMap { NSBitmapImageRep(data: $0.jpeg) }
    check(bigImage.map { max($0.pixelsWide, $0.pixelsHigh) } == 2560, "pick shot: scaled to a 2560 px long edge")
}

// MARK: - The circle session counts the picks

private func windowPickSessionCapTests() {
    var s = ArisGestureSession()
    _ = s.handle(.keyDown(0))
    _ = s.handle(.held200)
    s.otherShots = 8
    let g = ArisGesture(kind: .circle, bbox: CGRect(x: 100, y: 100, width: 200, height: 200), points: [ArisGesturePoint(x: 100, y: 100, t: 10)])
    check(s.handle(.gesture(g, display: 1, at: 10)) == [.reject(g)], "pick cap: with 8 windows picked a circle gets the 8/8 reject")
    s.otherShots = 7
    if case .startCapture = s.handle(.gesture(g, display: 1, at: 20)).first {
        check(true, "pick cap: 7 picks leave room for one circle")
    } else {
        check(false, "pick cap: 7 picks leave room for one circle")
    }
}
