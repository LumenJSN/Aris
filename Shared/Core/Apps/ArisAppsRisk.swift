//
//  ArisAppsRisk.swift
//  Shared/Core/Apps
//
//  The few app calls that can run code, send, or act for good, classified as that (the trust policy runs the owner's
//  mild requests without asking, so a call's declared effect must never be milder than what it can do):
//  - another app's interpreter: Terminal's `do script`, a browser's `do JavaScript`/`execute`, Shortcuts' `run`,
//    Automator, Script Editor, System Events' keystrokes, any command whose name or parameters say script, shell,
//    command or code; and menu items that run or execute. Permanent at least, the code text handed to the trust
//    policy's never-list, and asked every time (another app's interpreter can't be sandboxed);
//  - app.open of anything that makes an app act (custom URL schemes, shortcuts://, tel:, a mailto: with a body) or
//    that runs (an app outside the Applications folders, scripts, installers, executables), after aliases and links
//    are resolved;
//  - Return (any spelling, any modifiers) or a typed newline where it sends or submits: chat and mail composers,
//    form fields, terminals (where a line runs as code); an unknown focus takes the higher class.
//  When unsure, the higher class. Pure.
//

import Foundation

extension ArisApps {
    /// A call's effect and what the trust policy needs besides it.
    struct Assessment: Equatable, Sendable {
        var effect: Effect
        /// Code the call would run (a shell line, JavaScript, AppleScript), for the never-list and the sandbox rule.
        var code: String? = nil
        /// Whose interpreter runs it: "shell" (Terminal and the like), "javascript", "applescript", "ui" (keystrokes into
        /// other apps), "shortcut", "workflow", "program" (a file that runs), "unknown".
        var interpreter: String? = nil
        /// Ask the owner every time: no sandbox reaches another app's interpreter, so a standing grant never covers it.
        var askAlways = false
        var why = ""

        static func plain(_ effect: Effect, _ why: String = "") -> Assessment { Assessment(effect: effect, why: why) }

        /// The stricter of two.
        func joined(_ other: Assessment) -> Assessment {
            var out = other.effect > effect ? other : self
            out.askAlways = askAlways || other.askAlways
            out.code = [code, other.code].compactMap { $0 }.joined(separator: "\n").nilIfEmpty
            out.interpreter = interpreter ?? other.interpreter
            return out
        }
    }

    /// What Return or a typed newline does where the keys land.
    enum Surface: String, Sendable {
        /// A chat input or message composer: it sends.
        case chat
        /// A mail composer: ⌘⇧D or a Send button sends; Return in a To/Subject field submits.
        case mail
        /// A terminal: a line runs as code.
        case terminal
        /// A text field or search field (a form): Return submits it.
        case form
        /// A document or text view: Return is a new line.
        case plain
        /// The focus couldn't be read: taken as sending.
        case unknown
    }

    /// What a path is once its aliases and links are resolved.
    enum PathKind: String, Sendable {
        case folder, document
        /// An app in /Applications, /System/Applications, ~/Applications or CoreServices.
        case installedApp
        /// An app anywhere else (a download, a disk image).
        case otherApp
        /// A script, a workflow, an installer, a unix executable, a link file that opens anything.
        case runnable
        case missing
    }

    enum Risk {
        // MARK: - Apps by kind

        static let terminals: Set<String> = ["com.apple.terminal", "com.googlecode.iterm2", "dev.warp.warp-stable", "com.mitchellh.ghostty",
                                             "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "com.raphaelamorim.rio",
                                             "com.termius-dmg.mac", "com.panic.prompt3"]
        static let chats: Set<String> = ["com.kakao.kakaotalkmac", "com.apple.mobilesms", "com.tinyspeck.slackmacgap", "com.hnc.discord", "com.hnc.discordptb",
                                         "ru.keepcoder.telegram", "org.telegram.desktop", "net.whatsapp.whatsapp", "jp.naver.line.mac", "com.microsoft.teams2",
                                         "com.microsoft.teams", "us.zoom.xos", "com.facebook.archon", "com.apple.facetime", "com.skype.skype", "com.openai.chat",
                                         "com.anthropic.claudefordesktop", "com.signal.desktop", "org.whispersystems.signal-desktop"]
        static let mailClients: Set<String> = ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail-mac", "it.bloop.airmail2",
                                               "com.mimestream.mimestream", "com.superhuman.electron", "com.google.gmail", "com.canarymail.mac"]
        /// Apps whose scripting commands run code (every command that doesn't only read, or the ones named).
        static let interpreters: [String: (commands: Set<String>?, interpreter: String)] = [
            "com.apple.terminal": (nil, "shell"), "com.googlecode.iterm2": (nil, "shell"),
            "com.apple.safari": (["do javascript"], "javascript"), "com.google.chrome": (["execute"], "javascript"),
            "com.microsoft.edgemac": (["execute"], "javascript"), "company.thebrowser.browser": (["execute"], "javascript"),
            "com.brave.browser": (["execute"], "javascript"), "com.vivaldi.vivaldi": (["execute"], "javascript"),
            "com.apple.scripteditor2": (nil, "applescript"), "com.apple.automator": (nil, "workflow"),
            "com.apple.shortcuts": (["run"], "shortcut"), "com.apple.shortcuts.events": (["run"], "shortcut"),
            "com.apple.systemevents": (["keystroke", "key code", "click", "perform", "do shell script", "select", "pick", "increment", "decrement", "confirm"], "ui"),
            "com.apple.finder": (["open"], "program"),
        ]

