//
//  ArisAppsHands+Apps.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  app.find, app.alias, app.open, app.quit, app.hide, app.focus, app.running, app.frontmost.
//

import Foundation

extension ArisAppsHands {
    func find(_ arguments: ArisApps.JSON) -> ArisApps.Outcome {
        guard let query = arguments["query"]?.string, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure("app.find needs the name the owner said", effect: .observe)
        }
        let ranked = ranked(query)
        let top = ArisApps.JSON.array(ranked.prefix(5).map(\.json))
        switch ArisApps.Find.answer(ranked) {
        case .app(let match):
            return ArisApps.Outcome(ok: true, did: "‘\(query)’ is \(match.name)", now: match.running ? "\(match.name) is running" : "\(match.name) is installed, not running",
                                    data: .object(["app": match.json, "candidates": top]), effect: .observe, channel: "find", verified: true)
        case .web(let match):
            let browser = system.defaultBrowser()
            var data: [String: ArisApps.JSON] = ["app": match.json, "candidates": top]
            if let browser { data["browser"] = .string(browser) }
            return ArisApps.Outcome(ok: true, did: "‘\(query)’ is \(match.name) on the web (no app for it here): open \(match.web ?? "") in the browser",
                                    now: "", data: .object(data), effect: .observe, channel: "find", verified: true)
        case .ask(let matches):
            var outcome = ArisApps.Outcome(ok: false, did: "‘\(query)’ could be more than one app", now: "",
                                           data: .object(["candidates": .array(matches.map(\.json)), "question_en": .string(ArisApps.Find.question(query, matches).en)]),
                                           effect: .observe, channel: "find")
            outcome.question = ArisApps.Find.question(query, matches).ko
            return outcome
        case .notInstalled(let match):
            return ArisApps.Outcome(ok: false, did: "\(match.name) isn't installed on this Mac", now: "", data: .object(["app": match.json]), effect: .observe, channel: "find")
        case .none:
            return ArisApps.Outcome(ok: false, did: "no app on this Mac is called ‘\(query)’", now: "", data: .object(["candidates": top]), effect: .observe, channel: "find")
        }
    }

    func alias(_ arguments: ArisApps.JSON) -> ArisApps.Outcome {
        guard let name = arguments["name"]?.string, !ArisApps.Text.core(name).isEmpty else {
            return .failure("app.alias needs the name", effect: .changeReversible)
        }
        if arguments["forget"]?.bool == true {
            let updated = lock.withLock { () -> ArisApps.Aliases in aliases = aliases.forgetting(name); return aliases }
            store.saveAliases(updated)
            return ArisApps.Outcome(ok: true, did: "forgot ‘\(name)’", now: "", effect: .changeReversible, channel: "store", verified: true)
        }
        guard let said = arguments["app"]?.string else { return .failure("app.alias needs the app it means", effect: .changeReversible) }
        // The app is named exactly here (a name, a bundle id): the best installed match, never a question.
        guard let match = ArisApps.Find.rank(said, apps: candidates(), aliases: ArisApps.Aliases()).first(where: { $0.bundle != nil }), let bundle = match.bundle else {
            return .failure("no app called ‘\(said)’ to remember ‘\(name)’ for", effect: .changeReversible)
        }
        let updated = lock.withLock { () -> ArisApps.Aliases in aliases = aliases.learning(name, bundle: bundle); return aliases }
        store.saveAliases(updated)
        return ArisApps.Outcome(ok: true, did: "‘\(name)’ now means \(match.name)", now: "", data: match.json, effect: .changeReversible, channel: "store", verified: true)
    }

    func open(_ arguments: ArisApps.JSON, context: Context) -> ArisApps.Outcome {
        let front = arguments["front"]?.bool == true && !context.background
        let url = arguments["url"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        var path = arguments["path"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        // A known place by its name, or a path from ~ or /: the real path on this Mac, never a guessed home (tenth VM run, item 2).
        let reveal = arguments["reveal"]?.bool == true
        let home = Self.home()
        if let said = arguments["place"]?.string.flatMap({ $0.isEmpty ? nil : $0 }) {
            // Only a place's own name (the effect was judged for a known folder, never for a path written here).
            guard let place = ArisKnownPlaces.named(said) else { return .failure("couldn't open ‘\(said)’: \(ArisKnownPlaces.unknownLine)", effect: .changeReversible) }
            path = ArisKnownPlaces.path(place, home: home)
        } else if let said = path {
            switch ArisKnownPlaces.resolve(said, home: home, exists: { self.system.pathKind($0) != .missing }) {
            case .path(let real): path = real
            case .noSuchUser(let user): return .failure(ArisKnownPlaces.noSuchUserLine(user, home: home), effect: .changeReversible)
            case .unknown: return .failure("couldn't open ‘\(said)’: \(ArisKnownPlaces.unknownLine)", effect: .changeReversible)
            }
        }
        if reveal, path == nil { return .failure("reveal needs a path or a place", effect: .changeReversible) }
        var bundle: String?, name = ""
        if let said = arguments["app"]?.string, !said.isEmpty {
            switch resolve(said, effect: .changeReversible) {
            case .app(let target):
                bundle = target.bundle
                name = target.name
            case .answer(let outcome):
                // A web service with no app: its address opens in the browser.
                guard url == nil, path == nil, let web = outcome.data["web"]?.string else { return outcome }
                return finishOpen(ArisAppsOpenRequest(bundle: nil, path: nil, url: web, front: front), name: outcome.data["name"]?.string ?? said)
            }
        }
        if let url, URL(string: url)?.scheme == nil { return .failure("‘\(url)’ isn't a URL", effect: .changeReversible) }
        guard bundle != nil || url != nil || path != nil else { return .failure("app.open needs an app, a path or a url", effect: .changeReversible) }
        return finishOpen(ArisAppsOpenRequest(bundle: bundle, path: path, url: url, front: front, reveal: reveal), name: name)
    }

    /// The owner's home folder (tests set it).
    nonisolated(unsafe) static var home: () -> String = { NSHomeDirectory() }

    private func finishOpen(_ request: ArisAppsOpenRequest, name: String) -> ArisApps.Outcome {
        let answer = system.open(request)
        let what = [request.url, request.path].compactMap { $0 }.first.map { "\($0)" + (name.isEmpty ? "" : " in \(name)") } ?? name
        guard answer.ok else { return .failure("couldn't open \(what): \(answer.message)", effect: .changeReversible) }
        var now = ""
        if let bundle = request.bundle ?? (request.url.map { _ in system.defaultBrowser() } ?? nil), let running = running(bundle) {
            now = "\(running.name) is running" + (running.active ? " in front" : " in the background")
        }
        if request.reveal { return ArisApps.Outcome(ok: true, did: "showed \(what) in Finder", now: now, effect: .changeReversible, channel: "workspace", verified: true) }
        return ArisApps.Outcome(ok: true, did: "opened \(what)" + (request.front ? "" : " (in the background)"), now: now, effect: .changeReversible,
                                channel: request.url != nil ? "url" : "workspace", verified: !now.isEmpty)
    }

    func appAction(_ name: String, _ arguments: ArisApps.JSON, context: Context) -> ArisApps.Outcome {
        let target: Target
        switch resolve(arguments["app"]?.string, effect: .changeReversible) {
        case .app(let found): target = found
        case .answer(let outcome): return outcome
        }
        guard let running = target.running else {
            return name == "app.focus" ? open(.object(["app": .string(target.bundle), "front": .bool(true)]), context: context)
                : ArisApps.Outcome(ok: true, did: "\(target.name) isn't running", now: "\(target.name) isn't running", effect: .changeReversible, channel: "workspace", verified: true)
        }
        switch name {
        case "app.quit":
            guard system.quit(pid: running.pid) else { return .failure("\(target.name) didn't take the quit", effect: .changeReversible) }
            let gone = waitFor { self.running(target.bundle) == nil }
            return ArisApps.Outcome(ok: true, did: "asked \(target.name) to quit", now: gone ? "\(target.name) has quit" : "\(target.name) is still open (it may be asking about unsaved work)",
                                    effect: .changeReversible, channel: "workspace", verified: gone)
        case "app.hide":
            guard system.hide(pid: running.pid) else { return .failure("\(target.name) didn't hide", effect: .changeReversible) }
            return ArisApps.Outcome(ok: true, did: "hid \(target.name)", now: "", effect: .changeReversible, channel: "workspace")
        default:
            guard !context.background else { return .failure("a background task never brings an app forward", effect: .changeReversible) }
            if let window = arguments["window"]?.int {
                let reply = Self.envelope(engine.run(["window", "focus", "--window-id", String(window)], background: false))
                guard reply.ok else { return .failure("couldn't bring that window forward: \(reply.message)", effect: .changeReversible) }
            } else {
                guard system.activate(pid: running.pid) else { return .failure("\(target.name) didn't come forward", effect: .changeReversible) }
            }
            let front = waitFor { self.system.frontmost()?.pid == running.pid }
            return ArisApps.Outcome(ok: true, did: "brought \(target.name) forward", now: front ? "\(target.name) is in front" : "", effect: .changeReversible,
                                    channel: "workspace", verified: front)
        }
    }

    func running() -> ArisApps.Outcome {
        let apps = system.runningApps()
        let list = ArisApps.JSON.array(apps.map { app in
            .object(["name": .string(app.name), "bundle": .string(app.bundle), "hidden": .bool(app.hidden), "front": .bool(app.active)])
        })
        return ArisApps.Outcome(ok: true, did: "\(apps.count) apps running", now: apps.first(where: \.active).map { "\($0.name) is in front" } ?? "",
                                data: .object(["apps": list]), effect: .observe, channel: "workspace", verified: true)
    }

    func frontmost() -> ArisApps.Outcome {
        guard let front = system.frontmost() else { return .failure("no app is in front", effect: .observe) }
        var data: [String: ArisApps.JSON] = ["name": .string(front.name), "bundle": .string(front.bundle)]
        let windows = Self.envelope(engine.run(["window", "list", "--app", front.bundle], background: true)).data["windows"]?.array ?? []
        if let window = windows.first(where: { $0["is_frontmost"]?.bool == true }) ?? windows.first {
            data["window"] = .object(["id": window["window_id"] ?? .null, "title": window["window_title"] ?? .null])
        }
        return ArisApps.Outcome(ok: true, did: "\(front.name) is in front", now: data["window"]?["title"]?.string.map { "its window: \($0)" } ?? "",
                                data: .object(data), effect: .observe, channel: "workspace", verified: true)
    }

    /// Polls a condition for up to `pollSeconds` (the tests' fakes answer at once and set it to 0).
    func waitFor(_ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(pollSeconds)
        while true {
            if condition() { return true }
            if Date() >= end { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}
