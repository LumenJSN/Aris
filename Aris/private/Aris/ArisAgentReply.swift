//
//  ArisAgentReply.swift
//  Aris (also built into aris-agent)
//
//  What aris-agent tells the app while an answer is on its way, one JSON line each:
//  what the AI is doing, pieces of the answer as they arrive, then the answer or what
//  went wrong. Pieces let Aris start speaking before the AI has finished.
//

import Foundation

/// Something the AI wants to do that needs the user's yes first (ArisRiskPolicy): the exact command,
/// recipient or files, never the AI's own summary of them.
struct ArisConfirmation: Equatable, Sendable {
    let id: String
    /// A few words ("메시지 보내기", "Safari 사용"); for a countdown, who it goes to.
    let title: String
    /// Exactly what would happen; for a countdown, the message.
    let detail: String
    /// A message the user dictated: it goes out after a short countdown unless stopped, rather than being asked.
    let countdown: Bool
    /// What Aris says out loud for a countdown ("엄마한테 ‘곧 갈게’ 보낼게요").
    let spoken: String?
    /// "앞으로 이건 그냥 할까?": a yes makes this kind of action a standing permission (ArisStandingPermissions).
    let proposal: Bool
    /// The details with nothing cut, for the card's 전체 보기; nil when `detail` already has everything.
    let full: String?
    /// The values the user may change before they says yes (ArisCardEdit), chosen by the agent's code for the action's kind,
    /// never by the model; empty for a card that can't be edited.
    let fields: [ArisCardField]
    /// The yes button's word when it isn't 허용 or 보내기: only one of `allowLabels` (Aside's 설치 and 로그인 cards),
    /// anything else is dropped (security review L6).
    let allow: String?
    static let allowLabels: Set<String> = ["설치", "로그인", "Install", "Sign in"]
    /// The card asks about a write to the user's memory (`remember`/`forget`), set by the gate from the action itself: such a
    /// turn never auto-learns (QA BUG-6). Never read from the card's title.
    let memoryWrite: Bool
    /// A desktop card whose yes brings this app's window forward: the process it names (pid, bundle id, start time),
    /// set by the agent's desktop code. Only such a card hands activation back after the user's yes, and only to that very
    /// process (security review of 0c370061: not the turn's last operating app).
    let desktop: ArisCardTarget?
    /// The automatic check stopped this action (ArisAutoMode): the card says so and what was about to happen, its
    /// default is 하지 않기, and 그래도 하기 only asks for the action's own confirm card next. Its yes runs nothing.
    var stopped = false

    init(id: String, title: String, detail: String, countdown: Bool = false, spoken: String? = nil, proposal: Bool = false,
         full: String? = nil, fields: [ArisCardField] = [], allow: String? = nil, memoryWrite: Bool = false, desktop: ArisCardTarget? = nil) {
        self.memoryWrite = memoryWrite
        self.desktop = desktop
        self.id = id
        self.title = title
        self.detail = detail
        self.countdown = countdown
        self.spoken = spoken
        self.proposal = proposal
        self.full = full
        self.fields = fields
        self.allow = allow.flatMap { Self.allowLabels.contains($0) ? $0 : nil }
    }
}

/// The process a desktop card is about: its pid, bundle id and start time (a pid alone can be reused). Pure.
struct ArisCardTarget: Equatable, Sendable {
    let pid: Int32
    let bundle: String
    let started: Double

    var json: [String: Any] { ["pid": Int(pid), "bundle": bundle, "started": started] }

    static func parse(_ value: Any?) -> ArisCardTarget? {
        guard let object = value as? [String: Any], let pid = (object["pid"] as? Int).flatMap({ Int32(exactly: $0) }), pid > 0,
              let bundle = object["bundle"] as? String, !bundle.isEmpty, bundle.count <= 255,
              let started = (object["started"] as? NSNumber)?.doubleValue, started > 0 else { return nil }
        return ArisCardTarget(pid: pid, bundle: bundle, started: started)
    }

    /// The process with that pid now is still the one the card named: the same bundle id, the same start.
    func matches(bundle: String?, started: Double?) -> Bool {
        guard bundle == self.bundle, let started else { return false }
        return abs(started - self.started) < 0.001
    }
}

