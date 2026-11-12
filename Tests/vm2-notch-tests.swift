// Tests for what the second VM run (11 Nov 2026, a display without a notch) found in the notch and the side panels:
// the side tabs' names fit for every count of tabs in both languages, the closed pill's hover and click regions with a
// timer, the notch's hover checked against where the pointer really is, the muted mark's place in the closed pill, a
// muted Aris never reaching the speaker, and the smaller things. Called from main.swift; uses its check().
// Pure rules and source reads only: nothing is drawn on screen, spoken or stored.
import AppKit
import Foundation

func runVM2NotchTests() {
    vm2SideTabNameTests()
    vm2ClosedBandRegionTests()
    vm2PointerTruthTests()
    vm2MutedMarkTests()
    vm2MutedVoiceTests()
    vm2StepAsideTests()
    vm2AnswerBesideCardTests()
    vm2TagStopTests()
    vm2UpgradeSmallTests()
}

private func vm2Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

/// Every Swift file of the app (not the agent or the tools), as (path from boring.notch, text).
private func vm2AppSources() -> [(path: String, text: String)] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..").standardized
    let app = root.appendingPathComponent("Aris")
    guard let walk = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else { return [] }
    return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.compactMap { url in
        (try? String(contentsOf: url, encoding: .utf8)).map { (String(url.path.dropFirst(root.path.count + 1)), $0) }
    }
}

// MARK: - Bug 9: the selected side tab shows its whole name

/// The side panels' tab row, as ArisSideTabs lays it out in the 232-point panel: 14 and 20 in from the panel's edges,
/// the lock's 30-point disc and the 8 before it, and the pill's own 4 each side.
private let vm2TabRow: CGFloat = 232 - 14 - 20 - 30 - 8 - 2 * 4
private let vm2TabIcon: CGFloat = 16, vm2TabGap: CGFloat = 5, vm2TabPadding: CGFloat = 8, vm2TabSpacing: CGFloat = 2

/// A name's width as the tabs draw it (12-point semibold), measured, as ArisSlidingTabs measures it.
private func vm2TabLabel(_ name: String) -> CGFloat {
    ceil((name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width)
}

/// Every way to leave some of `tabs` switched on, in the panel's order.
private func vm2Subsets(_ tabs: [ArisSideTab]) -> [[ArisSideTab]] {
    (1..<(1 << tabs.count)).map { mask in tabs.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element) }
}

private func vm2SideTabNameTests() {
    typealias G = ArisSlidingTabsGeometry
    var checked = 0
    var narrowest = CGFloat.infinity
    for edge in ArisSideEdge.allCases {
        for shown in vm2Subsets(ArisSideTabChoice.all(edge)) {
            // As ArisLeftPanel and ArisRightPanel ask: 34, or 28 where four share the pill.
            let preferred: CGFloat = shown.count > 3 ? 28 : 34
            for english in [false, true] {
                let labels = shown.map { vm2TabLabel($0.name(english: english)) }
                let widths = labels.map {
                    G.unselectedWidth(label: $0, row: vm2TabRow, count: shown.count, preferred: preferred, floor: G.narrowest(icon: vm2TabIcon),
                                      icon: vm2TabIcon, gap: vm2TabGap, padding: vm2TabPadding, spacing: vm2TabSpacing)
                }
                for (index, tab) in shown.enumerated() {
                    let rest = G.frames(weights: shown.indices.map { $0 == index ? 1 : 0 }, width: vm2TabRow, unselectedWidths: widths, spacing: vm2TabSpacing)
                    let selected = rest.tabWidths[index]
                    let content = G.content(selectedness: 1, width: selected, start: rest.starts[index], exactStart: rest.exactStarts[index],
                                            selected: rest.indicatorWidth, unselected: rest.unselected, label: labels[index],
                                            icon: vm2TabIcon, gap: vm2TabGap, padding: vm2TabPadding)
                    let what = "\(tab.name(english: english)) among \(shown.count) on the \(edge.rawValue)"
                    check(!G.labelCut(label: labels[index], selected: rest.indicatorWidth, icon: vm2TabIcon, gap: vm2TabGap, padding: vm2TabPadding)
                          && content.visible >= labels[index],
                          "vm2 bug 9: the selected tab shows its whole name (\(what): \(labels[index]) points, \(content.visible) shown)")
                    check(content.lead >= vm2TabPadding - 0.5 && content.lead + vm2TabIcon + vm2TabGap + labels[index] <= selected - vm2TabPadding + 0.5,
                          "vm2 bug 9: the icon and the name sit inside the tab's padding (\(what))")
                    let others = rest.tabWidths.enumerated().filter { $0.offset != index }.map(\.element)
                    check(others.allSatisfy { $0 >= vm2TabIcon + 1 && $0 <= preferred },
                          "vm2 bug 9: every other tab stays at least an icon wide, never wider than before (\(what): \(others))")
                    check(abs(G.contentWidth(rest, spacing: vm2TabSpacing) - vm2TabRow) < 0.01, "vm2 bug 9: the tabs still fill the pill exactly (\(what))")
                    narrowest = min(narrowest, others.min() ?? preferred)
                    checked += 1
                }
            }
        }
    }
    // 15 ways to leave left tabs on (32 tab-selections) and 3 on the right (4), in two languages.
    check(checked == (32 + 4) * 2, "vm2 bug 9: every count of tabs on each side, in Korean and in English, was laid out (\(checked))")
    check(narrowest >= 17, "vm2 bug 9: the tightest row (four tabs, Clipboard selected) still leaves each icon its own 17 points (\(narrowest))")

    // Short names change nothing: 기록 among four keeps the others at 28, as mockup 5b drew it.
    let short = G.unselectedWidth(label: vm2TabLabel("기록"), row: vm2TabRow, count: 4, preferred: 28, floor: 17, icon: vm2TabIcon, gap: vm2TabGap,
                                  padding: vm2TabPadding, spacing: vm2TabSpacing)
    check(short == 28, "vm2 bug 9: a short name leaves the other tabs as wide as they were")
    // The same weights, one width for all: the old call still lays the row out as before.
    let old = G.frames(weights: [0, 1, 0], width: 150, unselected: 34, spacing: 2)
    check(old == G.frames(weights: [0, 1, 0], width: 150, unselectedWidths: [34, 34, 34], spacing: 2) && old.unselected == 34 && old.tabWidths == [34, 78, 34],
          "vm2 bug 9: one width for every tab lays the row out as it always did")
    // Half-way from a short name to a long one the others are half-way too, and the row is still full.
    let from = G.unselectedWidth(label: vm2TabLabel("History"), row: vm2TabRow, count: 4, preferred: 28, floor: 17, icon: vm2TabIcon, gap: vm2TabGap,
                                 padding: vm2TabPadding, spacing: vm2TabSpacing)
    let to = G.unselectedWidth(label: vm2TabLabel("Clipboard"), row: vm2TabRow, count: 4, preferred: 28, floor: 17, icon: vm2TabIcon, gap: vm2TabGap,
                               padding: vm2TabPadding, spacing: vm2TabSpacing)
    let mid = G.frames(weights: [0.5, 0, 0.5, 0], width: vm2TabRow, unselectedWidths: [from, 28, to, 28], spacing: vm2TabSpacing)
    check(to < from && mid.unselected <= from && mid.unselected >= to && abs(G.contentWidth(mid, spacing: vm2TabSpacing) - vm2TabRow) < 0.01,
          "vm2 bug 9: a move between a short and a long name blends the other tabs' width, the row full all the way")
    // A name no row could hold is still cut with its fade, never drawn over its neighbours.
    let huge = G.unselectedWidth(label: 400, row: vm2TabRow, count: 4, preferred: 28, floor: 17, icon: vm2TabIcon, gap: vm2TabGap,
                                 padding: vm2TabPadding, spacing: vm2TabSpacing)
    check(huge == 17 && G.labelCut(label: 400, selected: vm2TabRow - 3 * 19, icon: vm2TabIcon, gap: vm2TabGap, padding: vm2TabPadding),
          "vm2 bug 9: a name too long for any row stops at the floor and keeps its fade")
    check(G.unselectedWidth(label: 400, row: vm2TabRow, count: 1, preferred: 34, floor: 17, icon: vm2TabIcon, gap: vm2TabGap, padding: vm2TabPadding,
                            spacing: vm2TabSpacing) == 34, "vm2 bug 9: a single tab has nobody to make room")
    let tabs = vm2Source("Aris/private/Aris/Side/ArisSlidingTabs.swift")
    check(tabs.contains("ArisSlidingTabsGeometry.unselectedWidth(label: labelWidth($0), row: geometry.size.width, count: items.count,")
          && tabs.contains("unselectedWidths: narrow"), "vm2 bug 9: wiring: the tabs measure each name and lay the row out from it")
}

