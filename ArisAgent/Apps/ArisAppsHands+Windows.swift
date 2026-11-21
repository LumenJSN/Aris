//
//  ArisAppsHands+Windows.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  window.list, window.move, window.resize, window.tile, window.space, window.minimize, window.close: over the
//  engine's window calls (its Accessibility window list and setters), which work without bringing anything forward.
//

import Foundation

extension ArisAppsHands {
    struct WindowInfo {
        var id: Int
        var title: String
        var frame: ArisApps.Rect
        var front: Bool
    }

    func windows(of bundle: String) -> [WindowInfo] { readWindows(of: bundle).windows }

    /// The app's windows; nil when the engine couldn't list them (sixth VM run, item 4: never read as "no windows").
    func listedWindows(of bundle: String) -> [WindowInfo]? {
        let read = readWindows(of: bundle)
        return read.ok ? read.windows : nil
    }

    private func readWindows(of bundle: String) -> (ok: Bool, windows: [WindowInfo]) {
        let reply = Self.envelope(engine.run(["window", "list", "--app", bundle], background: true))
        let listed = reply.data["windows"]?.array
        return (reply.ok && listed != nil, (listed ?? []).compactMap { window in
            guard let id = window["window_id"]?.int else { return nil }
            let bounds = window["bounds"]
            let frame = ArisApps.Rect(x: bounds?["x"]?.number ?? 0, y: bounds?["y"]?.number ?? 0, width: bounds?["width"]?.number ?? 0, height: bounds?["height"]?.number ?? 0)
            return WindowInfo(id: id, title: window["window_title"]?.string ?? "", frame: frame, front: window["is_frontmost"]?.bool ?? false)
        })
    }

    static func json(_ window: WindowInfo, app: String? = nil) -> ArisApps.JSON {
        var object: [String: ArisApps.JSON] = ["id": .number(Double(window.id)), "title": .string(window.title), "front": .bool(window.front),
                                               "frame": .string("\(Int(window.frame.x)),\(Int(window.frame.y)) \(Int(window.frame.width))×\(Int(window.frame.height))")]
        if let app { object["app"] = .string(app) }
        return .object(object)
    }

    func windowList(_ arguments: ArisApps.JSON) -> ArisApps.Outcome {
        if let said = arguments["app"]?.string, !said.isEmpty {
            guard case .app(let target) = resolve(said, effect: .observe) else {
                if case .answer(let outcome) = resolve(said, effect: .observe) { return outcome }
                return .failure("no such app", effect: .observe)
            }
            guard target.running != nil else {
                return ArisApps.Outcome(ok: true, did: "\(target.name) isn't running", now: "\(target.name) has no windows", data: .object(["windows": .array([])]),
                                        effect: .observe, channel: "engine", verified: true)
            }
            let list = windows(of: target.bundle)
            return ArisApps.Outcome(ok: true, did: "\(target.name) has \(list.count) window\(list.count == 1 ? "" : "s")", now: list.first(where: \.front).map { "front: \($0.title)" } ?? "",
                                    data: .object(["windows": .array(list.map { Self.json($0) })]), effect: .observe, channel: "engine", verified: true)
        }
        var all: [ArisApps.JSON] = []
        for app in system.runningApps() where !app.hidden {
            all += windows(of: app.bundle).map { Self.json($0, app: app.name) }
        }
        return ArisApps.Outcome(ok: true, did: "\(all.count) windows open", now: "", data: .object(["windows": .array(all)]), effect: .observe, channel: "engine", verified: true)
    }

    /// The window a call names: its `window` id, else the app's front window, else its first.
    func window(_ arguments: ArisApps.JSON) -> (Target, WindowInfo)? {
        guard case .app(let target) = resolve(arguments["app"]?.string, effect: .changeReversible), target.running != nil else { return nil }
        let list = windows(of: target.bundle)
        if let id = arguments["window"]?.int { return list.first { $0.id == id }.map { (target, $0) } }
        return (list.first(where: \.front) ?? list.first).map { (target, $0) }
    }

    private func missingWindow(_ arguments: ArisApps.JSON) -> ArisApps.Outcome {
        if case .answer(let outcome) = resolve(arguments["app"]?.string, effect: .changeReversible) { return outcome }
        return .failure("no such window (the app isn't running or has none open)", effect: .changeReversible)
    }

    /// Moves and sizes a window through the engine; what is true afterwards is read back.
    func place(_ window: WindowInfo, at frame: ArisApps.Rect, target: Target) -> ArisApps.Outcome {
        let id = String(window.id)
        let moved = Self.envelope(engine.run(["window", "move", "--window-id", id, "--x", String(Int(frame.x)), "--y", String(Int(frame.y))], background: true))
        let sized = frame.width == window.frame.width && frame.height == window.frame.height ? moved
            : Self.envelope(engine.run(["window", "resize", "--window-id", id, "--width", String(Int(frame.width)), "--height", String(Int(frame.height))], background: true))
        guard moved.ok || sized.ok else { return .failure("\(target.name)'s window didn't move: \(moved.message)", effect: .changeReversible) }
        let after = windows(of: target.bundle).first { $0.id == window.id }
        let landed = after.map { abs($0.frame.x - frame.x) < 3 && abs($0.frame.y - frame.y) < 3 } ?? false
        return ArisApps.Outcome(ok: true, did: "moved \(target.name)'s window “\(window.title)”", now: after.map { "it is at \(Int($0.frame.x)),\(Int($0.frame.y)), \(Int($0.frame.width))×\(Int($0.frame.height))" } ?? "",
                                data: after.map { Self.json($0) } ?? .null, effect: .changeReversible, channel: "engine", verified: landed)
    }

