//
//  ArisRiskPolicy+Escalation.swift
//  aris-agent
//
//  For the escalation gate (ArisEscalation): what an action is aimed at (its scope, for standing permissions), and
//  the hard lines main Aris may never approve on its own: money, sending mail (drafts only), permanent deletion.
//  Every check here leans toward the hard line: a wrong guess only means asking (or refusing) when it wasn't needed.
//

import Foundation

extension ArisRiskPolicy {
    // MARK: - Scope

    /// What a standing permission for this action would cover: its kind, its app or connector, and its recipient
    /// or target (`arguments`: an MCP tool's parameters). A shell command's target is the whole command.
    static func scope(of action: ArisAction, tools: String = "", arguments: [String: Any] = [:]) -> ArisActionScope {
        switch action {
        case .shell(let command):
            let pieces = ArisCommandPolicy.segments(command) ?? [command]
            guard pieces.count == 1, let words = ArisCommandPolicy.words(command), let first = words.first else {
                return ArisActionScope(kind: "shell", app: "", target: command)
            }
            guard first == tools, words.count > 1 else {
                return ArisActionScope(kind: "shell", app: (first as NSString).lastPathComponent, target: command)
            }
            // A message is scoped to its recipient (spec §5); anything else to its exact words, so a yes to typing
            // one command into an app never covers other keystrokes there.
            let rest = Array(words.dropFirst(2))
            let target = words[1] == "message" || words[1] == "mail" ? rest.first ?? "" : rest.joined(separator: " ")
            return ArisActionScope(kind: words[1], app: "aris-tools", target: target)
        case .fileChange(let paths): return ArisActionScope(kind: "files", app: "", target: paths.joined(separator: ", "))
        case .mcp(let server, let tool):
            if let spec = ArisToolSchemas.spec(server: server, tool: tool) {
                let walked = ArisToolSchemas.walk(arguments, spec: spec)
                return ArisActionScope(kind: ([tool] + walked.kindParts).joined(separator: "+"), app: server,
                                       target: walked.targets.joined(separator: ", "))
            }
            return ArisActionScope(kind: tool, app: server, target: target(in: arguments))
        case .computerUse(let app): return ArisActionScope(kind: "computer-use", app: app, target: app)
        case .browserTask(let task): return ArisActionScope(kind: "aside", app: "aris_aside", target: task)
        }
    }

    /// Whether the call's scope says everything it does. A tool Aris knows field by field (ArisToolSchemas) must have
    /// every field understood; any other tool may carry only its targets and plain content (a string or rich text
    /// with no mentions, links or embeds). Either way it needs a target, and every target must be shaped like an id,
    /// an email or a phone number. Otherwise only the user may approve it.
    static func isFullyScoped(server: String, tool: String, arguments: [String: Any]) -> Bool {
        if let spec = ArisToolSchemas.spec(server: server, tool: tool) {
            let walked = ArisToolSchemas.walk(arguments, spec: spec)
            return walked.complete && !walked.targets.isEmpty
        }
        let targetValues = arguments.filter { isTargetKey($0.key) }.values
        let targets = targetValues.flatMap(identities)
        guard !targets.isEmpty, targetValues.allSatisfy(isStrictTarget), targets.allSatisfy(ArisToolSchemas.isIdentity) else { return false }
        return arguments.allSatisfy { key, value in
            if isTargetKey(key) { return true }
            return contentKeys.contains(key.lowercased()) && isContent(value)
        }
    }

    /// The parameters that say who or what a tool acts on: every one of them makes up the scope. On a tool Aris
    /// doesn't know field by field, a name or summary may pick who it reaches, so they count as targets too.
    private static let targetKeys: Set<String> = ["to", "cc", "bcc", "recipients", "recipient", "email", "emails", "attendees", "chat_id",
                                                  "channel", "parent", "path", "url", "id", "name", "summary"]
    /// The parameters that only carry what is said.
    private static let contentKeys: Set<String> = ["body", "content", "text", "message", "subject", "title"]
    /// Inside a target object, the fields that name someone or something.
    private static let identityKeys: Set<String> = ["email", "emails", "id", "phone", "phone_number", "phonenumber", "number", "address",
                                                    "handle", "url", "username", "name"]

