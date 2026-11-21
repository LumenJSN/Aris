//
//  ArisAppsSpecs.swift
//  Shared/Core/Apps
//
//  The app layer's capabilities as registry entries: each one's name, the short model-facing description that says
//  when to use it (this replaces the prose catalogue), its JSON-Schema-shaped arguments, and the effect class of a
//  call, worked out from that call's arguments (pressing "Send" in a chat app is outward, a scroll only looks). The
//  registry (jv-hands) takes these as they are; `wireName` is the name for providers that allow no dots. Pure: the
//  helper attaches the code that runs each one (ArisAgent/Apps/ArisAppsHands.swift).
//

import Foundation

extension ArisApps {
    /// What a call's effect may depend on besides its arguments (the helper fills it in from what it knows).
    struct EffectContext: Sendable {
        /// Where keys typed into this app (or into the target element, when one is named) land.
        var surface: @Sendable (_ app: String, _ target: String?) -> Surface = { _, _ in .unknown }
        /// The label of an element a call names (from the app's last read), when known.
        var label: @Sendable (_ app: String, _ target: String) -> String? = { _, _ in nil }
        /// The assessment of an app's command by id or description, when it is found.
        var command: @Sendable (_ app: String, _ command: String, _ arguments: JSON) -> Assessment? = { _, _, _ in nil }
        /// What a path is once aliases and links are resolved.
        var pathKind: @Sendable (String) -> PathKind = { _ in .runnable }
    }

    struct Spec: Sendable {
        var name: String
        var summary: String
        var parameters: JSON
        var assess: @Sendable (JSON, EffectContext) -> Assessment

        init(name: String, summary: String, parameters: JSON, assess: @escaping @Sendable (JSON, EffectContext) -> Assessment) {
            self.name = name
            self.summary = summary
            self.parameters = parameters
            self.assess = assess
        }

        /// The effect class of a call.
        func effect(_ arguments: JSON, _ context: EffectContext) -> Effect { assess(arguments, context).effect }

        /// `app.find` → `app_find` (API tool names allow letters, digits, `_` and `-` only).
        var wireName: String { name.replacingOccurrences(of: ".", with: "_") }

        static func named(_ wire: String) -> Spec? { Specs.all.first { $0.name == wire || $0.wireName == wire } }
    }

    /// Where app.type's at=end leaves the caret, as the app's Accessibility answered.
    enum CaretEnd: Equatable, Sendable {
        /// The text element's selected range was set to its end.
        case moved
        /// The element the text would go into isn't a text field, text area or web text input (or none was found).
        case notText
        /// A text element that wouldn't take the range; `focused`: it has the keyboard focus.
        case refused(focused: Bool)
    }

    enum Specs {
        /// The keys app.type's at=end falls back to (only into a focused text element that refused its caret moved).
        static let endKeys = "cmd+down"

        /// app.type's assessment: the text where it lands, and with at=end the end keys it may press too.
        static func typeAssessment(_ arguments: JSON, surface: Surface) -> Assessment {
            let typed = Risk.type(arguments["text"]?.string ?? "", surface: surface)
            // replace sets the field's whole value: what it held is gone and no undo restores an app's text, so it is a
            // destructive step by the desktop effect rules (ArisDesktopEffect: set-value is change-permanent), and asks
            // as such (third VM run, D2: a replay wiped "Existing line keep" as a run-with-undo step).
            if arguments["replace"]?.bool == true {
                var replacing = typed.joined(.plain(.changePermanent, "replaces what the field holds"))
                replacing.why = [typed.why, "replace sets the field's whole value; what it held can't be put back"].filter { !$0.isEmpty }.joined(separator: "; ")
                return replacing
            }
            guard arguments["at"]?.string == "end", arguments["replace"]?.bool != true else { return typed }
            var both = typed.joined(Risk.press(endKeys, surface: surface))
            both.why = [both.why, "at=end may press \(endKeys) first when the field won't take its caret moved"].filter { !$0.isEmpty }.joined(separator: "; ")
            return both
        }

        // MARK: - Schema pieces

