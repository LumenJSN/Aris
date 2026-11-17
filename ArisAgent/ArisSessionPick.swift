//
//  ArisSessionPick.swift
//  aris-agent
//
//  Which of the user's own Claude Code sessions a prompt goes to, and whether it may (the owner, 2026-11-15: "웹사이트 만든
//  세션한테 /unslop 돌려서 humanize 하라고 해"). The sessions are the app's, as its hooks heard them
//  (ClaudeSessionsRoute); the brain names one by its folder (or its id, after a question), never by guessing: two that
//  fit are asked about once. A session takes a prompt only while it waits idle at its prompt (its last hook a Stop or
//  the idle notification, no card or permission waiting). The text is one line, shown whole on the user's card, and never
//  one Claude Code would run as a shell command (a leading "!") or save as a memory (a leading "#"). Pure.
//

import Foundation

/// One session as the app's /aris/sessions lists it.
struct ArisLiveSession: Equatable {
    let id: String
    let cwd: String
    let state: String
    let lastHook: String
    let secondsAgo: Int
    let agent: String
    let asking: Bool
    /// "warp" (value: its focus link), "iterm" (its session id) or "app" (the terminal's bundle id); nil when unknown.
    let terminalKind: String?
    let terminalValue: String?

    init(id: String, cwd: String, state: String = "idle", lastHook: String = "Stop", secondsAgo: Int = 30, agent: String = "claude",
         asking: Bool = false, terminalKind: String? = nil, terminalValue: String? = nil) {
        self.id = id
        self.cwd = cwd
        self.state = state
        self.lastHook = lastHook
        self.secondsAgo = secondsAgo
        self.agent = agent
        self.asking = asking
        self.terminalKind = terminalKind
        self.terminalValue = terminalValue
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, !id.isEmpty, id.count <= 200, let cwd = json["cwd"] as? String else { return nil }
        let terminal = json["terminal"] as? [String: String]
        self.init(id: id, cwd: cwd, state: json["state"] as? String ?? "", lastHook: json["lastHook"] as? String ?? "",
                  secondsAgo: json["secondsAgo"] as? Int ?? 0, agent: json["agent"] as? String ?? "claude", asking: json["asking"] as? Bool ?? false,
                  terminalKind: terminal?["kind"], terminalValue: terminal?["value"])
    }

    /// The folder's own name (the home folder as "~").
    func folder(home: String) -> String {
        let path = (cwd as NSString).standardizingPath
        if path == (home as NSString).standardizingPath { return "~" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? String(id.prefix(8)) : name
    }

    /// The terminal it runs in, as a person names it.
    var terminalName: String {
        switch terminalKind {
        case "warp": return "Warp"
        case "iterm": return "iTerm2"
        case "app": return ArisSessionPick.terminalNames[terminalValue ?? ""] ?? "터미널"
        default: return "터미널"
        }
    }

    /// The terminal's bundle id, when it is known.
    var terminalBundle: String? {
        switch terminalKind {
        case "warp": return "dev.warp.Warp-Stable"
        case "iterm": return "com.googlecode.iterm2"
        case "app": return terminalValue
        default: return nil
        }
    }
}

/// `aris-tools session …` as every route reads it.
enum ArisSessionCall {
    /// Whether `words` (after the program) are a `session` call.
    static func isSession(_ words: [String]) -> Bool { words.first == "session" && words.count >= 2 }

    /// The words after `session` as a call may carry them: a known verb, within the limits (ArisSealedTools.sessionForm).
    static func isCall(_ words: [String]) -> Bool { ArisSealedTools.sessionForm(words) }
}

enum ArisSessionPick {
    enum Pick: Equatable {
        case one(ArisLiveSession)
        case none
        case many([ArisLiveSession])
    }

    static var terminalNames: [String: String] { ArisSessionHost.appNames }

