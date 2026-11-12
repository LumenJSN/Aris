//
//  ArisFrontNow.swift
//  aris-agent, aris-tools
//
//  Which app is in front, asked of the window server at the moment of asking. aris-agent runs for days with no AppKit
//  app of its own, and what NSWorkspace tells such a process about the app in front is kept up by notifications that
//  lag behind an app that was just launched: after Safari was opened over a TextEdit memo, the helper still "saw"
//  TextEdit in front, read the memo for "summarize this", sent it to the AI and learned a note from it, until the
//  helper was restarted (second upgrade run, bug 1). The window server's own list has no such memory: it is front to
//  back as the screen is now, with each window's owner. An app's own windows are on layer 0; the menu bar, the Dock,
//  Aris's notch and side panels are on higher ones. Two displays and a full-screen app are one list like any other:
//  the window he used last is first.
//  A look reads the app Aris itself says he was in (Aris is a real app: what it knows is current, and while he types
//  into the notch it names the app he came from), or the owner of the topmost window that is not Aris's or a macOS
//  prompt's; what was read counts only while that window is still that app's own topmost window when the read is
//  over (ArisLookTrust: a look that could not be confirmed teaches no note). A key press's "which app is in front"
//  is the app that has the keyboard now (frontPid). The live half is ArisFrontLive. Foundation only, so it is tested.
//

import Foundation

enum ArisFrontNow {
    /// A window on screen, as the window server lists it (front to back).
    struct Window: Equatable {
        /// The window server's number for it.
        let id: Int
        let pid: Int32
        /// 0: an app's own window.
        let layer: Int
        var alpha: Double = 1
        var width: Double = 800
        var height: Double = 600
        var onScreen = true
    }

    /// Narrower or lower than this (points), a layer-0 window is an app's hidden helper, never what he is looking at.
    static let smallest: Double = 40

    /// One entry of CGWindowListCopyWindowInfo, by the window server's own key names; nil when it names no owner.
    static func window(_ info: [String: Any]) -> Window? {
        guard let id = (info["kCGWindowNumber"] as? NSNumber)?.intValue, let pid = (info["kCGWindowOwnerPID"] as? NSNumber)?.int32Value,
              let layer = (info["kCGWindowLayer"] as? NSNumber)?.intValue else { return nil }
        let bounds = info["kCGWindowBounds"] as? [String: Any]
        let side = { (key: String) in (bounds?[key] as? NSNumber)?.doubleValue ?? 0 }
        return Window(id: id, pid: pid, layer: layer, alpha: (info["kCGWindowAlpha"] as? NSNumber)?.doubleValue ?? 1,
                      width: side("Width"), height: side("Height"), onScreen: (info["kCGWindowIsOnscreen"] as? NSNumber)?.boolValue ?? true)
    }

    /// An app's own window that can be seen: layer 0, on screen, not clear, not a dot.
    static func counts(_ window: Window) -> Bool {
        window.layer == 0 && window.onScreen && window.alpha > 0 && window.width >= smallest && window.height >= smallest
    }

    /// The process's topmost window that counts.
    static func topWindow(of pid: Int32, in windows: [Window]) -> Window? {
        windows.first { $0.pid == pid && counts($0) }
    }

    /// The topmost window that counts, of the processes not skipped.
    static func front(in windows: [Window], skipping skip: (Int32) -> Bool = { _ in false }) -> Window? {
        windows.first { counts($0) && !skip($0.pid) }
    }

    /// Whether the process shows anything of its own on screen below the Dock's and the menu bar's layers (a floating
    /// palette counts; a menu bar item or a notch does not).
    static func showsWindow(_ pid: Int32, in windows: [Window]) -> Bool {
        windows.contains { $0.pid == pid && $0.onScreen && $0.alpha > 0 && (0..<highest).contains($0.layer) && $0.width >= smallest && $0.height >= smallest }
    }

    /// The Dock's layer: an app's own windows and panels are below it.
    static let highest = 20

    /// How a look's app was found.
    enum Source: Equatable {
        /// Aris said which app he was in.
        case app
        /// The window server's order: the topmost window that is not Aris's or a macOS prompt's.
        case windows
    }

    /// The app a look reads, and the one window of it that is read (nil: it shows no window of its own).
    struct Target: Equatable {
        let pid: Int32
        let window: Int?
        let by: Source
    }