/// A Claude Code teammate's window opened (POST /teammate): which job, the terminal's pid, the folder it works in
/// (resolved), when it was launched, and its window when the agent could see it (else the app looks it up).
/// `hooks`: whether this Mac's Claude Code has the hooks that tell Aris when the session starts and stops
/// (ArisClaudeHookCheck); nil from an agent that doesn't say. Without them the job can't wait for a Stop (audit team-4).
struct ArisTeammateLaunch: Equatable, Sendable {
    let job: UUID
    let pid: Int32
    let cwd: String
    let at: Date
    let window: Int?
    var hooks: Bool? = nil
    /// What the job's row says while it works, when it isn't the usual line (the terminal the user uses couldn't be handed
    /// a command, so the window is in another one: ArisTerminalWords).
    var note: String? = nil
}

/// The window computer use is working in (`aris-tools desktop`): the app shows its overlay on it and a line in the notch.
/// `window`: the exact window computer use works in (its CoreGraphics number), else the app picks the pid's front window.
struct ArisOperatingTarget: Equatable, Sendable {
    let app: String
    let pid: Int32
    let window: Int?
    /// The notch's line ("카카오톡에서 입력 중…").
    let line: String
}

/// What POST /confirm did with an answer: delivered, refused (403: the agent couldn't tell this was the Aris app, or
/// the card shown wasn't the card it made), or gone (nobody waits for it any more, or the agent didn't answer).
enum ArisConfirmResult: Equatable, Sendable {
    case ok, refused, gone

    /// What the user hears when their answer was refused: it didn't reach the agent, and actions.log says why.
    static let refusedNotice = refusedNotice(english: false)
    /// `english`: the Mac's language (this file is built into aris-agent too, which has none: the app says which).
    static func refusedNotice(english: Bool) -> String {
        english ? "Your answer wasn't delivered: Aris couldn't confirm it came from this app (see actions.log)."
            : "Aris 앱 확인이 안 돼서 승인을 전달하지 못했어요 (actions.log 참고)"
    }

    static func from(status: Int?) -> ArisConfirmResult {
        switch status {
        case 200: return .ok
        case 403: return .refused
        default: return .gone
        }
    }

    /// An inbox card is taken out only when its answer arrived or nobody waits for it; a refused one stays, to be asked
    /// again.
    var acknowledges: Bool { self != .refused }
}

/// What a background job's turn did, as the agent counted it: its tool calls, its steps that failed or weren't done
/// (a refused or failed desktop action, a command that exited non-zero), and whether anything was done. Sent just
/// before the job's answer, so the app never ticks a job green that did nothing, or whose step failed (ArisJobVerdict).
struct ArisJobWork: Equatable, Sendable {
    var tools: Int
    var failed: Int
    var acted: Bool
}

enum ArisAgentReply: Equatable, Sendable {
    /// What the AI is doing ("웹 검색 중").
    case status(String)
    /// A step ended with an error (its command exited non-zero, its tool result was an error): its tag gets no tick.
    /// The step's status when the agent knows which one, else nil (the step running now).
    case stepFailed(String?)
    /// The AI waits for the user's yes or no (POST /confirm).
    case confirm(ArisConfirmation)
    /// A background task's long result was saved here (and opened on screen).
    case file(String)
    /// The next piece of the answer.
    case delta(String)
    /// The whole answer; the last line.
    case answer(String)
    /// What went wrong; the last line.
    case failure(String)
    /// The id of this turn, for a teammate job it dispatched (POST /teammate "turn"): it lets the agent launch that
    /// job without asking. Only the app sees it, never a brain.
    case turn(String)
    /// A teammate's window opened; the stream stays open until the app closes it (the job is over).
    case launched(ArisTeammateLaunch)
    /// This turn counts as outside content (the screen, or text others wrote): its answer is never dispatched as jobs.
    /// `screen`: the conversation has seen the screen; the app keeps that with it (ArisHistoryEntry.sawScreen).
    /// `dispatch`: its jobs may still be dispatched (a screen turn): every one untrusted, and a Claude Code launch always
    /// asks the user (the turn never vouches).
    /// `outside`: the conversation has taken in outside text: nothing in it dispatches; the app keeps that with it.
    case untrusted(screen: Bool, dispatch: Bool = false, outside: Bool = false)
    /// The agent took this turn's jobs block out (outside text came in): the app hands the user's own words out instead,
    /// untrusted (ArisHandOutPlan). Sent just before the answer.
    case refusedJobs
    /// A hands-free turn read the user's messages, mail or notes: its answer is shown, never spoken (anyone near the Mac
    /// could hear it); the app says only that it's on the screen. Sent just before the answer.
    case shownOnly
    /// Computer use is working in this window now (each desktop call says it again; the app takes the overlay down when
    /// the calls stop or the answer comes).
    case operating(ArisOperatingTarget)
    /// The brain read one of the user's skills for this turn (`aris-tools skill read`): the answer shows "<title> 스킬 사용 중".
    case skill(String)
    /// aris-agent answers this turn itself, from its own record or its own routine store, and asks no AI ("why did
    /// you do that?", a routine made, changed, shown or deleted): the app's log and turns.jsonl say so, and no longer
    /// name a brain that was never asked (third VM run: "asking api" / "codex answered" on a Mac with no Codex).
    case helperAnswers
    /// A request's saved desktop steps were done again with no AI (ArisSavedStepsReplay) and answer this turn: the app's
    /// turns.jsonl says "saved-steps", not the brain that was never asked (eighth VM pass). A replay handed over to the AI
    /// says nothing: that turn is the brain's.
    case savedSteps
    /// A background job's work, just before its answer (ArisJobWork).
    case work(ArisJobWork)

