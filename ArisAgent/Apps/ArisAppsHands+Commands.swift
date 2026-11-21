//
//  ArisAppsHands+Commands.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  app.commands (what an app can do, discovered from its channels and cached per app version) and app.do (one
//  command run through the channel that costs the fewest permission prompts and still does it, its effect checked
//  where the channel allows: a menu item's mark, a window that appeared, the script's answer).
//

import Foundation
import UniformTypeIdentifiers

extension ArisAppsHands {
    struct Discovery {
        var info: ArisApps.BundleInfo?
        var commands: [ArisApps.Command]
        var dictionary: ArisApps.Sdef.Dictionary?
        var menuRead: Bool
        var grant: ArisApps.Grant
    }

    /// Every command the app offers now: the cached ones of its version (scripting dictionary, App Intents, links,
    /// documents, Services) and its live menu bar when it is running.
    func discover(_ target: Target) -> Discovery {
        let info = target.path.flatMap { system.bundleInfo(path: $0) }
        let versionKey = info?.versionKey ?? target.bundle
        note { $0.seeing(target.bundle, versionKey: versionKey) }
        var dictionary = lock.withLock { dictionaries[versionKey] }
        if dictionary == nil, let path = target.path, info?.scriptable ?? true, let data = system.scriptingDictionary(path: path) {
            dictionary = ArisApps.Sdef.parse(data)?.resolved { [system] path in system.includedDictionary(path: path) }
            if let dictionary { lock.withLock { dictionaries[versionKey] = dictionary } }
        }
        var fixed = store.cachedCommands(versionKey)
        if fixed == nil {
            let intents = target.path.flatMap { system.intentsMetadata(path: $0) }.map(ArisApps.Intents.parse) ?? []
            let shortcuts = system.shortcuts()
            fixed = ArisApps.Commands.merge([
                dictionary.map { ArisApps.Commands.fromSdef($0, bundle: target.bundle) } ?? [],
                ArisApps.Commands.fromIntents(intents, shortcuts: shortcuts),
                ArisApps.Commands.fromShortcuts(shortcuts, app: target.name),
                info.map(ArisApps.Commands.fromBundle) ?? [],
            ])
            store.cacheCommands(fixed!, for: versionKey)
        }
        var menu: [ArisApps.Command] = []
        if let running = target.running, let bar = ax.menuBar(pid: running.pid) { menu = ArisApps.Commands.fromMenu(bar) }
        let grant = target.running == nil ? record(target.bundle).automation : system.automation(bundle: target.bundle)
        if dictionary != nil { note { $0.noting(target.bundle, grant: grant) } }
        return Discovery(info: info, commands: ArisApps.Commands.merge([menu, fixed ?? []]), dictionary: dictionary, menuRead: target.running != nil,
                         grant: record(target.bundle).automation)
    }

    func commands(_ arguments: ArisApps.JSON) -> ArisApps.Outcome {
        let target: Target
        switch resolve(arguments["app"]?.string, effect: .observe) {
        case .app(let found): target = found
        case .answer(let outcome): return outcome
        }
        let found = discover(target)
        let limit = max(1, min(100, arguments["limit"]?.int ?? 25))
        let hits = ArisApps.Commands.search(arguments["query"]?.string, in: found.commands, limit: limit)
        var counts: [String: ArisApps.JSON] = [:]
        for channel in ArisApps.Channel.allCases {
            let count = found.commands.filter { $0.channel == channel }.count
            if count > 0 { counts[channel.rawValue] = .number(Double(count)) }
        }
        var notes: [String] = []
        if !found.menuRead { notes.append("\(target.name) isn't running, so its menu commands aren't listed; app.do opens it in the background when needed") }
        if found.dictionary != nil {
            switch found.grant {
            case .granted: notes.append("its scripting commands run in the background")
            case .denied: notes.append("Automation for \(target.name) is off, so its scripting commands are skipped")
            case .notAsked, .unknown: notes.append("its scripting commands would need macOS's permission once; menu commands need none")
            }
        }
        return ArisApps.Outcome(ok: true, did: "\(target.name): \(found.commands.count) commands, \(hits.count) shown", now: notes.joined(separator: "; "),
                                data: .object(["commands": .array(hits.map(\.command.json)), "channels": .object(counts),
                                               "automation": .string(found.grant.rawValue), "version": .string(found.info?.versionKey ?? "")]),
                                effect: .observe, channel: "discovery", verified: true)
    }

