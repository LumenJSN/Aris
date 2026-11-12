//
//  ArisRiskPolicy.swift
//  aris-agent
//
//  Every action an AI takes for Aris passes here first: reading and small local changes
//  run at once, anything that leaves the Mac, can't be undone or is unknown waits for the
//  user's yes in the notch, and a few things (sudo, disks, security, Aris's own setup) are
//  never done. A "critical" turn (Jev: sending, deleting, money) only ever asks more.
//  The words come from the AI, which can be steered by web pages and mail it reads, so this
//  is deliberately plain code, not another AI's judgement.
//

import Foundation

enum ArisRisk: String, Equatable {
    /// `countdown`: a message the user dictated; Aris says it and sends unless stopped (ArisRiskPolicy+Dictation).
    case auto, countdown, confirm, never
}

enum ArisAction: Equatable {
    /// A shell command (already unwrapped from `zsh -lc`).
    case shell(String)
    /// Files a patch writes.
    case fileChange([String])
    /// A tool from an MCP server or app (Notion, Gmail…).
    case mcp(server: String, tool: String)
    /// Computer use asking to work in an app.
    case computerUse(app: String)
    /// A task handed to Aside, the browser agent working on the user's logged-in sites.
    case browserTask(String)
}

enum ArisRiskPolicy {
    /// `request`: the user's own words for this turn (from the microphone), for telling a dictated message apart.
    static func risk(of action: ArisAction, tools: String, home: String, critical: Bool = false, request: String = "") -> ArisRisk {
        switch action {
        case .shell(let command): return shell(command, tools: tools, home: home, critical: critical, request: ArisMemoryText.ownWords(request))
        case .fileChange(let paths): return files(paths, home: home)
        // The computer-use runtime runs code that can read anything: always asked, never by its tool's name.
        case .mcp(let server, let tool): return server == computerUseRepl ? .confirm : mcpTool(tool)
        // Every app can run code or send from its menus, and computer use reads the screen: always asked. Websites are
        // Aside's: never computer use in a browser.
        case .computerUse(let app): return computerUseIsNever([app]) || isBrowser(name: app) ? .never : .confirm
        // Only a plain lookup runs without a card (security review H1): anything else, acting or unclear, asks.
        case .browserTask(let task): return critical || !isLookup(task) ? .confirm : .auto
        }
    }

    /// Why the policy rates an action never, in words for the audit, the ledger and the brain (QA live on b9c766bc: a
    /// never with no reason anywhere). Follows `risk(of:)`'s own order; a never it can't place says so.
    static func neverReason(_ action: ArisAction, tools: String, home: String, critical: Bool = false, request: String = "") -> String {
        switch action {
        case .shell(let command): return shellNeverReason(command, tools: tools, home: home, critical: critical, request: request)
        case .computerUse(let app): return isBrowser(name: app) ? "computer use in a browser (websites are Aside's)" : "computer use is never in \(app) (the never-list)"
        case .fileChange: return "a file change in a protected place"
        case .mcp(_, let tool): return "the tool \(tool) is on the never-list"
        case .browserTask: return "a browser task Aris never does"
        }
    }

    private static func shellNeverReason(_ command: String, tools: String, home: String, critical: Bool, request: String) -> String {
        let scanned = withoutPlainText(command, tools: tools)
        let readsOnly = ArisCommandPolicy.words(command).flatMap(readOnlyForm) != nil
        if isNever(withoutPlainText(ArisDesktopShell.commandLine(command, tools: tools), tools: tools), readsOnly: readsOnly) { return "a never-list command or pattern (sudo, rm -rf of home, a computer-use runtime…)" }
        if drivesCalendarApp(scanned, tools: tools) { return "Calendar or Reminders driven by keys or AppleScript (only aris-tools event|remind)" }
        if namesArisSecret(scanned, tools: tools) { return "it names Aris's own token or keys" }
        if let problem = desktopProblem(command, tools: tools) { return problem }
        if barePathProblem(command, tools: tools) != nil { return barePathReason }
        if let pieces = ArisCommandPolicy.segments(command), pieces.count > 1,
           let never = pieces.first(where: { shell($0, tools: tools, home: home, critical: critical, request: request) == .never }) {
            return "one of the chained commands: " + shellNeverReason(never, tools: tools, home: home, critical: critical, request: request)
        }
        return "the command policy's never-list for this command"
    }

    // MARK: - Browser tasks (Aside)

    /// Words for doing something on a site rather than looking: any of them (not negated as its own predicate) asks.
    /// English matches by prefix, each word of a phrase from its start (deleting, cancelling, signing up; "bookmark" too,
    /// which only asks more); stems drop a final e (delet, sav) so every form is caught.
    static let actingWords = [
        "보내", "전송", "주문", "구매", "구입", "결제", "삭제", "지워", "지우", "올려", "게시", "포스팅", "예약", "제출", "신청",
        "가입", "등록", "취소", "송금", "이체", "답장", "댓글", "팔로우", "좋아요", "업로드", "공유", "탈퇴", "구독",
        "로그인", "장바구니", "입력", "승인", "동의", "해지", "변경", "수정", "비밀번호", "작성", "저장", "차단",
        "클릭", "선택", "추가", "담아", "넣어", "환불", "반품", "신고", "참여", "투표", "다운로드", "남겨",
        "send", "sent", "order", "bought", "purchas", "paid", "checkout", "check out", "check in", "delet", "remov",
        "publish", "book", "reserv", "submit", "sign up", "regist", "cancel", "transfer", "reply", "replied", "comment",
        "follow", "unfollow", "upload", "subscrib", "unsubscrib", "log in", "login", "sign in", "add to cart", "accept",
        "confirm", "chang", "password", "email", "tweet", "writ", "wrote", "fill", "apply", "applied", "invit", "messag",
        "updat", "block", "select", "choos", "chose", "click", "creat", "download", "claim", "redeem", "renew", "return",
        "refund", "approv", "install", "enabl", "disabl", "withdraw",
    ]

    /// Short acting words matched as whole words in their forms (follow-up 4: "address", "settings", "payment", "postal"
    /// and "cartoon" don't ask): the word, -s/-es/-ed/-d/-ing, a doubled last letter (setting, putting) and a dropped e
    /// (leaving, saving).
    static let actingWholeWords = ["add", "set", "put", "pay", "buy", "leave", "join", "like", "save", "share", "vote", "post", "cart",
                                   "enter", "edit"]

    static func wholeWordPattern(_ word: String) -> String {
        let base = NSRegularExpression.escapedPattern(for: word)
        var forms = [base + "(s|es|ed|d|ing)?", base + NSRegularExpression.escapedPattern(for: String(word.suffix(1))) + "(ed|ing)"]
        if word.hasSuffix("e") { forms.append(NSRegularExpression.escapedPattern(for: String(word.dropLast())) + "ing") }
        return "\\b(?:" + forms.joined(separator: "|") + ")\\b"
    }

    /// Words that ask only to look (security review H1): a task runs without a card only with one of these and no
    /// acting word. Not list, check, review, price or read on their own (or 확인, 리뷰, 가격, 읽어, 보여): they come with
    /// actions too ("check in", "leave a review", "set the price").
    static let lookupWords = [
        "찾아", "알려", "검색", "비교", "얼마", "언제", "어디", "뭐야", "알아봐", "최저가",
        "look up", "find", "search", "compare", "what", "when", "where", "how much", "check the price", "check prices",
    ]

