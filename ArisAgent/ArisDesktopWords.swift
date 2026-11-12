//
//  ArisDesktopWords.swift
//  aris-agent
//
//  The words of `aris-tools desktop …`, read the one way the agent runs them, for every brain: from aris-tools (Codex,
//  the Claudes, the API brain's helper), from agy's aris-run block (ArisAgyRelay) and from a shell line with its text
//  on stdin (ArisDesktopShell). Only known verbs and flags, each value checked; refs only in their qualified form
//  (`@<Aris's snapshot id>:e<N>`, or `:t<N>` for a text mark read from the screen). The brain never names a window
//  or a process Aris didn't resolve, and never a Peekaboo flag: the controller builds Peekaboo's argv itself
//  (ArisPeekabooCommands). Pure.
//

import Foundation

enum ArisDesktopKind: Equatable { case read, action }

enum ArisDesktopVerb: String, CaseIterable {
    // Reads.
    case see, menuList = "menu list", dialogList = "dialog list", windowList = "window list", dockList = "dock list"
    // Actions.
    case click, type, setValue = "set-value", press, scroll, drag
    case menuClick = "menu click", dialogClick = "dialog click", dialogInput = "dialog input", dialogFile = "dialog file"
    /// `dock launch "<App>"` is read as `app launch "<App>"`: Peekaboo's Dock launch finds an item by its name (a folder
    /// or a file in the Dock could carry it), an app launch goes by the resolved bundle id (M7).
    case window, app
    /// The look-and-click way for a window with no accessibility there (a canvas): Aris looks, a vision brain points.
    case clickAt = "click-at"
    /// Several steps in one call (ArisDesktopBatch).
    case batch

    var kind: ArisDesktopKind {
        switch self {
        case .see, .menuList, .dialogList, .windowList, .dockList: return .read
        default: return .action
        }
    }

    /// The verbs whose text comes on stdin (or as the relay's quoted word).
    var takesText: Bool { self == .type || self == .setValue || self == .dialogInput || self == .batch }

    /// The verbs that act on a ref (the app is the one its snapshot was taken of).
    var takesRef: Bool { [.click, .type, .setValue, .scroll, .drag].contains(self) }
}

/// A qualified ref, `@<snapshot>:e<N>` (an accessibility element) or `@<snapshot>:t<N>` (a text mark from the screen).
struct ArisDesktopRef: Equatable, Hashable {
    let snapshot: String
    let element: Int
    var mark = false

    var text: String { "@\(snapshot):\(mark ? "t" : "e")\(element)" }

    static func parse(_ word: String) -> ArisDesktopRef? {
        guard word.range(of: #"^@[a-z0-9]{4,32}:[et][0-9]{1,6}$"#, options: .regularExpression) != nil,
              let colon = word.firstIndex(of: ":"), let element = Int(word[word.index(colon, offsetBy: 2)...]) else { return nil }
        return ArisDesktopRef(snapshot: String(word[word.index(after: word.startIndex)..<colon]), element: element,
                              mark: word[word.index(after: colon)] == "t")
    }
}

struct ArisDesktopRequest: Equatable {
    let verb: ArisDesktopVerb
    var ref: ArisDesktopRef? = nil
    /// drag's destination.
    var to: ArisDesktopRef? = nil
    /// The app named with --app (or the app word of `app …` and `dock launch …`).
    var app: String? = nil
    /// A window id the brain named (one Aris listed for that app).
    var window: Int? = nil
    /// A window's title the brain named (ArisWindowTitleMatch: exact, else a unique start).
    var title: String? = nil
    /// `window …` and `app …`: focus, close, launch…
    var operation: String? = nil
    /// press's chords; scroll's direction; menu's path; dialog's button, field, path, name, select.
    var keys: [String] = []
    var direction: String? = nil
    var amount: Int? = nil
    var path: String? = nil
    var button: String? = nil
    var field: String? = nil
    var name: String? = nil
    var select: String? = nil
    var x: Int? = nil, y: Int? = nil, width: Int? = nil, height: Int? = nil
    var ocr = false
    var annotate = false
    var double = false
    var right = false
    /// click-at's description of what to click.
    var target: String? = nil
    /// type's, set-value's or dialog input's text.
    var text: String? = nil
    /// batch's steps.
    var steps: [ArisDesktopStep] = []

    /// It brings a window or an app to the front (only with a card, only while the user is there).
    var bringsForward: Bool {
        switch verb {
        case .dialogFile: return true
        case .window: return operation == "focus"
        case .app: return operation == "launch" || operation == "focus"
        default: return false
        }
    }