// MARK: - Bug 6: the closed pill's hover and click regions, with and without a timer

private func vm2ClosedBandRegionTests() {
    typealias B = ArisClosedBand
    // 185: the camera of a 14-inch display, and the pill of a display with none (the VMs). 204 and 230: the wider
    // cameras of "More Space" resolutions.
    for notch in [CGFloat(185), 204, 230] {
        let width = B.surfaceWidth(notchWidth: notch), ear = ArisBand.earWidth(notchWidth: notch)
        check(width == ArisBand.bodyWidth(notchWidth: notch) + 26 && abs(width - (2 * 13 + 2 * ear + notch)) < 0.01,
              "vm2 bug 6: the closed surface is the band and its two 13-point shoulders (\(notch))")
        let middle = width / 2, leftEar = 13 + ear / 2, rightEar = width - 13 - ear / 2, rightEnd = width - 4, leftEnd: CGFloat = 4
        // The band of a parked answer, the jobs' band, Claude's and music's: a rest anywhere opens Aris.
        for other in [ArisNotchDecisions.Closed.star(.parked), .star(.tasks), .star(.turn), .claude, .music, .dueAlert, .empty, .notice] {
            check(B.hoverInsets(other, notchWidth: notch) == nil
                  && [leftEnd, leftEar, middle, rightEar, rightEnd].allSatisfy { B.spot(x: $0, closed: other, notchWidth: notch) == .opensAris },
                  "vm2 bug 6: without a timer every part of the closed pill opens Aris (\(other), \(notch))")
        }
        // With a timer: the same, but for the ring's ear.
        for x in [middle, middle - notch / 2 + 2, middle + notch / 2 - 2, rightEar, rightEnd] {
            check(B.spot(x: x, closed: .timer, notchWidth: notch) == .opensAris,
                  "vm2 bug 6: while a timer runs the middle, the time and the right end of the pill still open Aris (x \(x) of \(width))")
        }
        check(B.spot(x: leftEar, closed: .timer, notchWidth: notch) == .timerControl && B.spot(x: leftEnd, closed: .timer, notchWidth: notch) == .timerControl,
              "vm2 bug 6: the ring's ear is the timer's own control (\(notch))")
        let control = B.timerControlWidth(notchWidth: notch)
        check(control == ear && control < width / 4 && control >= 2 * 14,
              "vm2 bug 6: the timer's control is its ear, a clearly bounded part of the pill (\(control) of \(width)), wide enough for the ring")
        check(B.hoverInsets(.timer, notchWidth: notch) == B.Insets(leading: 13 + ear, trailing: 0),
              "vm2 bug 6: the notch's own hover starts where the timer's ear ends and reaches the right edge")
        // The control is drawn above the surface, centred on its ear: the band is centred on the camera.
        let centre = width / 2 + B.timerControlOffset(notchWidth: notch)
        check(abs(centre - leftEar) < 0.01 && abs((centre + control / 2) - (width / 2 - notch / 2)) < 0.01,
              "vm2 bug 6: the control sits exactly on the left ear, ending at the camera's edge (\(notch))")
        // At rest nothing changed: the camera's width opens, the ears are the star's room.
        check(B.hoverInsets(.star(.home), notchWidth: notch) == B.Insets(leading: 13 + ear, trailing: 13 + ear)
              && B.spot(x: middle, closed: .star(.home), notchWidth: notch) == .opensAris
              && B.spot(x: leftEar, closed: .star(.home), notchWidth: notch) == .starRoom && B.spot(x: rightEar, closed: .star(.home), notchWidth: notch) == .starRoom,
              "vm2 bug 6: at rest the camera's width opens the notch and the ears stay the star's room, as before (\(notch))")
        let strip = ArisClosedBand.region(CGRect(x: 0, y: 0, width: width, height: 32), insets: B.hoverInsets(.star(.home), notchWidth: notch))
        check(abs(strip.width - (ArisStarBand.hitWidth(mode: .home, notchWidth: notch) ?? 0)) < 0.01 && abs(strip.midX - width / 2) < 0.01,
              "vm2 bug 6: the resting strip is the same centred camera's width the notch used before (\(notch))")
    }
    let root = vm2Source("Aris/private/Notch/ArisNotchRoot.swift"), ear = vm2Source("Aris/private/Aris/ArisTimerEar.swift")
    check(root.contains("ArisHitStrip(insets: hoverInsets, pad:") && root.contains("closed ? ArisClosedBand.hoverInsets(closedKind, notchWidth: notchWidth, body: bandBody) : nil"),
          "vm2 bug 6: wiring: the notch's hover and click region comes from the closed band's rule")
    check(root.contains("if closedKind == .timer {") && root.contains("ArisTimerEarControl(width: ArisClosedBand.timerControlWidth(notchWidth: notchWidth, body: bandBody), height: displayedHeight)")
          && root.contains(".offset(x: ArisClosedBand.timerControlOffset(notchWidth: notchWidth, body: bandBody))"),
          "vm2 bug 6: wiring: the timer's control is drawn on its ear, above the notch's own hover")
    let drawing = ear.components(separatedBy: "struct ArisTimerEarControl").first ?? ""
    check(drawing.contains(".allowsHitTesting(false)") && !drawing.contains(".onTapGesture") && !drawing.contains(".contextMenu") && !drawing.contains(".help("),
          "vm2 bug 6: wiring: the timer's band is only drawn (no click, menu or tooltip of its own across the pill)")
    let control = ear.components(separatedBy: "struct ArisTimerEarControl").last ?? ""
    check(control.contains(".frame(width: width, height: height)") && control.contains(".onTapGesture { timer.togglePause() }") && control.contains(".contextMenu { ArisTimerMenu() }"),
          "vm2 bug 6: wiring: pause, resume and the menu live on the ear's control")
    // No system tooltip anywhere inside the closed notch's own hover: one over the band kept the hover from arriving.
    for file in ["Aris/private/Aris/ArisActivity.swift", "Aris/private/Claude/ClaudeLiveActivity.swift", "Aris/private/Notch/ArisNotchClosedParts.swift"] {
        check(!vm2Source(file).isEmpty && !vm2Source(file).contains(".help("), "vm2 bug 6: wiring: no tooltip sits on a closed band the pointer opens Aris from (\(file))")
    }
}