    /// A plain lookup: it names a lookup and no acting word is left once each word's own negation is taken off.
    static func isLookup(_ task: String) -> Bool {
        let text = task.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return taskMentions(lookupWords, in: text, negatable: false, prefix: false) && !taskMentions(actingWords, in: text, negatable: true, prefix: true)
            && !taskMentions(actingWholeWords, in: text, negatable: true, prefix: false, whole: true)
    }

    /// One of `words` in `text`; `negatable`: a mention negated as its own predicate doesn't count. English: `prefix`, each
    /// word from its start with anything after; else whole words with their -s, -es, -ed, -d and -ing forms.
    private static func taskMentions(_ words: [String], in text: String, negatable: Bool, prefix: Bool, whole: Bool = false) -> Bool {
        words.contains { word in
            let english = word.unicodeScalars.first.map { $0.isASCII } == true
            let pieces = word.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = whole ? wholeWordPattern(word) : !english ? NSRegularExpression.escapedPattern(for: word)
                : prefix ? "\\b" + pieces.map { $0 + "\\w*" }.joined(separator: "\\s+")
                : "\\b" + pieces.joined(separator: "\\s+") + "(s|es|ed|d|ing)?\\b"
            var from = text.startIndex
            while let found = text.range(of: pattern, options: .regularExpression, range: from..<text.endIndex) {
                if !negatable || !negatedPredicate(found, in: text, english: english) { return true }
                from = found.upperBound
            }
            return false
        }
    }

