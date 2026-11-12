// Tests for QA BUG-44: a short ⌥⇧ tap armed window picking on every display and the ink, and after Esc those
// full-screen surfaces stayed up over every app. Every overlay is counted while it is up, and each exit path puts it
// away; a disarmed pick surface lets clicks through at once; a tap never arms either.
import AppKit
import Foundation

func runQAOverlayTests() {
    MainActor.assumeIsolated { qaOverlayCensusTests() }
}

@MainActor
private func qaOverlayCensusTests() {
    let screens: [(id: UInt32, frame: CGRect)] = [(1, CGRect(x: 0, y: 0, width: 1800, height: 1169)),
                                                 (2, CGRect(x: 1800, y: 0, width: 2560, height: 1440)),
                                                 (3, CGRect(x: -2560, y: 0, width: 2560, height: 1440))]
    let deps = ArisWindowPicker.Dependencies(screens: { screens }, nsScreen: { _ in nil }, primaryHeight: { 1169 }, windowAt: { _ in nil },
                                             capture: { _ in nil }, secureInput: { false }, now: { 0 }, headless: true)
    let picker = ArisWindowPicker(dependencies: deps)
    let base = ArisOverlayCensus.count
    picker.arm()
    check(picker.overlayCount == 3 && ArisOverlayCensus.count == base + 3, "BUG-44: armed, a pick surface on each of 3 displays is counted")
    picker.cancel()
    check(picker.overlayCount == 0 && ArisOverlayCensus.count == base, "BUG-44: a dropped turn (Esc, an error) puts them all away")
    picker.arm()
    picker.putAway()
    check(picker.overlayCount == 0 && ArisOverlayCensus.count == base && !picker.isArmed, "BUG-44: the turn's end (idle) puts them away")
    picker.arm()
    check(ArisOverlayCensus.closeAll() >= 3 && ArisOverlayCensus.count == 0, "BUG-44: the census puts away whatever is left")
    picker.cancel()
    check(ArisOverlayCensus.count == 0, "BUG-44: back to none")

    let ink = ArisInkOverlay(display: 1, screenFrame: screens[0].frame, screen: nil, headless: true, now: { 0 })
    ink.show()
    check(ArisOverlayCensus.count == 1 && ink.isShown, "BUG-44: the ink panel is counted while up")
    ink.close()
    check(ArisOverlayCensus.count == 0 && !ink.isShown, "BUG-44: and not once it's closed")
    ink.show()
    _ = ArisOverlayCensus.closeAll()
    check(!ink.isShown && ArisOverlayCensus.count == 0, "BUG-44: a leftover ink panel is put away by the census")

    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris")
    let glue = (try? String(contentsOf: root.appendingPathComponent("ArisController+Gesture.swift"), encoding: .utf8)) ?? ""
    let controller = (try? String(contentsOf: root.appendingPathComponent("ArisController.swift"), encoding: .utf8)) ?? ""
    let tapped = glue.components(separatedBy: "func gestureTapped() {").dropFirst().first?.components(separatedBy: "\n    }\n").first ?? ""
    check(!tapped.contains("armPicker()") && !tapped.contains("controller?.tap()") && tapped.contains("hooks.cancelPicker()"),
          "BUG-44: a tap arms neither window picking nor the ink")
    check(controller.contains("closeGestureLeftovers()") && glue.contains("ArisOverlayCensus.closeAll()"),
          "BUG-44: the turn going idle and every cancel put the overlays away")
    let pickerSource = (try? String(contentsOf: root.appendingPathComponent("Gesture/ArisWindowPicker.swift"), encoding: .utf8)) ?? ""
    check(pickerSource.contains("$0.setInteractive(false); $0.view.removeAllWashes()"), "BUG-44: disarmed surfaces let clicks through at once")
}