    /// What the read judge and the audit see of it: the verb and its words (never the text).
    var summary: String {
        var words: [String] = [verb.rawValue]
        if let operation { words.append(operation) }
        if let ref { words.append(ref.text) }
        if !keys.isEmpty { words.append(keys.joined(separator: " ")) }
        if let to { words.append("--to " + to.text) }
        if let path { words.append(path) }
        if let button { words.append(button) }
        if ocr { words.append("--ocr") }
        if annotate { words.append("--annotate") }
        return words.joined(separator: " ")
    }
}

struct ArisDesktopUsage: Error, Equatable {
    let text: String
}

enum ArisDesktopWords {
    static let usage = """
        usage: aris-tools desktop see --app "<App>" [--window <id> | --title "<window title>"] [--ocr] | click <ref> [--double|--right] | type <ref> --stdin | \
        set-value <ref> --stdin | press <keys…> --app "<App>" [--window <id> | --title "<window title>"] | scroll <ref> --direction up|down|left|right [--amount N] | \
        drag <ref> --to <ref> | menu list|click --app "<App>" [--path "File › Export › PDF…"] | \
        dialog list|click|input|file --app "<App>" [--button "<label>"] [--field "<label>"] [--path <folder or file>] [--name <file name>] | \
        window list|focus|close|minimize|restore|maximize|move|resize --app "<App>" [--window <id>] | app launch|focus|hide|quit "<App>" | \
        dock list | click-at --app "<App>" --target "<what to click>" [--window <id> | --title "<window title>"] | \
        batch --app "<App>" [--title "<window title>"] --stdin (one step a line: click <ref or "label">, type <ref or "label"> <text>, set-value …, press <keys…>, scroll … up|down)
        """
    /// The most text one type, set-value or dialog input takes.
    static func maxText(_ verb: ArisDesktopVerb) -> Int { verb == .setValue ? 131_072 : 10_000 }
    static let markLine = "A text mark (@…:tN) is only a spot to click with a plain `desktop click`. To type, set, scroll or drag, use an element ref (@…:eN) from `desktop see`."

    /// The most chords one press takes (several keys in one step: `press cmd+a delete`).
    static let maxChords = 12

    static let windowOperations: Set<String> = ["focus", "close", "minimize", "restore", "maximize", "move", "resize"]
    static let appOperations: Set<String> = ["launch", "focus", "hide", "quit"]

    /// The words after `desktop`. `text`: what came on stdin (aris-tools) or nil. `positionalText`: the relay's form,
    /// where Aris itself holds the words (`type <ref> '<text>'`).
    static func parse(_ words: [String], text: String? = nil, positionalText: Bool = false) -> Result<ArisDesktopRequest, ArisDesktopUsage> {
        guard words.allSatisfy({ !$0.contains("\0") && $0.count <= 400 }), words.count <= 24, let first = words.first else {
            return .failure(ArisDesktopUsage(text: usage))
        }
        guard let (verb, used) = verb(words) else { return .failure(ArisDesktopUsage(text: usage)) }
        var rest = Array(words.dropFirst(used))
        var request = ArisDesktopRequest(verb: verb)
        if verb.takesRef {
            guard let word = rest.first, let ref = ArisDesktopRef.parse(word) else {
                return .failure(ArisDesktopUsage(text: "\(first) takes a ref from `desktop see`, like @s8f3k2:e3 (a bare e3 or elem_3 is refused)"))
            }
            // A text mark read from the screen is only a spot to click: never typed into, set, scrolled or dragged (I3).
            guard !ref.mark || verb == .click else { return .failure(ArisDesktopUsage(text: markLine)) }
            request.ref = ref
            rest.removeFirst()
        }
        if verb == .window || verb == .app {
            let allowed = verb == .window ? windowOperations : appOperations
            guard let operation = rest.first, allowed.contains(operation) else {
                return .failure(ArisDesktopUsage(text: "\(first) takes " + allowed.sorted().joined(separator: ", ")))
            }
            request.operation = operation
            rest.removeFirst()
        }
        do {
            try read(&request, rest: rest, text: text, positionalText: positionalText)
        } catch let usage as ArisDesktopUsage {
            return .failure(usage)
        } catch {
            return .failure(ArisDesktopUsage(text: usage))
        }
        return .success(request)
    }

    /// The verb and how many words name it (`menu click` is two).
    private static func verb(_ words: [String]) -> (ArisDesktopVerb, Int)? {
        let first = words[0], second = words.count > 1 ? words[1] : ""
        switch first {
        case "see", "snapshot": return (.see, 1)
        case "list-windows": return (.windowList, 1)
        case "dock" where second == "launch":
            // Read as `app launch` (the words after it: the app's name).
            return (.app, 1)
        case "menu", "dialog", "dock":
            if let verb = ArisDesktopVerb(rawValue: "\(first) \(second)") { return (verb, 2) }
            return nil
        case "window": return second == "list" ? (.windowList, 2) : (.window, 1)
        default:
            guard let verb = ArisDesktopVerb(rawValue: first), !first.contains(" ") else { return nil }
            return (verb, 1)
        }
    }