// MARK: - Bug 7: the notch's hover against where the pointer really is

private func vm2PointerTruthTests() {
    typealias P = ArisNotchPointer
    // A 1512 × 982 display; the notch window is 640 wide at the top centre; the open surface is 464 × 300 at the
    // window's top centre (SwiftUI measures from the window's top-left, the screen from its bottom-left).
    let window = CGRect(x: 436, y: 982 - 420, width: 640, height: 420)
    let open = CGRect(x: 88, y: 0, width: 464, height: 300)
    let onScreen = P.onScreen(surface: open, window: window)
    check(onScreen == CGRect(x: 524, y: 682, width: 464, height: 300), "vm2 bug 7: the surface's place on the screen: its top at the screen's top, its sides where the window puts them")
    check(P.isOn(pointer: CGPoint(x: 756, y: 900), surface: open, window: window) && P.isOn(pointer: CGPoint(x: 530, y: 690), surface: open, window: window),
          "vm2 bug 7: a pointer inside the open notch is on it")
    check(!P.isOn(pointer: CGPoint(x: 650, y: 455), surface: open, window: window) && !P.isOn(pointer: CGPoint(x: 300, y: 950), surface: open, window: window)
          && !P.isOn(pointer: CGPoint(x: 756, y: 600), surface: open, window: window),
          "vm2 bug 7: a pointer in another app's window, beside the notch or under it, is not on it")
    check(P.isOn(pointer: CGPoint(x: 756, y: 682 - 6), surface: open, window: window) && !P.isOn(pointer: CGPoint(x: 756, y: 682 - 6), surface: open, window: window, slack: 0)
          && !P.isOn(pointer: CGPoint(x: 756, y: 682 - 12), surface: open, window: window),
          "vm2 bug 7: resting on the rim still counts for staying open (8 points), never for a hover that was told it ended")
    // A second display to the left of the main one (negative x), its notch window likewise.
    let left = CGRect(x: -1100, y: 200, width: 640, height: 420)
    check(P.isOn(pointer: CGPoint(x: -780, y: 500), surface: open, window: left) && !P.isOn(pointer: CGPoint(x: 756, y: 900), surface: open, window: left),
          "vm2 bug 7: each display's notch is checked against its own window")
    // Nothing measured: never a reason to close.
    check(P.isOn(pointer: CGPoint(x: 0, y: 0), surface: .zero, window: window) && P.isOn(pointer: CGPoint(x: 0, y: 0), surface: open, window: nil),
          "vm2 bug 7: before the surface or its window is known the pointer counts as on the notch")
    // Closed, at rest: only the camera's width counts, as for the hover itself.
    let closed = CGRect(x: 175, y: 0, width: 290, height: 32)
    let insets = ArisClosedBand.hoverInsets(.star(.home), notchWidth: 185)
    check(P.isOn(pointer: CGPoint(x: 756, y: 970), surface: closed, window: window, insets: insets, slack: 0)
          && !P.isOn(pointer: CGPoint(x: 436 + 175 + 20, y: 970), surface: closed, window: window, insets: insets, slack: 0),
          "vm2 bug 7: at rest the pointer on the star's ear is not on the notch's own hover")

    // The watch: two checks in a row must miss, a held button never counts, and being found starts over.
    var misses = 0
    misses = P.misses(misses, onNotch: false, buttonDown: false)
    check(misses == 1 && !P.hasLeft(misses: misses), "vm2 bug 7: one check that misses the pointer is not yet a leave")
    misses = P.misses(misses, onNotch: false, buttonDown: false)
    check(misses == 2 && P.hasLeft(misses: misses), "vm2 bug 7: two in a row are: the notch is told the pointer left")
    check(P.misses(1, onNotch: true, buttonDown: false) == 0, "vm2 bug 7: found on the notch again, the count starts over")
    check(P.misses(1, onNotch: false, buttonDown: true) == 0, "vm2 bug 7: a drag that began on the notch never closes it under the hand")
    check(P.checkEvery * Double(P.missesToLeave) <= 1, "vm2 bug 7: a notch left without a hover event closes within about a second, not 45")

    // The measurement is used only when it agreed with a hover that had just begun.
    check(P.trusted(measured: true, onNotchAtEnter: true) && !P.trusted(measured: true, onNotchAtEnter: false) && !P.trusted(measured: false, onNotchAtEnter: true),
          "vm2 bug 7: a measurement that disagrees with a hover that just began is never acted on")
    check(P.ignoresExit(inside: false, hovering: true, trusted: true, onNotch: true), "vm2 bug 7: told the pointer left while it is on the notch: it has not left")
    check(!P.ignoresExit(inside: false, hovering: true, trusted: true, onNotch: false) && !P.ignoresExit(inside: false, hovering: true, trusted: false, onNotch: true)
          && !P.ignoresExit(inside: true, hovering: true, trusted: true, onNotch: true) && !P.ignoresExit(inside: false, hovering: false, trusted: true, onNotch: true),
          "vm2 bug 7: a real leave, an untrusted measurement and a hover beginning all go through as before")

    let behaviour = vm2Source("Aris/private/Notch/ArisNotchRoot+Behaviour.swift"), root = vm2Source("Aris/private/Notch/ArisNotchRoot.swift")
    check(behaviour.contains("misses = ArisNotchPointer.misses(misses, onNotch: pointerOnNotch(slack: ArisNotchPointer.slack),")
          && behaviour.contains("buttonDown: NSEvent.pressedMouseButtons != 0)") && behaviour.contains("guard ArisNotchPointer.hasLeft(misses: misses) else { continue }")
          && behaviour.contains("if mayCloseAutomatically { vm.close() }"),
          "vm2 bug 7: wiring: while hovered the notch reads the pointer's place and closes as a hover exit would")
    check(behaviour.contains("guard !Task.isCancelled, hovering, pointerTrusted else { break }"), "vm2 bug 7: wiring: the watch runs only while the notch believes it is hovered")
    check(root.contains(".onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { surfaceFrame = $0 }")
          && root.contains(".environment(\\.arisNotchHovered, hovering)"), "vm2 bug 7: wiring: the surface is measured, and its controls are told when the pointer has left")
    // The controls shown on hover let go with the notch.
    for (file, line) in [("Aris/private/Aris/Home/ArisMuteSwitch.swift", ".arisNotchHover($hovering)"),
                         ("Aris/private/Aris/Home/ArisActivityTag.swift", ".arisNotchHover($hovering)"),
                         ("Aris/private/Aris/Home/ArisNotchHeader.swift", ".arisNotchHover($hovering)"),
                         ("Aris/private/Aris/Home/ArisReceiptChip.swift", ".arisNotchHover($hovering)"),
                         ("Aris/private/Aris/Home/ArisReceiptRow.swift", ".onChange(of: onNotch) { _, on in if !on { model.hovering = false } }")] {
        check(vm2Source(file).contains(line), "vm2 bug 7: wiring: a control shown on hover lets go when the pointer leaves the notch (\(file))")
    }
}