    var isLast: Bool {
        switch self {
        case .answer, .failure: return true
        case .status, .stepFailed, .delta, .confirm, .file, .turn, .launched, .untrusted, .refusedJobs, .shownOnly, .operating, .skill, .helperAnswers, .savedSteps, .work: return false
        }
    }

    /// One JSON line, newline included.
    var line: Data {
        let object: [String: Any]
        switch self {
        case .status(let text): object = ["status": text]
        case .stepFailed(let label): object = ["stepFailed": label ?? ""]
        case .confirm(let ask):
            var fields: [String: Any] = ["id": ask.id, "title": ask.title, "detail": ask.detail]
            if ask.countdown { fields["countdown"] = true }
            if let spoken = ask.spoken { fields["spoken"] = spoken }
            if ask.proposal { fields["proposal"] = true }
            if let full = ask.full { fields["full"] = full }
            if !ask.fields.isEmpty { fields["fields"] = ArisCardEdit.json(ask.fields) }
            if let allow = ask.allow { fields["allow"] = allow }
            if let desktop = ask.desktop { fields["desktop"] = desktop.json }
            if ask.stopped { fields["stopped"] = true }
            object = ["confirm": fields]
        case .file(let path): object = ["file": path]
        case .delta(let text): object = ["delta": text]
        case .answer(let text): object = ["answer": text]
        case .failure(let text):
            // A failure that is a brain's missing set-up also says so in a typed form (ArisBrainTrouble).
            object = ArisBrainTrouble.named(in: text).map { ["error": text, "trouble": $0.json] } ?? ["error": text]
        case .turn(let id): object = ["turn": id]
        case .launched(let launch):
            var fields: [String: Any] = ["job": launch.job.uuidString, "pid": Int(launch.pid), "cwd": launch.cwd,
                                         "at": launch.at.timeIntervalSince1970]
            if let window = launch.window { fields["window"] = window }
            if let hooks = launch.hooks { fields["hooks"] = hooks }
            if let note = launch.note { fields["note"] = note }
            object = ["launched": fields]
        case .untrusted(let screen, let dispatch, let outside):
            var fields: [String: Any] = ["untrusted": true]
            if screen { fields["screen"] = true }
            if dispatch { fields["dispatch"] = true }
            if outside { fields["outside"] = true }
            object = fields
        case .refusedJobs: object = ["refusedJobs": true]
        case .shownOnly: object = ["shownOnly": true]
        case .operating(let target):
            var fields: [String: Any] = ["app": target.app, "pid": Int(target.pid), "line": target.line]
            if let window = target.window { fields["window"] = window }
            object = ["operating": fields]
        case .skill(let title): object = ["skill": title]
        case .helperAnswers: object = ["own": true]
        case .savedSteps: object = ["savedSteps": true]
        case .work(let work): object = ["work": ["tools": work.tools, "failed": work.failed, "acted": work.acted]]
        }
        return ((try? JSONSerialization.data(withJSONObject: object)) ?? Data()) + Data("\n".utf8)
    }

    static func line(answer: String?, error: String?) -> Data {
        (answer.map(ArisAgentReply.answer) ?? .failure(error ?? "The AI didn't answer.")).line
    }