    private static func normal(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " \"'`/"))
    }

    /// The session `which` names among `sessions` (Claude Code's alone): its id (or the first 8+ characters of it), its
    /// folder's path or name exactly, else the one folder whose name holds it (or is held in it). Two or more that fit
    /// equally: `many`, to ask the user once.
    static func pick(_ which: String, among sessions: [ArisLiveSession], home: String) -> Pick {
        let claude = sessions.filter { $0.agent == "claude" }
        let raw = which.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return claude.count == 1 ? .one(claude[0]) : claude.isEmpty ? .none : .many(claude) }
        if let exact = claude.first(where: { $0.id == raw }) { return .one(exact) }
        if raw.count >= 8, raw.range(of: "^[0-9a-fA-F-]+$", options: .regularExpression) != nil {
            let byId = claude.filter { $0.id.lowercased().hasPrefix(raw.lowercased()) }
            if byId.count == 1 { return .one(byId[0]) }
        }
        let expanded = raw.hasPrefix("~") ? home + raw.dropFirst() : raw
        if expanded.hasPrefix("/") {
            let path = (expanded as NSString).standardizingPath
            return verdict(claude.filter { ($0.cwd as NSString).standardizingPath == path })
        }
        let wanted = normal(raw)
        guard !wanted.isEmpty else { return .none }
        let named = claude.filter { normal($0.folder(home: home)) == wanted || (wanted == "~" || wanted == "home") && $0.folder(home: home) == "~" }
        if !named.isEmpty { return verdict(named) }
        guard wanted.count >= 3 else { return .none }
        return verdict(claude.filter {
            let folder = normal($0.folder(home: home))
            return folder.count >= 3 && (folder.contains(wanted) || wanted.contains(folder))
        })
    }

    private static func verdict(_ found: [ArisLiveSession]) -> Pick {
        found.isEmpty ? .none : found.count == 1 ? .one(found[0]) : .many(found)
    }

    /// The hooks after which Claude Code waits idle at its prompt.
    static let idleHooks: Set<String> = ["Stop", "Notification:idle_prompt"]

    /// Why the session can't take a prompt now, as far as its hooks say; nil when it waits idle at its prompt.
    static func busy(_ session: ArisLiveSession) -> ArisSessionStop? {
        if session.agent != "claude" { return .notClaude }
        if session.asking || session.state == "notification" || session.lastHook == "PermissionRequest"
            || session.lastHook == "Notification:permission_prompt" { return .waitingOnUser }
        if ["thinking", "typing", "building", "juggling"].contains(session.state) { return .working }
        guard idleHooks.contains(session.lastHook) else { return .notIdle }
        return nil
    }

    /// The most a prompt may be.
    static let longestText = 2_000

    /// The text to type, checked: one line (no line break or control character, nothing hidden), within the limit, and
    /// never what Claude Code takes as a shell command ("!…") or a memory to save ("#…").
    static func text(_ raw: String) -> Result<String, ArisSessionStop> {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .failure(.emptyText) }
        guard text.count <= longestText else { return .failure(.longText) }
        let hidden = text.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format
                || scalar.properties.generalCategory == .lineSeparator || scalar.properties.generalCategory == .paragraphSeparator
        }
        guard !hidden else { return .failure(.multiLine) }
        if text.hasPrefix("!") || text.hasPrefix("#") { return .failure(.shellPrefix) }
        return .success(text)
    }

    /// The user's card: the session (its folder, where it lives, its terminal) and the exact text, all of it.
    static func card(_ session: ArisLiveSession, text: String, home: String, english: Bool) -> ArisMCPCard {
        let place = ArisCardWords.friendlyPath(session.cwd, home: home, english: english)
        let detail = english
            ? "Session: \(ArisCardWords.clean(session.folder(home: home), limit: 60)) (\(place)) · \(session.terminalName)\nText to send: \(ArisCardWords.typedShown(text))"
            : "세션: \(ArisCardWords.clean(session.folder(home: home), limit: 60)) (\(place)) · \(session.terminalName)\n보낼 글: \(ArisCardWords.typedShown(text))"
        return ArisMCPCard(title: english ? "Send to a Claude Code session" : "Claude Code 세션에 보내기", detail: detail, full: nil, fields: [])
    }

    /// The sessions as `session list` prints them, newest first: the folder, the terminal, its state, how long ago, and
    /// its id (to name one exactly after asking which). No text a session wrote.
    static func listing(_ sessions: [ArisLiveSession], home: String) -> String {
        guard !sessions.isEmpty else { return "No Claude Code session is known right now (Aris sees one once it does something while Aris runs)." }
        return sessions.map { session in
            let state = busy(session).map { $0.short } ?? "idle at its prompt"
            let agent = session.agent == "claude" ? "Claude Code" : session.agent == "codex" ? "Codex" : session.agent == "gemini" ? "Gemini CLI" : session.agent
            return "- \(session.folder(home: home)) (\(agent), \(session.terminalName)): \(state), \(ago(session.secondsAgo)); id \(session.id)"
        }.joined(separator: "\n")
    }

    static func ago(_ seconds: Int) -> String {
        seconds < 60 ? "just now" : seconds < 3_600 ? "\(seconds / 60) min ago" : "\(seconds / 3_600) h ago"
    }

    /// For the brain when more than one session fits: ask the user once, then send again with the one's id.
    static func manyLine(_ found: [ArisLiveSession], home: String) -> String {
        "[Aris] Not sent: more than one Claude Code session fits. Ask the user once which one (by folder), then call again with its id:\n"
            + listing(found, home: home)
    }

    /// For the brain when none fits.
    static func noneLine(_ sessions: [ArisLiveSession], home: String) -> String {
        let claude = sessions.filter { $0.agent == "claude" }
        guard !claude.isEmpty else {
            return "[Aris] Not sent: Aris knows no Claude Code session right now. Tell the user in one short line: \"지금 아는 Claude Code 세션이 없어요.\""
        }
        return "[Aris] Not sent: no Claude Code session fits that name. The sessions Aris knows:\n" + listing(claude, home: home)
            + "\nPick the one the user means by its folder; if it isn't plain which, ask them once."
    }
}