// MARK: - Bug 8: the muted mark in the closed pill

private func vm2MutedMarkTests() {
    typealias M = ArisMutedMark
    let kinds: [ArisNotchDecisions.Closed] = [.notice, .star(.turn), .star(.tasks), .star(.parked), .star(.home), .dueAlert, .timer, .claude, .music, .empty]
    for kind in kinds {
        for notch in [true, false] {
            check(M.place(closed: kind, muted: false, hasNotch: notch) == nil && M.place(closed: kind, muted: false, hasNotch: notch, earTaken: true) == nil,
                  "vm2 bug 8: not muted, nothing is drawn (\(kind), camera \(notch))")
        }
    }
    check(M.place(closed: .star(.home), muted: true, hasNotch: true) == .ear, "vm2 bug 8: at rest on a display with a camera the mark is in the right ear, as designed")
    check(M.place(closed: .empty, muted: true, hasNotch: false) == .strip, "vm2 bug 8: on a display with no camera the resting strip carries the mark at its end")
    check(M.place(closed: .empty, muted: true, hasNotch: true) == nil, "vm2 bug 8: a camera's bare housing (the star stepped aside) draws nothing over it")
    check(M.place(closed: .star(.parked), muted: true, hasNotch: false, earTaken: true) == .besideMark
          && M.place(closed: .star(.parked), muted: true, hasNotch: true, earTaken: true) == .besideMark,
          "vm2 bug 8: an answer waiting keeps its dot, and the mark sits beside it (both kinds of display)")
    check(M.place(closed: .star(.parked), muted: true, hasNotch: false) == .ear && M.place(closed: .star(.turn), muted: true, hasNotch: true) == .ear,
          "vm2 bug 8: with no dot in the ear the mark has the ear to itself")
    check(M.place(closed: .star(.turn), muted: true, hasNotch: true, earTaken: true) == .besideMark, "vm2 bug 8: beside the paused-listening mark too")
    check(M.place(closed: .star(.tasks), muted: true, hasNotch: true) == .ear && M.place(closed: .star(.tasks), muted: true, hasNotch: true, earTaken: true) == nil,
          "vm2 bug 8: the jobs' band shows it while its right ear is free (the pill under the notch holds the count)")
    check([ArisNotchDecisions.Closed.timer, .claude, .music, .dueAlert, .notice].allSatisfy { M.place(closed: $0, muted: true, hasNotch: true) == nil && M.place(closed: $0, muted: true, hasNotch: false) == nil },
          "vm2 bug 8: a band whose two ears belong to something else (a timer's ring and clock, Claude, music) is left alone")
    // Every state Aris itself holds the pill in shows the mark, on both kinds of display.
    let own: [(ArisNotchDecisions.Closed, Bool)] = [(.star(.parked), true), (.star(.parked), false), (.star(.turn), true), (.star(.turn), false)]
    check(own.allSatisfy { kind, taken in [true, false].allSatisfy { M.place(closed: kind, muted: true, hasNotch: $0, earTaken: taken) != nil } }
          && M.place(closed: .star(.home), muted: true, hasNotch: true) != nil && M.place(closed: .empty, muted: true, hasNotch: false) != nil,
          "vm2 bug 8: resting or with an answer parked, muted always shows, with or without a camera")

    let marks = vm2Source("Aris/private/Aris/Home/ArisMutedMarks.swift"), activity = vm2Source("Aris/private/Aris/ArisActivity.swift")
    let root = vm2Source("Aris/private/Notch/ArisNotchRoot.swift")
    check(activity.contains("mute: ArisMutedMark.place(closed: .star(mode), muted: muted, hasNotch: true, earTaken: paused || dot != nil))")
          && activity.contains("case .rest:\n            ArisMutedEar(muted: muted)"), "vm2 bug 8: wiring: the star's band draws the mark where the rule puts it")
    check(root.contains("ArisMutedStripMark(muted: ArisMutedMark.place(closed: .empty, muted: muted, hasNotch: vm.hasNotch) == .strip)"),
          "vm2 bug 8: wiring: the resting strip of a display with no camera draws it")
    check(!marks.isEmpty && !marks.contains("repeatForever") && !marks.contains("TimelineView") && !marks.contains("symbolEffect") && !marks.contains("phaseAnimator"),
          "vm2 bug 8: the mark is still: nothing in it blinks, pulses or loops")
}