    private static func read(_ request: inout ArisDesktopRequest, rest: [String], text: String?, positionalText: Bool) throws {
        let verb = request.verb
        var index = 0
        var positional: [String] = []
        var stdin = false
        func value(_ flag: String) throws -> String {
            guard index + 1 < rest.count, !rest[index + 1].hasPrefix("--") else { throw ArisDesktopUsage(text: "\(flag) needs a value") }
            index += 1
            return rest[index]
        }
        func number(_ flag: String, _ range: ClosedRange<Int>) throws -> Int {
            guard let number = Int(try value(flag)), range.contains(number) else { throw ArisDesktopUsage(text: "\(flag) takes \(range.lowerBound) to \(range.upperBound)") }
            return number
        }
        func words(_ flag: String, limit: Int = 200) throws -> String {
            let words = try value(flag)
            guard !words.isEmpty, words.count <= limit, !hasControl(words) else { throw ArisDesktopUsage(text: "\(flag) takes plain words") }
            return words
        }
        while index < rest.count {
            let word = rest[index]
            switch (verb, word) {
            case (_, "--app") where ![.app, .dockList].contains(verb) && !verb.takesRef:
                let app = try value(word)
                guard isAppName(app) else { throw ArisDesktopUsage(text: "--app takes an app's name") }
                request.app = app
            // press and click-at name their window too (audit desk-1: the keys went to the front one whatever the user named).
            case (.see, "--window"), (.window, "--window"), (.windowList, "--window"), (.press, "--window"), (.clickAt, "--window"):
                request.window = try number(word, 1...Int(Int32.max))
            case (.see, "--title"), (.window, "--title"), (.batch, "--title"), (.press, "--title"), (.clickAt, "--title"):
                request.title = try words(word)
            case (.see, "--ocr"): request.ocr = true
            case (.see, "--annotate"): request.annotate = true
            case (.see, "-i"), (.see, "--compact"): break // the old snapshot's flags: the tree is always the compact one
            case (.click, "--double"): request.double = true
            case (.click, "--right"): request.right = true
            case (.scroll, "--direction"):
                let direction = try value(word)
                guard ["up", "down", "left", "right"].contains(direction) else { throw ArisDesktopUsage(text: "--direction takes up, down, left or right") }
                request.direction = direction
            case (.scroll, "--amount"): request.amount = try number(word, 1...50)
            case (.drag, "--to"):
                guard let to = ArisDesktopRef.parse(try value(word)) else { throw ArisDesktopUsage(text: "--to takes a ref from the same `desktop see`") }
                guard !to.mark else { throw ArisDesktopUsage(text: markLine) }
                request.to = to
            case (.menuClick, "--path"):
                let path = try words(word, limit: 300)
                // `›` too: a shell line Aris lets through can't carry `>`.
                let parts = path.replacingOccurrences(of: "›", with: ">").components(separatedBy: ">").map { $0.trimmingCharacters(in: .whitespaces) }
                guard (1...8).contains(parts.count), parts.allSatisfy({ !$0.isEmpty }) else { throw ArisDesktopUsage(text: "--path takes a menu path like \"File › Export › PDF…\"") }
                request.path = parts.joined(separator: " > ")
            case (.dialogClick, "--button"): request.button = try words(word)
            case (.dialogInput, "--field"): request.field = try words(word)
            case (.dialogFile, "--path"):
                let path = try words(word, limit: 1_024)
                guard path.hasPrefix("/") || path.hasPrefix("~/"), !path.split(separator: "/").contains("..") else { throw ArisDesktopUsage(text: "--path takes a full folder or file path") }
                request.path = path
            case (.dialogFile, "--name"):
                let name = try words(word)
                guard !name.contains("/") else { throw ArisDesktopUsage(text: "--name takes a file name, not a path") }
                request.name = name
            case (.dialogFile, "--select"): request.select = try words(word)
            case (.window, "--x"): request.x = try number(word, -20_000...20_000)
            case (.window, "--y"): request.y = try number(word, -20_000...20_000)
            case (.window, "--width"): request.width = try number(word, 100...20_000)
            case (.window, "--height"): request.height = try number(word, 100...20_000)
            case (.clickAt, "--target"): request.target = try words(word)
            case (_, "--stdin") where verb.takesText:
                stdin = true
            default:
                guard !word.hasPrefix("-") || word == "-" else { throw ArisDesktopUsage(text: "\(verb.rawValue) doesn't take \(word)") }
                positional.append(word)
            }
            index += 1
        }
        try finish(&request, positional: positional, stdin: stdin, text: text, positionalText: positionalText)
    }