    // MARK: - app.do

    /// The command a call names: an id, a menu path, or the best match of a description; or the question to ask.
    func pick(_ said: String, in commands: [ArisApps.Command]) -> (ArisApps.Command?, ArisApps.Outcome?) {
        if let exact = commands.first(where: { $0.id == said }) { return (exact, nil) }
        if said.contains("›") || said.contains(">") {
            let path = ArisApps.MenuBar.path(said)
            if let item = commands.first(where: { command in
                guard let steps = command.path, steps.count == path.count else { return false }
                return zip(steps, path).allSatisfy { ArisApps.MenuBar.titleKey($0) == ArisApps.MenuBar.titleKey($1) }
            }) { return (item, nil) }
        }
        let hits = ArisApps.Commands.search(said, in: commands, limit: 5, minimum: 0.55)
        guard let best = hits.first else { return (nil, nil) }
        // Two different commands equally good: ask which (the same title on two channels is one command).
        if hits.count > 1, best.score - hits[1].score < 0.04, ArisApps.Text.key(hits[1].command.title) != ArisApps.Text.key(best.command.title),
           hits[1].command.effect != best.command.effect || best.command.channel == hits[1].command.channel {
            var outcome = ArisApps.Outcome.failure("‘\(said)’ matches more than one command", effect: best.command.effect,
                                                   data: .object(["commands": .array(hits.prefix(3).map(\.command.json))]))
            outcome.question = "‘\(said)’: " + hits.prefix(3).map { $0.command.path?.joined(separator: " › ") ?? $0.command.title }.joined(separator: ", ") + " 중 어느 것인가요?"
            return (nil, outcome)
        }
        return (best.command, nil)
    }

    /// The same command on other channels: what a step falls back to.
    func alternatives(for command: ArisApps.Command, said: String, in commands: [ArisApps.Command]) -> [ArisApps.Command] {
        let wanted = Set([command.title, said])
        return commands.filter { other in
            other.id != command.id && other.channel != command.channel && other.effect == command.effect
                && wanted.contains { ArisApps.Commands.score($0, other) >= 0.8 }
        }
    }