// MARK: - The running tag's stop mark and press (the upgrade run's bug 5)

private func vm2TagStopTests() {
    let tag = vm2Source("Aris/private/Aris/Home/ArisActivityTag.swift")
    let body = tag.components(separatedBy: "/// Waits out what is left of the ten seconds").first ?? ""
    check(!body.isEmpty && !body.contains(".help("), "vm2u bug 5: no system tooltip sits on a running tag (with one there its hover never arrived and a press was lost)")
    check(body.contains("Color.clear.contentShape(Capsule())\n                        .arisNotchHover($hovering)\n                        .gesture(press(in: geometry.size))")
          && !body.contains(".onHover {"),
          "vm2u bug 5: the pointer and the press are taken by one still piece over the tag")
    check(body.contains("ArisHoverTip(text: stop.help)") && body.contains(".accessibilityHint(pressable ? stop?.help ?? \"\" : \"\")"),
          "vm2u bug 5: what a press does is still said: the notch's own tip, and to assistive tools")
    check(body.contains("private var offersStop: Bool { pressable && (hovering || previewHover) }") && body.contains("ArisTagStopMark().opacity(offersStop ? 1 : 0)"),
          "vm2u bug 5: under the pointer the face gives way to the stop mark")
    check(tag.contains("static let tipWait = 0.6") && body.contains(".animation(ArisHoverTip.motion.delay(offersStop ? ArisTagMeterLook.tipWait : 0), value: offersStop)"),
          "vm2u bug 5: the stop mark comes first, the tip a moment after, and both go at once")
    let tip = vm2Source("Aris/private/Aris/Design/ArisHoverTip.swift")
    check(tip.contains("struct ArisHoverTip: View") && !vm2Source("Aris/private/Aris/Home/ArisNotchHeader.swift").contains("struct ArisHoverTip"),
          "vm2u bug 5: the tip is the notch's own, the one beside the stop button")
}

// MARK: - A muted Aris sends nothing to the loudspeaker, and the log says so

private func vm2MutedVoiceTests() {
    // The door the voice itself asks: muted, only the Settings preview plays.
    check(!ArisQuiet.voiceMayPlay(muted: true, preview: false), "vm2 mute: a muted Aris says nothing")
    check(ArisQuiet.voiceMayPlay(muted: true, preview: true), "vm2 mute: the Settings preview is the one thing that plays while muted (the user pressed it to hear the voice)")
    check(ArisQuiet.voiceMayPlay(muted: false, preview: false) && ArisQuiet.voiceMayPlay(muted: false, preview: true), "vm2 mute: not muted, the door is open")
    check(ArisQuiet.voiceLog(aloud: true) == "speaking" && !ArisQuiet.voiceLog(aloud: false).hasPrefix("speaking") && ArisQuiet.voiceLog(aloud: false).contains("nothing is spoken"),
          "vm2 mute: the log says \"speaking\" only when the voice will really read the answer")

    // The voice has two ways in, and both stop at the door before anything can sound.
    let speaker = vm2Source("Aris/private/Aris/ArisSpeaker.swift")
    let voice = speaker.components(separatedBy: "final class ArisSpeaker {").last ?? ""
    let open = voice.components(separatedBy: "\n").filter { $0.hasPrefix("    func ") }.map { String($0.dropFirst(9).prefix { $0 != "(" }) }
    check(open == ["speak", "speak", "duck", "unduck", "stop"], "vm2 mute: the voice can be started only through its two speak calls (\(open))")
    check(voice.contains("    func speak(_ text: String, preview: Bool = false) async {\n        stop()\n        guard ArisQuiet.voiceMayPlay(muted: ArisQuietGate.muted, preview: preview) else { return }\n"),
          "vm2 mute: wiring: one line said asks the door first, and still stops the voice that was speaking")
    check(voice.contains("    func speak(sentences: AsyncStream<String>) async {\n        stop()\n") && voice.contains("""
            guard ArisQuiet.voiceMayPlay(muted: ArisQuietGate.muted, preview: false) else {
                for await _ in sentences {}
                return
            }
            let mine = generation
    """), "vm2 mute: wiring: an answer read as it is written asks the door first, and can never be a preview")
    // Everything the voice plays goes through private helpers of those two calls.
    let helpers = ["speakWithElevenLabs", "speakWithSystemVoice", "startPlayback", "play"]
    check(helpers.allSatisfy { voice.contains("private func \($0)(") } && !voice.contains("\n    func play") && !voice.contains("\n    func speakWith"),
          "vm2 mute: what makes the sound is private to the voice, behind the door")

    // Across the whole app: who hands words to the voice, and who may call it a preview.
    let sources = vm2AppSources()
    let calls = sources.flatMap { file in
        file.text.components(separatedBy: "\n").filter { $0.contains("speaker.speak(") }.map { (file.path, $0.trimmingCharacters(in: .whitespaces)) }
    }
    let previews = calls.filter { $0.1.contains("preview: true") }
    check(calls.count >= 20, "vm2 mute: the whole app was read for calls to the voice (\(calls.count) found in \(sources.count) files)")
    check(previews.map(\.0).sorted() == ["Aris/components/Settings/ArisAIServicesLive.swift", "Aris/components/Settings/ArisLiveSettings.swift"],
          "vm2 mute: only the Settings window's two 미리 듣기 buttons play as a preview (\(previews.map(\.0)))")
    check(sources.allSatisfy { !$0.text.contains("preview: true") || $0.path.hasPrefix("Aris/components/Settings/") || !$0.text.contains(".speak(") },
          "vm2 mute: no typed turn, spoken turn, card or announcement can pass as a preview")
    // No second voice anywhere: the only other synthesizers are the Settings voice samples and the first-run guide's narration.
    let synthesizers = sources.filter { $0.text.contains("AVSpeechSynthesizer()") }.map(\.path).sorted()
    check(synthesizers == ["Aris/components/Settings/ArisAIServicesLive.swift", "Aris/private/Aris/ArisSpeaker.swift", "Aris/private/Aris/Onboarding/ArisOnboardingAudio.swift"],
          "vm2 mute: Aris's replies have one voice (\(synthesizers))")
    // Typed, spoken, a card's question, Aris's own news: every one of them reaches the voice only through speak().
    let controller = vm2Source("Aris/private/Aris/ArisController.swift")
    check(controller.contains("let aloud = !silentSpeech && ArisQuietGate.maySpeak(heard: session.heard)\n                log.notice(\"\\(ArisQuiet.voiceLog(aloud: aloud), privacy: .public)\")")
          && !controller.contains("log.notice(\"speaking\")"), "vm2 mute: wiring: a typed turn's log line is true while muted")
    check(controller.contains("guard ArisQuietGate.maySpeak(heard: session.heard) else { return }\n        do {\n            try await Self.within(timeout) { await talking() }\n            log.notice(\"spoke\")"),
          "vm2 mute: wiring: \"spoke\" is logged only after the gate let the voice talk")
}
// MARK: - A press that opens Settings gets out of its way; the fix is a button

