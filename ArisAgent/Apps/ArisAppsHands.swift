//
//  ArisAppsHands.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  The app layer's capabilities, run: one object holding the system seams and what it has learned (the owner's
//  aliases, each app's channels, the command cache, each app's last read), with one entry point `call(name, args)`
//  that the registry's faces call. The specs (names, descriptions, schemas, effect classes) are pure and live in
//  Shared/Core/Apps/ArisAppsSpecs.swift; this file and its extensions are the code behind them. Nothing here takes the
//  owner's focus unless the call asks to bring something forward, and a background task never does.
//

import Foundation

/// A weak hold on the hands for the effect context's closures.
final class ArisAppsWeak: @unchecked Sendable {
    weak var hands: ArisAppsHands?
    init(_ hands: ArisAppsHands) { self.hands = hands }
}

/// One step of a recipe, put to the trust policy as a call of its own.
struct ArisAppsGateRequest {
    let call: String
    let arguments: ArisApps.JSON
    let assessment: ArisApps.Assessment
    /// The recipe it belongs to, and what the recipe as a whole was assessed as (what the owner was asked about once).
    let recipe: String
    let approved: ArisApps.Assessment
    let background: Bool
}

protocol ArisAppsGate: AnyObject {
    /// nil: run it; else why not (said to the owner, or put on the recipe's one card).
    func refusal(_ request: ArisAppsGateRequest) -> String?
}

final class ArisAppsHands {
    /// One call's circumstances.
    struct Context {
        /// A background task: nothing is brought forward and no permission prompt is ever caused.
        var background = false
    }

    let system: ArisAppsSystem
    let ax: ArisAppsAccessibility
    let engine: ArisAppsEngine
    let store: ArisAppsStore

    let lock = NSLock()
    var aliases: ArisApps.Aliases
    var book: ArisApps.ChannelBook
    /// Each app's last read (by bundle): its engine snapshot, window and elements, for ids in later calls.
    var reads: [String: LastRead] = [:]
    /// The trust decision for each step inside a recipe (jv-trust's policy, handed in by the registry). Without one,
    /// a step runs only when its assessment is within what the recipe as a whole was assessed (and so approved) as.
    var gate: ArisAppsGate?
    /// Capabilities outside the app layer a recipe names ("event", "files.find"): the registry hands them in.
    var external: ((String, ArisApps.JSON) -> ArisApps.Outcome?)?
    /// Each app version's scripting dictionary, parsed once (by BundleInfo.versionKey).
    var dictionaries: [String: ArisApps.Sdef.Dictionary] = [:]
    /// How long a call waits to see its effect (an app quitting, a window appearing).
    var pollSeconds: TimeInterval = 2
    /// How long a menu press waits for a window it opens to show up and take the focus (fifth VM run, D5: File › New's
    /// window came a moment after the press, so the next step typed into it while reading the old window, and its undo
    /// was never made). Each look ends the wait as soon as the window list changed.
    var settleSeconds: TimeInterval = 0.8
    /// How long app.type keeps looking at the field it typed into until it shows the text (sixth VM run, item 1: a new
    /// document's first change came back unread right after it). Each look ends the wait once it does.
    var readBackSeconds: TimeInterval = 1.5
    /// Keeps the text a replace erases (the undo store's verified copy) and gives its id; nil: it can't be kept, and the
    /// replace has no undo. Unset (the tests): nothing is kept.
    var keepText: ((String) -> String?)?
    /// Calls and replays under way (ArisAppsHands+MenuPress): the owner's app goes back in front when the last ends.
    var frontHolds = 0
    /// The owner's app to put back, and the app brought forward instead, while a hold is open.
    var frontReturn: FrontReturn?
    /// The installed list, read once a minute at most.
    var installedCache: (at: Date, apps: [ArisApps.AppRecord])?

    struct LastRead {
        var snapshot: String
        var window: Int
        var elements: [ArisApps.ReadElement]
    }

    init(system: ArisAppsSystem, ax: ArisAppsAccessibility, engine: ArisAppsEngine, store: ArisAppsStore) {
        self.system = system
        self.ax = ax
        self.engine = engine
        self.store = store
        aliases = store.loadAliases()
        book = store.loadBook()
    }

    // MARK: - The entry point

