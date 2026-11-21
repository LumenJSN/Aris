//
//  ArisAppsCommands.swift
//  Shared/Core/Apps
//
//  app.commands: what an app can do right now, discovered from every channel it offers and merged into one list with
//  a stable id per command: its scripting dictionary (commands, and "make new <thing>" / "list <things>" for each
//  thing the application holds), its App Intents, its menu bar (every item, with enabled state, checkmark and keys),
//  its URL schemes, document types and Services. A request in Korean or English is matched by its meaning-bearing
//  words (ArisAppsLexicon), so "새 창" finds "New Window" and "새로운 윈도우". Each command carries the effect class
//  of running it. Pure.
//

import Foundation

extension ArisApps {
    enum Channel: String, Codable, Sendable, CaseIterable {
        /// The scripting dictionary (Apple Events): background, answers with a result; needs the app's Automation grant.
        case sdef
        /// A Shortcut of the owner's (`shortcuts run`), which is how an App Intent is run from outside.
        case shortcut
        /// An App Intent the app declares; listed for what it says the app can do (run through a Shortcut).
        case intent
        /// A menu-bar item pressed through Accessibility: every app, in the background, no new permission.
        case menu
        /// A URL scheme the app handles (opened by LaunchServices).
        case url
        /// A document type the app opens.
        case document
        /// A Service the app offers on the selection.
        case service
        /// The computer-use engine: the app's Accessibility tree, then vision and synthetic input.
        case engine
    }

    struct Command: Codable, Equatable, Sendable {
        var id: String
        var title: String
        var detail: String = ""
        var channel: Channel
        var path: [String]? = nil
        var enabled: Bool? = nil
        var checked: Bool? = nil
        var keys: String? = nil
        var parameters: [String] = []
        var effect: Effect
        /// False for an App Intent no Shortcut of the owner's runs: shown for what it says, done by another channel.
        var runnable = true
        /// It runs code in the app's interpreter (Terminal's do script, a browser's JavaScript, Shortcuts' run…).
        var runsCode = false
        /// The argument that carries the code ("direct" for the direct parameter).
        var codeParameter: String? = nil
        var interpreter: String? = nil
        /// For a document type: the extensions and type identifiers a path must have to be opened as it.
        var documentExtensions: [String]? = nil
        var documentTypes: [String]? = nil

        var json: JSON {
            var object: [String: JSON] = ["id": .string(id), "title": .string(title), "channel": .string(channel.rawValue), "effect": .string(effect.rawValue)]
            if !detail.isEmpty { object["detail"] = .string(detail) }
            if let path { object["path"] = .string(path.joined(separator: " › ")) }
            if let enabled, !enabled { object["enabled"] = .bool(false) }
            if let checked, checked { object["checked"] = .bool(true) }
            if let keys { object["keys"] = .string(keys) }
            if !parameters.isEmpty { object["parameters"] = .array(parameters.map(JSON.string)) }
            if !runnable { object["runnable"] = .bool(false) }
            if runsCode { object["runs_code"] = .bool(true) }
            return .object(object)
        }
    }

    enum Commands {
        // MARK: - Effect of a command

        /// The effect of running a command named by these words, on this channel.
        static func effect(_ text: String, channel: Channel) -> Effect {
            let concepts = Set(Lexicon.units(text).flatMap(Lexicon.meanings))
            let ordered = Lexicon.words(text), words = Set(ordered)
            if concepts.contains("send") || concepts.contains("call") { return .outward }
            if concepts.contains("run") { return .changePermanent }
            if concepts.contains("empty") && concepts.contains("trash") { return .changePermanent }
            if concepts.contains("delete") {
                let forGood = !words.isDisjoint(with: ["permanently", "immediately", "영구", "영구히", "즉시", "완전히"])
                return channel == .menu && !forGood ? .changeReversible : .changePermanent
            }
            if channel == .sdef, let first = ordered.first, ["get", "count", "exists", "list"].contains(first) { return .observe }
            if channel == .intent || channel == .shortcut, let first = ordered.first, ["get", "find", "search", "show", "list"].contains(first) { return .observe }
            return .changeReversible
        }

        // MARK: - Builders, one per channel

        static func key(_ steps: [String]) -> String { steps.map(Text.key).joined(separator: ">") }