        static func surface(bundle: String, focusedRole: String?) -> Surface {
            let key = bundle.lowercased()
            if terminals.contains(key) { return .terminal }
            if chats.contains(key) { return .chat }
            if mailClients.contains(key) { return .mail }
            switch focusedRole {
            case nil: return .unknown
            case "textField", "searchField", "comboBox", "secureTextField": return .form
            default: return .plain
            }
        }

        // MARK: - Code in scripting commands

        /// Words in a command's name that mean it runs code.
        static let codeNames = ["do script", "do shell script", "do javascript", "run script", "run applescript", "run shell script",
                                "run javascript", "execute", "evaluate", "eval", "do command", "run command", "write text", "keystroke", "key code"]
        /// Words in a parameter's name or a direct parameter's description that mean it carries code.
        static let codeWords = ["script", "javascript", "applescript", "shell", "command", "code", "source", "expression", "osascript"]

        /// Whether a scripting command runs code, and which parameter (or "direct") carries it.
        static func runsCode(_ command: Sdef.Command, bundle: String?) -> (runs: Bool, parameter: String?, interpreter: String) {
            let name = command.name.lowercased()
            func words(_ text: String) -> Set<String> { Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }) }
            let codeParameter = command.parameters.first { parameter in !words(parameter.name).isDisjoint(with: codeWords) }?.name
            // A direct parameter that takes free text described as code ("The AppleScript source to evaluate"), never an
            // object reference ("the object for the command", "the tab to execute the command in").
            let directIsCode = command.direct.map { direct in
                (direct.type.isEmpty || direct.type.contains("text") || direct.type.contains("any")) && !words(direct.description).isDisjoint(with: codeWords)
                    && !direct.description.lowercased().contains("the command")
            } ?? false
            if let bundle, let known = interpreters[bundle.lowercased()] {
                // An app that is an interpreter (no list): every command but the ones that only read.
                let listed = known.commands.map { $0.contains(name) } ?? !["get", "count", "exists"].contains(name)
                if listed { return (true, codeParameter ?? "direct", known.interpreter) }
            }
            if codeNames.contains(where: { name == $0 || name.hasPrefix($0 + " ") }) || codeParameter != nil || directIsCode {
                return (true, codeParameter ?? "direct", name.contains("javascript") ? "javascript" : name.contains("shell") || name.contains("do script") ? "shell" : "unknown")
            }
            return (false, nil, "")
        }

        /// The assessment of running a command (its effect, and for code the text it would run).
        /// `kind`: what a path is once resolved (the url and document channels open what the call names, judged as
        /// app.open judges it).
        static func command(_ command: Command, bundle: String, arguments: JSON, kind: (String) -> PathKind = { _ in .runnable }) -> Assessment {
            if command.channel == .url || command.channel == .document {
                return Assessment.plain(command.effect, command.title)
                    .joined(opening(url: arguments["url"]?.string, path: arguments["path"]?.string, kind: kind))
            }
            guard command.runsCode else { return .plain(command.effect, command.title) }
            // A Shortcut: its name is what runs, and the policy decides (it runs, said first, when the owner named it).
            if command.interpreter == "shortcut" {
                let name = command.channel == .sdef ? (arguments["direct"]?.string ?? arguments.object?.values.compactMap(\.string).first) : command.title
                return Assessment(effect: max(.changePermanent, command.effect), code: name, interpreter: "shortcut", askAlways: false,
                                  why: "the Shortcut “\(name ?? "?")” runs")
            }
            let carried = command.codeParameter.flatMap { arguments[$0]?.string } ?? arguments["direct"]?.string
                ?? arguments.object?.values.compactMap(\.string).first
            return Assessment(effect: max(.changePermanent, command.effect), code: carried, interpreter: command.interpreter ?? "unknown", askAlways: true,
                              why: "“\(command.title)” runs code in \(bundle)")
        }

        /// A command named only by words or an id that wasn't found: the higher class when it looks like code or is a
        /// scripting id.
        static func unknownCommand(_ said: String) -> Assessment {
            let lowered = said.lowercased()
            if codeNames.contains(where: lowered.contains) || codeWords.contains(where: lowered.contains) || Lexicon.units(said).flatMap(Lexicon.meanings).contains("run") {
                return Assessment(effect: .changePermanent, interpreter: "unknown", askAlways: true, why: "‘\(said)’ may run code")
            }
            if lowered.hasPrefix("sdef:") || lowered.hasPrefix("intent:") || lowered.hasPrefix("shortcut:") {
                return .plain(.changePermanent, "an unknown scripting command")
            }
            return .plain(Commands.effect(said, channel: .menu))
        }

        // MARK: - Opening

        static let calling: Set<String> = ["tel", "telprompt", "facetime", "facetime-audio", "facetime-group", "sms", "imessage", "skype", "callto", "whatsapp", "kakaotalk"]
        static let showing: Set<String> = ["http", "https", "x-apple.systempreferences", "maps", "x-apple-helpviewer"]

        /// app.open's effect from what it opens.
        static func opening(url: String?, path: String?, kind: (String) -> PathKind) -> Assessment {
            var result = Assessment.plain(.changeReversible, "opens it")
            if let url {
                let scheme = (URL(string: url)?.scheme ?? url.components(separatedBy: ":").first ?? "").lowercased()
                if scheme == "file", let file = URL(string: url)?.path { result = result.joined(opening(url: nil, path: file, kind: kind)) }
                else if showing.contains(scheme) { result = result.joined(.plain(.changeReversible, "shows a page")) }
                else if scheme == "mailto" {
                    let query = URLComponents(string: url)?.queryItems ?? []
                    let carries = query.contains { ["body", "attachment", "cc", "bcc"].contains($0.name.lowercased()) && !($0.value ?? "").isEmpty }
                    result = result.joined(carries ? .plain(.changePermanent, "a mail with its text filled in") : .plain(.changeReversible, "an empty mail"))
                } else if calling.contains(scheme) {
                    result = result.joined(.plain(.outward, "it calls or messages someone"))
                } else if scheme == "shortcuts" || scheme == "workflow" {
                    // As app.do's shortcut channel: the Shortcut's name is what runs, and asking is the policy's.
                    let name = URLComponents(string: url)?.queryItems?.first { $0.name.lowercased() == "name" }?.value ?? url
                    result = result.joined(Assessment(effect: .changePermanent, code: name, interpreter: "shortcut", askAlways: false, why: "it runs the Shortcut “\(name)”"))
                } else {
                    result = result.joined(Assessment(effect: .changePermanent, interpreter: "unknown", why: "‘\(scheme):’ makes an app act"))
                }
            }
            if let path {
                switch kind(path) {
                case .folder, .document, .installedApp, .missing: break
                case .otherApp, .runnable:
                    result = result.joined(Assessment(effect: .changePermanent, code: path, interpreter: "program", askAlways: true, why: "\((path as NSString).lastPathComponent) runs"))
                }
            }
            return result
        }

        /// Extensions of files that run something when opened.
        static let runnableExtensions: Set<String> = ["command", "tool", "sh", "bash", "zsh", "csh", "fish", "workflow", "action", "terminal", "scpt", "scptd",
                                                      "applescript", "jar", "pkg", "mpkg", "dmg", "py", "rb", "pl", "php", "js", "jxa", "osascript", "run", "bin",
                                                      "webloc", "inetloc", "fileloc", "shortcut", "prefpane", "saver", "qlgenerator", "kext", "plugin", "mobileconfig",
                                                      "itermcolors", "url", "desktop", "service", "osax"]

        static let appFolders = ["/Applications/", "/System/Applications/", "/System/Library/CoreServices/", "/System/Volumes/Preboot/Cryptexes/App/System/Applications/"]

        /// A resolved path's kind from its extension, whether it is a folder and whether it is executable.
        static func kind(resolved path: String, isFolder: Bool, executable: Bool, exists: Bool, home: String) -> PathKind {
            guard exists else { return .missing }
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "app" {
                let homeApps = home.hasSuffix("/") ? home + "Applications/" : home + "/Applications/"
                let installed = (appFolders + [homeApps]).contains { path.hasPrefix($0) } && !path.dropFirst(1).contains("/Volumes/")
                return installed ? .installedApp : .otherApp
            }
            if runnableExtensions.contains(ext) { return .runnable }
            if isFolder { return .folder }
            return executable ? .runnable : .document
        }

        // MARK: - Keys and newlines

        /// A key chord in one spelling: modifiers sorted, names folded ("Cmd+Return", "⌘↩", "command+enter" → cmd+return).
        static func normalized(_ chord: String) -> (modifiers: Set<String>, key: String) {
            let glyphs: [Character: String] = ["⌘": "cmd", "⇧": "shift", "⌥": "opt", "⌃": "ctrl", "↩": "return", "⏎": "return", "⌤": "return"]
            var text = chord.lowercased()
            var modifiers = Set<String>()
            for (glyph, name) in glyphs where text.contains(glyph) {
                if ["cmd", "shift", "opt", "ctrl"].contains(name) { modifiers.insert(name) }
                text = text.replacingOccurrences(of: String(glyph), with: name == "return" ? "+return" : "+")
            }
            let parts = text.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let names = ["command": "cmd", "meta": "cmd", "super": "cmd", "control": "ctrl", "option": "opt", "alt": "opt"]
            var key = ""
            for part in parts {
                let name = names[part] ?? part
                if ["cmd", "shift", "opt", "ctrl", "fn"].contains(name) { modifiers.insert(name) } else { key = name }
            }
            let enter = ["return", "enter", "kp_enter", "kpenter", "numpadenter", "numpad_enter", "keypadenter", "keypad_enter", "\n", "\r", "linefeed", "newline", "cr"]
            if enter.contains(key) { key = "return" }
            return (modifiers, key)
        }

        /// Whether these keys (several separated by spaces) press Return, with any modifiers.
        static func pressesReturn(_ keys: String) -> Bool {
            keys.split(separator: " ").contains { normalized(String($0)).key == "return" } || keys.contains("↩") || keys.contains("⏎")
        }

        /// What Return (or a typed newline) does on a surface.
        static func returnEffect(_ surface: Surface, code: String?) -> Assessment {
            switch surface {
            case .chat, .mail, .form: return .plain(.outward, "Return sends or submits here")
            case .unknown: return .plain(.outward, "the focus couldn't be read, so Return is taken as sending")
            case .terminal: return Assessment(effect: .changePermanent, code: code, interpreter: "shell", askAlways: true, why: "a line typed into a terminal runs")
            case .plain: return .plain(.changeReversible, "a new line")
            }
        }

        /// app.press: Return where it sends or runs; ⌘⇧D (Mail's send) in a mail app; other keys are a reversible change.
        static func press(_ keys: String, surface: Surface) -> Assessment {
            if pressesReturn(keys) { return returnEffect(surface, code: nil) }
            let sendsMail = keys.split(separator: " ").contains { let chord = normalized(String($0)); return chord.key == "d" && chord.modifiers == ["cmd", "shift"] }
            if sendsMail, surface == .mail || surface == .unknown { return .plain(.outward, "⌘⇧D sends the mail") }
            return .plain(.changeReversible)
        }

        /// app.type: text with a newline or carriage return sends where Return sends, and runs in a terminal.
        static func type(_ text: String, surface: Surface) -> Assessment {
            if surface == .terminal, text.contains("\n") || text.contains("\r") { return returnEffect(.terminal, code: text) }
            if text.contains("\n") || text.contains("\r"), surface != .plain { return returnEffect(surface, code: nil) }
            return .plain(.changeReversible)
        }
    }
}

extension ArisApps.Recipes {
    /// A recipe step's check when no trust policy is handed in: it runs only within what the recipe as a whole was
    /// assessed (and so approved) as: no higher effect, no code that wasn't read back, nothing that must always ask.
    static func stepRefusal(_ step: ArisApps.Assessment, approved: ArisApps.Assessment) -> String? {
        if step.effect > approved.effect { return "this step would be \(step.effect.rawValue) (\(step.why)), more than the task was approved as" }
        if step.askAlways, !approved.askAlways { return "this step runs code (\(step.why)), which the task wasn't approved for" }
        if let code = step.code, !(approved.code ?? "").contains(code) { return "this step runs code that wasn't read back: \(code.prefix(80))" }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
