//
//  ArisTeammateGate.swift
//  aris-agent
//
//  Whether a Claude Code teammate may be launched, and where. The folder must be a real folder under the home folder,
//  resolved through any links, and not a protected place; a real folder outside the home folder (another disk, /tmp)
//  is never taken silently: the user's card names it (audit gate-20). A launch goes ahead without the user only when it is one of the
//  jobs his own untainted turn just dispatched (ArisTeammateTurns), that turn carried no outside text in its context or
//  memory, and neither the brief nor the user's words name an outbound step; anything else, any scheduled run, and any
//  caller without such a turn, is asked first. The card goes only to the app (through the inbox), never back to the
//  caller, and only the app itself may answer it. At most two sessions run at once.
//  The outbound list is advisory: it can't name every way out. The backstops are Claude Code's own permission prompts
//  in the visible terminal and the vouching rules.
//

import Foundation

enum ArisTeammateGate {
    /// A model-written Claude Code brief is a page or two at most.
    static let maxPrompt = 20_000
    /// Lines of the prompt shown on the card (the whole prompt is behind 전체 보기).
    static let cardLines = 3
    /// Launch questions' ids start with this; only the app may answer them.
    static let questionPrefix = "teammate-"
    /// What the job says when it opens without a card: from then on only Claude Code's own questions stop it.
    static let autoNotice = "Claude Code가 스스로 묻는 것 외에는 확인 없이 진행해요"
    /// What the caller hears while the card waits for the user in the app (never the card or its id).
    static let waitingNotice = "확인 기다리는 중"

    /// What the caller's stream gets: a launch that needs the user only says it waits; the card itself goes to the app.
    static func requesterReply(needsYes: Bool) -> ArisAgentReply {
        .status(needsYes ? waitingNotice : autoNotice)
    }

    /// A yes or no to a card counts only from the Aris app: alive as it said, signed as com.lumenjsn.aris by Aris's own
    /// team (`bundleId` is what ArisPeer read from the process's code signature, never a name it gives itself), holding
    /// this connection, and not the connection that asked for a launch. Nil when all hold; else the first that failed.
    static func appCheck(alive: Bool, bundleId: String?, ownsSocket: Bool, sameConnection: Bool) -> ArisPeer.Failure? {
        if !alive { return .alive }
        if bundleId != ArisPeer.appBundleId { return .bundle }
        if !ownsSocket { return .socket }
        return sameConnection ? .sameConnection : nil
    }

    static func isApp(alive: Bool, bundleId: String?, ownsSocket: Bool, sameConnection: Bool) -> Bool {
        appCheck(alive: alive, bundleId: bundleId, ownsSocket: ownsSocket, sameConnection: sameConnection) == nil
    }

    /// Whether a turn may vouch for the Claude Code jobs it dispatches: the user's own main turn, asked by the Aris app
    /// itself (ArisPeer, checked while its connection is open), with nothing others wrote in its context or memory.
    static func vouches(mainTurn: Bool, fromApp: Bool, context: String?, memory: String?) -> Bool {
        mainTurn && fromApp && mayVouch(context: context, memory: memory)
    }

    /// The jobs a turn's answer records for vouching (and so whether the app gets a {"turn"} line): only for a turn
    /// that vouches, whose conversation took in no outside text, and whose answer dispatches a Claude Code job.
    static func turnSpecs(vouches: Bool, tainted: Bool, answer: String) -> [ArisJobSpec]? {
        guard vouches, !tainted, let specs = ArisDispatch.parse(answer, teammateIds: [ArisTeammate.claudeCodeId]),
              specs.contains(where: { $0.assignee == .teammate(ArisTeammate.claudeCodeId) }) else { return nil }
        return specs
    }