        static func fromMenu(_ bar: MenuBar) -> [Command] {
            bar.leaves.map { entry in
                let title = entry.item.title
                return Command(id: "menu:" + key(entry.path), title: title, detail: entry.path.dropLast().joined(separator: " › "), channel: .menu,
                               path: entry.path, enabled: entry.item.enabled, checked: entry.item.checked, keys: entry.item.shortcut,
                               effect: effect(entry.path.joined(separator: " "), channel: .menu))
            }
        }

        /// `bundle`: the app, for the table of apps whose scripting commands run code (ArisAppsRisk).
        static func fromSdef(_ dictionary: Sdef.Dictionary, bundle: String? = nil) -> [Command] {
            var out: [Command] = []
            let skipped: Set<String> = ["run", "reopen", "launch", "activate", "open location", "set", "get", "copy", "exists", "count"]
            for command in dictionary.commands where !skipped.contains(command.name) {
                let parameters = command.parameters.map { $0.optional ? "[\($0.name)]" : $0.name }
                var entry = Command(id: "sdef:" + Text.key(command.name), title: command.name, detail: command.description, channel: .sdef,
                                    parameters: (command.direct.map { ["(\($0.type.isEmpty ? "object" : $0.type))"] } ?? []) + parameters,
                                    effect: effect(command.name + " " + command.description, channel: .sdef))
                let code = Risk.runsCode(command, bundle: bundle)
                if code.runs {
                    entry.runsCode = true
                    entry.codeParameter = code.parameter
                    entry.interpreter = code.interpreter
                    entry.effect = max(entry.effect, .changePermanent)
                }
                out.append(entry)
            }
            let canMake = dictionary.commands.contains { $0.name == "make" }
            for element in dictionary.topElements {
                let klass = dictionary.classNamed(element)
                let properties = (klass?.properties ?? []).filter(\.writable).map(\.name)
                if canMake, !["window", "document"].contains(element) || dictionary.topElements.count <= 2 {
                    var make = Command(id: "sdef:make:" + Text.key(element), title: "make new \(element)", detail: klass?.description ?? "",
                                       channel: .sdef, parameters: properties, effect: .changeReversible)
                    // In an app that is an interpreter (Terminal, Script Editor, Automator), what is made can run.
                    if let bundle, let known = Risk.interpreters[bundle.lowercased()], known.commands == nil {
                        make.runsCode = true
                        make.interpreter = known.interpreter
                        make.effect = .changePermanent
                    }
                    out.append(make)
                }
                out.append(Command(id: "sdef:list:" + Text.key(element), title: "list \(klass?.plural ?? element + "s")", detail: klass?.description ?? "",
                                   channel: .sdef, parameters: (klass?.properties ?? []).prefix(8).map(\.name), effect: .observe))
            }
            return out
        }

        /// App Intents; one an owner's Shortcut is named after runs through that Shortcut.
        static func fromIntents(_ actions: [Intents.Action], shortcuts: [String] = []) -> [Command] {
            actions.map { action in
                guard let shortcut = shortcuts.first(where: { Text.key($0) == Text.key(action.title) }) else {
                    return Command(id: "intent:" + action.id, title: action.title, detail: action.description, channel: .intent,
                                   parameters: action.parameters, effect: effect(action.title, channel: .intent), runnable: false)
                }
                var command = Command(id: "intent:" + action.id, title: shortcut, detail: action.description, channel: .shortcut,
                                      parameters: action.parameters, effect: effect(action.title, channel: .intent))
                return runsShortcut(command: &command)
            }
        }

        static func fromShortcuts(_ names: [String], app: String) -> [Command] {
            let wanted = Text.key(app)
            return names.filter { !wanted.isEmpty && Text.key($0).contains(wanted) }.map { name in
                var command = Command(id: "shortcut:" + Text.key(name), title: name, detail: "Shortcut", channel: .shortcut, effect: effect(name, channel: .shortcut))
                return runsShortcut(command: &command)
            }
        }

        /// A Shortcut can run shell scripts, send messages and delete files, whatever its title says: running one is
        /// running code, at least permanent, with the Shortcut's name as what runs (whether to ask is the policy's).
        static func runsShortcut(command: inout Command) -> Command {
            command.runsCode = true
            command.interpreter = "shortcut"
            command.effect = max(command.effect, .changePermanent)
            return command
        }

