// Acceptance tests for the clean-room notch windows (cleanroom-specs/02-notch-windows.md), pure parts.
import AppKit

func runWindowTests() {
    typealias W = ArisNotchWindowRules
    let size = CGSize(width: 640, height: 820)
    check(W.origin(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), windowSize: size) == CGPoint(x: 436, y: 162),
          "placement: centred and flush with the top")
    check(W.origin(screenFrame: CGRect(x: -1920, y: 982, width: 1920, height: 1080), windowSize: size) == CGPoint(x: -1280, y: 1242),
          "placement: a screen left of and above the main one")
    check(W.origin(screenFrame: CGRect(x: 1512, y: -1080, width: 1920, height: 1080), windowSize: size) == CGPoint(x: 2152, y: -820),
          "placement: a screen below the main one")
    check(W.openNotchRegion(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), openSize: CGSize(width: 640, height: 190))
          == CGRect(x: 436, y: 792, width: 640, height: 190), "drag region: where the open notch would be")

    let screens = ["A", "B"]
    check(W.display(mode: .preferredDisplay, preferred: "B", screens: screens, main: "A") == "B"
          && W.display(mode: .preferredDisplay, preferred: "C", screens: screens, main: "A") == nil
          && W.display(mode: .preferredDisplay, preferred: nil, screens: screens, main: "A") == nil,
          "display: preferred only, nothing when it is unplugged")
    check(W.display(mode: .fallbackIfPreferredUnavailable, preferred: "B", screens: screens, main: "A") == "B"
          && W.display(mode: .fallbackIfPreferredUnavailable, preferred: "C", screens: screens, main: "A") == "A",
          "display: preferred, else the main screen")
    check(W.display(mode: .activeDisplay, preferred: "B", screens: screens, main: "A") == "A", "display: active follows the main screen")

    let one: [(uuid: String?, frame: CGRect)] = [("A", CGRect(x: 0, y: 0, width: 1512, height: 982)), ("B", CGRect(x: 1512, y: 0, width: 1920, height: 1080))]
    check(W.ScreenSet(one) == W.ScreenSet(one), "screens: the same list -> no rebuild")
    check(W.ScreenSet(one) != W.ScreenSet(Array(one.prefix(1))), "screens: a display removed -> rebuild")
    check(W.ScreenSet(one) != W.ScreenSet([one[0], ("B", CGRect(x: 1512, y: 100, width: 1920, height: 1080))]), "screens: a moved display -> rebuild")
    check(W.ScreenSet(one) != W.ScreenSet([one[0], ("C", one[1].frame)]), "screens: another display in the same place -> rebuild")

    let base: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
    check(W.collectionBehavior(hideNonNotchedFromMissionControl: true, hasNotch: true) == base
          && W.collectionBehavior(hideNonNotchedFromMissionControl: false, hasNotch: false) == base,
          "spaces: every space, over full-screen apps, stationary, no cycling")
    check(W.collectionBehavior(hideNonNotchedFromMissionControl: true, hasNotch: false) == base.union(.transient),
          "spaces: a display without a notch leaves Mission Control when that setting is on")
}