    static func parse(_ line: String) -> ArisAgentReply? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let text = object["answer"] as? String { return .answer(text) }
        if let text = object["error"] as? String { return .failure(text) }
        if let text = object["delta"] as? String { return .delta(text) }
        if let text = object["status"] as? String { return .status(text) }
        if let label = object["stepFailed"] as? String { return .stepFailed(label.isEmpty ? nil : String(label.prefix(80))) }
        if let path = object["file"] as? String { return .file(path) }
        if let title = object["skill"] as? String { return .skill(String(title.prefix(40))) }
        if let id = object["turn"] as? String { return .turn(id) }
        if object["refusedJobs"] as? Bool == true { return .refusedJobs }
        if object["own"] as? Bool == true { return .helperAnswers }
        if object["savedSteps"] as? Bool == true { return .savedSteps }
        if let work = object["work"] as? [String: Any], let tools = work["tools"] as? Int, let failed = work["failed"] as? Int {
            return .work(ArisJobWork(tools: max(0, tools), failed: max(0, failed), acted: work["acted"] as? Bool == true))
        }
        if object["shownOnly"] as? Bool == true { return .shownOnly }
        if let fields = object["operating"] as? [String: Any], let app = fields["app"] as? String,
           let pid = (fields["pid"] as? Int).flatMap({ Int32(exactly: $0) }), pid > 0, let line = fields["line"] as? String {
            return .operating(ArisOperatingTarget(app: String(app.prefix(80)), pid: pid, window: fields["window"] as? Int, line: String(line.prefix(80))))
        }
        if object["untrusted"] as? Bool == true {
            return .untrusted(screen: object["screen"] as? Bool == true, dispatch: object["dispatch"] as? Bool == true,
                              outside: object["outside"] as? Bool == true)
        }
        if let fields = object["launched"] as? [String: Any], let job = (fields["job"] as? String).flatMap(UUID.init(uuidString:)),
           let pid = (fields["pid"] as? Int).flatMap({ Int32(exactly: $0) }), let cwd = fields["cwd"] as? String, let at = fields["at"] as? Double {
            return .launched(ArisTeammateLaunch(job: job, pid: pid, cwd: cwd, at: Date(timeIntervalSince1970: at), window: fields["window"] as? Int,
                                               hooks: fields["hooks"] as? Bool, note: (fields["note"] as? String).map { String($0.prefix(200)) }))
        }
        if let ask = object["confirm"] as? [String: Any], let id = ask["id"] as? String, let title = ask["title"] as? String,
           let detail = ask["detail"] as? String {
            var card = ArisConfirmation(id: id, title: title, detail: detail, countdown: ask["countdown"] as? Bool ?? false,
                                        spoken: ask["spoken"] as? String, proposal: ask["proposal"] as? Bool ?? false,
                                        full: ask["full"] as? String, fields: ArisCardEdit.parse(ask["fields"]),
                                        allow: ask["allow"] as? String, desktop: ArisCardTarget.parse(ask["desktop"]))
            card.stopped = ask["stopped"] as? Bool == true
            return .confirm(card)
        }
        return nil
    }
}

/// Why no AI could take a question: which one, and what it lacks on this Mac. The agent ends the turn with its line
/// (in the user's language), and the same line read back (`named(in:)`, or the failure line's "trouble" field) tells
/// the app to put a way to Settings › AI 서비스 beside it, instead of a developer's "Couldn't start … (is it installed?)"
/// (audit f2-no-brain-5).
struct ArisBrainTrouble: Equatable, Sendable {
    enum Missing: String, Sendable, CaseIterable {
        /// The AI's own program (codex, claude, agy) isn't on this Mac.
        case program
        /// The API brain has no key saved.
        case key
        /// The API brain has no provider or model chosen yet.
        case setup
        /// No AI at all can run here (a background job or a schedule with nobody to take it).
        case any
    }

    /// The AI that couldn't start; nil for `any`.
    let brain: ArisBrain?
    let missing: Missing

    /// Whether the user's words are Korean (a line for them is then Korean, else English).
    static func isKorean(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    }