        static func fromBundle(_ info: BundleInfo) -> [Command] {
            var out: [Command] = []
            for scheme in info.schemes where !["http", "https", "file"].contains(scheme) {
                out.append(Command(id: "url:" + scheme, title: "open \(scheme): link", detail: "URL scheme", channel: .url, parameters: ["url"], effect: .changeReversible))
            }
            for document in info.documents where !document.name.isEmpty && document.role != "None" {
                var command = Command(id: "open:" + Text.key(document.name), title: "open \(document.name)",
                                      detail: (document.extensions + document.types).prefix(6).joined(separator: ", "), channel: .document,
                                      parameters: ["path"], effect: .changeReversible)
                command.documentExtensions = document.extensions.map { $0.lowercased() }
                command.documentTypes = document.types
                out.append(command)
            }
            for service in info.services {
                out.append(Command(id: "service:" + Text.key(service.title), title: service.title, detail: "Service on the selection",
                                   channel: .service, parameters: service.sendTypes, effect: effect(service.title, channel: .service)))
            }
            return out
        }

        /// Every channel's commands, ids unique (a later duplicate dropped).
        static func merge(_ lists: [[Command]]) -> [Command] {
            var seen = Set<String>(), out: [Command] = []
            for command in lists.flatMap({ $0 }) where !seen.contains(command.id) {
                seen.insert(command.id)
                out.append(command)
            }
            return out
        }

        // MARK: - Search

        struct Hit: Equatable, Sendable {
            var command: Command
            var score: Double
        }

        /// How well a request matches one command's words, 0…1.2.
        static func score(_ query: String, _ command: Command) -> Double {
            let asked = Lexicon.units(query)
            guard !asked.isEmpty else { return 0 }
            let title = Lexicon.terms(command.title)
            let context = Lexicon.terms(([command.detail] + (command.path?.dropLast() ?? []) + command.parameters).joined(separator: " "))
            let titleMeanings = Set(title.flatMap(Lexicon.meanings)), contextMeanings = Set(context.flatMap(Lexicon.meanings))
            func meet(_ word: String, _ terms: [String], _ meanings: Set<String>) -> Double {
                if terms.contains(word) { return 1 }
                let mine = Lexicon.meanings(word)
                if !mine.isEmpty, !mine.isDisjoint(with: meanings) { return 0.85 }
                if word.count >= 2, terms.contains(where: { $0.count >= 2 && ($0.hasPrefix(word) || word.hasPrefix($0)) }) { return 0.6 }
                if word.count >= 3, terms.contains(where: { Text.similarity(word, $0) >= 0.8 }) { return 0.5 }
                return 0
            }
            var total = 0.0
            for word in asked { total += max(meet(word, title, titleMeanings), 0.6 * meet(word, context, contextMeanings)) }
            var score = total / Double(asked.count)
            // Every word of the title asked for: a full match beats a partial one.
            let titleWords = Lexicon.words(command.title)
            if !titleWords.isEmpty {
                let covered = titleWords.filter { word in asked.contains(word) || !Lexicon.meanings(word).isDisjoint(with: Set(asked.flatMap(Lexicon.meanings))) }
                score += 0.1 * Double(covered.count) / Double(titleWords.count)
            }
            if Text.key(query) == Text.key(command.title) { score += 0.2 }
            if command.enabled == false { score *= 0.8 }
            if !command.runnable { score *= 0.7 }
            return score
        }

        /// Channels' order when two commands score the same: the one that runs in the background with a result first.
        static let channelOrder: [Channel] = [.sdef, .shortcut, .menu, .url, .document, .service, .intent, .engine]

        /// The commands matching a request, best first (all of them, in menu order, for an empty request).
        static func search(_ query: String?, in commands: [Command], limit: Int = 40, minimum: Double = 0.45) -> [Hit] {
            guard let query, !Lexicon.words(query).isEmpty else { return commands.prefix(limit).map { Hit(command: $0, score: 0) } }
            let order = Dictionary(uniqueKeysWithValues: channelOrder.enumerated().map { ($1, $0) })
            return commands.map { Hit(command: $0, score: score(query, $0)) }.filter { $0.score >= minimum }
                .sorted { abs($0.score - $1.score) > 0.001 ? $0.score > $1.score : (order[$0.command.channel] ?? 9) < (order[$1.command.channel] ?? 9) }
                .prefix(limit).map { $0 }
        }
    }
}