    func perform(_ arguments: ArisApps.JSON, context: Context) -> ArisApps.Outcome {
        guard let said = arguments["command"]?.string, !said.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure("app.do needs the command", effect: .changeReversible)
        }
        var target: Target
        switch resolve(arguments["app"]?.string, effect: .changeReversible) {
        case .app(let found): target = found
        case .answer(let outcome): return outcome
        }
        // Not running: opened in the background so its menus and scripting answer.
        if target.running == nil {
            _ = system.open(ArisAppsOpenRequest(bundle: target.bundle, path: nil, url: nil, front: false))
            _ = waitFor { self.running(target.bundle) != nil }
            target.running = running(target.bundle)
        }
        // Exactness is only ever the mark on the command that was rated, never an argument beside it.
        if let refused = ArisApps.Exact.refusedArguments.first(where: { arguments[$0] != nil }) {
            return .failure("app.do takes no ‘\(refused)’: nothing was pressed", effect: .changeReversible)
        }
        let found = discover(target)
        // A taught menu step ("=Format › Wrap to Page"): its item by its exact titles (and key), never a near match
        // (fourth VM run, D5).
        let named = ArisApps.Exact.parse(said)
        if named.exact {
            switch ArisApps.Exact.menu(named.text, key: named.key, in: found.commands, app: target.name) {
            case .found(let command): return pressMenu(command, target: target)
            case .missing(let why): return .failure(why, effect: .changeReversible)
            }
        }
        let (picked, question) = pick(said, in: found.commands)
        if let question { return question }
        guard let command = picked else {
            let near = ArisApps.Commands.search(said, in: found.commands, limit: 5, minimum: 0.3)
            return .failure("\(target.name) has no command like ‘\(said)’; app.read shows its window to act on with app.click/app.type",
                            effect: .changeReversible, data: .object(["near": .array(near.map(\.command.json))]))
        }
        let plan = ArisApps.Choice.plan(target: command, alternatives: alternatives(for: command, said: said, in: found.commands),
                                        record: record(target.bundle), background: context.background)
        if let blocked = plan.blocked { return .failure("couldn't run “\(command.title)” in \(target.name): \(blocked)", effect: command.effect) }
        var tried: [String] = []
        for index in plan.steps.indices {
            switch ArisApps.Choice.next(plan, at: index, record: record(target.bundle), appName: target.name, goAhead: arguments["permission_ok"]?.bool == true) {
            case .done: break
            case .sayFirst(let notice, let english, let step):
                note { $0.notingNoticeSaid(target.bundle) }
                var outcome = ArisApps.Outcome.failure("waiting: “\(step.command.title)” in \(target.name) needs macOS's permission once (\(tried.isEmpty ? "only its scripting dictionary can do it" : "the other ways failed: " + tried.joined(separator: "; ")))",
                                                       effect: command.effect, data: .object(["needs": .string("automation"), "notice_en": .string(english),
                                                                                             "then": .string("say the notice, then call app.do again with permission_ok true")]))
                outcome.notice = notice
                return outcome
            case .run(let step):
                var outcome = execute(step.command, target: target, arguments: arguments["arguments"] ?? .object([:]), context: context, dictionary: found.dictionary)
                outcome.effect = ArisApps.Risk.command(step.command, bundle: target.bundle, arguments: arguments["arguments"] ?? .object([:]), kind: system.pathKind).effect
                if outcome.ok {
                    note { $0.noting(target.bundle, channel: step.command.channel, worked: true) }
                    if step.prompts { note { $0.noting(target.bundle, grant: .granted) } }
                    return outcome
                }
                tried.append("\(step.command.channel.rawValue): \(outcome.did)")
                if step.command.channel == .sdef, let code = outcome.data["code"]?.int, [-1743, -10004].contains(code) {
                    note { $0.noting(target.bundle, grant: .denied) }
                }
                // Wrong arguments say nothing about the channel: it stays usable for this app.
                if outcome.data["arguments"]?.bool != true { note { $0.noting(target.bundle, channel: step.command.channel, worked: false, why: outcome.did) } }
            }
        }
        return .failure("couldn't run “\(command.title)” in \(target.name): " + tried.joined(separator: "; "), effect: command.effect)
    }

    // MARK: - One channel

    func execute(_ command: ArisApps.Command, target: Target, arguments: ArisApps.JSON, context: Context, dictionary: ArisApps.Sdef.Dictionary?) -> ArisApps.Outcome {
        switch command.channel {
        case .menu: return pressMenu(command, target: target)
        case .service:
            var service = command
            service.path = [target.name, "Services", command.title]
            return pressMenu(service, target: target)
        case .sdef: return script(command, target: target, arguments: arguments, dictionary: dictionary)
        case .shortcut:
            let result = system.runShortcut(command.title, input: arguments["input"]?.string)
            return result.ok ? ArisApps.Outcome(ok: true, did: "ran the Shortcut “\(command.title)”", now: String(result.output.prefix(2_000)), effect: command.effect,
                                                channel: "shortcut", verified: true)
                : .failure("the Shortcut “\(command.title)” failed: \(result.output.prefix(300))", effect: command.effect)
        case .url, .document:
            let url = arguments["url"]?.string, path = arguments["path"]?.string
            if command.channel == .url {
                guard let url, path == nil else { return .failure("“\(command.title)” takes a url only", effect: command.effect, data: Self.badArguments) }
                guard url.lowercased().hasPrefix(command.id.dropFirst(4) + ":") else {
                    return .failure("that link isn't a \(command.id.dropFirst(4)): link", effect: command.effect, data: Self.badArguments)
                }
            } else {
                // A document channel opens a document of its own type, never a link and never something that runs.
                guard url == nil, let path else { return .failure("“\(command.title)” takes a file path only", effect: command.effect, data: Self.badArguments) }
                guard Self.matches(path, command) else {
                    return .failure("\((path as NSString).lastPathComponent) isn't a \(command.title.dropFirst(5)) file", effect: command.effect, data: Self.badArguments)
                }
            }
            let result = system.open(ArisAppsOpenRequest(bundle: target.bundle, path: path, url: url, front: false))
            return result.ok ? ArisApps.Outcome(ok: true, did: "opened \(url ?? path ?? "") in \(target.name)", now: "", effect: command.effect, channel: command.channel.rawValue)
                : .failure(result.message, effect: command.effect)
        case .intent, .engine:
            return .failure("“\(command.title)” has no channel that runs it from outside", effect: command.effect)
        }
    }

    /// A failure that was the call's arguments, not the channel.
    static let badArguments = ArisApps.JSON.object(["arguments": .bool(true)])

    /// Whether a file is of the document type a command was built from: its extension, else its type identifier
    /// conforming to one of the command's.
    static func matches(_ path: String, _ command: ArisApps.Command) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        // "*" (any file) is no type at all: a file must be of a type the app names.
        if command.documentExtensions?.contains(ext) == true { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return (command.documentTypes ?? []).contains { identifier in UTType(identifier).map { type.conforms(to: $0) } ?? false }
    }

    func pressMenu(_ command: ArisApps.Command, target: Target) -> ArisApps.Outcome {
        guard let running = target.running ?? self.running(target.bundle), let path = command.path else {
            return .failure("\(target.name) isn't running", effect: command.effect)
        }
        let before = windows(of: target.bundle)
        let pressed = pressMenuItem(pid: running.pid, path: path, app: target.name)
        guard pressed.ok else { return .failure(pressed.message, effect: command.effect) }
        let shown = path.joined(separator: " › ")
        // What is true now: the item's mark flipped, or a window came or went.
        var now = "", verified = false
        if let after = ax.menuBar(pid: running.pid)?.item(at: path), after.checked != (command.checked ?? false) {
            now = "“\(command.title)” is now \(after.checked ? "on" : "off")"
            verified = true
        }
        // A list that couldn't be read says nothing about the windows (sixth VM run, item 4: "now has 0 windows").
        let after = settledWindows(of: target.bundle, before: before, marked: verified) ?? before
        if let new = after.first(where: { window in !before.contains { $0.id == window.id } }) {
            now = [now, "a new window “\(new.title)” opened"].filter { !$0.isEmpty }.joined(separator: "; ")
            verified = true
        } else if after.count < before.count {
            now = [now, "\(target.name) now has \(after.count) window\(after.count == 1 ? "" : "s")"].filter { !$0.isEmpty }.joined(separator: "; ")
            verified = true
        }
        return ArisApps.Outcome(ok: true, did: "pressed \(shown) in \(target.name)", now: now, effect: command.effect, channel: "menu", verified: verified)
    }

    func script(_ command: ArisApps.Command, target: Target, arguments: ArisApps.JSON, dictionary: ArisApps.Sdef.Dictionary?) -> ArisApps.Outcome {
        guard let dictionary else { return .failure("\(target.name) has no scripting dictionary", effect: command.effect) }
        let given = arguments.object ?? [:]
        let source: String
        do {
            let parts = command.id.split(separator: ":").map(String.init)
            if parts.count == 3, parts[1] == "make", let klass = dictionary.topElements.first(where: { ArisApps.Text.key($0) == parts[2] }) {
                source = try ArisApps.Script.make(klass, bundle: target.bundle, dictionary: dictionary, properties: given)
            } else if parts.count == 3, parts[1] == "list", let klass = dictionary.topElements.first(where: { ArisApps.Text.key($0) == parts[2] }) {
                source = try ArisApps.Script.list(klass, bundle: target.bundle, dictionary: dictionary)
            } else {
                var parameters = given
                let direct = parameters.removeValue(forKey: "direct")
                source = try ArisApps.Script.command(command.title, bundle: target.bundle, dictionary: dictionary, direct: direct, parameters: parameters)
            }
        } catch {
            return .failure("“\(command.title)” can't be written with those arguments (\(error))", effect: command.effect, data: Self.badArguments)
        }
        let result = system.runScript(source, timeout: 10)
        guard result.ok else {
            return .failure("\(target.name) refused “\(command.title)”: \(result.output.prefix(300))", effect: command.effect,
                            data: result.code.map { .object(["code": .number(Double($0))]) } ?? .null)
        }
        return ArisApps.Outcome(ok: true, did: "ran “\(command.title)” in \(target.name) by its scripting dictionary", now: String(result.output.prefix(4_000)),
                                data: .object(["result": .string(String(result.output.prefix(4_000)))]), effect: command.effect, channel: "sdef", verified: true)
    }
}