    func call(_ name: String, _ arguments: ArisApps.JSON, context: Context = Context()) -> ArisApps.Outcome {
        // An app brought forward for this call goes back when it ends, or when the replay it is part of ends (sixth VM
        // run, item 4: ArisAppsHands+MenuPress).
        beginFrontHold()
        defer { endFrontHold() }
        return dispatch(name, arguments, context: context)
    }

    private func dispatch(_ name: String, _ arguments: ArisApps.JSON, context: Context) -> ArisApps.Outcome {
        guard let spec = ArisApps.Spec.named(name) else { return .failure("no capability \(name)", effect: .observe) }
        let effect = assess(spec, arguments).effect
        switch spec.name {
        case "app.find": return find(arguments)
        case "app.alias": return alias(arguments)
        case "app.open": return open(arguments, context: context)
        case "app.quit", "app.hide", "app.focus": return appAction(spec.name, arguments, context: context)
        case "app.running": return running()
        case "app.frontmost": return frontmost()
        case "window.list": return windowList(arguments)
        case "window.move", "window.resize", "window.minimize", "window.close", "window.space": return windowAction(spec.name, arguments, context: context)
        case "window.tile": return tile(arguments, context: context)
        case "app.commands": return commands(arguments)
        case "app.do": return perform(arguments, context: context)
        case "app.read": return read(arguments, context: context)
        case "app.type": return type(arguments, context: context, effect: effect)
        case "app.click": return click(arguments, context: context, effect: effect)
        case "app.press": return press(arguments, context: context, effect: effect)
        case "app.select": return select(arguments, context: context, effect: effect)
        case "app.scroll": return scroll(arguments, context: context)
        case "app.recipe": return recipe(arguments, context: context)
        default: return .failure("\(name) has no code", effect: effect)
        }
    }

    /// The effect class of one call before it runs (for the trust policy).
    func effect(_ name: String, _ arguments: ArisApps.JSON) -> ArisApps.Effect { assess(name, arguments).effect }

    /// The whole assessment of one call before it runs: its effect, and the code it would run (for the never-list).
    func assess(_ name: String, _ arguments: ArisApps.JSON) -> ArisApps.Assessment {
        guard let spec = ArisApps.Spec.named(name) else { return .plain(.changePermanent, "not an app capability") }
        return assess(spec, arguments)
    }

    private func assess(_ spec: ArisApps.Spec, _ arguments: ArisApps.JSON) -> ArisApps.Assessment {
        spec.assess(arguments, effectContext)
    }

    var effectContext: ArisApps.EffectContext {
        let box = ArisAppsWeak(self)
        return ArisApps.EffectContext(
            surface: { said, target in box.hands?.surface(app: said, target: target) ?? .unknown },
            label: { said, target in box.hands?.label(app: said, target: target) },
            command: { said, command, arguments in box.hands?.commandAssessment(app: said, command: command, arguments: arguments) },
            pathKind: { path in box.hands?.system.pathKind(path) ?? .runnable })
    }

    // MARK: - Saying which app

    enum Resolved {
        case app(Target)
        case answer(ArisApps.Outcome)
    }

    struct Target {
        var bundle: String
        var name: String
        var path: String?
        var running: ArisAppsRunning?
    }

    func installed() -> [ArisApps.AppRecord] {
        if let cached = lock.withLock({ installedCache }), Date().timeIntervalSince(cached.at) < 60 { return cached.apps }
        let apps = system.installedApps()
        lock.withLock { installedCache = (Date(), apps) }
        return apps
    }

    /// Installed and running apps as one candidate list for app.find.
    func candidates() -> [ArisApps.AppRecord] {
        let front = system.frontmost()?.bundle
        let running = system.runningApps().map {
            ArisApps.AppRecord(bundle: $0.bundle, names: [$0.name], running: true, frontmost: $0.bundle == front, installed: true)
        }
        return installed() + running
    }

    func ranked(_ said: String) -> [ArisApps.Find.Match] {
        ArisApps.Find.rank(said, apps: candidates(), aliases: lock.withLock { aliases })
    }