private func vm2StepAsideTests() {
    typealias D = ArisNotchDecisions
    check(D.stepsAsideForSettings(open: true, cardWaiting: false, approvalsPending: false), "vm2 step aside: the open notch closes when a press in it opens Settings")
    check(!D.stepsAsideForSettings(open: true, cardWaiting: true, approvalsPending: false) && !D.stepsAsideForSettings(open: true, cardWaiting: false, approvalsPending: true),
          "vm2 step aside: a card or an approval still waiting keeps the notch where it is")
    check(!D.stepsAsideForSettings(open: false, cardWaiting: false, approvalsPending: false), "vm2 step aside: a closed notch has nothing to do")
    check(ArisSideEdgeRules.stepsAside(open: true, pinned: false) && !ArisSideEdgeRules.stepsAside(open: true, pinned: true) && !ArisSideEdgeRules.stepsAside(open: false, pinned: false),
          "vm2 step aside: an open side panel folds, one locked open stays")
    check(!ArisModelOfferQuiet.mayShow(dragging: false, turn: false, card: false, onboarding: false, settings: true)
          && ArisModelOfferQuiet.mayShow(dragging: false, turn: false, card: false, onboarding: false, settings: false)
          && ArisModelOfferQuiet.mayShow(dragging: false, turn: false, card: false, onboarding: false),
          "vm2 step aside: the dictation model's offer waits while the Settings window is in front")

    // Every press in the notch or a side panel that opens Aris's Settings goes through the one call that steps aside.
    let panels = ["Aris/private/Aris/Home/", "Aris/private/Aris/Side/", "Aris/private/Notch/", "Aris/private/Aris/ArisFixModel.swift", "Aris/private/Aris/ArisTodoView.swift"]
    let direct = vm2AppSources().filter { file in panels.contains { file.path.hasPrefix($0) } && file.path != "Aris/private/Notch/ArisStepAside.swift" }
        .flatMap { file in file.text.components(separatedBy: "\n").filter { $0.contains("ArisSettingsWindow.shared.show()") }.map { "\(file.path): \($0.trimmingCharacters(in: .whitespaces))" } }
    // The closed notch's right-click menu is the one left: there is no open notch to put away.
    check(direct.count == 1 && direct[0].contains("ArisNotchRoot+Behaviour.swift") && direct[0].contains("Button(\"Settings\")"),
          "vm2 step aside: wiring: no press in a panel opens Settings and stays over it (\(direct))")
    let aside = vm2Source("Aris/private/Notch/ArisStepAside.swift")
    check(aside.contains("ArisSettingsWindow.shared.show()\n        NotificationCenter.default.post(name: .arisSettingsOpenedByPress, object: nil)\n        ArisSidePanels.shared.stepAside()"),
          "vm2 step aside: wiring: showing Settings from a panel tells the notch and the side panels")
    for file in ["Aris/private/Aris/Home/ArisNotchHeader.swift", "Aris/private/Aris/Home/ArisTurnView.swift", "Aris/private/Aris/ArisFixModel.swift",
                 "Aris/private/Aris/Side/ArisUsageCard.swift", "Aris/private/Aris/ArisTodoView.swift"] {
        check(vm2Source(file).contains("ArisStepAside.showSettings()"), "vm2 step aside: wiring: \(file) opens Settings and steps aside")
    }
    check(vm2Source("Aris/private/Notch/ArisNotchRoot+Behaviour.swift").contains(".onReceive(NotificationCenter.default.publisher(for: .arisSettingsOpenedByPress)) { _ in root.settingsOpened() }"),
          "vm2 step aside: wiring: the notch hears it")
    check(vm2Source("Aris/private/Aris/ArisModelCard.swift").contains("settings: settings.visible"), "vm2 step aside: wiring: the model's offer asks whether Settings is in front")

    // The fix under a failure is a button in the notch's own pill, not a line of grey text.
    let fix = vm2Source("Aris/private/Aris/Home/ArisFixButtons.swift")
    check(fix.contains("ArisFixPill(title: feedback ?? words + \" ›\", help: words, action: press)") && !fix.contains("ArisOpenAnswerButton("),
          "vm2 fix button: the button that fixes a failure is drawn as a button")
    check(fix.contains("static let fill = 0.15") && fix.contains("static let hoverFill = 0.3") && fix.contains("static let height: CGFloat = 23")
          && fix.contains(".foregroundStyle(.white.opacity(0.95))"),
          "vm2 fix button: it uses the tokens the notch's other buttons use (the 23-point capsule at white 15%, 30% under the pointer, words at .95)")
    let header = vm2Source("Aris/private/Aris/Home/ArisNotchHeader.swift"), chip = vm2Source("Aris/private/Aris/ArisAgentChip.swift")
    check(header.contains(".background(Capsule().fill(.white.opacity(hovering ? 0.3 : 0.15)))") && header.contains(".frame(height: 23)")
          && chip.contains(".background(Capsule(style: .continuous).fill(.white.opacity(0.15)))") && chip.contains(".foregroundStyle(.white.opacity(0.95))"),
          "vm2 fix button: those are the header's 닫기 and the agent chip's 다시 시작, unchanged")
}
// MARK: - The upgrade run: an answer beside a card (its fix button, its marks, its height)