    /// `told`: the app Aris says is in front (nil: it didn't say); `windows`: the screen now, front to back;
    /// `steppedOver`: Aris, the helper and macOS's passing panels (ArisLookTarget), never what he is looking at;
    /// `ordinary`: an app with a Dock icon. The app Aris named when it is one of his and shows a window; else the owner
    /// of the topmost ordinary window (Aris itself is in front while he types into the notch, and an app with nothing
    /// on screen is not what "this" is); nil when nothing on screen is his.
    static func lookTarget(told: Int32?, windows: [Window], steppedOver: (Int32) -> Bool, ordinary: (Int32) -> Bool) -> Target? {
        if let told, !steppedOver(told), showsWindow(told, in: windows) {
            return Target(pid: told, window: topWindow(of: told, in: windows)?.id, by: .app)
        }
        if let top = front(in: windows, skipping: { steppedOver($0) || !ordinary($0) }) { return Target(pid: top.pid, window: top.id, by: .windows) }
        return nil
    }

    /// Whether what a look read is the target's: asked again when the read is over (a look takes seconds: he may have
    /// gone to another window). The window that was read must still be on screen, still that process's, and still its
    /// topmost; found by the window order, it must still be the topmost of all. A target with no window had none read:
    /// what Aris said stands.
    static func confirmed(_ target: Target, after windows: [Window], steppedOver: (Int32) -> Bool, ordinary: (Int32) -> Bool) -> Bool {
        guard let id = target.window else { return target.by == .app }
        guard let now = windows.first(where: { $0.id == id }), now.pid == target.pid, topWindow(of: target.pid, in: windows)?.id == id else { return false }
        guard target.by == .windows else { return true }
        return front(in: windows, skipping: { steppedOver($0) || !ordinary($0) })?.id == id
    }

    /// The app in front for a key press or a check that has no word from Aris: the one Accessibility says has the
    /// keyboard (`focused`, when aris-agent may ask), else the owner of the topmost window that counts.
    static func frontPid(focused: Int32?, windows: [Window]) -> Int32? {
        if let focused, focused > 0 { return focused }
        return front(in: windows)?.pid
    }

    /// Whether keys may go to `target` now: only when Accessibility says it has the keyboard (security review 9, L4: no
    /// answer from Accessibility is no, never the window order's guess).
    static func keysGo(focused: Int32?, target: Int32) -> Bool {
        guard let focused, focused > 0 else { return false }
        return focused == target
    }

    /// Whether an app's own Info.plist says it is an ordinary app (it has a Dock icon): asked of the file when AppKit
    /// has nothing current to say about a process. `bundlePath`: the folder the process's program is in, when it ends in .app.
    static func ordinary(bundlePath: String?, info: [String: Any]?) -> Bool {
        guard let bundlePath, bundlePath.hasSuffix(".app"), let info else { return false }
        let on = { (key: String) -> Bool in
            if let flag = info[key] as? Bool { return flag }
            if let number = info[key] as? NSNumber { return number.boolValue }
            return ["1", "true", "yes"].contains((info[key] as? String ?? "").lowercased())
        }
        return !on("LSUIElement") && !on("LSBackgroundOnly")
    }

    /// The .app a program runs from: `/Applications/Safari.app/Contents/MacOS/Safari` → `/Applications/Safari.app`
    /// (the innermost one: a browser's helper is its own app); nil for a program that is in none.
    static func bundlePath(executable: String) -> String? {
        let parts = executable.components(separatedBy: "/")
        guard let index = parts.lastIndex(where: { $0.hasSuffix(".app") }), index + 2 < parts.count,
              parts[index + 1] == "Contents", parts[index + 2] == "MacOS" else { return nil }
        return parts[...index].joined(separator: "/")
    }
}

/// A look whose target could not be confirmed says so in its own words (ArisLook.context), and a turn whose prompt
/// carries that line learns no note: the garden memo was learned as "the front window" while Safari was (second
/// upgrade run, bug 1). The line is the helper's: outside text that copies it only stops a note being learned.
enum ArisLookTrust {
    static let unconfirmedLine = "(Aris could not confirm that this text is from the window the user is looking at: the windows changed while it was read. Say which app's window it came from, ask the user to check, and keep no note about it.)"

    /// Whether a turn's notes may be kept: never from a turn over a look that could not be confirmed.
    static func keepsNotes(prompt: String?) -> Bool {
        !(prompt ?? "").contains(unconfirmedLine)
    }
}