    /// The app a call names, or the answer to give instead (a question, "not installed", nothing by that name).
    func resolve(_ said: String?, effect: ArisApps.Effect) -> Resolved {
        guard let said = said?.trimmingCharacters(in: .whitespaces), !said.isEmpty else {
            if let front = system.frontmost() { return .app(Target(bundle: front.bundle, name: front.name, path: path(of: front.bundle), running: front)) }
            return .answer(.failure("no app named and none in front", effect: effect))
        }
        let ranked = ranked(said)
        switch ArisApps.Find.answer(ranked) {
        case .app(let match):
            let bundle = match.bundle ?? said
            return .app(Target(bundle: bundle, name: match.name, path: match.path ?? path(of: bundle), running: running(bundle)))
        case .ask(let matches):
            var outcome = ArisApps.Outcome.failure("‘\(said)’ could mean more than one app", effect: effect, data: .object(["candidates": .array(matches.map(\.json))]))
            outcome.question = ArisApps.Find.question(said, matches).ko
            return .answer(outcome)
        case .web(let match):
            return .answer(.failure("\(match.name) has no app on this Mac; it opens in the browser (app.open with its url: \(match.web ?? ""))",
                                    effect: effect, data: match.json))
        case .notInstalled(let match):
            return .answer(.failure("\(match.name) isn't installed on this Mac", effect: effect, data: match.json))
        case .none:
            return .answer(.failure("no app on this Mac is called ‘\(said)’", effect: effect))
        }
    }

    func running(_ bundle: String) -> ArisAppsRunning? {
        system.runningApps().first { $0.bundle.caseInsensitiveCompare(bundle) == .orderedSame }
    }

    func path(of bundle: String) -> String? {
        installed().first { $0.bundle.caseInsensitiveCompare(bundle) == .orderedSame }?.path
    }

    // MARK: - What the effect context asks

    /// Where keys land in an app: its kind (terminal, chat, mail), else the role of the named element (from its last
    /// read) or of the focused one; unknown when neither can be read.
    func surface(app said: String, target: String?) -> ArisApps.Surface {
        guard let match = ranked(said).first, let bundle = match.bundle else { return .unknown }
        var role: String?
        if let target, !target.isEmpty, let last = lock.withLock({ reads[bundle.lowercased()] }),
           case .one(let element) = ArisApps.Read.locate(target, in: last.elements) {
            role = element.role
        } else if let pid = running(bundle)?.pid {
            role = ax.focusedRole(pid: pid)
        }
        return ArisApps.Risk.surface(bundle: bundle, focusedRole: role)
    }

    /// The role of the element a call names (from the app's last read), or of the focused one; nil when unknown.
    func role(app said: String, target: String?) -> String? {
        guard let match = ranked(said).first, let bundle = match.bundle else { return nil }
        if let target, !target.isEmpty, let last = lock.withLock({ reads[bundle.lowercased()] }),
           case .one(let element) = ArisApps.Read.locate(target, in: last.elements) {
            return element.role
        }
        return running(bundle).flatMap { ax.focusedRole(pid: $0.pid) }
    }

    func label(app said: String, target: String) -> String? {
        guard let bundle = ranked(said).first?.bundle, let last = lock.withLock({ reads[bundle.lowercased()] }) else { return nil }
        if case .one(let element) = ArisApps.Read.locate(target, in: last.elements) { return element.label.isEmpty ? element.value : element.label }
        return nil
    }

    /// The command a call names, found as app.do finds it, assessed with its arguments; nil when it isn't found.
    func commandAssessment(app said: String, command: String, arguments: ArisApps.JSON) -> ArisApps.Assessment? {
        guard case .app(let target) = resolve(said, effect: .observe) else { return nil }
        let commands = discover(target).commands
        guard let found = pick(command, in: commands).0 else { return nil }
        return ArisApps.Risk.command(found, bundle: target.bundle, arguments: arguments, kind: system.pathKind)
    }

    // MARK: - Recording

    func note(_ change: (ArisApps.ChannelBook) -> ArisApps.ChannelBook) {
        let updated = lock.withLock { () -> ArisApps.ChannelBook in
            book = change(book)
            return book
        }
        store.saveBook(updated)
    }

    func record(_ bundle: String) -> ArisApps.AppChannels { lock.withLock { book.record(bundle) } }

    /// The engine's envelope: whether it succeeded, its message, its data.
    static func envelope(_ reply: ArisApps.JSON) -> (ok: Bool, message: String, data: ArisApps.JSON) {
        let ok = reply["success"]?.bool ?? false
        let message = reply["error"]?["message"]?.string ?? reply["outcome"]?["refusal_reason"]?.string ?? (ok ? "done" : "the engine refused")
        return (ok, message, reply["data"] ?? .null)
    }
}