    /// Korean: the stem's own predicate is a "don't" (구매하지 말고, 구매는 하지 마, 주문 금지), nothing in between.
    /// English: a "don't" right before the word, no other word between (don't buy; never "don't delay and buy").
    private static func negatedPredicate(_ found: Range<String.Index>, in text: String, english: Bool) -> Bool {
        if english {
            return text[..<found.lowerBound].range(of: #"\b(don't|dont|do not|never|without|no|not)\s+$"#, options: .regularExpression) != nil
        }
        return text[found.upperBound...].range(of: #"^(은|는|을|를|도)?\s?(하지\s?(말|마|않)|지\s?(말|마|않)|\s?금지)"#, options: .regularExpression) != nil
    }

    /// One of `words` is in `task`, negated or not (the hard lines: a negation there must not switch one off).
    static func mentions(_ words: [String], in task: String) -> Bool {
        let lowered = task.lowercased()
        return words.contains { word in
            // Korean stems match inside words (주문해줘); English only as whole words ("book", not "MacBook").
            let english = word.unicodeScalars.first.map { $0.isASCII } == true
            let pattern = english ? "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b" : NSRegularExpression.escapedPattern(for: word)
            return lowered.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func workFolder(home: String) -> String { home + "/.config/aris/aris/work" }

    // MARK: - Shell

    private static let neverCommands: Set<String> = [
        "sudo", "su", "doas", "diskutil", "dd", "mkfs", "newfs_apfs", "newfs_hfs", "csrutil", "tccutil", "security",
        "launchctl", "systemsetup", "spctl", "nvram", "pfctl", "shutdown", "reboot", "halt", "chown", "fdesetup",
        "dscl", "passwd", "kextload", "bless",
    ]
    private static let neverPatterns = [
        #"\brm\s+(-\w+\s+)*-\w*[rR]\w*\s+(-\w+\s+)*["']?(/|~|\$HOME|\$\{HOME\}|/Users/[^/\s"']+)/?["']?(\s|$)"#,
        #"\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(sh|bash|zsh)\b"#,
        #"(?i)with\s+administrator\s+privileges"#,
    ]
    private static let reading: Set<String> = [
        "ls", "cat", "head", "tail", "wc", "file", "stat", "find", "mdfind", "mdls", "grep", "rg", "pwd", "date",
        "cal", "which", "echo", "du", "df", "sw_vers", "uname", "whoami",
    ]
    private static let writingInWork: Set<String> = ["mkdir", "touch", "cp", "mv"]
    private static let plainWritingFlags: Set<String> = ["-p", "-f", "-n", "-r", "-R", "-v", "-i", "-a"]
    private static let findActions: Set<String> = ["-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprint0", "-fprintf", "-fls"]

    /// Flags that make a reading command run another program or write a file (rg --pre runs one per file searched).
    private static func runsOrWrites(_ command: String, _ argument: String) -> Bool {
        let short = argument.hasPrefix("-") && !argument.hasPrefix("--")
        switch command {
        case "find": return findActions.contains(argument)
        case "rg": return argument.hasPrefix("--pre") || argument.hasPrefix("--hostname-bin") || argument.hasPrefix("--search-zip")
            || (short && argument.contains("z"))
        case "file": return argument.hasPrefix("--compile") || (short && argument.contains("C"))
        default: return false
        }
    }

    /// rg always searches folders; grep with -r/-R/--recursive. (A pattern given with -e/-f isn't followed: asked.)
    private static func searchesFolders(_ command: String, _ arguments: [String]) -> Bool {
        let recursiveGrep = arguments.contains { $0 == "--recursive" || $0.hasPrefix("-d") || ($0.hasPrefix("-") && !$0.hasPrefix("--") && ($0.contains("r") || $0.contains("R"))) }
        return command == "rg" || (command == "grep" && recursiveGrep)
    }

    /// A flag that names the search pattern (or a file of them), so no plain word is the pattern.
    private static func givesPattern(_ arguments: [String]) -> Bool {
        arguments.contains { argument in
            if argument.hasPrefix("--") { return argument.hasPrefix("--regexp") || argument.hasPrefix("--file") }
            return argument.hasPrefix("-") && (argument.contains("e") || argument.contains("f"))
        }
    }

    /// Where keys, tokens and histories live, under the home folder.
    private static let secretPlaces = ["/.ssh", "/.gnupg", "/Library/Keychains", "/.codex", "/.claude", "/.aws", "/.config", "/.docker",
                                       "/.kube", "/.netrc", "/.npmrc", "/.pypirc", "/.git-credentials", "/.peekaboo"]

    /// A search under `folder` would reach one of those places (the home folder, ~/.config, / …).
    static func coversSecrets(_ folder: String, home: String) -> Bool {
        folder == "/" || secretPlaces.contains { isInside(home + $0, folder) || isInside(folder, home + $0) }
    }

    private static func shell(_ command: String, tools: String, home: String, critical: Bool, request: String = "") -> ArisRisk {
        // The never-list first, desktop lines included (C1). A desktop heredoc's body is text to type, which the shell never
        // runs (ArisDesktopShell reads it word for word): only its first line is the command.
        // Read without the text a note, message or to-do carries when the line is plain aris-tools calls (audit gate-7).
        let scanned = withoutPlainText(command, tools: tools)
        // One plain command in a shape that only reads (diskutil list, launchctl list): its program's place on the
        // never-list doesn't refuse it (audit gate-18). The never patterns and every check below still apply.
        let readForm = ArisCommandPolicy.words(command).flatMap(readOnlyForm)
        if isNever(withoutPlainText(ArisDesktopShell.commandLine(command, tools: tools), tools: tools), readsOnly: readForm != nil) { return .never }
        // Calendar and Reminders change only through `aris-tools event|remind`, never their apps driven by keys or
        // AppleScript (security review of BUG-53: the desktop refusal alone left `keys --app Calendar` and osascript).
        if drivesCalendarApp(scanned, tools: tools) { return .never }
        // The hook token and Aris's keys are never read by a brain, not even after a yes (security review of batch 3).
        if namesArisSecret(scanned, tools: tools) { return .never }
        // Computer use: aris-tools only hands the call to the agent, whose desktop engine gates it for every brain alike
        // (reads judged, actions on the user's card, never-list): asking here too would ask twice. A heredoc's quoted body is
        // never run by the shell.
        if isDesktop(command, tools: tools) { return .auto }
        // A plain desktop call in words the engine won't read ("type <text field> --app TextEdit"): never a "Mac 작업" card
        // over it, then the engine's own card for the same action (QA BUG-39: two cards, one auto-declined). It's
        // refused, and the brain writes it again with a ref from `desktop see`, which the engine asks about once.
        if ArisDesktopShell.parse(command, tools: tools) != nil { return .never }
        // "a && b": each command on its own; the riskiest decides.
        if let pieces = ArisCommandPolicy.segments(command), pieces.count > 1 {
            let risks = pieces.map { shell($0, tools: tools, home: home, critical: critical, request: request) }
            // The countdown card shows only the message: anything riding along with it is asked about instead.
            return [ArisRisk.never, .confirm].first(where: risks.contains) ?? (risks.contains(.countdown) ? .confirm : .auto)
        }
        guard let words = ArisCommandPolicy.words(command), let first = words.first else { return .confirm }
        let arguments = Array(words.dropFirst())
        if first == tools {
            if dictatedMessage(arguments, request: request) != nil { return .countdown }
            return arisTool(arguments, critical: critical, request: request, home: home)
        }
        // zsh turns ~user and =command into paths this gate never sees: ask.
        if arguments.contains(where: { ($0.hasPrefix("~") && $0 != "~" && !$0.hasPrefix("~/")) || $0.hasPrefix("=") }) { return .confirm }
        let paths = arguments.filter { !$0.hasPrefix("-") }.map { expand($0, home: home) }
        let work = workFolder(home: home)
        // A system command in a shape that only reads (pmset -g batt, defaults read …): at once, like the reading
        // commands; a file it reads is judged as theirs are; a read that could show something private asks (audit gate-22).
        if let readForm {
            guard case .runs(_, let files) = readForm else { return .confirm }
            let read = files.map { URL(fileURLWithPath: expand($0, home: home)).resolvingSymlinksInPath().path }
            return read.contains { isSecret($0, work: work) } ? .confirm : .auto
        }
        if reading.contains(first) {
            if arguments.contains(where: { runsOrWrites(first, $0) }) { return .confirm }
            // A link is judged by what it points at.
            let resolved = paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            if searchesFolders(first, arguments) {
                // A search over a folder reads every file under it: ask when that could include keys or tokens
                // (or when no folder is named: it searches wherever it was started).
                // The first word is the pattern, unless a flag gave it (-e/-f/--regexp/--file, attached or not).
                let targets = givesPattern(arguments) ? resolved : Array(resolved.dropFirst())
                if targets.isEmpty || targets.contains(where: { coversSecrets($0, home: home) }) { return .confirm }
            }
            return resolved.contains { isSecret($0, work: work) } ? .confirm : .auto
        }
        // Only plain flags: an option with a value (--target-directory=…, -t dir) could aim the write elsewhere.
        let plainFlags = arguments.filter { $0.hasPrefix("-") }.allSatisfy(plainWritingFlags.contains)
        if writingInWork.contains(first), plainFlags, !critical, !paths.isEmpty, paths.allSatisfy({ isInside($0, work) }) { return .auto }
        return .confirm
    }

    /// The hook token (any process holding it reaches the notch app's routes) or one of Aris's key files: named, or
    /// reachable by a glob in Aris's folder. Checked on the words as the shell reads them (quotes taken out) and raw.
    static func namesArisSecret(_ command: String, tools: String = "") -> Bool {
        let parsed = (ArisCommandPolicy.segments(command) ?? [command]).map { ArisCommandPolicy.words($0)?.joined(separator: " ") ?? $0 }
        return ([command] + parsed).contains { text in
            var lowered = text.lowercased()
            if !tools.isEmpty { lowered = lowered.replacingOccurrences(of: tools.lowercased(), with: "") }
            if lowered.contains("claude-hook") || lowered.contains("hook-token") { return true }
            if lowered.range(of: #"\.config/(aris|boring-notch)/[^\s'"]*-key\b"#, options: .regularExpression) != nil { return true }
            // A glob in Aris's own folder (outside its work folder) could match the token or a key.
            return lowered.range(of: #"\.config/(aris|boring-notch)(/(?!aris/work/)[^\s'"]*)?[*?\[]"#, options: .regularExpression) != nil
        }
    }

    static let calendarAppNames: Set<String> = ["calendar", "캘린더", "ical", "com.apple.ical", "reminders", "미리 알림", "미리알림", "com.apple.reminders"]

    /// `aris-tools keys|type --app Calendar|Reminders`, or osascript (or a Shortcuts/open run of a script) aimed at them.
    static func drivesCalendarApp(_ command: String, tools: String) -> Bool {
        let lowered = command.lowercased()
        if lowered.contains("osascript") || lowered.contains("tell application") {
            let named = #"(?i)(tell\s+application\s+(id\s+)?"(calendar|ical|com\.apple\.ical|reminders|com\.apple\.reminders|캘린더|미리\s*알림)"|application\s*\(\s*["'](calendar|reminders|com\.apple\.ical|com\.apple\.reminders)["']\s*\))"#
            if command.range(of: named, options: .regularExpression) != nil { return true }
        }
        return (ArisCommandPolicy.segments(command) ?? [command]).contains { piece in
            guard let words = ArisCommandPolicy.words(piece), words.first == tools, words.count > 1, ["keys", "type"].contains(words[1]),
                  let flag = words.firstIndex(of: "--app"), flag + 1 < words.count else { return false }
            return calendarAppNames.contains(words[flag + 1].lowercased().trimmingCharacters(in: .whitespaces))
        }
    }

    /// Never-commands at the start of any command in the line (after ; && | $( or a backtick), and a few patterns.
    /// `readsOnly`: the whole line is one plain command in a read-only shape (readOnlyForm), so the program's own name
    /// doesn't refuse it; the patterns and the computer-use runtime still do.
    private static func isNever(_ command: String, readsOnly: Bool = false) -> Bool {
        // Computer use's own runtime (Peekaboo, its folder) run as a program: only the agent does that, on every brain (I11).
        if ArisProtectedPlaces.executesComputerRuntime(command) { return true }
        let pieces = readsOnly ? [] : commandStarts(command).map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        }
        for piece in pieces {
            let words = piece.split(separator: " ").map(String.init).drop { $0.contains("=") }
            // The program as the shell runs it: quotes and backslashes around or inside its name taken off ("sudo", s\udo).
            let program = words.first.map { $0.filter { !"'\"\\".contains($0) } }
            if let first = program.map({ ($0 as NSString).lastPathComponent }), neverCommands.contains(first) { return true }
        }
        return neverPatterns.contains { command.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: - aris-tools

    private static let readingTools: Set<String> = [
        "weather", "stock", "currency", "memory", "recall", "windows", "shortcuts", "calendars", "screen", "selection", "tab", "finder", "show", "canvas", "brief", "find", "activity",
        // Aris's own shelf listed (QA VM: it asked a card): a look, its names outside text.
        "shelf",
    ]
    private static let askingTools: Set<String> = ["message", "mail", "trash"]
    /// Moving windows, opening apps and links, sound and music: easy to undo, so even a critical turn doesn't ask.
    private static let undoableTools: Set<String> = ["window", "new", "tile", "app", "link", "folder", "volume", "music", "timer", "maps"]
    /// Small local changes that stay on the Mac (memory, notes, reminders, events, the clipboard): at once, unless critical.
    /// Anything not named in a list here, including tools added later, asks first.
    /// (`note` isn't one: a note can carry outside text, so it is asked on its card with its title and first lines, QA retest.)
    private static let smallLocalTools: Set<String> = ["remember", "forget", "remind", "event", "use-calendar", "calendar", "clipboard", "todo", "board", "open"]
    /// Apps computer use never works in, by name and by bundle id (lowercased): terminals (commands go through the shell
    /// gate), password stores and the Mac's system profile.
    private static let neverComputerUse: Set<String> = Set([
        "Terminal", "iTerm", "iTerm2", "Warp", "Ghostty", "kitty", "Alacritty", "WezTerm", "Hyper",
        // Aris itself: its cards are the user's to answer, its settings hold the services and keys (security review I5).
        "Aris", "아리스", "com.lumenjsn.aris",
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
        "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
        "Keychain Access", "Passwords", "1Password", "1Password 7", "Bitwarden", "KeePassXC", "Enpass", "System Information",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "org.keepassxc.keepassxc", "in.sinew.Enpass-Desktop", "com.apple.SystemProfiler",
        "터미널", "키체인 접근", "암호", "시스템 정보",
        // Apps that run code: scripts, workflows, shortcuts, IDEs.
        "Script Editor", "스크립트 편집기", "Automator", "Shortcuts", "단축어", "Script Debugger", "Xcode", "Visual Studio Code",
        "Visual Studio Code - Insiders", "Cursor", "Zed", "Windsurf", "IntelliJ IDEA", "IntelliJ IDEA CE", "PyCharm", "PyCharm CE",
        "WebStorm", "GoLand", "CLion", "Rider", "Android Studio", "Sublime Text", "Nova", "BBEdit",
        "com.apple.ScriptEditor2", "com.apple.Automator", "com.apple.shortcuts", "com.latenightsw.ScriptDebugger8", "com.apple.dt.Xcode",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.exafunction.windsurf",
        "com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm", "com.jetbrains.pycharm.ce", "com.jetbrains.WebStorm",
        "com.jetbrains.goland", "com.jetbrains.CLion", "com.jetbrains.rider", "com.google.android.studio", "com.sublimetext.4",
        "com.panic.Nova", "com.barebones.bbedit",
        // More apps that run code or are agents themselves.
        "Antigravity", "Claude", "IDLE", "Python Launcher", "Wing Pro", "Wing Personal", "Wing 101", "ChatGPT", "Codex", "Raycast", "Alfred",
        "Keyboard Maestro", "Hammerspoon", "BetterTouchTool", "Docker", "Docker Desktop", "RStudio", "Fleet", "Positron",
        "com.google.antigravity-ide", "com.google.antigravity", "com.anthropic.claudefordesktop", "org.python.IDLE", "org.python.PythonLauncher",
        "com.wingware.wingpro", "com.wingware.wingpersonal", "com.wingware.wing101", "com.openai.chat", "com.openai.codex", "com.raycast.macos",
        "com.runningwithcrayons.Alfred", "com.stairways.keyboardmaestro.editor", "com.stairways.keyboardmaestro.engine",
        "org.hammerspoon.Hammerspoon", "com.hegenberg.BetterTouchTool", "com.docker.docker", "com.rstudio.desktop", "org.rstudio.RStudio",
        "com.jetbrains.fleet", "com.posit.positron",
        // The installer (security review I7). System Settings is an ordinary app (the owner: "위험한 것도 아닌데"); only its
        // permission, account and profile panes are off limits (blocksSettingsPane).
        "Installer", "설치 프로그램", "com.apple.installer",
        // More password stores.
        "Dashlane", "LastPass", "NordPass", "Proton Pass", "com.dashlane.Dashlane", "com.dashlane.dashlanephonefinal", "com.lastpass.LastPass",
        "com.lastpass.lastpassmacdesktop", "com.nordsec.nordpass", "com.nordpass.macos.NordPass", "me.proton.pass.electron", "ch.protonmail.pass",
        // Peekaboo's own app: computer use's runtime is the agent's alone (I11).
        "Peekaboo", "boo.peekaboo.mac", "boo.peekaboo.mac.debug",
    ].map { $0.lowercased() } + authPrompts)

    /// The processes that put up sign-in, password and permission prompts (lowercased names and bundle ids): never
    /// worked in, and while one shows a window (at any level) no app action runs (I7).
    static let authPrompts: [String] = [
        "SecurityAgent", "com.apple.SecurityAgent", "coreautha", "com.apple.coreautha", "LocalAuthenticationRemoteService",
        "com.apple.LocalAuthentication.UIAgent", "LocalAuthentication UIAgent", "CoreServicesUIAgent", "com.apple.coreservices.uiagent",
        "UserNotificationCenter", "com.apple.UserNotificationCenter", "universalAccessAuthWarn",
        "com.apple.accessibility.universalAccessAuthWarn", "Keychain Circle Notification", "com.apple.security.Keychain-Circle-Notification",
        "AuthenticationServicesAgent", "com.apple.AuthenticationServicesCore.AuthenticationServicesAgent",
    ].map { $0.lowercased() }

    // MARK: - System Settings

    /// System Settings by name or bundle id (lowercased).
    private static let settingsApps: Set<String> = ["system settings", "system preferences", "시스템 설정", "시스템 환경설정",
                                                     "com.apple.systempreferences", "com.apple.settings"]

    static func isSystemSettings(_ identifiers: [String?]) -> Bool {
        identifiers.compactMap { $0?.trimmingCharacters(in: .whitespaces).lowercased() }.contains(where: settingsApps.contains)
    }

    /// Whether a window owner (by name or bundle id, any case) is one of the prompts above.
    static func isAuthPrompt(_ owner: String) -> Bool { authPrompts.contains(owner.trimmingCharacters(in: .whitespaces).lowercased()) }

    /// Whether any of an app's names or bundle ids (in any case) is one computer use never works in.
    static func computerUseIsNever(_ identifiers: [String?]) -> Bool {
        identifiers.compactMap { $0?.trimmingCharacters(in: .whitespaces).lowercased() }.contains(where: neverComputerUse.contains)
    }

    // MARK: - Computer use

    /// One `aris-tools desktop …` call the engine takes as it is, so its every effect goes through the engine's own gate
    /// (which marks the app it reads, and cards every action once outside text came in): exactly one plain call, or a
    /// type, set-value or dialog input with its text in a quoted heredoc (ArisDesktopShell, every word plain), nothing on
    /// the never-list, and words the engine reads (ArisDesktopWords). Only such a line skips the shell gate's outbound,
    /// taint and repeat checks; any other desktop-looking line is judged as a command (C1).
    static func isDesktop(_ command: String, tools: String) -> Bool {
        guard let line = ArisDesktopShell.parse(command, tools: tools), !isNever(ArisDesktopShell.commandLine(command, tools: tools)) else { return false }
        let stdin = line.words.contains("--stdin")
        return (try? ArisDesktopWords.parse(line.words, text: line.text ?? (stdin ? "" : nil)).get()) != nil
    }

    /// A desktop line the engine can't read: why (its words' usage error), for the refusal the brain gets; nil when the
    /// line isn't a desktop call or reads fine (QA live on 827cfdb4: a batch with --title was "never" with no reason).
    static func desktopProblem(_ command: String, tools: String) -> String? {
        guard let line = ArisDesktopShell.parse(command, tools: tools) else { return nil }
        let stdin = line.words.contains("--stdin")
        if case .failure(let usage) = ArisDesktopWords.parse(line.words, text: line.text ?? (stdin ? "" : nil)) {
            return "Refused: Aris couldn't read that desktop call (\(usage.text)). Write it again as the usage says; nothing was done."
        }
        return nil
    }

    /// Said (and shown) when computer use is asked for in a browser: websites are a browser task for Aside.
    static let browserRefusal = "브라우저 작업은 Aside로 할게요"
    /// The MCP server computer use runs in (a JavaScript REPL).
    static let computerUseRepl = "cua_repl"
    /// Web browsers by bundle id.
    private static let browserBundles: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium",
        "company.thebrowser.Browser", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.operasoftware.OperaGX", "com.kagi.kagimacOS",
        "app.zen-browser.zen", "com.vivaldi.Vivaldi",
    ]
    /// Web browsers by name (lowercase, exact).
    private static let browsers: Set<String> = [
        "safari", "safari technology preview", "google chrome", "google chrome canary", "chrome", "chromium", "arc", "firefox",
        "firefox developer edition", "firefox nightly", "microsoft edge", "edge", "brave browser", "brave", "opera", "opera gx",
        "orion", "zen", "zen browser", "vivaldi",
    ]

    /// Web apps a browser wraps as their own app (Safari's Add to Dock, Chrome and Edge apps), by bundle id prefix.
    private static let webAppPrefixes = ["com.apple.safari.webapp.", "com.google.chrome.app.", "com.microsoft.edgemac.app."]

    /// A web browser (or a web app one wraps) by name or bundle id, in any case, or any app that opens web links
    /// (`webHandlers`: bundle ids, from Launch Services).
    static func isBrowser(name: String, bundle: String? = nil, webHandlers: Set<String> = []) -> Bool {
        if browsers.contains(name.trimmingCharacters(in: .whitespaces).lowercased()) { return true }
        guard let id = bundle?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return browserBundles.contains { $0.lowercased() == id } || webHandlers.contains { $0.lowercased() == id }
            || webAppPrefixes.contains(where: id.hasPrefix)
    }

    /// The computer-use steps that only look: the only ones the user's earlier yes for an app covers (a step that changes
    /// something goes to main Aris's judge, ArisEscalation.computerUseVerdict, or to the user).
    private static let plainComputerUseSteps: Set<String> = ["get_app_state", "scroll", "list_apps"]
    /// Apps where a step can send (mail, chat, calls), by bundle id and by name: every step there asks.
    private static let sendingBundles: Set<String> = [
        "com.apple.MobileSMS", "com.apple.mail", "com.apple.FaceTime", "com.kakao.KakaoTalkMac", "com.tinyspeck.slackmacgap",
        "com.hnc.Discord", "ru.keepcoder.Telegram", "com.tdesktop.Telegram", "net.whatsapp.WhatsApp", "desktop.WhatsApp",
        "com.microsoft.teams", "com.microsoft.teams2", "com.microsoft.Outlook", "us.zoom.xos", "jp.naver.line.mac",
        "org.whispersystems.signal-desktop", "com.readdle.smartemail-Mac", "it.bloop.airmail2", "com.mimestream.Mimestream",
        "org.localsend.localsend_app", "com.tencent.xinWeChat",
        // More mail, chat and call apps (security review I7).
        "org.mozilla.thunderbird", "com.facebook.archon", "com.facebook.Messenger", "com.automattic.beeper.desktop", "com.beeper.beeper-desktop",
        "com.skype.skype", "com.microsoft.SkypeForBusiness", "com.viber.osx", "Mattermost.Desktop", "com.mattermost.desktop", "Cisco-Systems.Spark",
        "com.cisco.webexmeetingsapp", "com.webex.meetingmanager", "com.readdle.SparkDesktop", "com.readdle.spark",
    ]
    private static let sendingApps: Set<String> = ["messages", "메시지", "mail", "kakaotalk", "카카오톡", "slack", "discord", "telegram",
                                                   "whatsapp", "microsoft teams", "microsoft outlook", "outlook", "zoom", "line", "signal",
                                                   "facetime", "spark", "airmail", "mimestream", "localsend", "wechat", "微信", "위챗",
                                                   "thunderbird", "messenger", "beeper", "skype", "viber", "mattermost", "webex", "cisco webex",
                                                   "webex meetings", "spark desktop", "spark mail", "메신저", "스카이프"]
    /// Words for deleting, sending, sharing or paying (and the keys that delete), anywhere in a step's name or values.
    private static let riskyStepWords = ["delet", "remov", "trash", "eras", "purg", "destroy", "backspace", "send", "submit", "post",
                                         "publish", "share", "upload", "forward", "reply", "pay", "purchas", "buy", "order", "checkout",
                                         "transfer", "discard", "wipe", "log out", "logout", "quit",
                                         "삭제", "지우", "지워", "휴지통", "보내", "전송", "공유", "게시", "결제", "구매", "주문", "송금", "제거", "발송",
                                         "구입", "이체", "削除", "删除", "送信", "发送",
                                         // Keys that quit, force quit or log out.
                                         "cmd+q", "command+q", "meta+q", "super+q", "⌘q", "cmd+opt+esc", "cmd+option+esc", "cmd+shift+q",
                                         "cmd+opt+shift+q", "super+shift+q"]
    /// The text as words are looked for in it: compatibility-folded (ｓｅｎｄ → send), lowercased, and every character
    /// that shows nothing (format and default-ignorable ones) taken out.
    static func folded(_ text: String) -> String {
        let scalars = text.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars.filter { !ArisJSTokens.isHidden($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    /// An app where a step can send (mail, chat, calls), by bundle id or name.
    static func isSendingApp(bundle: String?, name: String) -> Bool {
        bundle.map(sendingBundles.contains) == true || sendingApps.contains(name.lowercased())
    }

    /// Any word for deleting, sending, sharing or paying (or a key that deletes) in the text, in any case.
    static func mentionsRiskyStep(_ text: String) -> Bool {
        let lowered = folded(text)
        return riskyStepWords.contains(where: lowered.contains)
    }

    /// Whether the user's earlier yes for an app may cover this computer-use step: a known step, in an app resolved to its
    /// bundle id that doesn't send, with no word for deleting, sending or paying in its name or any of its values.
    static func computerUseStepIsPlain(bundle: String?, name: String, tool: String, arguments: [String: Any]) -> Bool {
        guard let bundle, !computerUseIsNever([bundle, name]), plainComputerUseSteps.contains(tool), !sendingBundles.contains(bundle),
              !sendingApps.contains(name.lowercased()) else { return false }
        let text = ([tool] + texts(in: arguments)).joined(separator: " ").lowercased()
        return !mentionsRiskyStep(text)
    }

    private static func texts(in value: Any) -> [String] {
        switch value {
        case let object as [String: Any]: return object.keys.sorted().flatMap { [$0] + texts(in: object[$0] as Any) }
        case let list as [Any]: return list.flatMap(texts)
        default: return ["\(value)"]
        }
    }
    /// Apps keys and text may go to without asking on a clean turn: plain writing apps (lowercase, exact).
    private static let safeTypingApps: Set<String> = ["notes", "메모", "textedit", "텍스트 편집기", "pages", "keynote", "numbers", "stickies", "스티커"]

    /// The apps of safeTypingApps by bundle id (lowercase): what the desktop engine's type matches (QA BUG-15).
    private static let safeTypingBundles: Set<String> = ["com.apple.textedit", "com.apple.notes", "com.apple.iwork.pages", "com.apple.iwork.keynote",
                                                         "com.apple.iwork.numbers", "com.apple.stickies"]

    /// An app keys and text may go to without asking (aris-tools type's safeTypingApps): it can't run code or send.
    /// By its bundle id, so another app that only takes one of these names isn't one.
    static func isSafeTypingApp(name: String, bundle: String?) -> Bool {
        guard let bundle else { return false }
        return safeTypingBundles.contains(bundle.lowercased())
    }

    private static func arisTool(_ arguments: [String], critical: Bool, request: String, home: String) -> ArisRisk {
        guard let tool = arguments.first else { return .auto }
        // External services: aris-tools only hands the call to the agent, whose one gate (ArisMCPPolicy) runs reads and
        // puts every write to the user, for every brain alike; asking here too would ask twice.
        if tool == "mcp" { return .auto }
        // The user's skills: aris-tools only hands the words to the agent, which reads inside the skill's folder and asks the user
        // on a card before any script runs (ArisSkillRoutes), for every brain alike.
        if tool == "skill" { return .auto }
        // The user's routines: aris-tools only hands the words to the agent, which reads a routine back to the user on its own card
        // before one is saved or removed (ArisRoutineRoutes), for every brain alike; listing and showing only read.
        if tool == "routine" { return .auto }
        // Website work for Aside: aris-tools hands the brief to the agent, whose one gate (ArisAside.risk, Codex's rule)
        // asks the user when it should, for every brain alike.
        if tool == "aside" { return .auto }
        // What later turns read back as the user's memory: at once only when it is exactly the span the user said this turn
        // ("…기억해", "remember …"); any other wording (the brain's own, or several memories with --all) asks him.
        if tool == "remember" || tool == "forget" {
            return isUsersWords(arguments.dropFirst().joined(separator: " "), in: request) ? .auto : .confirm
        }
        // `osascript` through aris-tools runs only the four scripts that restart, shut down, log out or sleep the Mac
        // (aris-tools refuses any other, and runs these only with the pass the gate mints on the user's yes): always their card.
        if tool == "osascript" { return .confirm }
        // A file named without its folder ("trash qa-1111"): never guessed and never run; the brain is told to send the
        // full path, and that call asks on the user's card (ArisRiskPolicy+BareNames: VM run 2, bug 3).
        if namesBareFile(arguments) { return .never }
        // Moving or trashing a protected place (or the home folder, or a folder that holds one) is never done. These tools take
        // no flags, so every argument is a path (only a literal -- is dropped). Paths are
        // judged as aris-tools will see them: relative ones from Aris's folder (where the AI's commands run), links followed.
        if tool == "move" || tool == "trash",
           arguments.dropFirst().filter({ $0 != "--" }).contains(where: { touchesProtected($0, home: home) }) {
            return .never
        }
        // A rename is a move within its folder, gated like one: never a protected place (the item or its new path), else
        // The user's card. A new folder too.
        if tool == "rename" {
            let rest = Array(arguments.dropFirst())
            guard rest.count == 2 else { return .confirm }
            let renamed = (rest[0] as NSString).deletingLastPathComponent + "/" + rest[1]
            return touchesProtected(rest[0], home: home) || touchesProtected(renamed, home: home) || rest[1].contains("/") ? .never : .confirm
        }
        if tool == "folder", arguments.dropFirst().first == "new" {
            return arguments.dropFirst(2).contains(where: { touchesProtected($0, home: home) }) ? .never : .confirm
        }
        // A conversion (convert, merge, split, compress) only makes new files beside the originals, never over anything
        // (the owner: "말하면 그냥 돼"): at once on a clean turn, as on the open Claude; never a protected place. After the
        // screen it still runs when the user's own words name the files (or they picked them: --finder, --shelf), and asks on
        // his card otherwise and after outside text (asksAfterOutsideText, coveredByRequest: audit gate-4). A call
        // aris-tools wouldn't read asks (it then refuses).
        if ArisConvertWords.verbs.contains(tool) {
            guard let call = ArisConvertWords.parse(arguments) else { return .confirm }
            if call.paths.contains(where: { touchesProtected($0, home: home) }) { return .never }
            // On another disk (/Volumes/…) or anywhere else outside home: the user's card, not silence (HANDOVERS B2).
            return call.paths.contains(where: { isOutsideHome($0, home: home) }) ? .confirm : .auto
        }
        // `undo` is read exactly as aris-tools reads it. An AI can never give the yes (only the app's own request can),
        // and a command aris-tools would reject is never run.
        if tool == "undo" {
            guard let parsed = ArisUndoArguments.parse(Array(arguments.dropFirst())), !parsed.confirmed else { return .never }
            // Bringing a removed schedule back makes scheduled work, like `schedule add`: always the user (never approved by
            // anyone else, learned, or remembered: ArisEscalation.approvableTools, isRepeatable).
            if undoRevivesSchedule(Array(arguments.dropFirst()), home: home) { return .confirm }
            // Any other undo is asked about too (it is in no list below).
        }
        // A schedule is work that runs later on its own: making one always asks the user (and is never learned or approved by
        // anyone else: ArisEscalation.approvableTools). Listing them only reads, and removing one only takes work away.
        if tool == "schedule" { return ["list", "remove"].contains(arguments.dropFirst().first ?? "") ? .auto : .confirm }
        // A settings deep link into a protected pane (Privacy & Security, Users & Groups, passwords, profiles) opens it
        // like any other settings link when it is the plain pane link and nothing else (audit gate-15: opening changes
        // nothing, and the app's own permission guide opens the same panes). Acting inside stays refused (the desktop
        // gate's three tiers, the user 2026-11-07), and so does a link in any other form (parameters, a second word).
        if tool == "link", arguments.dropFirst().contains(where: ArisSettingsPane.isProtectedLink) {
            return arguments.count == 2 && ArisCommandPolicy.isSettingsLink(arguments[1]) ? .auto : .never
        }
        // One public page, read (aris-tools checks the address): a read like the weather, judged on a careful turn.
        if tool == "web" { return arguments.count == 3 && arguments[1] == "fetch" ? .auto : .confirm }
        // `activity log` writes the log for the notch app (through aris-agent alone): never an AI's (QA BUG-18).
        if tool == "activity", arguments.dropFirst().first == "log" { return .never }
        // `screen --pid` reads the window of a process the caller names: aris-agent's own look alone asks that way (with
        // Aris in front), never an AI (security review 3, L1).
        if tool == "screen", arguments.contains("--pid") { return .never }
        if readingTools.contains(tool) || (tool == "clipboard" && !arguments.contains("set")) { return .auto }
        // A maps lookup (--json) only prints the place and its ETAs, nothing opens: a read like the weather (QA BUG-1),
        // judged on a careful turn (ArisReadGate.isJudgedRead), never outbound.
        if ArisReadGate.isMapsLookup(arguments) { return .auto }
        // The user's own apps read (messages, mail, notes, files, Obsidian): at once, as outside text (bringsInUntrusted).
        // Only the exact read verbs: any other `mail …` is a send and asks below.
        if ArisLocalReadPolicy.isRead(arguments) { return .auto }
        if askingTools.contains(tool) { return .confirm }
        // Taking an item off the list can't be undone from Aris.
        if tool == "todo" && arguments.dropFirst().first == "remove" { return .confirm }
        // Removing or moving a calendar event: always the user's card, naming the exact event (QA BUG-53).
        if tool == "event", ArisEventCard.isEdit(Array(arguments.dropFirst())) { return .confirm }
        if undoableTools.contains(tool) { return .auto }
        // `event find` only looks, on a critical turn too ("…일정 지워 줘" is one): the delete's own card is the one card
        // (QA BUG-53 retest: a card came up just to find the event).
        if tool == "event", arguments.dropFirst().first == "find" { return .auto }
        if critical { return .confirm }
        if tool == "keys" || tool == "type" {
            // Keystrokes can run code in many apps (terminals, Script Editor, IDEs, Shortcuts, Office macros) or send
            // things (Mail, a browser's address bar). Only a few plain writing apps, named exactly, run at once on a
            // clean turn; aris-tools then insists that exact app is in front. Once outside text or the screen came in
            // these ask too (readBackWrites): their menus and file panels reach further than the document.
            guard let flag = arguments.firstIndex(of: "--app"), flag + 1 < arguments.count else { return .confirm }
            let app = arguments[flag + 1].lowercased().trimmingCharacters(in: .whitespaces)
            return safeTypingApps.contains(app) ? .auto : .confirm
        }
        // A shortcut can do anything online: only the one the user named runs at once.
        if tool == "shortcut" { return namesShortcut(arguments, request: request) ? .auto : .confirm }
        // A file opened from outside home (an external disk): the user's card (HANDOVERS B2). Each word, and all of them as
        // the one path aris-tools reads them as.
        if tool == "open", (arguments.dropFirst() + [arguments.dropFirst().joined(separator: " ")]).contains(where: { isOutsideHome($0, home: home) }) { return .confirm }
        return smallLocalTools.contains(tool) ? .auto : .confirm
    }

    /// Whether the user's own words name this shortcut (ignoring case and spaces).
    private static func namesShortcut(_ arguments: [String], request: String) -> Bool {
        guard !coversNothing(request) else { return false }  // a pasted page names no shortcut of his (review 9, M1)
        let name = arguments.dropFirst().joined(separator: "").lowercased().filter { !$0.isWhitespace }
        let said = request.lowercased().filter { !$0.isWhitespace }
        return name.count >= 2 && said.contains(name)
    }

    // MARK: - What leaves the Mac, and what brings outside text in

    /// aris-tools that carry data off the Mac without asking: a link (its address can hold anything), a
    /// shortcut (which can do anything online) and Maps opened (its words go to Apple's map service). A maps lookup
    /// (--json) isn't: it is a read, judged on a careful turn like the web's (ArisReadGate.isMapsLookup).
    private static let outboundTools: Set<String> = ["link", "shortcut", "maps", "web"]
    /// aris-tools that read text from outside Aris: what's on screen, selected, copied, or open in a browser.
    /// (Canvas announcements are written by teachers and classmates.)
    /// (Not `mcp`: the agent's gate marks the conversation itself before a service is reached, so the gate still sees the
    /// taint as it was when the brain wrote the call: M8.)
    private static let untrustedReadingTools: Set<String> = ["screen", "selection", "clipboard", "tab", "finder", "canvas", "brief", "find", "web", "shelf"]

    /// Sends something somewhere outside, at once. After the AI has read outside text (a web page, mail, a file),
    /// these ask first: that text could have told it to send what it knows.
    static func isOutbound(_ action: ArisAction, tools: String) -> Bool {
        switch action {
        case .shell(let command) where isDesktop(command, tools: tools):
            return false
        case .shell(let command):
            // A command that can't be read word by word might send anything.
            guard let calls = arisCalls(in: command, tools: tools) else { return true }
            // (A plain System Settings pane link opens a pane on this Mac: nothing leaves it.)
            return calls.contains { call in
                outboundTools.contains(call[0]) && !ArisReadGate.isMapsLookup(call)
                    && !(call.count == 2 && call[0] == "link" && ArisCommandPolicy.isSettingsLink(call[1]))
            }
        case .browserTask: return true
        case .fileChange, .mcp, .computerUse: return false
        }
    }

    /// Whether `aris-tools undo <arguments>` would bring a removed schedule back: the entry it names, or for a bare undo
    /// the latest undoable one, read (read-only) from `home`'s activity log. False when it can't tell (it asks anyway).
    static func undoRevivesSchedule(_ arguments: [String], home: String) -> Bool {
        guard let parsed = ArisUndoArguments.parse(arguments) else { return false }
        let log = URL(fileURLWithPath: home).appendingPathComponent(".config/aris/aris/activity.jsonl")
        let entry = parsed.id.map { ArisActivityBridge.entry(id: $0.uuidString, file: log) } ?? ArisActivityBridge.latestUndoable(file: log)
        return entry?.revivesSchedule == true
    }

    /// What runs at once in a clean turn but asks once outside text came in: anything outbound; a schedule added or
    /// removed (work that runs on its own, or the user's planned work quietly cancelled); and what later turns read back
    /// (memory, calendar events, to-dos), where planted words would steer them, and reading the memories themselves.
    /// A note isn't read back.
    /// A conversion too (audit gate-4: it was refused outright): outside words could have named the files, so the user sees
    /// which files and what they become. `conversions: false` leaves them out (a hands-free turn's own rule).
    static func asksAfterOutsideText(_ action: ArisAction, tools: String, conversions: Bool = true) -> Bool {
        if isOutbound(action, tools: tools) { return true }
        guard case .shell(let command) = action, !isDesktop(command, tools: tools) else { return false }
        return (ArisCommandPolicy.segments(command) ?? [command]).contains { piece in
            guard let words = ArisCommandPolicy.words(piece), words.first == tools else { return false }
            let rest = Array(words.dropFirst())
            // `event find` only looks (its output is outside text itself): never a card, even after outside text (QA BUG-53
            // retest: a card came up just to find; the delete's card is the one card).
            if rest.starts(with: ["event", "find"]) { return false }
            if conversions, let verb = rest.first, ArisConvertWords.verbs.contains(verb) { return true }
            return (readBackWrites + readBackReads).contains { rest.starts(with: $0) }
        }
    }

    /// A conversion the gate can't read as one plain aris-tools call: once outside text or the screen came in it is
    /// refused on every gated brain, never put to the user (their card couldn't say which files). That is a line that can't be
    /// read word by word (a pipe, a backslash) with aris-tools and a conversion's verb both in it, and one where
    /// aris-tools runs inside another program (`sh -c '…'`, `bash -c`, `env`, `xargs`). Only the subcommand counts (the
    /// first word after aris-tools, by its path or its name), never ordinary text: a note that says "split the bill" is
    /// a note. A conversion written plainly (alone, or chained with && or ;) isn't refused any more: it asks on the user's
    /// card, or runs when his own words cover it (asksAfterOutsideText: audit gate-4).
    static func refusedAfterOutsideText(_ action: ArisAction, tools: String) -> Bool {
        guard case .shell(let command) = action, !isDesktop(command, tools: tools) else { return false }
        return runsConversion(command, tools: tools, depth: 0) && !readsAsConversions(command, tools: tools)
    }

    /// Every conversion in the line is aris-tools' own call at the start of a chained command, each read word by word.
    private static func readsAsConversions(_ command: String, tools: String) -> Bool {
        guard let pieces = ArisCommandPolicy.segments(command) else { return false }
        return pieces.allSatisfy { piece in
            guard let words = ArisCommandPolicy.words(piece) else { return false }
            if words.first == tools, words.count > 1, ArisConvertWords.verbs.contains(words[1]) { return true }
            return !runsConversion(piece, tools: tools, depth: 0)
        }
    }

    private static func runsConversion(_ line: String, tools: String, depth: Int) -> Bool {
        guard depth < 4 else { return false }
        let name = (tools as NSString).lastPathComponent
        for piece in commandPieces(line) {
            // Read word by word (quotes kept together); a piece that can't be (a backslash) by its whitespace.
            let words = ArisCommandPolicy.words(piece) ?? piece.split(whereSeparator: \.isWhitespace).map(String.init)
            for (index, word) in words.enumerated() {
                let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: "'\"`"))
                if bare == tools || (bare as NSString).lastPathComponent == name, index + 1 < words.count,
                   ArisConvertWords.verbs.contains(words[index + 1].trimmingCharacters(in: CharacterSet(charactersIn: "'\"`"))) { return true }
                // A shell's -c string is a command line of its own.
                if index > 0, words[index - 1].hasPrefix("-"), !words[index - 1].hasPrefix("--"), words[index - 1].contains("c"),
                   runsConversion(word, tools: tools, depth: depth + 1) { return true }
            }
        }
        return false
    }

    /// A line cut at |, ;, & and line breaks outside quotes.
    private static func commandPieces(_ line: String) -> [String] {
        var pieces: [String] = [], piece = "", single = false, double = false, escaped = false
        for character in line {
            if escaped { escaped = false; piece.append(character); continue }
            if character == "\\", !single { escaped = true; piece.append(character); continue }
            if character == "'", !double { single.toggle() } else if character == "\"", !single { double.toggle() }
            if !single, !double, "|;&\n".contains(character) {
                pieces.append(piece)
                piece = ""
            } else {
                piece.append(character)
            }
        }
        pieces.append(piece)
        return pieces.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Reading the user's memories once outside text (or the screen) came in could have them sent out: asked.
    private static let readBackReads = [["memory"], ["recall"]]

    /// (`weather --set-home <city>` saves the home place the weather, the brief and travel times use: a write, so it asks
    /// after outside text like the others: security review L2.)
    /// Keys and typed text too, into the apps that take them at once on a clean turn (safeTypingApps): any chord and any
    /// text reach those apps' menus and file panels, so words a page or the screen supplied never press or type without
    /// The user's card (security review 2 H1). And two small writes: which calendar new events go into, and a to-do ticked
    /// off (security review 2 L5).
    private static let readBackWrites = [["schedule", "add"], ["schedule", "remove"], ["remember"], ["forget"], ["event"], ["remind"], ["clipboard", "set"], ["todo", "add"],
                                         ["todo", "edit"], ["weather", "--set-home"], ["keys"], ["type"], ["use-calendar"], ["todo", "done"]]

    /// Brings text into the AI that someone else may have written: a file outside Aris's work folder, the screen,
    /// the clipboard, a tool's result, a browser task's report, an app seen through computer use.
    static func bringsInUntrusted(_ action: ArisAction, tools: String, home: String) -> Bool {
        switch action {
        // The desktop engine marks the app it reads itself (ArisBrainDriver.markAppRead), before the app is reached.
        case .shell(let command) where isDesktop(command, tools: tools):
            return false
        case .shell(let command):
            let pieces = ArisCommandPolicy.segments(command) ?? [command]
            return pieces.contains { piece in
                guard let words = ArisCommandPolicy.words(piece), let first = words.first else { return false }
                // A schedule's prompt was written by a model.
                if first == tools {
                    // A maps lookup's places and addresses are anyone's words too (follow-up M1).
                    // `event find` prints calendar titles, which anyone sending an invitation wrote (security review of BUG-53).
                    if words.count > 2, words[1] == "event", words[2] == "find" { return true }
                    // The to-do list, an item ticked off, changed or removed (each prints stored titles), and the 한 일 log
                    // (its lines quote them): words a brain may itself have stored on an earlier pass of the automatic check,
                    // so they come back as outside text, never as the user's own list read clean (auto H2). Only `todo add`
                    // prints nothing but what the brain just passed.
                    if words.count > 1, words[1] == "todo", !(words.count > 2 && words[2] == "add") { return true }
                    if words.count > 1, words[1] == "activity" { return true }
                    return words.count > 1 && (untrustedReadingTools.contains(words[1]) || ArisLocalReadPolicy.commands.contains(words[1])
                        || ArisReadGate.isMapsLookup(Array(words.dropFirst()))
                        || words.dropFirst().starts(with: ["schedule", "list"])
                        // `recall --tainted` prints what turns that read outside content left (ArisWorkRecallWords).
                        || ArisWorkRecallWords.pullsTainted(Array(words.dropFirst())))
                }
                // A read-only system command whose output carries names other people chose (a volume, a device, a process).
                if case .runs(let outsideText, _)? = readOnlyForm(words) { return outsideText }
                guard reading.contains(first) else { return false }
                let work = workFolder(home: home)
                return words.dropFirst().filter { !$0.hasPrefix("-") }.map { expand($0, home: home) }.contains { !isInside($0, work) }
            }
        case .mcp, .browserTask, .computerUse: return true
        case .fileChange: return false
        }
    }

    /// The aris-tools calls in a command line, each its words after the program ("link …", "maps search … --json");
    /// nil when it can't be read.
    private static func arisCalls(in command: String, tools: String) -> [[String]]? {
        var calls: [[String]] = []
        for piece in ArisCommandPolicy.segments(command) ?? [command] {
            guard let words = ArisCommandPolicy.words(piece) else { return nil }
            if words.first == tools, words.count > 1 { calls.append(Array(words.dropFirst())) }
        }
        return calls
    }

    /// Whether a yes to this action may stand for the same action again soon. Never for what leaves the Mac or
    /// can't be undone (a message, mail, the trash, a site, an outside tool): a retry would do it twice.
    static func isRepeatable(_ action: ArisAction, tools: String) -> Bool {
        switch action {
        // A retried click or typed text would land twice.
        case .shell(let command) where isDesktop(command, tools: tools):
            return false
        case .shell(let command):
            let pieces = ArisCommandPolicy.segments(command) ?? [command]
            // Restarting, shutting down, logging out or sleeping the Mac asks every time.
            if pieces.contains(where: { powerCommand($0, tools: tools) != nil }) { return false }
            return !pieces.contains { piece in
                guard let words = ArisCommandPolicy.words(piece), words.first == tools, words.count > 1 else { return false }
                // A retried `schedule add` would make a second schedule; an undo is a different thing each time (a bare one
                // takes whatever is latest, and one may bring a schedule back).
                return askingTools.contains(words[1]) || words[1] == "schedule" || words[1] == "undo"
            }
        case .fileChange, .computerUse: return true
        case .mcp, .browserTask: return false
        }
    }
}
