//
//  ArisPeekabooCommands.swift
//  aris-agent
//
//  Peekaboo's argv, built by Aris alone from what it resolved (never a brain's words): the app by its bundle id
//  (Peekaboo refuses executable names for actions, and menus and buttons are localized), an exact window id or a fresh
//  exact-window snapshot on every call, background delivery unless the call is one the user consented to bring forward.
//  Every value that could start with a dash goes in `--flag=value` form, so text is never read as a flag. Pure.
//

import CoreGraphics
import Foundation

enum ArisPeekabooCommands {
    /// A process as Peekaboo's --app takes it: the bundle id, else `PID:<n>`.
    static func app(_ target: ArisDesktopTarget) -> String { target.bundle ?? "PID:\(target.pid)" }

    /// A look at one window: the accessibility tree only, or with a screenshot saved at `path` (annotated: Peekaboo's
    /// element marks drawn on it).
    static func see(window: Int, path: String? = nil, annotate: Bool = false) -> [String] {
        var argv = ["see", "--window-id", String(window)]
        if let path { argv += ["--path", path] + (annotate ? ["--annotate"] : []) } else { argv += ["--tree", "--no-screenshot"] }
        return argv + ["--json"]
    }

    /// `actionOnly`: the element's own Accessibility action and nothing else (Peekaboo 4.9.8's `--input-strategy`
    /// takes actionFirst, synthFirst, actionOnly or synthOnly; its default for a click is actionFirst, which falls back
    /// to synthetic pointer input when the element has no action). A click that holds the lock for its app alone.
    static func click(_ element: String, snapshot: String, double: Bool = false, right: Bool = false, foreground: Bool = false,
                      actionOnly: Bool = false) -> [String] {
        ["click", "--on", element, "--snapshot", snapshot] + (double ? ["--double"] : []) + (right ? ["--right"] : [])
            + (foreground ? ["--foreground"] : []) + (actionOnly ? ["--input-strategy", "actionOnly"] : []) + ["--json"]
    }

    /// A point click, window-relative: in the background against the snapshot's window, or (the user consented) a real
    /// pointer click in the pinned window.
    static func clickAt(_ point: CGPoint, snapshot: String, window: Int, foreground: Bool) -> [String] {
        let at = "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
        return foreground ? ["click", "--at", at, "--window-id", String(window), "--foreground", "--input-strategy", "synthOnly", "--json"]
            : ["click", "--at", at, "--snapshot", snapshot, "--json"]
    }

    /// Peekaboo reads `\n`, `\t`, `\b`, `\e` and `\\` in typed text as keys: a backslash the user wrote is doubled so it
    /// is typed as one.
    static func literal(_ text: String) -> String { composed(text).replacingOccurrences(of: "\\", with: "\\\\") }

    /// Text as the app gets it: composed (NFC), the form a person's keyboard produces (Korean as syllables, never jamo).
    static func composed(_ text: String) -> String { text.precomposedStringWithCanonicalMapping }

    static func type(_ text: String, window: Int, foreground: Bool = false) -> [String] {
        ["type", "--text=" + literal(text), "--window-id", String(window)] + (foreground ? ["--foreground"] : []) + ["--json"]
    }

    static func setValue(_ value: String, element: String, snapshot: String) -> [String] {
        ["set-value", "--value=" + composed(value), "--on", element, "--snapshot", snapshot, "--json"]
    }

    static func press(_ keys: [String], snapshot: String) -> [String] { ["press"] + keys + ["--snapshot", snapshot, "--json"] }

    /// Keys to the pinned window brought forward (the user's card said so).
    static func pressForward(_ keys: [String], window: Int) -> [String] { ["press"] + keys + ["--window-id", String(window), "--foreground", "--json"] }

    static func scroll(_ direction: String, amount: Int, element: String, snapshot: String) -> [String] {
        ["scroll", "--direction", direction, "--amount", String(amount), "--on", element, "--snapshot", snapshot, "--json"]
    }

    static func drag(from: String, to: String, snapshot: String) -> [String] { ["drag", "--from", from, "--to", to, "--snapshot", snapshot, "--json"] }

    static func menuList(_ target: ArisDesktopTarget) -> [String] { ["menu", "list", "--app", app(target), "--json"] }

    static func menuClick(_ path: String, _ target: ArisDesktopTarget) -> [String] { ["menu", "click", "--app", app(target), "--path=" + path, "--json"] }

    static func dialogList(_ target: ArisDesktopTarget) -> [String] { ["dialog", "list", "--app", app(target), "--json"] }

    static func dialogClick(_ button: String, _ target: ArisDesktopTarget) -> [String] { ["dialog", "click", "--button=" + button, "--app", app(target), "--json"] }

    static func dialogInput(_ text: String, field: String?, _ target: ArisDesktopTarget) -> [String] {
        ["dialog", "input", "--text=" + composed(text)] + (field.map { ["--field=" + $0] } ?? []) + ["--app", app(target), "--json"]
    }

    /// A file panel, in one step: its folder, the file's name, then its button (`select`, else its default: Save or Open).
    /// It needs the panel in front (the user's card said so). `window`: the panel's own window, so the panel and its accessory
    /// view are never two candidates (bench te_saveas: "ambiguous across 2 eligible dialogs").
    static func dialogFile(path: String?, name: String?, select: String?, window: Int? = nil, _ target: ArisDesktopTarget) -> [String] {
        ["dialog", "file", "--app", app(target)] + (window.map { ["--window-id", String($0)] } ?? []) + (path.map { ["--path=" + $0] } ?? [])
            + (name.map { ["--name=" + composed($0)] } ?? []) + (select.map { ["--select=" + $0] } ?? []) + ["--foreground", "--json"]
    }

    static func windowList(_ target: ArisDesktopTarget) -> [String] { ["window", "list", "--app", app(target), "--json"] }

    static func window(_ operation: String, window: Int, x: Int? = nil, y: Int? = nil, width: Int? = nil, height: Int? = nil) -> [String] {
        var argv = ["window", operation, "--window-id", String(window)]
        if let x, let y { argv += ["--x", String(x), "--y", String(y)] }
        if let width, let height { argv += ["--width", String(width), "--height", String(height)] }
        return argv + ["--json"]
    }

    static func app(_ operation: String, _ target: ArisDesktopTarget) -> [String] {
        switch operation {
        case "launch":
            guard let bundle = target.bundle else { return [] }
            return ["app", "launch", "--bundle-id", bundle, "--wait-for-window", "--foreground", "--json"]
        default: return ["app", operation, "--app", app(target), "--json"]
        }
    }

    static func dockList() -> [String] { ["dock", "list", "--json"] }
}
