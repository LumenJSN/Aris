// Acceptance tests for the clean-room platform helpers (cleanroom-specs/14-utilities.md, 12 accent colour).
import AppKit
import Foundation

@MainActor
func runPlatformTests() {
    screenDirectoryTests()
    relaunchTests()
    bundleVersionTests()
    accentTests()
    blurViewTests()
}

private final class FakeScreen {
    let uuid: String?
    init(_ uuid: String?) { self.uuid = uuid }
}

@MainActor
private func screenDirectoryTests() {
    let a = FakeScreen("AAAA"), b = FakeScreen("BBBB"), nameless = FakeScreen(nil)
    var directory = ArisScreenDirectory(screens: [a, b, nameless], uuid: \.uuid)
    check(directory.screen(for: "AAAA") === a && directory.screen(for: "BBBB") === b, "displays: a UUID finds its screen")
    check(directory.screen(for: "CCCC") == nil, "displays: an unknown UUID finds nothing")
    check(directory.all.count == 2, "displays: screens without a UUID are left out")
    // A reconfiguration hands out new screen objects for the same displays.
    let a2 = FakeScreen("AAAA")
    directory.rebuild(screens: [a2], uuid: \.uuid)
    check(directory.screen(for: "AAAA") === a2 && directory.screen(for: "BBBB") == nil,
          "displays: after a reconfiguration the UUID finds the new screen, unplugged ones are gone")
    check(ArisDisplayUUID.string(for: CGDirectDisplayID(0xFFFF_FFF0)) == nil, "displays: a display id the system doesn't know has no UUID")
    if let main = NSScreen.screens.first, let uuid = main.displayUUID {
        check(uuid == uuid.uppercased() && uuid.split(separator: "-").count == 5, "displays: the UUID is upper-case and dashed")
        check(NSScreen.screen(withUUID: uuid) == main, "displays: NSScreen lookup by UUID")
    }
}

private func relaunchTests() {
    var opened: [(URL, NSWorkspace.OpenConfiguration)] = [], touched: [URL] = [], events: [String] = []
    var result = true
    let relauncher = ArisRelauncher(
        open: { url, config, done in opened.append((url, config)); done(result) },
        noteChange: { touched.append($0) },
        terminate: { events.append("terminate") })
    let app = URL(fileURLWithPath: "/Applications/Aris.app")
    relauncher.relaunch(at: app) { events.append("before") }
    check(opened.count == 1 && opened[0].0 == app && opened[0].1.createsNewApplicationInstance,
          "relaunch: opens the app as a new instance")
    check(events == ["before", "terminate"] && touched.map(\.path) == ["/Applications"],
          "relaunch: on success notes the folder, runs the closure, then quits")
    result = false; events = []
    relauncher.relaunch(at: app) { events.append("before") }
    check(events.isEmpty, "relaunch: on failure it stays running and skips the closure")
    opened = []
    relauncher.relaunch(at: nil) { events.append("before") }
    check(opened.isEmpty && events.isEmpty, "relaunch: no app URL, nothing happens")
}

private func bundleVersionTests() {
    let info = ArisBundleVersion(info: ["CFBundleShortVersionString": "2.8", "CFBundleVersion": "214"])
    check(info.release == "2.8" && info.build == "214", "versions: release and build come from the Info dictionary")
    let empty = ArisBundleVersion(info: [:])
    check(empty.release == nil && empty.build == nil, "versions: missing keys are nil")
    check(ArisBundleVersion(info: ["CFBundleVersion": 7]).build == nil, "versions: a non-string value is nil")
}

private func accentTests() {
    let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    let data = ArisAccent.archive(color)
    let back = data.flatMap(ArisAccent.unarchive)?.usingColorSpace(.sRGB)
    check(back.map { abs($0.redComponent - 0.2) < 0.001 && abs($0.blueComponent - 0.6) < 0.001 } == true,
          "accent: archive / unarchive round-trip")
    check(ArisAccent.unarchive(Data([1, 2, 3])) == nil, "accent: corrupt data decodes to nothing")
    let system = NSColor.controlAccentColor
    check(ArisAccent.effective(custom: true, data: Data([9])) == system, "accent: custom on but corrupt -> system accent")
    check(ArisAccent.effective(custom: false, data: data) == system, "accent: custom off -> system accent")
    let custom = ArisAccent.effective(custom: true, data: data).usingColorSpace(.sRGB)
    check(custom.map { abs($0.greenComponent - 0.4) < 0.001 } == true, "accent: custom on -> the stored colour")
    check(ArisAccent.Preset.allCases.count == 8, "accent: eight presets")
    let blue = ArisAccent.Preset.blue.rgb, graphite = ArisAccent.Preset.graphite.rgb
    check(blue == (0, 0.478, 1) && graphite == (0.557, 0.557, 0.576), "accent: preset values are Apple's palette")
    check(ArisAccent.backgroundAlpha == 0.25, "accent: the background variant is the accent at 25 %")
}

private func blurViewTests() {
    let view = NSVisualEffectView()
    ArisBlur.configure(view, material: .hudWindow, blending: .behindWindow)
    check(view.material == .hudWindow && view.blendingMode == .behindWindow && view.state == .active && view.isEmphasized,
          "blur: material, blending, always active, emphasised")
    ArisBlur.configure(view, material: .popover, blending: .withinWindow)
    check(view.material == .popover && view.blendingMode == .withinWindow, "blur: an update changes material and blending")
}