private func vm2AnswerBesideCardTests() {
    typealias D = ArisAnswerDocument
    // Bug 1: the fix button under every reply that is up.
    check(D.showsFix(settledCard: false, permissionCard: false), "vm2u bug 1: a failure's button shows under the reply, with a card asked for or not")
    check(!D.showsFix(settledCard: false, permissionCard: true), "vm2u bug 1: beside the permission card, whose own button is the same fix, there is no second one")
    check(!D.showsFix(settledCard: true, permissionCard: false), "vm2u bug 1: a card's words left up after its answer get none")
    let turn = vm2Source("Aris/private/Aris/Home/ArisTurnView.swift")
    check(turn.contains("if session.settledCard { settledCard } else { answer }") && !turn.contains("cardLine }") && !turn.contains("private var cardLine"),
          "vm2u bug 1: wiring: one branch draws every reply, so none can leave the button out")
    check(turn.contains("return ArisAnswerDocument.showsFix(settledCard: session.settledCard, permissionCard: permissionCard) ? fixes.offer(for: session) : nil"),
          "vm2u bug 1: wiring: a card that has no values (Reminders access off) no longer hides the button")
    check(turn.components(separatedBy: "ArisFixButtons(offer: fix)").count == 2, "vm2u bug 1: wiring: the button is drawn in that one branch")

    // Bug 2: the spoken line's tags are never shown, and nothing said is lost.
    let kept = "<say>Sydney and Cairo are the warmest right now.</say>\nRight now: Sydney 19°, Cairo 24°.\n\n### Comparison\n| City | Now |\n|---|---|\n| Cairo | 24° |"
    let drawn = ArisSpeakable.withoutSayTags(kept)
    check(!drawn.contains("<say>") && !drawn.contains("</say>"), "vm2u bug 2: the spoken line's tags are not drawn")
    check(drawn.hasPrefix("Sydney and Cairo are the warmest right now.\nRight now: Sydney 19°") && drawn.contains("### Comparison") && drawn.contains("| Cairo | 24° |"),
          "vm2u bug 2: every word of an answer kept as written is still on screen, the line first")
    check(ArisSpeakable.withoutSayTags("<say>Checking Orlando first") == "Checking Orlando first", "vm2u bug 2: a line still arriving shows without its opening tag")
    check(ArisSpeakable.withoutSayTags("  <SAY>Hi.</SAY>  ") == "Hi." && ArisSpeakable.withoutSayTags("<say>Hi.</say>\n\nMore.") == "Hi.\nMore.",
          "vm2u bug 2: the tags go whatever their case, and the rest follows the line")
    // (fix-6, vm2 6: a say tag in prose goes wherever it is; code keeps it.)
    for plain in ["It's 24° in Cairo.", "", "1 < 2 in the middle", "코드: `<say>x</say>`", "```html\n<say>x</say>\n```"] {
        check(ArisSpeakable.withoutSayTags(plain) == plain, "vm2u bug 2: an answer with no leading spoken line is drawn as written (“\(plain)”)")
    }
    // What is drawn as the card's own plain line, and what as the document.
    check(D.isPlainLine("It's 24° in Cairo, partly cloudy.") && D.isPlainLine("카이로는 지금 24도예요.") && D.isPlainLine(String(repeating: "A long sentence about the weather. ", count: 6)),
          "vm2u bug 2: one plain line or paragraph above a card stays the card's own line (pick B)")
    for marked in [drawn, "### 1. check the weather in orlando\nOrlando is 7° and cloudy.\n\n### 2. tell me the time\nIt's 2:16 PM.", "- one\n- two",
                   "| a | b |\n|---|---|\n| 1 | 2 |", "Line one.\n\nLine two.", "It is **24°** now.", "Run `date` to see."] {
        check(!D.isPlainLine(marked), "vm2u bug 2: an answer with headings, a table, a list, more paragraphs or inline marks is drawn as every other answer (“\(marked.prefix(24))…”)")
    }
    // The formatter draws them: a heading is a label, a table a table, never their raw marks.
    let pieces = D.pieces(from: drawn)
    check(pieces.contains { if case .block(.label("Comparison")) = $0 { true } else { false } }
          && pieces.contains { if case .block(.table(let header, let rows)) = $0 { header == ["City", "Now"] && rows == [["Cairo", "24°"]] } else { false } },
          "vm2u bug 2: the comparison's heading and table are drawn as a label and a table")
    let account = D.pieces(from: "### 1. check the weather in orlando\nOrlando is 7° and cloudy.\n\n### 2. tell me the time\nIt's 2:16 PM.\n\n### 3. open notes\nOpened Notes.")
    check(account.count == 6 && account.filter { if case .block(.label) = $0 { true } else { false } }.count == 3,
          "vm2u bug 2: a routine's account is its three steps, each a label and its line")
    check(turn.contains("private var shownReply: String { ArisSpeakable.withoutSayTags(session.reply) }")
          && turn.contains("ArisAnswerText(text: shownReply, budget: answerBudget)") && turn.contains("ArisWidgetLine(text: shownReply)")
          && turn.contains("private var plainCardLine: Bool { widgets.isCardLine(session.reply) && ArisAnswerDocument.isPlainLine(shownReply) }"),
          "vm2u bug 2: wiring: an answer beside a card goes through the same formatter as any other")
    check(turn.contains("private var answerBudget: CGFloat { room.text(prompt: promptRoom, footer: footerRoom + moreRoom + cardRoom) }")
          && turn.contains("private var readerBudget: CGFloat { room.answer(prompt: promptRoom, footer: cardRoom) }")
          && turn.contains("ArisBoard.shared.open(answer: shownReply, question: session.heard)"),
          "vm2u bug 2: wiring: the same height budget (less the card's room), scrolling inside it, and 자세히 보기 for the whole of a long one")
    // The reader is offered as soon as the account is taller than the room the card leaves.
    let room = ArisAnswerRoom(surfaceMax: 710, composer: 46)
    let withCard = room.answer(prompt: 60, footer: 350 + 12), without = room.answer(prompt: 60)
    check(withCard < without && ArisAnswerReader.offers(content: withCard + 40, budget: withCard) && !ArisAnswerReader.offers(content: withCard + 40, budget: without),
          "vm2u bug 2: with a card under it, a long account offers 자세히 보기 where the card's room ends, not where an answer alone would")
}
// MARK: - The upgrade run's smaller things in the answer area (its bug 9)