        private static func string(_ description: String) -> JSON { .object(["type": .string("string"), "description": .string(description)]) }
        private static func integer(_ description: String) -> JSON { .object(["type": .string("integer"), "description": .string(description)]) }
        private static func boolean(_ description: String) -> JSON { .object(["type": .string("boolean"), "description": .string(description)]) }
        private static func choice(_ values: [String], _ description: String) -> JSON {
            .object(["type": .string("string"), "enum": .array(values.map(JSON.string)), "description": .string(description)])
        }
        private static func object(_ properties: [String: JSON], required: [String] = []) -> JSON {
            .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(JSON.string)),
                     "additionalProperties": .bool(false)])
        }
        private static let app = string("The app as the owner said it (\"카톡\", \"크롬\", \"Notes\") or its bundle id")
        private static let window = integer("A window id from window.list (optional: the app's front window)")
        private static let target = string("An element id from app.read (\"e12\"), or a description of it (\"보내기 버튼\", \"the search field\")")
        private static func fixed(_ effect: Effect) -> @Sendable (JSON, EffectContext) -> Assessment { { _, _ in .plain(effect) } }

        /// Words on a control that make pressing it outward, permanent or running code ("보내기", "Empty Trash", "Run").
        static func effectOfLabel(_ label: String) -> Assessment {
            // A control's label is judged strictly: "Delete" on a button may be for good (a menu's Delete is the trash).
            let effect = Commands.effect(label, channel: .service)
            let runs = Lexicon.units(label).flatMap(Lexicon.meanings).contains("run")
            return Assessment(effect: effect, interpreter: runs ? "unknown" : nil, askAlways: runs, why: label)
        }

        /// A recipe's assessment: its declared effect and every step's, with the inputs filled in (a value only known
        /// when the recipe runs, such as a found file, is assessed again then).
        static func recipe(_ recipe: Recipe, inputs: [String: String], context: EffectContext) -> Assessment {
            var result = Assessment.plain(recipe.effect, recipe.titleEnglish)
            for part in recipe.parts {
                if let when = part.when, (inputs[when] ?? "").isEmpty { continue }
                for way in part.ways {
                    for step in way {
                        if let when = step.when, (inputs[when] ?? "").isEmpty { continue }
                        result = result.joined(.plain(step.effect))
                        guard let spec = Spec.named(step.call), let arguments = Recipes.arguments(step, inputs: inputs, last: nil) else { continue }
                        result = result.joined(spec.assess(.object(arguments), context))
                    }
                }
            }
            return result
        }

        // MARK: - The capabilities

        static let all: [Spec] = [
            Spec(name: "app.find", summary: "Find which app the owner means by a name or nickname (Korean or English, running or installed). Use before acting when the name is unclear; an ambiguous name comes back as one short question to ask.",
                 parameters: object(["query": string("What the owner called the app")], required: ["query"]), assess: fixed(.observe)),
            Spec(name: "app.alias", summary: "Remember that the owner calls an app by this name (after they corrected a wrong guess), so app.find gets it right next time.",
                 parameters: object(["name": string("The name the owner used"), "app": string("The app it means (name or bundle id)"),
                                     "forget": boolean("Forget this name instead")], required: ["name"]), assess: fixed(.changeReversible)),
            Spec(name: "app.open", summary: "Open an app, a folder, a file or a URL (a web page, or an app's own link such as spotify: or mailto:), or show a file in Finder. The direct way: never open a folder or file by pressing keys or typing a path into Finder. A well-known folder goes in place; any other from ~ or /. In the background unless front is true.",
                 parameters: object(["app": app,
                                     "place": .object(["type": .string("string"), "enum": .array(ArisKnownPlaces.ids.map { .string($0) }),
                                                       "description": .string("A known folder, by name: 다운로드 = downloads, 문서 = documents, 바탕화면 = desktop, 홈 = home, 응용 프로그램 = applications, 사진 = pictures, 음악 = music, 동영상 = movies, 휴지통 = trash")]),
                                     "path": string("A file or folder to open: from ~ (~/Downloads/a.pdf) or /. Never a made-up /Users/… path"),
                                     "url": string("A URL to open"),
                                     "reveal": boolean("Show the path or place selected in Finder instead of opening it"),
                                     "front": boolean("Bring it to the front (when the owner asked to open or see it himself)")]),
                 assess: { arguments, context in
                     // A place is a fixed everyday folder; a path is judged as written (its kind follows links and ~).
                     let place = arguments["place"]?.string.flatMap { ArisKnownPlaces.named($0) }
                     return Risk.opening(url: arguments["url"]?.string, path: place == nil ? arguments["path"]?.string : nil, kind: context.pathKind)
                 }),
            Spec(name: "app.quit", summary: "Quit an app (it asks about unsaved work itself).",
                 parameters: object(["app": app], required: ["app"]), assess: fixed(.changeReversible)),
            Spec(name: "app.hide", summary: "Hide an app's windows.", parameters: object(["app": app], required: ["app"]), assess: fixed(.changeReversible)),
            Spec(name: "app.focus", summary: "Bring an app (or one of its windows) to the front. Only when the owner asked to see or use it; other app calls work in the background.",
                 parameters: object(["app": app, "window": window], required: ["app"]), assess: fixed(.changeReversible)),
            Spec(name: "app.running", summary: "List the running apps (name, bundle, whether hidden or in front).", parameters: object([:]), assess: fixed(.observe)),
            Spec(name: "app.frontmost", summary: "Which app and window is in front now.", parameters: object([:]), assess: fixed(.observe)),
            Spec(name: "window.list", summary: "List an app's windows (or every app's) with ids, titles and frames.",
                 parameters: object(["app": app]), assess: fixed(.observe)),
            Spec(name: "window.move", summary: "Move a window to a point, or to the left/right half, a corner, the center, or another display.",
                 parameters: object(["app": app, "window": window, "to": string("left, right, top, bottom, top-left, top-right, bottom-left, bottom-right, center, full, next-display, or x,y")],
                                    required: ["to"]), assess: fixed(.changeReversible)),
            Spec(name: "window.resize", summary: "Resize a window to a width and height in points.",
                 parameters: object(["app": app, "window": window, "width": integer("Points"), "height": integer("Points")], required: ["width", "height"]),
                 assess: fixed(.changeReversible)),
            Spec(name: "window.tile", summary: "Lay out windows of one or more apps side by side or in a grid on the current display.",
                 parameters: object(["apps": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "description": .string("Apps whose windows to tile")]),
                                     "grid": string("RxC, e.g. 1x2 or 2x2 (optional)")], required: ["apps"]), assess: fixed(.changeReversible)),
            Spec(name: "window.space", summary: "Put a window in full screen (its own Space) or back, or onto another display. macOS has no public way to move a window to a numbered desktop.",
                 parameters: object(["app": app, "window": window, "to": choice(["fullscreen", "exit-fullscreen", "next-display"], "Where")], required: ["to"]),
                 assess: fixed(.changeReversible)),
            Spec(name: "window.minimize", summary: "Minimize a window to the Dock, or restore it.",
                 parameters: object(["app": app, "window": window, "restore": boolean("Restore instead")]), assess: fixed(.changeReversible)),
            Spec(name: "window.close", summary: "Close a window (the app asks about unsaved work itself).",
                 parameters: object(["app": app, "window": window]), assess: fixed(.changeReversible)),
            Spec(name: "app.commands", summary: "What an app can do right now, from its menus, scripting dictionary, App Intents and links, searchable in Korean or English. Use to find the command for a request before app.do.",
                 parameters: object(["app": app, "query": string("What the owner wants done, in their words (optional: every command)"),
                                     "limit": integer("Most commands to return (default 25)")], required: ["app"]), assess: fixed(.observe)),
            Spec(name: "app.do", summary: "Run one of an app's commands (an id from app.commands, or a description such as \"새 창\" or \"File › Export\") through the best channel, in the background, and report what changed.",
                 parameters: object(["app": app, "command": string("A command id from app.commands, a menu path, or a description"),
                                     "arguments": .object(["type": .string("object"), "description": .string("The command's arguments by name (scripting commands, make new, Shortcuts)")]),
                                     "permission_ok": boolean("The owner was just told that macOS will ask for permission once, and agreed")],
                                    required: ["app", "command"]),
                 assess: { arguments, context in
                     // A taught step's mark ("=Format › New [cmd+n]") is no word of the command's: rated by its path.
                     let app = arguments["app"]?.string ?? "", command = Exact.parse(arguments["command"]?.string ?? "").text
                     let worded = Risk.unknownCommand(command)
                     guard let found = context.command(app, command, arguments["arguments"] ?? .object([:])) else { return worded }
                     // Words that say code keep the higher class even when the command found looks mild.
                     // A Shortcut found by its name is judged as a Shortcut (its words saying "run" add nothing).
                     return worded.askAlways && found.interpreter != "shortcut" ? found.joined(worded) : found
                 }),
            Spec(name: "app.read", summary: "Read what an app shows: its window as structured text with element ids (focused field, selection, document, list, table, or the visible chat). Use the ids with app.click, app.type, app.select, app.scroll. On a long page, find narrows the read to the lines holding a word.",
                 parameters: object(["app": app, "window": window, "part": choice(Read.Part.allCases.map(\.rawValue), "Which part (default all)"),
                                     "find": string("Only the elements whose name or text holds this word"),
                                     "offset": integer("Continue from here (the last read's `next`)"), "limit": integer("Most characters (default 6000)")], required: ["app"]),
                 assess: fixed(.observe)),
            // A taught step's call may also carry `line: "new"` (ArisApps.NewLine): not offered to the model, and only ever
            // able to leave out the one leading line break of the rated `text`, never to add anything to it.
            Spec(name: "app.type", summary: "Type text into an app's field or document (by id or description, else the focused field), in the background where the app allows. " +
                 "To write into a document, one call with at=end: the text goes after what is there, no select-all and no replace, and the app's undo takes it back.",
                 parameters: object(["app": app, "text": string("The text"), "target": target, "replace": boolean("Replace what the field holds"),
                                     "at": choice(["caret", "end"], "Where the text goes: at the caret (default) or added at the end of the field or document")],
                                    required: ["app", "text"]),
                 assess: { arguments, context in
                     typeAssessment(arguments, surface: context.surface(arguments["app"]?.string ?? "", arguments["target"]?.string))
                 }),
            Spec(name: "app.click", summary: "Press a button, row, link, checkbox or tab in an app by its id or its exact name from an app.read of this turn (read first; a target that wasn't read is refused).",
                 parameters: object(["app": app, "target": string("The element's id from app.read (\"e12\"), or its exact name as that read printed it"),
                                     "part": choice(Read.Part.allCases.map(\.rawValue), "The part of the window the element is in"),
                                     "double": boolean("Double-click")], required: ["app", "target"]),
                 assess: { arguments, context in
                     // The label that will be pressed (a taught step's "=Pay now" is rated as "Pay now").
                     let app = arguments["app"]?.string ?? "", target = Exact.parse(arguments["target"]?.string ?? "").text
                     return effectOfLabel(context.label(app, target) ?? target)
                 }),
            Spec(name: "app.press", summary: "Press keys in an app (\"cmd+n\", \"return\", \"esc\"); in a chat or mail app Return sends.",
                 parameters: object(["app": app, "keys": string("Keys, e.g. cmd+shift+t or return; several separated by spaces")], required: ["app", "keys"]),
                 assess: { arguments, context in
                     Risk.press(arguments["keys"]?.string ?? "", surface: context.surface(arguments["app"]?.string ?? "", nil))
                 }),
            Spec(name: "app.select", summary: "Select an item in a list, table, tab bar, menu or pop-up by id or description, or choose an option of a pop-up button (buttons are app.click).",
                 parameters: object(["app": app, "target": target, "option": string("For a pop-up: the option to choose")], required: ["app", "target"]),
                 assess: { arguments, context in
                     let app = arguments["app"]?.string ?? "", target = Exact.parse(arguments["target"]?.string ?? "").text
                     let chosen = effectOfLabel(context.label(app, target) ?? target)
                     return arguments["option"]?.string.map { chosen.joined(effectOfLabel($0)) } ?? chosen
                 }),
            Spec(name: "app.scroll", summary: "Scroll an app's list or page (by id or description) to see more.",
                 parameters: object(["app": app, "target": target, "direction": choice(["up", "down", "left", "right"], "Direction (default down)"),
                                     "amount": integer("Lines, 1-50 (default 5)")], required: ["app"]), assess: fixed(.observe)),
            Spec(name: "app.recipe", summary: "Do a common task in one call (send a message in a chat app, compose or send a mail, play music, open a page or search, create a note, reminder or event, find and open a file, change a setting); each falls back across channels by itself.",
                 parameters: object(["recipe": choice(Recipes.all.map(\.id), "Which task"),
                                     "inputs": .object(["type": .string("object"), "description": .string("The task's inputs (app, to, text, subject, body, query, url, pane, setting, words, title, start)")])],
                                    required: ["recipe"]),
                 assess: { arguments, context in
                     guard let recipe = Recipes.recipe(arguments["recipe"]?.string ?? "") else { return .plain(.changePermanent, "an unknown recipe") }
                     var inputs: [String: String] = [:]
                     for (key, value) in arguments["inputs"]?.object ?? [:] { if let text = value.string { inputs[key] = text } }
                     return Specs.recipe(recipe, inputs: inputs, context: context)
                 }),
        ]
    }
}