    static func isTargetKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return targetKeys.contains(lowered) || lowered.hasSuffix("_id") || lowered.hasSuffix("_ids") || key.hasSuffix("Id") || key.hasSuffix("Ids")
            || key.hasSuffix("ID") || lowered.hasSuffix("_url") || key.hasSuffix("Url")
    }

    /// A target on a tool without a schema: a string, a list of strings or strict objects, or a strict object (only
    /// identity or target keys, holding strings or lists of strings). An object with any other field could carry
    /// something the scope doesn't show.
    private static func isStrictTarget(_ value: Any) -> Bool {
        switch value {
        case is String: return true
        case let list as [Any]: return list.allSatisfy { $0 is String || (($0 as? [String: Any]).map(isStrictObject) ?? false) }
        case let object as [String: Any]: return isStrictObject(object)
        default: return false
        }
    }

    private static func isStrictObject(_ object: [String: Any]) -> Bool {
        object.allSatisfy { key, inner in
            (identityKeys.contains(key.lowercased()) || isTargetKey(key))
                && (inner is String || (inner as? [Any])?.allSatisfy { $0 is String } == true)
        }
    }

    /// Chat-style mentions a tool without a schema may turn into a recipient: <@U1>, <!channel>, <#C1>, @here,
    /// @everyone, @name (an @ right before a word character).
    private static func mentionsSomeone(_ text: String) -> Bool {
        ["<@", "<!", "<#"].contains(where: text.contains) || text.range(of: #"@\w"#, options: .regularExpression) != nil
    }

    /// A string, or rich text that only says things: no mention, link, embed or Notion tag (any of those could be a
    /// recipient the scope doesn't name).
    private static func isContent(_ value: Any) -> Bool {
        if let text = value as? String { return !ArisToolSchemas.hidesTarget(text) && !mentionsSomeone(text) }
        guard value is [Any] else { return false }
        let walked = ArisToolSchemas.walk(["text": value], spec: ["text": ArisToolSchemas.richText])
        return walked.complete && walked.targets.isEmpty && !strings(in: value).contains(where: mentionsSomeone)
    }

    private static func strings(in value: Any) -> [String] {
        switch value {
        case let text as String: return [text]
        case let list as [Any]: return list.flatMap(strings)
        case let object as [String: Any]: return object.values.flatMap(strings)
        default: return []
        }
    }

    /// Every recipient and target in the call, each once, sorted and joined: a grant for A never covers a call that
    /// also goes to B.
    private static func target(in arguments: [String: Any]) -> String {
        let identities = arguments.filter { isTargetKey($0.key) }.values.flatMap(identities)
        return Set(identities).sorted().joined(separator: ", ")
    }

    private static func identities(_ value: Any) -> [String] {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        case let list as [Any]: return list.flatMap(identities)
        case let object as [String: Any]:
            // Every identity-like field (an email and a phone both count); an object with none gives all it holds.
            let named = object.keys.filter { identityKeys.contains($0.lowercased()) || isTargetKey($0) }.sorted()
            return (named.isEmpty ? object.keys.sorted() : named).compactMap { object[$0] }.flatMap(identities)
        default: return ["\(value)"]
        }
    }

    // MARK: - Hard lines

    /// `connector`: a ChatGPT app's id or name (Gmail), when the tool came through one. `arguments`: an MCP tool's
    /// parameters, whose folded kind (a page command, an update type) can make it a deletion.
    static func hardLine(of action: ArisAction, tools: String = "", connector: String = "", arguments: [String: Any] = [:]) -> ArisHardLine? {
        switch action {
        case .shell(let command): return shellHardLine(command, tools: tools)
        case .mcp(let server, let tool):
            if let line = toolHardLine(server: server, tool: tool, connector: connector) { return line }
            return destroys(server: server, tool: tool, arguments: arguments) ? .permanentDelete : nil
        case .browserTask(let task): return taskHardLine(task)
        case .fileChange, .computerUse: return nil
        }
    }

    /// Kind values that throw something away: the user is asked (replace_content rewrites a whole page).
    private static let destroyingKinds = ["delete", "cancel", "remove", "archive", "trash"]

    private static func destroys(server: String, tool: String, arguments: [String: Any]) -> Bool {
        guard let spec = ArisToolSchemas.spec(server: server, tool: tool) else { return false }
        return ArisToolSchemas.walk(arguments, spec: spec).kindParts.contains { part in
            let lowered = part.lowercased()
            return lowered == "replace_content" || destroyingKinds.contains(where: lowered.contains)
        }
    }

    // MARK: Tools

    /// A tool name's words: split at anything not a letter or digit and where a capital follows a small letter
    /// (sendEmail → send, email), lowercased.
    static func toolWords(_ name: String) -> [String] {
        var words: [String] = []
        var word = ""
        var previous: Character?
        for character in name {
            if !character.isLetter && !character.isNumber {
                if !word.isEmpty { words.append(word) }
                word = ""
            } else {
                if character.isUppercase, let previous, previous.isLowercase || previous.isNumber, !word.isEmpty {
                    words.append(word)
                    word = ""
                }
                word.append(character)
            }
            previous = character
        }
        if !word.isEmpty { words.append(word) }
        return words.map { $0.lowercased() }
    }

    /// Words that only mean paying: refused when the tool's name holds one (with s, es, ing or ed endings), unless
    /// it only looks something up (then the user is asked).
    private static let moneyWords = ["pay", "payment", "purchase", "buy", "checkout", "donate", "donation", "payout", "refund"]
    /// Words that mean money only next to another word: an order being placed, a transfer of funds.
    private static let orderingVerbs: Set<String> = ["create", "place", "submit", "make", "new", "add"]
    private static let fundsWords: Set<String> = ["fund", "funds", "money", "cash", "payment", "payments", "balance"]
    /// Anything starting like money (payload, cartography, buyer, transfer_ownership, update_sort_order): the user is asked.
    private static let moneyStems = ["order", "purchas", "buy", "pay", "charg", "checkout", "transfer", "donat", "refund", "invoice", "cart",
                                     "subscri", "tip"]
    /// Only these nouns may be looked at (get_order_status, list_subscriptions) with no question at all.
    private static let lookedAtNouns: Set<String> = ["order", "subscri"]
    private static let lookingVerbs: Set<String> = ["get", "list", "search", "read", "fetch", "find", "query"]
    private static let deletingStems = ["delet", "remov", "trash", "destroy", "eras", "purg"]
    private static let sendingStems = ["send"]
    private static let replyingStems = ["reply", "repli"]
    /// What a read-only mail tool may never do.
    private static let changingStems = ["send", "delet", "remov", "trash", "destroy", "eras", "purg", "forward", "reply", "modif", "move",
                                        "archiv", "label", "mark", "updat", "creat", "insert", "add", "set", "batch", "import", "spam"]

    private static func has(_ words: [String], _ stems: [String]) -> Bool {
        words.contains { word in stems.contains(where: word.hasPrefix) }
    }

    /// `word` is `base` or one of its forms: +s, +es, +ing, +ed (purchase → purchasing, purchased too).
    private static func isForm(_ word: String, of base: String) -> Bool {
        let stem = base.hasSuffix("e") ? String(base.dropLast()) : base
        return [base, base + "s", base + "es", base + "ing", base + "ed", base + "d", stem + "ing", stem + "ed"].contains(word)
    }

    private static func toolHardLine(server: String, tool: String, connector: String) -> ArisHardLine? {
        if let money = moneyLine(toolWords(tool)) { return money }
        let words = toolWords(tool)
        let place = [server, connector, tool].joined(separator: " ").lowercased()
        let isMail = place.contains("mail") || place.contains("outlook") || connector == ArisCodexDriver.gmail
        if isMail {
            // Refused only when the tool's own name says send; any other tool there that isn't plainly read-only
            // or draft-only asks.
            if has(words, sendingStems) { return .mailSend }
            let readOnly = words.first.map(lookingVerbs.contains) == true && !has(words, changingStems)
            let draftOnly = has(words, ["draft"]) && !has(words, sendingStems + deletingStems)
            // A reply goes out like a send (a tool named `reply`, by a message's id, with replyAll): it is the user's card
            // only when the call itself carries who it goes to and the whole text, and refused like any send that
            // can't be shown otherwise. It used to ask on a card that named no recipient at all.
            if !draftOnly, words.first.map(lookingVerbs.contains) != true, has(words, replyingStems) { return .mailSend }
            if !readOnly && !draftOnly { return .uncertain }
        }
        return has(words, deletingStems) ? .permanentDelete : nil
    }

    private static func moneyLine(_ words: [String]) -> ArisHardLine? {
        let looking = words.contains(where: lookingVerbs.contains)
        let ordering = words.contains(where: orderingVerbs.contains)
        let definite = words.contains { word in moneyWords.contains { isForm(word, of: $0) } }
            || (ordering && words.contains { isForm($0, of: "order") })
            || (words.contains { isForm($0, of: "transfer") } && words.contains(where: fundsWords.contains))
        if definite { return looking ? .uncertain : .money }
        let lookedAt = looking && words.contains { word in lookedAtNouns.contains(where: word.hasPrefix) }
        let resembles = words.contains { word in moneyStems.contains(where: word.hasPrefix) }
        return resembles && !(lookedAt && !words.contains { word in moneyStems.filter { !lookedAtNouns.contains($0) }.contains(where: word.hasPrefix) })
            ? .uncertain : nil
    }

    // MARK: Shell

    /// Any rm (inside the Trash too: that empties it), unlink, srm or shred, find -delete, and emptying the Trash.
    /// Read from the raw line, so a deletion inside quotes or $( ) still counts.
    private static let deletingPatterns = [
        #"(?:^|[\s;&|(`'"])(?:\S*/)?(?:rm|unlink|srm|shred)(?=\s|$|[;&|)'"`])"#,
        #"\bfind\b.*\s-delete\b"#,
        #"(?i)\bempty\s+(?:the\s+)?trash\b"#,
    ]

    /// Programs that send mail.
    private static let mailers: Set<String> = ["mail", "mailx", "sendmail", "msmtp", "mutt", "ssmtp"]
    /// AppleScript aimed at Mail or Messages.
    private static let sendingScript = #"(?i)(application\s+(id\s+)?"(mail|messages|com\.apple\.mail|com\.apple\.mobilesms)")"#
    private static let rawSender = #"(?:^|[\s;&|(`'"])(?:\S*/)?(?:sendmail|mailx?|msmtp|mutt|ssmtp)(?=\s|$|[;&|)'"`])"#
    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "ksh"]
    /// xargs and timeout flags that take the next word as their value.
    private static let xargsValueFlags: Set<String> = ["-I", "-n", "-L", "-P", "-s", "-E", "-d", "-J", "-R", "-S"]
    private static let timeoutValueFlags: Set<String> = ["-s", "-k", "--signal", "--kill-after"]

    /// The programs a command runs, by file name, with their arguments: past VAR=value words and the env (and its
    /// -S string), command, exec, nohup, time, nice, timeout and xargs wrappers, and into `sh -c` scripts. A piece
    /// that can't be read word by word comes back with an empty name and its raw text.
    static func programs(_ words: [String], depth: Int = 0) -> [(name: String, arguments: [String])] {
        var rest = words[...]
        while let first = rest.first {
            let name = (first as NSString).lastPathComponent
            if first.contains("="), !first.hasPrefix("-"), !first.contains("/") {
                rest = rest.dropFirst()
                continue
            }
            switch name {
            case "command", "exec", "nohup", "time":
                rest = rest.dropFirst()
                while rest.first?.hasPrefix("-") == true { rest = rest.dropFirst() }
            case "nice":
                rest = rest.dropFirst()
                if rest.first == "-n" { rest = rest.dropFirst(2) } else if rest.first?.hasPrefix("-") == true { rest = rest.dropFirst() }
            case "timeout":
                rest = rest.dropFirst()
                while let flag = rest.first, flag.hasPrefix("-") { rest = rest.dropFirst(timeoutValueFlags.contains(flag) ? 2 : 1) }
                rest = rest.dropFirst()
            case "xargs":
                rest = rest.dropFirst()
                while let flag = rest.first, flag.hasPrefix("-") { rest = rest.dropFirst(xargsValueFlags.contains(flag) ? 2 : 1) }
            case "env":
                rest = rest.dropFirst()
                while let flag = rest.first, flag.hasPrefix("-") || flag.contains("=") {
                    if flag == "-S" || flag == "--split-string" || (flag.hasPrefix("-S") && flag.count > 2) {
                        let string = flag.count > 2 && !flag.hasPrefix("--") ? String(flag.dropFirst(2)) : rest.dropFirst().first ?? ""
                        let tail = rest.dropFirst(flag.count > 2 && !flag.hasPrefix("--") ? 1 : 2)
                        guard depth < 4, let split = ArisCommandPolicy.words(string) else { return [("", [string])] }
                        return programs(split + tail, depth: depth + 1)
                    }
                    rest = rest.dropFirst(flag == "-u" || flag == "-C" ? 2 : 1)
                }
            default:
                let arguments = Array(rest.dropFirst())
                if shells.contains(name), let flag = arguments.firstIndex(where: { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("c") }),
                   flag + 1 < arguments.count {
                    let script = arguments[flag + 1]
                    guard depth < 4 else { return [("", [script])] }
                    return (ArisCommandPolicy.segments(script) ?? [script]).flatMap { piece in
                        ArisCommandPolicy.words(piece).map { programs($0, depth: depth + 1) } ?? [("", [piece])]
                    }
                }
                return [(name, arguments)]
            }
        }
        return []
    }

    /// Whether a program sends something. A mailer definitely does (refused); a script for Mail or Messages, any
    /// network tool, or a piece that can't be read (empty name) searched raw only might (the user is asked).
    private static func sends(_ name: String, _ arguments: [String]) -> ArisHardLine? {
        let text = arguments.joined(separator: " ")
        if name.isEmpty {
            let found = text.range(of: rawSender, options: .regularExpression) != nil || text.range(of: sendingScript, options: .regularExpression) != nil
            return found ? .uncertain : nil
        }
        if mailers.contains(name) { return .mailSend }
        if name == "osascript" { return text.range(of: sendingScript, options: .regularExpression) != nil ? .uncertain : nil }
        // A network tool's options aren't parsed (config files, -K, -e, schemes…): every invocation asks.
        return networkTools.contains(name) ? .uncertain : nil
    }

    /// Programs that reach the network: any invocation, whatever its options, is `uncertain` (the user is asked, it is
    /// never learned or judged). Their options are deliberately not parsed.
    private static let networkTools: Set<String> = ["curl", "wget", "nc", "ncat", "socat", "ssh", "scp", "sftp", "rsync", "ftp", "telnet",
                                                    "aria2c", "http", "https"]

    private static func shellHardLine(_ command: String, tools: String) -> ArisHardLine? {
        let pieces = ArisCommandPolicy.segments(command) ?? [command]
        let found = pieces.flatMap { piece -> [ArisHardLine] in
            guard let words = ArisCommandPolicy.words(piece) else { return sends("", [piece]).map { [$0] } ?? [] }
            // `mail reply` only opens a draft in Mail: the user's card every time (never learned, standing or judged), not a send.
            if !tools.isEmpty, words.first == tools, words.count > 1, words[1] == "mail", ArisMailReplyWords.isReply(Array(words.dropFirst(2))) { return [.uncertain] }
            if !tools.isEmpty, words.first == tools, words.count > 1 { return words[1] == "mail" ? [.mailSend] : [] }
            return programs(words).compactMap { sends($0.name, $0.arguments) }
        }
        if found.contains(.mailSend) { return .mailSend }
        if deletingPatterns.contains(where: { command.range(of: $0, options: .regularExpression) != nil }) { return .permanentDelete }
        return found.isEmpty ? nil : .uncertain
    }

    // MARK: Browser tasks

    /// Korean as verb stems (주문해, not 주문 내역), English as whole words.
    private static let taskMoneyWords = ["주문해", "주문하", "구매해", "구매하", "구입해", "구입하", "결제", "송금", "이체", "구독해", "구독하", "기부", "후원",
                                     "buy", "purchase", "pay", "checkout", "check out", "place an order", "send money", "subscribe",
                                     "donate", "tip", "payout", "refund", "invoice", "add to cart"]
    private static let mailWords = ["메일", "이메일", "mail", "gmail", "email", "outlook"]
    private static let mailSendWords = ["보내", "전송", "발송", "send"]
    private static let mailReplyWords = ["답장", "전달", "reply", "forward"]
    private static let foreverWords = ["영구 삭제", "영구삭제", "완전히 삭제", "휴지통 비우", "permanently delete", "empty the trash", "empty trash"]

    /// A site task's words can only suggest money or a mail send: the user is asked (never refused, never learned).
    /// Every mention counts: "구매하지 말고" still names money.
    private static func taskHardLine(_ task: String) -> ArisHardLine? {
        if mentions(taskMoneyWords, in: task) { return .uncertain }
        let lowered = task.lowercased()
        let drafting = lowered.contains("초안") || lowered.contains("draft")
        if mailWords.contains(where: lowered.contains),
           mentions(mailSendWords, in: task)
            || (!drafting && mentions(mailReplyWords, in: task)) { return .uncertain }
        return mentions(foreverWords, in: task) ? .permanentDelete : nil
    }
}