    /// One line for the notch: what is missing and where to fix it.
    func line(korean: Bool) -> String {
        let name = brain?.title ?? "AI"
        switch missing {
        case .program:
            return korean ? "이 Mac에 \(name)가 설치되어 있지 않아요. 설정 › AI 서비스에서 연결하거나 다른 AI를 골라 주세요."
                          : "\(name) isn't installed on this Mac. Connect it or pick another AI in Settings › AI services."
        case .key:
            return korean ? "API 브레인에 쓸 키가 없어요. 설정 › AI 서비스에서 API 키를 넣어 주세요."
                          : "The API brain has no key yet. Add one in Settings › AI services."
        case .setup:
            return korean ? "API 브레인이 아직 설정되지 않았어요. 설정 › AI 서비스에서 제공자와 모델을 골라 주세요."
                          : "The API brain isn't set up yet. Pick a provider and a model in Settings › AI services."
        case .any:
            return korean ? "지금 쓸 수 있는 AI가 없어요. 설정 › AI 서비스에서 AI를 하나 연결해 주세요."
                          : "No AI is ready on this Mac. Connect one in Settings › AI services."
        }
    }

    /// Every trouble there is.
    static var all: [ArisBrainTrouble] {
        [ArisBrain.claude, .codex, .antigravity].map { ArisBrainTrouble(brain: $0, missing: .program) }
            + [ArisBrainTrouble(brain: .api, missing: .key), ArisBrainTrouble(brain: .api, missing: .setup), ArisBrainTrouble(brain: nil, missing: .any)]
    }

    /// The trouble a failure line is, when it is one of these lines exactly (either language); nil for any other failure.
    static func named(in message: String) -> ArisBrainTrouble? {
        all.first { $0.line(korean: true) == message || $0.line(korean: false) == message }
    }

    var json: [String: Any] { brain.map { ["missing": missing.rawValue, "brain": $0.rawValue] } ?? ["missing": missing.rawValue] }

    static func parse(_ value: Any?) -> ArisBrainTrouble? {
        guard let object = value as? [String: Any], let missing = (object["missing"] as? String).flatMap(Missing.init(rawValue:)) else { return nil }
        let trouble = ArisBrainTrouble(brain: (object["brain"] as? String).flatMap(ArisBrain.init(rawValue:)), missing: missing)
        return all.contains(trouble) ? trouble : nil
    }

    /// The line for an AI whose own tool (or, for the API brain, key) is missing: what the notch shows with a button
    /// to Settings › AI 서비스 under it (fresh install F2).
    static func cannotStart(_ brain: ArisBrain, korean: Bool) -> String {
        ArisBrainTrouble(brain: brain, missing: brain == .api ? .key : .program).line(korean: korean)
    }

    /// Whether `text` is one of these lines (the agent's failure line, as the notch shows it).
    static func isCannotStart(_ text: String) -> Bool { named(in: text) != nil }

    /// The button under it.
    static func settingsButton(english: Bool) -> String { english ? "Open Settings › AI services" : "설정 › AI 서비스 열기" }
}

/// When a process started, which with its pid names it for good (a pid alone can be reused). The app sends its own
/// with a background job; aris-agent checks the pid still has that start time before treating the app as there.
enum ArisProcessStart {
    /// Seconds since 1970, from the kernel's process table; nil when there is no such process or it can't be read.
    static func of(pid: Int32) -> Double? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        return Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
    }
}

// MARK: - Editable confirm cards (the owner's ②A)

/// One value on a confirm card that the user may change before they says yes. Which fields an action has is the agent's code
/// (ArisEditableAction), never the model's. A `fixed` field is shown (and echoed) but can't be changed (an event's length).
struct ArisCardField: Equatable, Sendable {
    enum Role: String, Sendable { case recipient, text, time }

    let key: String
    let label: String
    let role: Role
    let value: String
    /// What the AI first wrote, on a card that asks again about values the user changed; nil when `value` is the AI's.
    let original: String?
    let fixed: Bool

    init(key: String, label: String, role: Role, value: String, original: String? = nil, fixed: Bool = false) {
        self.key = key
        self.label = label
        self.role = role
        self.value = value
        self.original = original
        self.fixed = fixed
    }

    /// What the highlighter compares against: the AI's own value.
    var first: String { original ?? value }
}