    private static func finish(_ request: inout ArisDesktopRequest, positional: [String], stdin: Bool, text: String?, positionalText: Bool) throws {
        let verb = request.verb
        switch verb {
        case .type, .setValue, .dialogInput, .batch:
            if positionalText {
                guard positional.count == 1, !stdin else { throw ArisDesktopUsage(text: "\(verb.rawValue) … '<text>'") }
                request.text = positional[0]
            } else {
                guard positional.isEmpty, stdin, let text else {
                    throw ArisDesktopUsage(text: "\(verb.rawValue) takes its text on stdin only: \(verb.rawValue) … --stdin <<'ARIS' … ARIS")
                }
                request.text = text
            }
            guard let text = request.text, text.utf8.count <= maxText(verb) else { throw ArisDesktopUsage(text: "the text is too long") }
            if verb == .batch {
                request.steps = try ArisDesktopBatch.steps(text, relay: positionalText)
                request.text = nil
            }
        case .press:
            guard (1...maxChords).contains(positional.count), positional.allSatisfy(isKeyCombo) else {
                throw ArisDesktopUsage(text: "press <keys like return, cmd+s or `cmd+a delete`, at most \(maxChords)> --app \"<App>\"")
            }
            request.keys = positional.map { $0.lowercased() }
        case .app:
            guard positional.count == 1, isAppName(positional[0]) else { throw ArisDesktopUsage(text: "\(verb.rawValue) takes one app's name") }
            request.app = positional[0]
        default:
            guard positional.isEmpty else { throw ArisDesktopUsage(text: "\(verb.rawValue) doesn't take \(positional[0])") }
        }
        switch verb {
        case .see, .menuList, .menuClick, .dialogList, .dialogClick, .dialogInput, .dialogFile, .windowList, .window, .press, .clickAt, .batch:
            guard request.app != nil else { throw ArisDesktopUsage(text: "\(verb.rawValue) needs --app \"<App>\"") }
        default: break
        }
        switch verb {
        case .menuClick where request.path == nil: throw ArisDesktopUsage(text: "menu click --app \"<App>\" --path \"File › Export › PDF…\"")
        case .dialogClick where request.button == nil: throw ArisDesktopUsage(text: "dialog click --app \"<App>\" --button \"<label>\"")
        case .dialogFile where request.path == nil && request.name == nil: throw ArisDesktopUsage(text: "dialog file --app \"<App>\" --path <folder or file> [--name <file name>]")
        case .scroll where request.direction == nil: throw ArisDesktopUsage(text: "scroll <ref> --direction up|down|left|right")
        case .drag:
            guard let to = request.to, to.snapshot == request.ref?.snapshot else { throw ArisDesktopUsage(text: "drag <ref> --to <ref> (both from the same `desktop see`)") }
        case .click where request.ref?.mark == true && (request.double || request.right): throw ArisDesktopUsage(text: markLine)
        case .clickAt where request.target == nil: throw ArisDesktopUsage(text: "click-at --app \"<App>\" --target \"<what to click>\"")
        case .window:
            if request.operation == "move", request.x == nil || request.y == nil { throw ArisDesktopUsage(text: "window move --app \"<App>\" --x N --y N") }
            if request.operation == "resize", request.width == nil || request.height == nil { throw ArisDesktopUsage(text: "window resize --app \"<App>\" --width N --height N") }
        default: break
        }
    }

    static func isAppName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= 80 && !trimmed.hasPrefix("-") && !trimmed.contains("/") && !hasControl(trimmed)
    }

    /// Keys like `return`, `cmd+s`, `shift+tab`, `cmd+,`: never a quit, log-out, force-quit or app-switch combo.
    static func isKeyCombo(_ combo: String) -> Bool {
        let lowered = combo.lowercased()
        guard lowered.range(of: #"^[a-z0-9+,./;'\[\]\\=`]{1,40}$"#, options: .regularExpression) != nil, !lowered.hasPrefix("-") else { return false }
        let parts = Set(lowered.split(separator: "+").map(String.init))
        let command = !parts.isDisjoint(with: ["cmd", "command", "meta", "super"])
        if command, !parts.isDisjoint(with: ["q", "tab", "space", "h", "m"]) { return false }
        if command, parts.contains("esc") || parts.contains("escape") { return false }
        if parts.contains("ctrl") || parts.contains("control"), parts.contains("space") { return false }
        return true
    }

    static func hasControl(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