    func windowAction(_ name: String, _ arguments: ArisApps.JSON, context: Context) -> ArisApps.Outcome {
        guard let (target, window) = self.window(arguments) else { return missingWindow(arguments) }
        switch name {
        case "window.move":
            guard let to = arguments["to"]?.string, let frame = ArisApps.Layout.frame(to, window: window.frame, displays: system.displays()) else {
                return .failure("window.move takes one of \(ArisApps.Layout.positions.joined(separator: ", ")) or x,y", effect: .changeReversible)
            }
            return place(window, at: frame, target: target)
        case "window.resize":
            guard let width = arguments["width"]?.int, let height = arguments["height"]?.int, width >= 50, height >= 50 else {
                return .failure("window.resize needs a width and height of at least 50 points", effect: .changeReversible)
            }
            return place(window, at: ArisApps.Rect(x: window.frame.x, y: window.frame.y, width: Double(width), height: Double(height)), target: target)
        case "window.space":
            let to = arguments["to"]?.string ?? ""
            if to == "next-display", let frame = ArisApps.Layout.frame(to, window: window.frame, displays: system.displays()) { return place(window, at: frame, target: target) }
            if to == "next-display" { return .failure("there is only one display", effect: .changeReversible) }
            guard ["fullscreen", "exit-fullscreen"].contains(to), let running = target.running else {
                return .failure("window.space takes fullscreen, exit-fullscreen or next-display (macOS has no public way to move a window to a numbered desktop)",
                                effect: .changeReversible)
            }
            guard ax.setFullScreen(pid: running.pid, window: window.id, on: to == "fullscreen") else {
                return .failure("\(target.name)'s window can't go \(to == "fullscreen" ? "full screen" : "back from full screen")", effect: .changeReversible)
            }
            return ArisApps.Outcome(ok: true, did: to == "fullscreen" ? "put \(target.name)'s window in full screen" : "took \(target.name)'s window out of full screen",
                                    now: "", effect: .changeReversible, channel: "ax")
        default:
            let operation = name == "window.close" ? "close" : (arguments["restore"]?.bool == true ? "restore" : "minimize")
            let reply = Self.envelope(engine.run(["window", operation, "--window-id", String(window.id)], background: context.background))
            guard reply.ok else { return .failure("couldn't \(operation) \(target.name)'s window: \(reply.message)", effect: .changeReversible) }
            let after = windows(of: target.bundle)
            let gone = !after.contains { $0.id == window.id }
            let now = operation == "close" ? (gone ? "the window is closed" : "the window is still open (the app may be asking about unsaved work)")
                : "\(target.name) has \(after.count) window\(after.count == 1 ? "" : "s") open"
            return ArisApps.Outcome(ok: true, did: "\(operation)d \(target.name)'s window “\(window.title)”",
                                    now: now, effect: .changeReversible, channel: "engine", verified: operation == "close" ? gone : false)
        }
    }

    func tile(_ arguments: ArisApps.JSON, context: Context) -> ArisApps.Outcome {
        let names = arguments["apps"]?.array?.compactMap(\.string) ?? []
        guard !names.isEmpty else { return .failure("window.tile needs the apps", effect: .changeReversible) }
        var placed: [(Target, WindowInfo)] = []
        for said in names {
            switch resolve(said, effect: .changeReversible) {
            case .answer(let outcome): return outcome
            case .app(let target):
                guard target.running != nil else { return .failure("\(target.name) isn't running", effect: .changeReversible) }
                let list = windows(of: target.bundle)
                // One app named: all its windows; several: each one's front window.
                placed += (names.count == 1 ? list : Array((list.first(where: \.front) ?? list.first).map { [$0] } ?? [])).map { (target, $0) }
            }
        }
        guard !placed.isEmpty else { return .failure("none of those apps has a window open", effect: .changeReversible) }
        guard let area = ArisApps.Layout.display(of: placed[0].1.frame, in: system.displays()) else { return .failure("no display", effect: .changeReversible) }
        let frames = ArisApps.Layout.tile(count: placed.count, grid: arguments["grid"]?.string, in: area)
        var results: [ArisApps.Outcome] = []
        for (index, frame) in frames.enumerated() { results.append(place(placed[index].1, at: frame, target: placed[index].0)) }
        let ok = results.filter(\.ok).count
        return ArisApps.Outcome(ok: ok > 0, did: "tiled \(ok) of \(placed.count) windows", now: results.map(\.now).filter { !$0.isEmpty }.joined(separator: "; "),
                                effect: .changeReversible, channel: "engine", verified: results.allSatisfy(\.verified))
    }
}