/// What the user changed on a card, and the card's text as finally shown, which the yes echoes (ArisShownCard): built here
/// the same way in the app and in the agent.
enum ArisCardEdit {
    /// The longest value a field takes.
    static let maxLength = 2000
    /// How long the agent waits for an answer to an editable card in a conversation (the user may be typing). Under the
    /// app's /ask idle timeout (130 s); the app stops waiting `appMargin` before it.
    static let questionTimeout: TimeInterval = 120
    static let appMargin: TimeInterval = 10

    static func values(_ fields: [ArisCardField]) -> [String: String] {
        Dictionary(fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// The fields whose value now differs from the card's own: what goes back with the yes (never a fixed one).
    static func edits(_ fields: [ArisCardField], _ current: [String: String]) -> [String: String] {
        var changed: [String: String] = [:]
        for field in fields where !field.fixed { if let now = current[field.key], now != field.value { changed[field.key] = now } }
        return changed
    }

    /// Highlighted: the value differs from what the AI first wrote.
    static func isMarked(_ field: ArisCardField, _ current: [String: String]) -> Bool {
        (current[field.key] ?? field.value) != field.first
    }

    /// The card's text for its fields as shown, one "label: value" per field.
    static func shown(_ fields: [ArisCardField], _ current: [String: String]) -> String {
        fields.map { "\($0.label): \($0.fixed ? $0.value : current[$0.key] ?? $0.value)" }.joined(separator: "\n")
    }

    /// Every value as aris-tools must read it (ArisCardEdit.accepts): the card's yes waits until they are.
    static func allAccepted(_ fields: [ArisCardField], _ current: [String: String]) -> Bool {
        fields.allSatisfy { $0.fixed || accepts(current[$0.key] ?? $0.value, role: $0.role) }
    }

    /// A value aris-tools reads as the user meant it: not empty, not an option, no control or format characters (a ZWJ only
    /// inside an emoji sequence of a message), a message may have lines but a recipient and a time are one line (no
    /// line or paragraph separator either), and a time is exactly YYYY-MM-DD HH:MM on a real day.
    static func accepts(_ value: String, role: ArisCardField.Role) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-"), value.count <= maxLength else { return false }
        let scalars = Array(value.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            let category = scalar.properties.generalCategory
            if role == .text, scalar == "\n" { continue }
            if role == .text, scalar.value == 0x200D, index > 0, index + 1 < scalars.count,
               scalars[index - 1].properties.isEmoji || scalars[index - 1].value == 0xFE0F, scalars[index + 1].properties.isEmoji { continue }
            if CharacterSet.controlCharacters.contains(scalar) || category == .lineSeparator || category == .paragraphSeparator { return false }
        }
        return role != .time || isMoment(value)
    }

    static func isMoment(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$"#, options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }

    /// The lines of an editable card's details above its fields' own text (why it asks); nil when none.
    static func note(_ question: ArisConfirmation) -> String? {
        let fields = shown(question.fields, values(question.fields))
        let rest = question.detail.hasSuffix(fields) ? String(question.detail.dropLast(fields.count)) : ""
        let note = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? nil : note
    }

    static func json(_ fields: [ArisCardField]) -> [[String: String]] {
        fields.map { field in
            var object = ["key": field.key, "label": field.label, "role": field.role.rawValue, "value": field.value]
            if let original = field.original { object["original"] = original }
            if field.fixed { object["fixed"] = "1" }
            return object
        }
    }

    /// The stream's fields; anything malformed, an unknown role or a repeated key is dropped.
    static func parse(_ raw: Any?) -> [ArisCardField] {
        var seen: Set<String> = []
        return (raw as? [[String: Any]] ?? []).compactMap { object in
            guard let key = object["key"] as? String, let label = object["label"] as? String, let value = object["value"] as? String,
                  let role = (object["role"] as? String).flatMap(ArisCardField.Role.init(rawValue:)), seen.insert(key).inserted else { return nil }
            return ArisCardField(key: key, label: label, role: role, value: value, original: object["original"] as? String,
                                 fixed: object["fixed"] as? String == "1")
        }
    }

    /// /confirm's "edits": string values no longer than `maxLength`, at most 8 of them; nil when malformed, empty when absent.
    static func edits(from raw: Any?) -> [String: String]? {
        guard let raw else { return [:] }
        guard let object = raw as? [String: Any], object.count <= 8 else { return nil }
        var edits: [String: String] = [:]
        for (key, value) in object {
            guard let text = value as? String, text.count <= maxLength, key.count <= 32 else { return nil }
            edits[key] = text
        }
        return edits
    }
}