    /// A turn may vouch for its jobs only when its context and memory carry nothing others wrote: every context line
    /// is the time, the front app or an empty calendar, and nothing is remembered. Calendar events, music, recent
    /// turns, background tasks, or anything new count as outside text.
    static func mayVouch(context: String?, memory: String?) -> Bool {
        guard (memory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let plain = [#"^now: "#, #"^front app: "#, #"^calendar: nothing in the next \d+ days$"#, #"^today \([^)\n]*\): nothing$"#]
        return (context ?? "").split(whereSeparator: \.isNewline).allSatisfy { line in
            plain.contains { line.range(of: $0, options: .regularExpression) != nil }
        }
    }

    /// Outbound steps in the brief and in the user's own words for that turn, each once.
    static func outbound(prompt: String, request: String?) -> [String] {
        var seen = Set<String>()
        return (ArisClaudeLaunch.outboundSteps(in: prompt) + ArisClaudeLaunch.outboundSteps(in: request ?? "")).filter { seen.insert($0).inserted }
    }

    /// The folder to work in, resolved; nil when it isn't an existing folder under `home` (not `home` itself), or it is
    /// (or leads through a link into) a protected place or ~/Library.
    static func folder(_ raw: String, home: String) -> String? {
        guard let (resolved, realHome) = resolvedFolder(raw, home: home) else { return nil }
        let inside = ArisProtectedPlaces.key(resolved), root = ArisProtectedPlaces.key(realHome)
        guard startsWith(inside, root + "/"), !ArisProtectedPlaces.blocks(resolved, home: realHome) else { return nil }
        let library = ArisProtectedPlaces.key(realHome + "/Library")
        guard !isExactly(inside, library), !startsWith(inside, library + "/") else { return nil }
        return resolved
    }

    /// `raw` as an existing folder, resolved through any links, with the home folder resolved the same way; nil when it
    /// isn't a full path to a real folder, or carries control characters (before or after resolving).
    private static func resolvedFolder(_ raw: String, home: String) -> (path: String, home: String)? {
        guard !raw.isEmpty, !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let expanded = isExactly(raw, "~") ? home : startsWith(raw, "~/") ? home + dropScalar(raw) : raw
        guard startsWith(expanded, "/"), let resolved = realPath(expanded), let realHome = realPath(home),
              !resolved.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        var info = stat()
        guard stat(resolved, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
        return (resolved, realHome)
    }

    /// The system's own places: Claude Code is never opened in one, or in anything under one.
    static let systemPlaces = ["/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/dev", "/cores", "/Network",
                               "/private/etc", "/private/var/db", "/private/var/root", "/private/var/log", "/private/var/run"]
    /// Folders that only hold other places (every disk, the system's private folders): never the folder itself.
    static let holdingPlaces = ["/Volumes", "/private", "/private/var", "/Users"]

    /// A real folder outside the home folder (another disk, /tmp, a shared folder), resolved: launching there was
    /// refused outright (audit gate-20) and now goes to the user's card, which names the folder. Nil when it isn't one, or
    /// it is the system's own place, or a folder that holds the home folder ("/", "/Users": everything of his would
    /// be "inside the project"). The home folder itself and what is under it are `folder`'s to decide.
    static func outsideFolder(_ raw: String, home: String) -> String? {
        guard let (resolved, realHome) = resolvedFolder(raw, home: home) else { return nil }
        let inside = ArisProtectedPlaces.key(resolved), root = ArisProtectedPlaces.key(realHome)
        guard !isExactly(inside, "/"), !isExactly(inside, root), !startsWith(inside, root + "/"), !startsWith(root, inside + "/") else { return nil }
        let under = { (place: String) in isExactly(inside, ArisProtectedPlaces.key(place)) || startsWith(inside, ArisProtectedPlaces.key(place) + "/") }
        guard !systemPlaces.contains(where: under), !holdingPlaces.contains(where: { isExactly(inside, ArisProtectedPlaces.key($0)) }) else { return nil }
        return resolved
    }

    /// Where a launch runs: a folder under the home folder, or one outside it that the user must be asked about.
    struct Place: Equatable {
        let path: String
        let outsideHome: Bool
    }

    static func place(_ raw: String, home: String) -> Place? {
        if let inside = folder(raw, home: home) { return Place(path: inside, outsideHome: false) }
        return outsideFolder(raw, home: home).map { Place(path: $0, outsideHome: true) }
    }

    /// What the launch card says of a folder outside the home folder.
    static let outsideHomeNote = "⚠️ 홈 폴더 밖의 폴더예요"

    private static func realPath(_ path: String) -> String? {
        guard let found = realpath(path, nil) else { return nil }
        defer { free(found) }
        return String(cString: found)
    }

    /// The prompt becomes `claude`'s one argument and its first message. One that starts with "-" would be read as an
    /// option ("--permission-mode=bypassPermissions"); one whose first character is a Claude Code input shortcut
    /// ("!" runs a shell command without its permission prompt, "/" a slash command, "#" or "@" something else) might
    /// be taken as that. Neither may be what `claude` gets.
    /// Spaces and invisible format characters (a byte-order mark U+FEFF, zero-width spaces and joiners) are skipped
    /// to find the first real character. What `claude` gets is the prompt file, which always starts with a fixed line
    /// (ArisTeammateLauncher.argument): that is what this is asked about, so a brief the user's request begins with a
    /// path, "#123" or "@src/…" launches (audit gate-20), and the argument still never starts with any of these.
    static func isSafePrompt(_ prompt: String) -> Bool {
        guard !startsWith(prompt, "-"),
              let first = prompt.unicodeScalars.first(where: { !$0.properties.isWhitespace && $0.properties.generalCategory != .format })
        else { return false }
        return !"-!/#@&".unicodeScalars.contains(first)
    }

    /// An @-mention of a file outside the project ("@~/.ssh/id_rsa", "@/etc/hosts", "@src/../../x", "@\"~/x\"") would pull
    /// it into Claude Code's context: such a brief is refused. Two layers, both failing closed:
    /// - anywhere in the brief, "@" (optionally followed by a quote) and then "~", "/" or "..", an "@\"" / "@'" that
    ///   is never closed, or a ".." segment after an "@" in the same word;
    /// - anywhere, an "@\"…\"" or "@'…'" whose quoted text has a ".." segment or starts with "~" or "/";
    /// - every mention Claude Code could read, as a superset of its own parser: any "@" not right after an email
    ///   character (`isMentionStart`). Its bare token (up to the next JavaScript whitespace) and, when a quote follows the
    ///   "@", its quoted token, each in every form Claude Code opens (`openedForms`: as written, with trailing
    ///   punctuation or particles trimmed, and before a "#L1-5" suffix), resolved against the (resolved) working folder
    ///   through any links; a ".." segment, a form that lands outside the folder, or a token longer than `maxMention`,
    ///   refuses the brief.
    /// An import alias written like a mention ("@/components/Header.tsx") is left out first (`withoutAliases`).
    static func mentionsOutsideFiles(_ brief: String, cwd: String, home: String, exists: (String) -> Bool = existsOnDisk) -> Bool {
        let prompt = withoutAliases(brief, cwd: cwd, home: home, exists: exists)
        if prompt.range(of: Self.rootOrClimb, options: .regularExpression) != nil || hasUnclosedQuote(prompt)
            || climbsAfterAt(prompt) || quotedClimbsOrRoots(prompt) { return true }
        guard let tokens = mentions(in: prompt) else { return true }
        let forms = Set(tokens.flatMap(openedForms))
        return forms.contains { isResourceMention($0) || !isInside($0, cwd: cwd, home: home) }
    }

    /// Something is at this path (a link that leads nowhere counts).
    static func existsOnDisk(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// What stands in for an import alias while the brief is checked: plain letters, never a mention.
    static let aliasMark = "alias"

    /// A web project's import alias ("@/components/Header.tsx", the "@/" of a Next.js or Vite project) looks like a
    /// mention of a file at the top of the disk, and such a brief was refused (audit gate-20). It can't name any file
    /// outside the project when, in every form Claude Code could open (`openedForms`): the disk has nothing at that
    /// path's first folder ("/components": so there is no file there to read), the same text under the project folder
    /// stays inside it (through any links), no ".." climbs, no part is empty or ".", and the word holds no second "@".
    /// Only then is it an alias.
    /// "@/etc/hosts", "@/Users/…", "@/tmp/x" name real places and are not.
    static func isAlias(_ token: String, cwd: String, home: String, exists: (String) -> Bool = existsOnDisk) -> Bool {
        guard startsWith(token, "/"), !token.unicodeScalars.contains("@"), token.unicodeScalars.count <= maxMention else { return false }
        return openedForms(token).allSatisfy { form in
            guard startsWith(form, "/"), !climbs(form) else { return false }
            let parts = form.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) }
            // "/x/…": parts[0] is empty, parts[1] the first folder. A bare "/", or an empty or "." part anywhere ("//x",
            // "/./etc", "/x/"), is no alias: the path is taken only as it is written.
            guard parts.count >= 2, parts.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." }), !exists("/" + parts[1]) else { return false }
            return isInside("./" + dropScalar(form), cwd: cwd, home: home)
        }
    }

    /// The brief with every import alias (`isAlias`) replaced by `aliasMark`, for the checks only: what Claude Code is
    /// told is never changed.
    static func withoutAliases(_ prompt: String, cwd: String, home: String, exists: (String) -> Bool = existsOnDisk) -> String {
        let scalars = Array(prompt.unicodeScalars)
        var out = String.UnicodeScalarView()
        var at = 0
        while at < scalars.count {
            guard scalars[at] == "@", at + 1 < scalars.count, scalars[at + 1] == "/" else {
                out.append(scalars[at])
                at += 1
                continue
            }
            // The whole word after the "@" (a word longer than a mention may be is never an alias: nothing is cut short).
            var end = at + 1
            while end < scalars.count, !isMentionSpace(scalars[end]), end - at - 1 <= maxMention { end += 1 }
            let whole = end == scalars.count || isMentionSpace(scalars[end])
            if whole, isAlias(String(String.UnicodeScalarView(scalars[(at + 1)..<end])), cwd: cwd, home: home, exists: exists) {
                out.append(contentsOf: aliasMark.unicodeScalars)
                at = end
            } else {
                out.append(scalars[at])
                at += 1
            }
        }
        return String(out)
    }

    /// An MCP resource mention ("fs:file:///etc/hosts", "1fs:x", "my.server:x"): a ":" before the form's first "/",
    /// followed by something other than whitespace, unless what follows is only a line reference ("README.md:12",
    /// "main.swift:3-9", trailing punctuation aside). The configured server names aren't read: every such form counts.
    static func isResourceMention(_ form: String) -> Bool {
        let scalars = Array(form.unicodeScalars)
        guard let colon = scalars.firstIndex(of: ":") else { return false }
        if let slash = scalars.firstIndex(of: "/"), slash < colon { return false }
        let rest = Array(scalars[(colon + 1)...])
        guard let next = rest.first, !isMentionSpace(next) else { return false }
        var reference = rest
        while let last = reference.last, !(last.isASCII && (last.properties.isAlphabetic || ("0"..."9").contains(last) || last == "_")) {
            reference.removeLast()
        }
        return String(String.UnicodeScalarView(reference)).range(of: #"^[0-9]+(-[0-9]+)?$"#, options: .regularExpression) == nil
    }

    /// A mention starts at any "@" except one right after a character an email address can hold before its "@"
    /// ("a@b.c", "user@example.com"): spaces, CJK marks (。、？！), brackets, punctuation and other letters all start one.
    static func isMentionStart(after previous: Unicode.Scalar?) -> Bool {
        guard let previous else { return true }
        let email = previous.isASCII && (previous.properties.isAlphabetic || ("0"..."9").contains(previous) || "._%+-".unicodeScalars.contains(previous))
        return !email
    }

    /// "@", or "@" and a quote with any JavaScript whitespace after it (Claude Code trims the path), then "~", "/" or "..".
    static let rootOrClimb = #"@(["'][\t\n\u000B\f\r \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]*)?(~|/|\.\.)"#

    // Path text is compared by Unicode scalars, as Claude Code (JavaScript) does, never by Characters: a combining
    // mark after "~", "/" or "#" would otherwise hide it.
    static func startsWith(_ text: String, _ prefix: String) -> Bool { text.unicodeScalars.starts(with: prefix.unicodeScalars) }
    static func isExactly(_ text: String, _ other: String) -> Bool { text.unicodeScalars.elementsEqual(other.unicodeScalars) }
    private static func dropScalar(_ text: String) -> String { String(String.UnicodeScalarView(text.unicodeScalars.dropFirst())) }

    /// A ".." segment, split on "/" by scalars.
    static func climbs(_ path: String) -> Bool {
        path.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false).contains { $0.elementsEqual("..".unicodeScalars) }
    }

    /// `text` without JavaScript whitespace (String.prototype.trim's set) at either end, as Claude Code trims a path.
    static func spaceTrimmed(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        while let first = scalars.first, isMentionSpace(first) { scalars.removeFirst() }
        while let last = scalars.last, isMentionSpace(last) { scalars.removeLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    /// The paths Claude Code may open for a mention's token: as written; with trailing characters outside [0-9A-Za-z_]
    /// trimmed (punctuation, Korean particles: "hostslink.", "keys를"); and the part before the first "#" (a line
    /// range, "#L1-5", split by scalar as Claude Code does, so a combining mark after "#" doesn't hide it), as is and
    /// trimmed; and each of those with surrounding whitespace trimmed (Claude Code trims before it opens). Without
    /// repeats or empty ones.
    static func openedForms(_ token: String) -> [String] {
        func trimmed(_ text: String) -> String {
            var scalars = Array(text.unicodeScalars)
            while let last = scalars.last, !(last.isASCII && (last.properties.isAlphabetic || ("0"..."9").contains(last) || last == "_")) {
                scalars.removeLast()
            }
            return String(String.UnicodeScalarView(scalars))
        }
        let beforeHash = token.unicodeScalars.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { String(String.UnicodeScalarView($0)) } ?? token
        var seen = Set<String>()
        return [token, trimmed(token), beforeHash, trimmed(beforeHash)].flatMap { [$0, spaceTrimmed($0)] }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Any quoted "@\"…\"" or "@'…'" (wherever its "@" is) whose text climbs ("..") or starts at "~" or "/". An unclosed
    /// or overlong one counts too.
    private static func quotedClimbsOrRoots(_ prompt: String) -> Bool {
        let scalars = Array(prompt.unicodeScalars)
        var at = 0
        while at + 1 < scalars.count {
            defer { at += 1 }
            guard scalars[at] == "@", scalars[at + 1] == "\"" || scalars[at + 1] == "'" else { continue }
            let quote = scalars[at + 1]
            var close = at + 2
            while close < scalars.count, scalars[close] != quote {
                close += 1
                if close - at - 2 > maxMention { return true }
            }
            guard close < scalars.count else { return true }
            let text = spaceTrimmed(String(String.UnicodeScalarView(scalars[(at + 2)..<close])))
            if startsWith(text, "~") || startsWith(text, "/") || climbs(text) { return true }
        }
        return false
    }

    static let maxMention = 1_024
    /// More mentions than a real brief would ever hold: refused, which also keeps the scan's work bounded.
    static let maxMentions = 200

    /// A ".." path segment after an "@" in the same word, wherever that "@" is ("(@src/../../x)", "a@b/../c"), in one
    /// pass: Claude Code might read an "@" after punctuation as a mention too.
    private static func climbsAfterAt(_ prompt: String) -> Bool {
        var sawAt = false, segment = 0, dots = 0
        for scalar in prompt.unicodeScalars {
            if isMentionSpace(scalar) || scalar == "/" {
                if sawAt && segment == 2 && dots == 2 { return true }
                if scalar != "/" { sawAt = false }
                segment = 0
                dots = 0
                continue
            }
            if scalar == "@" { sawAt = true }
            segment += 1
            if scalar == "." { dots += 1 }
        }
        return sawAt && segment == 2 && dots == 2
    }

    /// An "@\"" or "@'" with no matching quote after it: the last one decides (one closed means every earlier one is).
    private static func hasUnclosedQuote(_ prompt: String) -> Bool {
        let scalars = Array(prompt.unicodeScalars)
        return ["\"", "'"].map { Unicode.Scalar($0)! }.contains { (quote: Unicode.Scalar) in
            guard let last = scalars.indices.dropLast().last(where: { scalars[$0] == "@" && scalars[$0 + 1] == quote }) else { return false }
            return !scalars[(last + 2)...].contains(quote)
        }
    }

    /// What JavaScript's \s matches (Claude Code splits mentions on it): ASCII whitespace, NBSP, the Unicode spaces,
    /// the line and paragraph separators, and the byte-order mark.
    static func isMentionSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        default: return false
        }
    }

    /// Every token a mention could name, in one pass over the scalars: for each "@" that starts a mention
    /// (`isMentionStart`), the text up to the next space, and, when a quote follows the "@", the text up to its closing
    /// quote. Nil when a token runs past `maxMention`, a quote never closes, or there are more than `maxMentions`.
    static func mentions(in prompt: String) -> [String]? {
        let scalars = Array(prompt.unicodeScalars)
        func text(_ range: Range<Int>) -> String { String(String.UnicodeScalarView(scalars[range])) }
        var tokens: [String] = []
        var count = 0
        for at in scalars.indices where scalars[at] == "@" && isMentionStart(after: at == 0 ? nil : scalars[at - 1]) {
            count += 1
            if count > maxMentions { return nil }
            var end = at + 1
            while end < scalars.count, !isMentionSpace(scalars[end]) {
                end += 1
                if end - at - 1 > maxMention { return nil }
            }
            tokens.append(text((at + 1)..<end))
            guard at + 1 < scalars.count, scalars[at + 1] == "\"" || scalars[at + 1] == "'" else { continue }
            let quote = scalars[at + 1]
            var close = at + 2
            while close < scalars.count, scalars[close] != quote {
                close += 1
                if close - at - 2 > maxMention { return nil }
            }
            guard close < scalars.count else { return nil }
            tokens.append(text((at + 2)..<close))
        }
        return tokens
    }

    private static func isInside(_ mention: String, cwd: String, home: String) -> Bool {
        guard !climbs(mention) else { return false }
        let full: String
        if isExactly(mention, "~") || startsWith(mention, "~/") {
            full = home + dropScalar(mention)
        } else if startsWith(mention, "~") {
            return false
        } else {
            full = startsWith(mention, "/") ? mention : cwd + "/" + mention
        }
        let landed = resolvedThroughLinks((full as NSString).standardizingPath)
        let inside = ArisProtectedPlaces.key(landed), root = ArisProtectedPlaces.key(cwd)
        return isExactly(inside, root) || startsWith(inside, root + "/")
    }

    /// `path` with its deepest existing part resolved through links (the rest, not there yet, appended as written).
    private static func resolvedThroughLinks(_ path: String) -> String {
        var head = path, tail: [String] = []
        while head != "/" && !head.isEmpty {
            if let real = realPath(head) { return ([real] + tail.reversed()).joined(separator: "/") }
            tail.append((head as NSString).lastPathComponent)
            head = (head as NSString).deletingLastPathComponent
        }
        return path
    }

    /// The folder still resolves to exactly what was checked (nothing was swapped for a link in between).
    /// `outsideHome`: the folder was one outside the home folder (`outsideFolder`), and must still be exactly that.
    static func isUnchanged(_ cwd: String, home: String, outsideHome: Bool = false) -> Bool {
        (outsideHome ? outsideFolder(cwd, home: home) : folder(cwd, home: home)) == cwd
    }

    /// The user is asked unless their own turn vouches for this launch and nothing in it goes outside the Mac. A folder
    /// outside the home folder is always asked about, vouched or not.
    static func needsYes(vouched: Bool, outbound: [String], outsideHome: Bool = false) -> Bool {
        !vouched || !outbound.isEmpty || outsideHome
    }

    /// The card's last lines: a folder outside the home folder first, then why a vouched launch asks (versionNote).
    static func cardNote(outsideHome: Bool, version: String?) -> String? {
        let lines = (outsideHome ? [outsideHomeNote] : []) + (version.map { [$0] } ?? [])
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// The card: where it runs, the start of what it was told, and the outbound steps. Never a proposal: a launch is
    /// never learned as a standing permission.
    /// `note`: why it asks when it otherwise wouldn't (versionNote).
    static func card(id: String, cwd: String, prompt: String, outbound: [String], note: String? = nil) -> ArisConfirmation {
        let visible = flaggingInvisibles(prompt), folder = flaggingInvisibles(cwd)
        let lines = visible.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let opening = lines.prefix(cardLines).map { $0.count > 120 ? String($0.prefix(120)) + "…" : $0 }
        // Nothing hides past the first lines: the card says how many more there are (전체 보기 shows them all).
        let more = lines.count > cardLines ? ["(+\(lines.count - cardLines)줄 더)"] : []
        let steps = (outbound.isEmpty ? "" : "\n바깥으로 나가는 일: " + outbound.joined(separator: ", ")) + (note.map { "\n" + $0 } ?? "")
        return ArisConfirmation(id: id, title: "Claude Code 열기", detail: "폴더: \(folder)\n" + (opening + more).joined(separator: "\n") + steps,
                                full: "폴더: \(folder)\n\n\(visible)" + steps)
    }

    /// Every invisible format or bidi control character anywhere in the text shown as a visible mark ("⟦U+202E⟧"), so
    /// a launch card can't hide or reorder what Claude Code is told.
    static func flaggingInvisibles(_ text: String) -> String {
        String(text.unicodeScalars.reduce(into: String.UnicodeScalarView()) { out, scalar in
            let bidi = (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
                || [0x200E, 0x200F, 0x061C].contains(scalar.value)
            if scalar.properties.generalCategory == .format || bidi {
                out.append(contentsOf: "⟦U+\(String(format: "%04X", scalar.value))⟧".unicodeScalars)
            } else {
                out.append(scalar)
            }
        })
    }

    // MARK: - The claude binary

    /// Claude Code versions whose mention parser and path handling the gate was checked against (a differential run
    /// against that version's own parser). A newer one launches only after the user's yes until it is checked and added.
    static let testedClaudeVersions: Set<String> = ["2.1.317"]

    /// The claude the launch runs: ~/.local/bin/claude resolved, which must be a version under
    /// ~/.local/share/claude/versions named x.y.z (the installer's layout). Nil otherwise. Never runs `claude --version`.
    static func claudeBinary(home: String) -> (path: String, version: String)? {
        guard let binary = realPath(home + "/.local/bin/claude"), let versions = realPath(home + "/.local/share/claude/versions"),
              isExactly((binary as NSString).deletingLastPathComponent, versions) else { return nil }
        let version = (binary as NSString).lastPathComponent
        guard version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else { return nil }
        var info = stat()
        guard stat(binary, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return (binary, version)
    }

    /// A launch goes ahead without asking only for the user's vouched words and a checked binary at a tested version.
    static func launchVouched(words: String?, binary: (path: String, version: String)?) -> Bool {
        guard words != nil, let binary else { return false }
        return testedClaudeVersions.contains(binary.version)
    }

    /// What the card says when only the version keeps a vouched launch from going ahead on its own.
    static func versionNote(words: String?, binary: (path: String, version: String)?) -> String? {
        guard words != nil, !launchVouched(words: words, binary: binary) else { return nil }
        return "Claude Code가 업데이트돼서 (버전 \(binary?.version ?? "확인 불가")) 확인할게요"
    }
}

/// Main turns the user started (POST /ask, no screen, no outside text) that dispatched Claude Code jobs, kept for
/// this launch of the agent only (so an id from an earlier run means nothing). A turn vouches for each of its own
/// jobs once, word for word, for ten minutes; ids are UUIDs the brains never see.
struct ArisTeammateTurns {
    static let lifetime: TimeInterval = 600
    static let maxTurns = 50

    private struct Turn {
        let at: Date
        /// The user's own words for the turn.
        let request: String
        var jobs: [(prompt: String, cwd: String?)]
    }

    private var turns: [String: Turn] = [:]

    mutating func record(_ id: String, specs: [ArisJobSpec], request: String, at: Date) {
        let jobs = specs.filter { $0.assignee == .teammate(ArisTeammate.claudeCodeId) }.map { (prompt: $0.prompt, cwd: $0.cwd) }
        guard !jobs.isEmpty else { return }
        turns = turns.filter { at.timeIntervalSince($0.value.at) <= Self.lifetime }
        if turns.count >= Self.maxTurns, let oldest = turns.min(by: { $0.value.at < $1.value.at })?.key { turns[oldest] = nil }
        turns[id] = Turn(at: at, request: request, jobs: jobs)
    }

    /// The user's words for the turn (and the job is used up) when `turn` dispatched exactly this job and isn't older than
    /// ten minutes; nil otherwise.
    mutating func vouch(turn: String?, prompt: String, cwd: String?, now: Date) -> String? {
        guard let turn, var record = turns[turn] else { return nil }
        guard now >= record.at, now.timeIntervalSince(record.at) <= Self.lifetime else {
            turns[turn] = nil
            return nil
        }
        guard let index = record.jobs.firstIndex(where: { $0.prompt == prompt && $0.cwd == cwd }) else { return nil }
        record.jobs.remove(at: index)
        turns[turn] = record.jobs.isEmpty ? nil : record
        return record.request
    }
}

/// Claude Code sessions running at once: at most `capacity`; the rest wait in order.
struct ArisTeammateSlots {
    static let capacity = 2

    private(set) var running: [UUID] = []
    private(set) var waiting: [UUID] = []

    /// True: it runs now. False: it waits for a slot.
    mutating func claim(_ job: UUID) -> Bool {
        guard running.count < Self.capacity else {
            waiting.append(job)
            return false
        }
        running.append(job)
        return true
    }

    /// The job is over (or stopped waiting): the waiting job that gets its slot, if any.
    mutating func release(_ job: UUID) -> UUID? {
        if let index = waiting.firstIndex(of: job) {
            waiting.remove(at: index)
            return nil
        }
        guard let index = running.firstIndex(of: job) else { return nil }
        running.remove(at: index)
        guard !waiting.isEmpty else { return nil }
        let next = waiting.removeFirst()
        running.append(next)
        return next
    }
}