/// Why a prompt wasn't sent: each with the one Korean (or English) line the user hears, and a short form for the list.
enum ArisSessionStop: Equatable, Error {
    case emptyText, longText, multiLine, shellPrefix
    case notClaude, waitingOnUser, working, notIdle, gone
    case notRunning, manyProcesses, shellInFront
    case noAccessibility, unknownTerminal, tabNotFound, notInFront, screenNotIdle, noScreenRecording
    case secureInput, focusMoved, typingFailed, lockBusy, appUnreachable, draftInInput, terminalNotice
    /// The session lives where Aris can't type (an app with no terminal it knows), named.
    case hostNotSupported(String)
    /// Its host couldn't prove the exact place (tab, pane, window), named: nothing typed.
    case hostNotProven(String)
    /// A background session (`claude --bg`): no input box until it is opened.
    case backgroundSession

    var short: String {
        switch self {
        case .notClaude: return "not a Claude Code session"
        case .waitingOnUser: return "waiting for the user's answer or permission"
        case .working: return "working"
        case .notIdle, .gone: return "not idle at its prompt"
        default: return "not ready"
        }
    }

    /// The line for the user.
    func line(english: Bool) -> String {
        switch self {
        case .emptyText: return english ? "There was nothing to send." : "보낼 글이 비어 있어요."
        case .longText: return english ? "That's too long to send as one prompt." : "한 번에 보내기엔 글이 너무 길어요."
        case .multiLine: return english ? "I only send a single line of plain text." : "보낼 글은 줄바꿈 없는 한 줄이어야 해요."
        case .shellPrefix: return english ? "A prompt starting with ! or # would run a command or save a memory, so I didn't send it."
            : "!나 #로 시작하면 명령이 실행되거나 메모로 저장돼서 보내지 않았어요."
        case .notClaude: return english ? "I can only send to Claude Code sessions." : "Claude Code 세션에만 보낼 수 있어요."
        case .waitingOnUser: return english ? "That session is waiting for your answer, so I didn't type into it."
            : "그 세션이 지금 답이나 허락을 기다리고 있어서 보내지 않았어요."
        case .working: return english ? "That session is still working, so I didn't send it." : "그 세션이 아직 일하는 중이라 보내지 않았어요."
        case .notIdle, .gone: return english ? "That session isn't waiting at its prompt, so I didn't send it." : "그 세션이 입력을 기다리는 상태가 아니라서 보내지 않았어요."
        case .notRunning: return english ? "That session's Claude Code isn't running any more." : "그 세션의 Claude Code가 더 이상 실행 중이 아니에요."
        case .manyProcesses: return english ? "Several Claude Codes run in that folder, so I can't be sure which window it is." : "그 폴더에 Claude Code가 여러 개 떠 있어서 어느 창인지 확실하지 않아 보내지 않았어요."
        case .shellInFront: return english ? "That terminal isn't at Claude Code's input right now, so I didn't type anything." : "그 터미널이 지금 Claude Code 입력창이 아니라서 아무것도 입력하지 않았어요."
        case .noAccessibility: return english ? "Aris needs Accessibility to type into the terminal." : "터미널에 입력하려면 Aris에 손쉬운 사용 권한이 필요해요."
        case .unknownTerminal: return english ? "I don't know which terminal that session is in, so I didn't send it." : "그 세션이 어느 터미널에 있는지 몰라서 보내지 않았어요."
        case .tabNotFound: return english ? "I couldn't find that session's terminal tab, so I didn't send it." : "그 세션의 터미널 탭을 찾지 못해서 보내지 않았어요."
        case .notInFront: return english ? "I couldn't bring that session's tab to the front for sure, so I didn't type." : "그 세션 탭을 확실히 앞으로 가져오지 못해서 입력하지 않았어요."
        case .screenNotIdle: return english ? "The screen didn't show Claude Code waiting at its input, so I didn't type." : "화면에 Claude Code 입력창이 보이지 않아서 입력하지 않았어요."
        case .noScreenRecording: return english ? "Aris needs Screen Recording to check the terminal before typing." : "입력 전에 터미널을 확인하려면 Aris에 화면 기록 권한이 필요해요."
        case .secureInput: return english ? "A password field has the keyboard, so I didn't type." : "비밀번호 입력 중이라 입력하지 않았어요."
        case .focusMoved: return english ? "The window in front changed while typing, so I didn't press Return." : "입력하는 사이에 앞 창이 바뀌어서 엔터를 누르지 않았어요."
        case .typingFailed: return english ? "Typing into the terminal didn't work." : "터미널에 입력하지 못했어요."
        case .lockBusy: return english ? "Another task is using the keyboard right now." : "다른 작업이 키보드를 쓰고 있어서 보내지 않았어요."
        case .appUnreachable: return english ? "I couldn't reach the list of sessions." : "세션 목록을 확인하지 못했어요."
        case .terminalNotice: return english ? "The terminal is showing a notice that would take the keys, so I didn't type. Dismiss it and ask again."
            : "터미널에 키를 가로채는 안내가 떠 있어서 입력하지 않았어요. 안내를 닫고 다시 말해 주세요."
        case .draftInInput: return english ? "Something is already typed in that session's input box, so I didn't add to it." : "그 세션 입력창에 이미 쓰다 만 글이 있어서 보내지 않았어요."
        case .hostNotSupported(let app): return english ? "I can't send to a Claude Code session inside \(app) yet, so I didn't." : "\(app) 안의 Claude Code 세션에는 아직 보낼 수 없어서 보내지 않았어요."
        case .hostNotProven(let app): return english ? "I couldn't find that session's exact place in \(app), so I didn't type anything."
            : "\(app)에서 그 세션의 정확한 자리를 찾지 못해서 아무것도 입력하지 않았어요."
        case .backgroundSession: return english ? "That session runs in the background with no input box. Open it with `claude attach` and ask again."
            : "그 세션은 백그라운드에서 돌고 있어서 입력창이 없어요. 터미널에서 claude attach로 열어 두고 다시 말해 주세요."
        }
    }

    /// What the brain is told: nothing was sent (or not Return), and the exact line to say.
    func note(english: Bool) -> String {
        let after = self == .focusMoved ? "The text may be in the session's input box, but Return was not pressed. " : "Nothing was typed. "
        return "[Aris] Not sent: Aris's own check stopped it (the user didn't say no). \(after)Tell the user exactly this one line and stop: \"\(line(english: english))\""
    }
}