private func vm2UpgradeSmallTests() {
    // A card he said no to: the step that waited on it did not run, so it gets no tick.
    let ask = ArisConfirmation(id: "c1", title: "Mac action", detail: "restart")
    let working = ArisSession().listening().hearing("restart my mac").thinking().working("웹에서 찾는 중").working("Mac에서 작업 중")
    let asking = working.asking(ask)
    let declined = asking.answered(delivered: true, allowed: false)
    check(declined.phase == .thinking && declined.steps.map(\.label) == ["웹에서 찾는 중"] && declined.steps.allSatisfy(\.done),
          "vm2u bug 9: after a no, the step that waited on the card is gone, never ticked; what had finished keeps its check (\(declined.steps.map(\.label)))")
    check(declined.answering("Okay, I won't.").tags.map(\.label) == ["웹에서 찾는 중"], "vm2u bug 9: and the answer after it shows no tick for it")
    let allowed = asking.answered(delivered: true, allowed: true)
    check(allowed.steps.map(\.label) == ["웹에서 찾는 중", "Mac에서 작업 중"] && allowed.steps.map(\.done) == [true, false] && asking.answered().steps == allowed.steps,
          "vm2u bug 9: after a yes the step that waited on the card runs on, not yet ticked (vm3 bug C); what had finished keeps its check")
    check(vm2Source("Aris/private/Aris/ArisController.swift").contains("session = session.answered(delivered: delivered == .ok, allowed: allow)"),
          "vm2u bug 9: wiring: the turn tells the session whether he said yes")

    // After Undo, the card above lists what is there now.
    check(ArisWidgetKind.todo.listsWhatUndoChanges && ArisWidgetKind.calendar.listsWhatUndoChanges
          && ArisWidgetKind.allCases.filter(\.listsWhatUndoChanges).count == 2, "vm2u bug 9: the to-do card and the day's events are read again after an undo, the other cards are not")
    check(vm2Source("Aris/private/Aris/ArisReceiptModel.swift").contains("show(desk.undoEnded(outcome, for: pressed.act, english: ArisUIWords.english))\n            // The card above the line (the to-dos, today's events) lists what is there now, without what was undone.\n            ArisWidgetModel.shared.undoHappened()"),
          "vm2u bug 9: wiring: the receipt's undo tells the card")
    let widgets = vm2Source("Aris/private/Aris/ArisWidgetModel.swift")
    check(widgets.contains("guard let shown = current, shown.request.kind.listsWhatUndoChanges else { return }") && widgets.contains("guard current?.id == shown.id else { return }"),
          "vm2u bug 9: wiring: only the card still on screen is read again")

    // The helper's sentence fits its button, and the button names the helper.
    for english in [false, true] {
        let line = ArisAgentCopy.notRunning(english: english), button = ArisFixWords.title(.settings(.helper, again: true), english: english)
        check(!line.contains("설정") && !line.lowercased().contains("settings"), "vm2u bug 9: the helper's failure line no longer sends him to Settings (“\(line)”)")
        check(ArisAppFix.fix(forLine: line) == .settings(.helper, again: true), "vm2u bug 9: the line still earns its restart button and a quiet 다시 해보기")
        check(button == (english ? "Restart the helper" : "에이전트 다시 시작하기"), "vm2u bug 9: the button says it restarts the helper, not Aris (“\(button)”)")
        check(ArisFixWords.helperPress(answering: true, english: english) == ArisFixWords.helperBack(english: english)
              && ArisFixWords.helperPress(answering: false, english: english) == ArisFixWords.helperRestarting(english: english)
              && ArisFixWords.helperBack(english: english) != ArisFixWords.helperRestarting(english: english),
              "vm2u bug 9: a press says what it did: restarting, or that the helper is running again")
    }
    check(ArisAgentCopy.notRunning(english: true) == "Aris's helper isn't running. Restart the helper." && ArisAgentCopy.notRunning(english: false) == "Aris 에이전트가 꺼져 있어요. 에이전트를 다시 시작해 주세요.",
          "vm2u bug 9: the sentence and the button use the same words")
    // Pressed when the helper had already come back: the offer keeps 다시 해보기 beside the button.
    var desk = ArisFixDesk()
    let failed = ArisFixMoment(phase: .failed, heard: "what's on my calendar", reply: ArisAgentCopy.notRunning(english: true))
    let helper = ArisFix.settings(.helper, again: true)
    check(desk.offer(failed) == ArisFixOffer(fix: helper, again: true), "vm2u bug 9: the helper's button comes with 다시 해보기")
    desk = desk.pressing(helper, under: failed.reply)
    check(desk.offer(failed) == ArisFixOffer(fix: helper, again: true), "vm2u bug 9: after the press 다시 해보기 is still offered")
    // The final VM run reversed the rule that stood here ("a helper that was already back is not asked again by
    // itself"): since the helper lives in the app it is always back before the press, and the question was never
    // asked again. The outcome decides now (ArisHelperWatch; fix-5-tests.swift has the whole table).
    let lost = ArisHelperWatch().moving(from: ArisFixMoment(phase: .thinking, heard: failed.heard), to: failed, now: Date())
    check(lost.pressed(under: failed, now: Date()).looked(answering: true, moment: failed, now: Date()).1 == .askAgain(failed.heard),
          "vm2u bug 9 (final 1): a helper that was already back at the press gets the same question again, by itself")
    // The restart goes ahead when the helper was just asked and did not answer, even if the last probe had it up.
    check(ArisAgentLink.restarts(.down, asked: false) && ArisAgentLink.restarts(.failed, asked: false) && !ArisAgentLink.restarts(.up, asked: false),
          "vm2u bug 9: the star's own restart is offered as before")
    check(ArisAgentLink.restarts(.up, asked: true) && !ArisAgentLink.restarts(.restarting, asked: true) && !ArisAgentLink.restarts(.back, asked: true),
          "vm2u bug 9: the button restarts a helper that did not answer just now, never twice at once")
    let model = vm2Source("Aris/private/Aris/ArisFixModel.swift")
    check(model.contains("let answering = await ArisAgentClient.probe() == .answered\n                if !answering { ArisAgentMonitor.shared.restart(asked: true) }\n                say(ArisFixWords.helperPress(answering: answering, english: ArisUIWords.english))"),
          "vm2u bug 9: wiring: the press asks the helper first, restarts it only if it is down, and says which")
}
