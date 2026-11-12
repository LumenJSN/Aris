//
//  ArisDesktopBatch.swift
//  aris-agent
//
//  `desktop batch`: several steps in one call (click, type, set-value, press, scroll), so the brain doesn't take a turn
//  between steps it already knows. Nothing about one step changes: the gate decides on every step before anything is done
//  (a refusal refuses the whole batch), and each step is one ordinary action with its own fresh look, its stale-snapshot
//  guard, its read-back and its text ladder (ArisDesktopController). The user sees one card for the whole batch, with every
//  step's exact text. It stops at the first step that isn't confirmed. A send (Return, a Send button) can only be the last
//  step. Later steps name a control of the look the batch started from (its ref) or by its label: found again in the
//  newest look, or the batch stops there, with nothing done at that step. A window that opens stops it.
//  System Settings and Finder go a step at a time: their tiers and places are judged per call, against the window as it
//  is then. In a sending app the card must be able to say what goes: one text, into a field in the window now that gives
//  its value; the send is held to exactly that (the same guard as one call). Anything else there goes a step at a time,
//  and so does a paste (its own card shows the clipboard) and everything in Calendar and Reminders (each call asks).
//

import Foundation

struct ArisDesktopStep: Equatable {
    enum Target: Equatable {
        case ref(ArisDesktopRef)
        case label(String)
    }

    let verb: ArisDesktopVerb
    var target: Target? = nil
    var keys: [String] = []
    var text: String? = nil
    var direction: String? = nil
    var amount: Int? = nil

    /// The one action this step is: `ref` the control found for it, `window` where its keys go.
    func request(ref: ArisDesktopRef?, app: String, window: Int?) -> ArisDesktopRequest {
        var request = ArisDesktopRequest(verb: verb)
        request.ref = ref
        request.app = app
        request.keys = keys
        request.text = text
        request.direction = direction
        request.amount = amount
        if verb == .press { request.window = window }
        return request
    }
}

enum ArisDesktopBatch {
    /// A key combo as a set of normalised names: modifier aliases mapped (command/meta/super/⌘ → cmd, control → ctrl,
    /// option/opt → alt), the deleting keys as one ("backspace" → delete), order and case aside (security review:
    /// "a+cmd", "meta+a" and "super+a" are select-all too).
    static func normalized(_ combo: String) -> Set<String> {
        let aliases = ["command": "cmd", "meta": "cmd", "super": "cmd", "⌘": "cmd", "control": "ctrl", "option": "alt", "opt": "alt",
                       "backspace": "delete", "forwarddelete": "delete", "del": "delete"]
        return Set(combo.lowercased().split(separator: "+").map { aliases[String($0)] ?? String($0) })
    }

    static func isSelectAll(_ combo: String) -> Bool { normalized(combo) == ["cmd", "a"] }
    static func isDeletion(_ combo: String) -> Bool { normalized(combo).contains("delete") }

    /// A control or text mark that selects everything ("Select All", "모두 선택", "전체 선택").
    static func selectsAll(label: String) -> Bool {
        label.range(of: #"(?i)^\s*(select\s+all|모두\s*선택|전체\s*선택)\s*$"#, options: .regularExpression) != nil
    }

    /// The batch replaces what is there: anywhere in it, a select-all (keys, or a "Select All" control) followed by
    /// typing or a delete (security review: "type x, cmd+a, type y" and "cmd+a, delete" passed). `labels`: what each
    /// step's target is called, when known.
    /// A step that selects everything and deletes in one go counts by itself (audit desk-3: `press cmd+a delete`, the
    /// form the prompt teaches, passed as one step), and so does a delete in a later step that selects again.
    static func replacesAll(_ steps: [ArisDesktopStep], labels: [String?] = []) -> Bool {
        var selected = false
        for (index, step) in steps.enumerated() {
            let label: String? = index < labels.count ? labels[index] : nil
            let named: String? = { if case .label(let text) = step.target { return text }; return nil }()
            if selected, step.text != nil || step.keys.contains(where: isDeletion) { return true }
            if step.keys.contains(where: isSelectAll) || [label, named].compactMap({ $0 }).contains(where: selectsAll(label:)) {
                if selectsThenDeletes(step.keys) { return true }
                selected = true
            }
        }
        return false
    }

    /// One press that selects everything and then deletes it (`cmd+a delete`): a select-all with a deleting key after it.
    static func selectsThenDeletes(_ keys: [String]) -> Bool {
        guard let first = keys.firstIndex(where: isSelectAll) else { return false }
        return keys[(first + 1)...].contains(where: isDeletion)
    }

    /// What one press leaves of a selection of everything: true when its last word on it is a select-all, false when a
    /// delete or a caret key came after (nothing is selected any more), nil when it touches neither.
    static func leavesAllSelected(_ keys: [String]) -> Bool? {
        var state: Bool?
        for key in keys {
            if isSelectAll(key) { state = true } else if isDeletion(key) || ArisDesktopVerify.movesCaretOnly([key]) { state = false }
        }
        return state
    }

    /// Whether a look shows everything in the focused text control selected; nil when the look can't tell.
    static func allSelected(in look: ArisDesktopObservation?) -> Bool? {
        guard let field = look?.focusedElement, field.isTextEntry, let range = field.selectedRange, let text = field.rawValue ?? field.value else { return nil }
        return range.length > 0 && range.location == 0 && range.length >= text.utf16.count
    }

    /// The user's words ask for the document to be replaced or cleared, not added to: whole words only.
    static func asksToReplace(_ request: String) -> Bool {
        // Korean verbs by their stems (a particle or ending follows); English as whole words.
        // Emptying it is his to ask for too (삭제, 비워, 없애, delete, empty: audit desk-3, now that one `press cmd+a delete`
        // is held to their words as well). Never the bare stem 지우: it is also a name.
        let korean = #"(바꿔|바꾸|바꿀|바꾼|지우고|지우기|지울|지워|삭제|비워|비우고|비울|없애|다시\s*써|새로\s*써|덮어\s*써|덮어써)"#
        let english = #"(?i)\b(replace|overwrite|clear|erase|delete|remove|empty|wipe)\b"#
        return request.range(of: korean, options: .regularExpression) != nil || request.range(of: english, options: .regularExpression) != nil
    }

    static let appendLine = "Not done: selecting everything (or deleting) before typing would replace the whole document, and the user asked to " +
        "write or add, not to replace. Type at the end instead: click at the end of the text (or press cmd+down first), then type, with no select-all or delete."

    static let maxSteps = 10
    /// How often, and how far apart, the window is read again for a control the last step should have brought up.
    static let settleLooks = 3
    static let settleWait: TimeInterval = 0.12

    static let oneAtATimeLine = "Refused: this goes a step at a time here (System Settings, Finder, or a messaging app whose card couldn't say exactly what goes). Use single desktop calls."
    static let calendarStepLine = "Refused: in Calendar and Reminders desktop steps go one call at a time (each asks the user on a card), never as a batch. " +
        "To add, change or delete an event or a reminder, use `aris-tools event …` or `aris-tools remind …`. Nothing was done."
    static let sendLastLine = "Refused: in a batch a send (Return, a Send button) can only be the last step. Nothing was done."
    static let oneAppLine = "Refused: every ref in a batch must come from one look at the app it names. Nothing was done."
    static let lookFirstLine = "Look first: `desktop see --app \"<App>\"`, then batch on what it shows (a sheet that can't be read goes a step at a time). Nothing was done."
    static let openedLine = "A new window opened, so the next step wasn't aimed at it. Act on the window below, or `desktop see` the new one."
    /// A batch step waits this long apart (8 reads, 1.6 s) for a window it may have opened: the next step must not be aimed
    /// past a panel that came up late (security review M1). A single call keeps the shorter wait.
    static let openWait: TimeInterval = 0.2
    static let frontLine = "Another of the app's windows came to the front (or one opened), so the next step wasn't aimed at it. Act on the window below, or `desktop see` again."
    static func uncoveredLine(_ label: String) -> String {
        "“\(ArisDesktopCard.shown(label))” needs the user's card, and this batch's card didn't show it, so nothing was done at this step. Do it as its own call."
    }
    static let notOnCardLine = "That step would send, and the user's card didn't say so, so it wasn't done."
    static let stoppedFormat = "Stopped at step %d of %d; the steps after it weren't done."
    /// A step that deletes, replaces, discards, sends, pays or quits (M2): the risk gate's own words, and these, English
    /// and Korean (this Mac's labels: 저장 안 함 is Don't Save, 대치 is a file panel's Replace).
    static func riskyWords(_ label: String) -> Bool {
        if ArisRiskPolicy.mentionsRiskyStep(label) { return true }
        let folded = ArisRiskPolicy.folded(label)
        return ["replace", "don't save", "don’t save", "dont save", "erase", "discard", "remove", "delete", "send", "pay", "buy", "quit",
                "삭제", "지우기", "지움", "제거", "바꾸기", "대치", "저장 안 함", "저장 안함", "버리기", "폐기", "결제", "구매", "종료", "보내기", "전송"]
            .contains(where: folded.contains)
    }

    /// The document apps where Return in the text is a new line, by exact bundle id (security review of b7997da3: a
    /// denylist of sending apps fails open for Discord, Slack or Google Chat as web apps, Element, Lark…).
    static let documentApps: Set<String> = ["com.apple.TextEdit", "com.apple.iWork.Pages", "com.apple.Notes", "md.obsidian", "net.shinyfrog.bear",
                                             "com.microsoft.Word", "com.apple.dt.Xcode"]

    /// Return pressed into a document's text is a new line, not a send (QA retest on 0c370061). An allowlist, failing
    /// closed: only a plain Return or Enter; only a document app by its exact bundle id, installed and signed as that
    /// app (never a browser, a web app or a sending app); into a text area that is no web content (its focus has no
    /// AXWebArea above it, `webAncestor` false, and no web area of the look holds it); in a look Peekaboo didn't cut,
    /// with no send control in it. Anything else keeps the send rule. Pure.
    static func newline(_ step: ArisDesktopStep, into control: ArisDesktopElement?, in look: ArisDesktopObservation?, target: ArisDesktopTarget,
                        webAncestor: Bool?) -> Bool {
        guard step.verb == .press, !step.keys.isEmpty, step.keys.allSatisfy({ ["return", "enter"].contains($0.lowercased()) }) else { return false }
        guard let bundle = target.bundle, documentApps.contains(bundle), target.known, !target.sending, !target.browser, !target.never else { return false }
        guard let control, control.role == "textArea" || control.axRole == "AXTextArea", let look, !look.truncated, webAncestor == false else { return false }
        let web = look.elements.contains { ($0.axRole == "AXWebArea" || $0.role == "webArea") && $0.bounds.contains(control.centre) }
        return !web && !look.shown.contains { $0.actionable && ArisDesktopGate.mentionsSend($0.label) }
    }

    /// A raw point the job's own card may cover without a spot card of its own (QA live on 827cfdb4), as an allowlist
    /// failing closed (security review of 4d40bb80): a document app as for `newline` (exact bundle, known, never sending,
    /// a browser or the never-list), focus not in web content, a look Peekaboo didn't cut with no web area at the point,
    /// and under the point a text area or field with a label that names nothing risky. A button, an image, a link, a menu
    /// item, an unlabelled control or nothing at all keeps the spot card. Pure.
    static func spotCovered(_ there: ArisDesktopElement?, at point: CGPoint, in look: ArisDesktopObservation, target: ArisDesktopTarget, webAncestor: Bool?) -> Bool {
        guard let bundle = target.bundle, documentApps.contains(bundle), target.known, !target.sending, !target.browser, !target.never else { return false }
        guard webAncestor == false, !look.truncated else { return false }
        guard !look.elements.contains(where: { ($0.axRole == "AXWebArea" || $0.role == "webArea") && $0.bounds.contains(point) }) else { return false }
        guard let there, there.isTextEntry, !there.isSecure, !there.id.hasPrefix("ocr_") else { return false }
        let label = there.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return !label.isEmpty && !riskyWords(label) && !ArisDesktopGate.mentionsSend(label)
    }

    /// The text control a step's keys go to: the last text control an earlier step worked in, else the window's focus.
    static func keysInto(_ index: Int, elements: [ArisDesktopElement?], look: ArisDesktopObservation?) -> ArisDesktopElement? {
        elements.prefix(index).reversed().compactMap { $0 }.first(where: \.isTextEntry) ?? look?.focusedElement
    }

    static func missing(_ what: String) -> String { "“\(what)” isn't in the window, so nothing was done at this step." }
    static func ambiguous(_ what: String) -> String { "More than one control is called “\(what)”, so nothing was done at this step. Use its ref." }

    // MARK: - The words

    /// The steps of a batch's text: one a line (or, in agy's relay line, separated by ` ;; `).
    static func steps(_ text: String, relay: Bool) throws -> [ArisDesktopStep] {
        let lines = relay ? text.components(separatedBy: " ;; ") : text.components(separatedBy: "\n")
        let steps = try lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(step)
        guard (1...maxSteps).contains(steps.count) else { throw ArisDesktopUsage(text: "batch takes 1 to \(maxSteps) steps, one a line") }
        // A text mark is read from the screen once, for the look it came from: only the first step can click one.
        for (index, step) in steps.enumerated() {
            if case .ref(let ref) = step.target, ref.mark, index > 0 || step.verb != .click { throw ArisDesktopUsage(text: ArisDesktopWords.markLine) }
        }
        return steps
    }

    private static let usage = "A batch step is: click <ref or \"label\"> | type <ref or \"label\"> <text> | set-value <ref or \"label\"> <text> | press <keys…> | scroll <ref or \"label\"> up|down [N]"

    private static func step(_ line: String) throws -> ArisDesktopStep {
        guard !line.unicodeScalars.contains(where: ArisCommandPolicy.isLineBreak) else { throw ArisDesktopUsage(text: usage) }
        let trimmed = String(line.drop(while: { $0 == " " }))
        let head = trimmed.prefix { $0 != " " }
        let rest = String(trimmed.dropFirst(head.count + 1))
        switch String(head) {
        case "click":
            let (target, after) = try self.target(rest)
            guard after.trimmingCharacters(in: .whitespaces).isEmpty else { throw ArisDesktopUsage(text: usage) }
            return ArisDesktopStep(verb: .click, target: target)
        case "type", "set-value":
            let (target, after) = try self.target(rest)
            guard !after.isEmpty, !after.trimmingCharacters(in: .whitespaces).isEmpty else { throw ArisDesktopUsage(text: usage) }
            return ArisDesktopStep(verb: head == "type" ? .type : .setValue, target: target, text: after)
        case "press":
            let keys = rest.split(separator: " ").map { $0.lowercased() }
            guard (1...ArisDesktopWords.maxChords).contains(keys.count), keys.allSatisfy(ArisDesktopWords.isKeyCombo) else { throw ArisDesktopUsage(text: usage) }
            return ArisDesktopStep(verb: .press, keys: keys)
        case "scroll":
            let (target, after) = try self.target(rest)
            let words = after.split(separator: " ").map(String.init)
            guard let direction = words.first, ["up", "down", "left", "right"].contains(direction), words.count <= 2 else { throw ArisDesktopUsage(text: usage) }
            let amount = words.count == 2 ? Int(words[1]) : nil
            if words.count == 2, amount.map({ (1...50).contains($0) }) != true { throw ArisDesktopUsage(text: usage) }
            return ArisDesktopStep(verb: .scroll, target: target, direction: direction, amount: amount)
        default:
            throw ArisDesktopUsage(text: usage)
        }
    }

    /// The control a step names and what follows it: a ref, or a label in double quotes.
    private static func target(_ text: String) throws -> (ArisDesktopStep.Target, String) {
        if text.hasPrefix("\"") {
            let body = text.dropFirst()
            guard let end = body.firstIndex(of: "\"") else { throw ArisDesktopUsage(text: usage) }
            let label = String(body[..<end])
            guard !label.isEmpty, label.count <= 160, !ArisDesktopWords.hasControl(label), !ArisMCPPolicy.hidesCharacters(label) else { throw ArisDesktopUsage(text: usage) }
            return (.label(label), String(body[body.index(after: end)...].dropFirst()))
        }
        let word = String(text.prefix { $0 != " " })
        guard let ref = ArisDesktopRef.parse(word) else { throw ArisDesktopUsage(text: usage) }
        return (.ref(ref), String(text.dropFirst(word.count + 1)))
    }

    // MARK: - Finding a step's control

    enum Found {
        case control(ArisDesktopElement)
        case missing
        case several
    }

    /// The control a label names in this look: the one shown with that label, the acting one when others only repeat it
    /// (a heading with the same words); a text step only a field.
    static func find(label: String, in look: ArisDesktopObservation, forText: Bool) -> Found {
        let wanted = label.precomposedStringWithCanonicalMapping
        var matches = look.shown.filter { $0.label.precomposedStringWithCanonicalMapping == wanted && (!forText || $0.isTextEntry) }
        if matches.count > 1 {
            let acting = matches.filter(\.actionable)
            if !acting.isEmpty { matches = acting }
        }
        return matches.isEmpty ? .missing : matches.count == 1 ? .control(matches[0]) : .several
    }

    /// The control a step names in a look: a ref's element as it was in the look the batch started from, found again.
    static func find(_ step: ArisDesktopStep, in look: ArisDesktopObservation, ledger: ArisComputerUseLedger) -> Found {
        switch step.target {
        case .none: return .missing
        case .label(let label): return find(label: label, in: look, forText: step.text != nil)
        case .ref(let ref):
            guard let element = ledger.element(ref) else { return .missing }
            // A text mark (the first step, its look the newest): the controller reads the screen again before the click.
            if ref.mark { return .control(element) }
            return ArisDesktopVerify.find(element, in: look).map(Found.control) ?? .missing
        }
    }

    /// What the user's card says of a step's control (a label not found yet is said as it was named).
    static func stepLabel(_ step: ArisDesktopStep, element: ArisDesktopElement?, english: Bool = false) -> String {
        if let element {
            return "\(element.role.isEmpty ? "" : ArisDesktopCard.roleWord(element.role, english: english) + " ")“\(ArisDesktopCard.shown(String(element.label.prefix(80))))”"
        }
        if case .label(let label) = step.target { return "“\(ArisDesktopCard.shown(label))”" }
        return english ? ArisDesktopCopy.anyRole : "요소"
    }
}

extension ArisDesktopCard {
    /// The card for a whole batch: every step, with its exact text and keys; in a sending app what the field holds and
    /// exactly what would go. `english`: the whole card in English (audit desk-11), else Korean.
    static func batch(_ steps: [ArisDesktopStep], elements: [ArisDesktopElement?], target: ArisDesktopTarget, window: String?, composer: String?, sends: String?,
                      remember: Bool, wiped: Bool, mayRaise: Bool = false, english: Bool = false) -> ArisMCPCard {
        let say = { (korean: String, inEnglish: String) in english ? inEnglish : korean }
        let empty = say("(비어 있음)", "(empty)")
        var lines: [String] = []
        if let window { lines.append(ArisDesktopCopy.windowLine(window, english: english)) }
        if target.sending, let composer { lines.append(say("칸에 지금 있는 글:\n", "In the field now:\n") + (composer.isEmpty ? empty : shown(composer))) }
        for (index, step) in steps.enumerated() {
            var line = "\(index + 1). \(verbLabel(step.verb, english: english))"
            if step.target != nil { line += ": " + ArisDesktopBatch.stepLabel(step, element: elements[index], english: english) }
            if !step.keys.isEmpty { line += ": " + keyWords(step.keys, english: english) }
            if let direction = step.direction { line += " (\(shown(direction)))" }
            if let text = step.text { line += say("\n입력하는 글:\n", "\nText to type:\n") + shown(text) }
            lines.append(line)
        }
        if let sends { lines.append(say("보낼 글 (입력한 뒤 칸에 있는 그대로):\n", "Text to send (what the field holds after the typing):\n") + (sends.isEmpty ? empty : shown(sends))) }
        if mayRaise {
            lines.append(say("백그라운드로 안 되는 단계는 창을 앞으로 가져와서 해요 (끝나면 원래 앱으로 돌아가요)",
                             "A step that can't be done in the background brings the window to the front (then the app you were in comes back)"))
        }
        if ArisDesktopBatch.replacesAll(steps, labels: elements.map { $0?.label }), let typed = steps.first(where: { $0.text != nil })?.text {
            let start = shown(String(typed.prefix(60))) + (typed.count > 60 ? "…" : "")
            lines.insert(say("⚠️ 문서 내용을 모두 지우고 ‘\(start)’로 바꿔요", "⚠️ This deletes everything in the document and puts ‘\(start)’ in its place"), at: 0)
        }
        lines += closing(target: target, remember: remember, wiped: wiped, english: english)
        let detail = lines.joined(separator: "\n")
        let short = detail.count > 600 ? String(detail.prefix(600)) + "…" : detail
        let name = shown(target.name)
        let title = sends != nil ? say("\(name)에서 보내기", "Send in \(name)") : say("\(name)에서 \(steps.count)단계 하기", "\(steps.count) steps in \(name)")
        return ArisMCPCard(title: title, detail: short, full: short == detail ? nil : detail, fields: [])
    }
}

extension ArisDesktopEngine {
    /// What a sending app's card can hold the batch to; nil: it can't, so a step at a time.
    private func sendingBasis(_ steps: [ArisDesktopStep], target: ArisDesktopTarget, window: ArisDesktopWindow, turn: ArisDesktopTurn) -> (basis: ArisDesktopBasis, sends: String?)? {
        guard access.trusted, case .success(let binary) = installer.ready() else { return nil }
        let session = ArisDesktopSession(engine: self, binary: binary, target: target, turn: turn)
        guard case .success(let (look, _)) = session.look(window, record: false) else { return nil }
        turn.ledger.discard(look.peekaboo)
        let written = steps.filter { $0.text != nil }
        guard written.count <= 1 else { return nil }
        var basis = ArisDesktopBasis(title: look.title, window: look.window)
        var after: String?
        var field: ArisDesktopElement?
        if let step = written.first {
            guard case .control(let found) = ArisDesktopBatch.find(step, in: look, ledger: turn.ledger), found.isTextEntry, !found.isSearch, !found.isSecure, !found.rawCapped,
                  let raw = found.rawValue else { return nil }
            field = found
            basis.composer = raw
            after = step.verb == .setValue ? ArisPeekabooCommands.composed(step.text ?? "") : ArisPeekabooCommands.composed(raw + (step.text ?? ""))
        }
        guard let last = steps.last else { return nil }
        var control: ArisDesktopElement?
        if case .control(let found) = ArisDesktopBatch.find(last, in: look, ledger: turn.ledger) { control = found }
        let composer = field ?? look.composer(for: control)
        guard Self.sends(last, control: control, composer: composer, app: target.name) else { return (basis, nil) }
        guard let composer, !composer.rawCapped, !composer.isSecure else { return nil }
        if after == nil {
            guard let raw = composer.rawValue else { return nil }
            basis.composer = raw
            after = raw
        }
        basis.send = true
        return (basis, after)
    }

    /// The step may send what the field holds: Return, a control named for it, or an icon with no name right by the field.
    fileprivate static func sends(_ step: ArisDesktopStep, control: ArisDesktopElement?, composer: ArisDesktopElement?, app: String) -> Bool {
        var named = control
        if named == nil, case .label(let label) = step.target { named = ArisDesktopElement(id: "elem_0", role: "", label: label) }
        if ArisDesktopGate.isSend(step.request(ref: nil, app: app, window: nil), element: named) { return true }
        if step.verb == .click, let control, control.isUnlabelledButton, let composer { return ArisDesktopObservation.distance(composer, control) <= sendReach }
        return false
    }

    /// One `desktop batch` call. Blocks its caller, as one call does.
    func handleBatch(_ request: ArisDesktopRequest, turn: ArisDesktopTurn, done: @escaping (ArisMCPOutcome) -> Void) {
        let steps = request.steps
        let what = "desktop batch · \(request.app ?? "")"
        let refuse = { (why: String) in
            turn.audit(["answer": "refused (\(why.prefix(80)))", "action": what, "brain": turn.brainName])
            done(.failed(why))
        }
        // Every step counts toward the turn's cap.
        var count = 0
        for _ in steps { count = turn.desktopStep() }
        guard count <= (turn.isTask ? Self.maxJobSteps : Self.maxSteps) else { return refuse(Self.stepsLine(job: turn.isTask)) }
        let target: ArisDesktopTarget
        switch resolve(request, turn: turn) {
        case .failure(let why): return refuse(why.text)
        case .success(let found): target = found
        }
        if turn.brain == .codex, computerEngine() == .codex { return refuse(Self.codexEngineLine) }
        // The never-list and browsers first, as for one call; then what is only judged a call at a time.
        if case .refuse(let why) = ArisDesktopGate.decide(steps[0].request(ref: nil, app: request.app ?? "", window: nil), target: target,
                                                          context: ArisDesktopContext(home: identity.home), remembered: false, secureInput: false), target.never || target.browser {
            return refuse(why)
        }
        if target.settings || target.bundle == ArisShownPlace.finder { return refuse(ArisDesktopBatch.oneAtATimeLine) }
        if ArisDesktopGate.isCalendarApp(target) { return refuse(ArisDesktopBatch.calendarStepLine) }
        // Selecting everything (or deleting) before typing replaces the document: only when the user's words say so (QA
        // retest: "…창에 X 라고 써 줘 / 덧붙여" was planned as click, cmd+a, type).
        if ArisDesktopBatch.replacesAll(steps), !ArisDesktopBatch.asksToReplace(turn.request) { return refuse(ArisDesktopBatch.appendLine) }
        // A select-all pressed earlier in this window, then text typed here: the same replace, across calls.
        if steps.contains(where: { $0.text != nil }), turn.ledger.selectedAll(in: windows.windows(of: target.pid).first?.id), !ArisDesktopBatch.asksToReplace(turn.request) {
            return refuse(ArisDesktopBatch.appendLine)
        }
        // Every ref from one look at this app, the newest of its window (the stale-snapshot guard, as for one call).
        var refs: [ArisDesktopRef] = []
        for case .ref(let ref)? in steps.map(\.target) { refs.append(ref) }
        for ref in refs {
            guard let owner = turn.ledger.target(ofSnapshot: ref.snapshot) else { return refuse(Self.notOursLine) }
            guard owner.pid == target.pid, owner.bundle == target.bundle, ref.snapshot == refs[0].snapshot else { return refuse(ArisDesktopBatch.oneAppLine) }
        }
        let appWindows = windows.windows(of: target.pid)
        let front = appWindows.first
        // The window the user named: a batch in another one, or with no ref in any window while they named one, is refused (QA
        // BUG-47 reopened).
        if let named = ArisWindowNaming.named(in: turn.request, windows: appWindows) {
            let inNamed = refs.first.flatMap { turn.ledger.window(ofSnapshot: $0.snapshot) } == named.id
            if !inNamed { return refuse(ArisWindowNaming.wrongWindowLine(named: named.title ?? "", app: target.name)) }
        }
        // A batch may name its window by title as the look did (QA live on 827cfdb4: `--title` after `see --title` was
        // refused as unreadable words, "never"): the refs' window must be that one; with no ref, that window.
        let titled: ArisDesktopWindow?
        if let title = request.title {
            switch ArisWindowTitleMatch.pick(title, in: appWindows) {
            case .one(let id): titled = appWindows.first { $0.id == id }
            case let match: return refuse(ArisWindowTitleMatch.line(match, wanted: title, app: target.name) ?? ArisDesktopBatch.lookFirstLine)
            }
        } else {
            titled = nil
        }
        let window: ArisDesktopWindow
        if let first = refs.first {
            if !turn.ledger.isLatest(first.snapshot) {
                // A stale ref: nothing, and the window as Aris last saw it (no new look, nothing through the controller: L1).
                guard let id = turn.ledger.window(ofSnapshot: first.snapshot), let latest = turn.ledger.latestLook(window: id) else {
                    return refuse("That ref is from an older look, and the window is gone. Look again.")
                }
                turn.audit(["answer": "refused (stale ref)", "action": what, "brain": turn.brainName])
                return done(ArisMCPOutcome(status: 1, output: ArisMCPPolicy.wrapped(ArisDesktopSession.staleLine(latest), server: target.name, tool: "desktop batch",
                                                                                     secrets: [], isError: true)))
            }
            guard let id = turn.ledger.window(ofSnapshot: first.snapshot), let found = windows.windows(of: target.pid).first(where: { $0.id == id }) else {
                return refuse("That window is gone (closed or moved off screen), so nothing was done. Look again.")
            }
            if let titled, titled.id != found.id {
                return refuse(ArisWindowNaming.wrongWindowLine(named: titled.title ?? request.title ?? "", app: target.name))
            }
            window = found
        } else if let titled {
            window = titled
        } else {
            guard let front else { return refuse("\(target.name) has no open window on screen.") }
            window = front
        }
        guard let start = turn.ledger.latestLook(window: window.id) else { return refuse(ArisDesktopBatch.lookFirstLine) }
        // The same replace across calls, in the window the batch really works in (not only the front one), and for a
        // delete as for text (audit desk-3).
        if steps.contains(where: { $0.text != nil || $0.keys.contains(where: ArisDesktopBatch.isDeletion) }), turn.ledger.selectedAll(in: window.id),
           !ArisDesktopBatch.asksToReplace(turn.request) {
            return refuse(ArisDesktopBatch.appendLine)
        }
        // Every step's gate, before anything is done.
        let taint = turn.taint(forApp: target.readKey)
        let context = ArisDesktopContext(taintForApp: taint, screen: turn.screen, handsFree: turn.handsFree, job: turn.isTask, relayed: turn.relayed, home: identity.home,
                                         request: turn.request, critical: turn.critical)
        let remembered = target.memoryKey.map { turn.ledger.allows($0, tainted: taint != .none) } ?? false
        let name = request.app ?? target.name
        var elements: [ArisDesktopElement?] = []
        var asks = false, remember = true
        for (index, step) in steps.enumerated() {
            var element: ArisDesktopElement?
            if case .control(let found) = ArisDesktopBatch.find(step, in: start, ledger: turn.ledger) { element = found }
            elements.append(element)
            switch ArisDesktopGate.decide(step.request(ref: nil, app: name, window: nil), target: target, context: context, remembered: remembered,
                                          secureInput: apps.secureInput, element: element) {
            case .refuse(let why): return refuse(why)
            case .judge: return refuse(ArisDesktopBatch.oneAtATimeLine)
            case .ask(let keep):
                asks = true
                remember = remember && keep
            case .run: break
            }
            if index < steps.count - 1, !ArisDesktopBatch.newline(step, into: ArisDesktopBatch.keysInto(index, elements: elements, look: start), in: start, target: target,
                                                                  webAncestor: apps.focusedInWebArea(pid: target.pid)),
               Self.sends(step, control: element, composer: element == nil ? nil : start.composer(for: element), app: name) {
                return refuse(ArisDesktopBatch.sendLastLine)
            }
        }
        var basis = ArisDesktopBasis(title: start.title, window: start.window)
        var sends: String?
        if target.sending {
            guard let held = sendingBasis(steps, target: target, window: window, turn: turn) else { return refuse(ArisDesktopBatch.oneAtATimeLine) }
            (basis, sends) = (held.basis, held.sends)
        }
        let opening = Set(windows.windows(of: target.pid).map(\.id))
        let frontId = windows.windows(of: target.pid).first?.id
        // What the user's card named for each step (nil: no card was shown).
        let named = steps.enumerated().map { index, step -> String? in
            if let element = elements[index] { return element.label }
            if case .label(let label) = step.target { return label }
            return nil
        }
        // Once the controls are known: a "Select All" control named by a ref counts too.
        if ArisDesktopBatch.replacesAll(steps, labels: elements.map { $0?.label }), !ArisDesktopBatch.asksToReplace(turn.request) { return refuse(ArisDesktopBatch.appendLine) }
        let run = { [self] (held: ArisDesktopBasis, card: [String?]?) in
            let outcome = runBatch(steps, name: name, target: target, window: window, opening: opening, front: frontId, basis: held, expected: sends, card: card, turn: turn)
            if outcome.status != 0 { turn.audit(["answer": "stopped (\(Self.reason(outcome.output)))", "action": what, "brain": turn.brainName]) }
            // The app in front when the card went up comes back, whether the steps worked or not.
            putBack(held.frontBefore, target: target)
            done(outcome)
        }
        guard asks else { return run(basis, nil) }
        let english = ArisDesktopCopy.isEnglish(turn.request)
        let card = ArisDesktopCard.batch(steps, elements: elements, target: target, window: basis.title, composer: basis.composer, sends: sends, remember: remember,
                                         wiped: target.memoryKey.map(turn.ledger.wasWiped) ?? false, mayRaise: !turn.isTask && !target.sending, english: english)
        turn.operating(ArisOperatingTarget(app: target.name, pid: target.pid, window: window.id, line: Self.statusLine(.batch, app: target.name, english: english)))
        let frontBefore = apps.frontmostPid().flatMap(apps.identity)
        turn.ask(!turn.isTask && !target.sending ? card.aimed(pid: target.pid, bundle: target.bundle) : card) { answer in
            DispatchQueue.global(qos: .userInitiated).async {
                guard case .yes = answer else {
                    turn.audit(["answer": answer == .unanswered ? "unanswered" : "no", "action": what, "brain": turn.brainName])
                    return done(.failed(Self.notYesLine(answer)))
                }
                guard turn.live else {
                    turn.audit(["answer": "dropped (the yes came after the turn ended)", "action": what, "brain": turn.brainName])
                    return done(.failed(Self.lateLine))
                }
                if remember, let key = target.memoryKey { turn.ledger.remember(key, tainted: turn.taint(forApp: target.readKey) != .none) }
                turn.audit(["answer": "yes", "action": what, "brain": turn.brainName])
                // The batch's one card covered bringing the window forward too (QA BUG-47 retest).
                var held = basis
                held.cardYes = !turn.isTask && !target.sending
                held.frontBefore = frontBefore
                run(held, named)
            }
        }
    }

    /// The steps, one ordinary action after another, until the first that isn't confirmed.
    /// `card`: what the user's card named for each step (nil: no card was shown). `front`: the app's front window when it began.
    private func runBatch(_ steps: [ArisDesktopStep], name: String, target: ArisDesktopTarget, window: ArisDesktopWindow, opening: Set<Int>, front: Int?, basis: ArisDesktopBasis,
                          expected: String?, card: [String?]?, turn: ArisDesktopTurn) -> ArisMCPOutcome {
        var held = basis
        var lines: [String] = []
        let stopped = { (index: Int, text: String) -> ArisMCPOutcome in
            let all = [String(format: ArisDesktopBatch.stoppedFormat, index + 1, steps.count)] + lines + ["\(index + 1). \(text)"]
            return ArisMCPOutcome(status: 1, output: ArisMCPPolicy.wrapped(all.joined(separator: "\n"), server: target.name, tool: "desktop batch", secrets: [], isError: true))
        }
        for (index, step) in steps.enumerated() {
            let ref: ArisDesktopRef?
            var element: ArisDesktopElement?
            var look = turn.ledger.latestLook(window: window.id)
            // Right before every click or press, the first too (a panel can come up while the card waits): the same
            // windows, the same one in front (M1).
            if [.click, .press].contains(step.verb) {
                let now = windows.windows(of: target.pid)
                if !Set(now.map(\.id)).subtracting(opening).isEmpty || now.first?.id != front {
                    return stopped(index, ArisDesktopBatch.frontLine + (look.map { "\n\n" + $0.render() } ?? ""))
                }
            }
            // The taint as it is now (outside text may have come in since the batch began).
            let taint = turn.taint(forApp: target.readKey)
            let context = ArisDesktopContext(taintForApp: taint, screen: turn.screen, handsFree: turn.handsFree, job: turn.isTask, relayed: turn.relayed, home: identity.home)
            if step.target == nil {
                ref = nil
            } else {
                // The control in the newest look; the last step may still be bringing it up.
                var found = look.map { ArisDesktopBatch.find(step, in: $0, ledger: turn.ledger) } ?? .missing
                if case .missing = found, index > 0, let binary = try? installer.ready().get() {
                    let session = ArisDesktopSession(engine: self, binary: binary, target: target, turn: turn)
                    for attempt in 0..<ArisDesktopBatch.settleLooks {
                        if attempt > 0 { Thread.sleep(forTimeInterval: ArisDesktopBatch.settleWait) }
                        guard case .success(let (again, _)) = session.look(window) else { break }
                        look = again
                        found = ArisDesktopBatch.find(step, in: again, ledger: turn.ledger)
                        if case .missing = found { continue }
                        break
                    }
                }
                let shown = look.map { "\n\n" + $0.render() } ?? ""
                switch found {
                case .missing:
                    return stopped(index, ArisDesktopBatch.missing(ArisDesktopBatch.stepLabel(step, element: nil).replacingOccurrences(of: "“", with: "").replacingOccurrences(of: "”", with: "")) + shown)
                case .several:
                    if case .label(let label) = step.target { return stopped(index, ArisDesktopBatch.ambiguous(label) + shown) }
                    return stopped(index, ArisDesktopBatch.missing("that control") + shown)
                case .control(let control):
                    guard let snapshot = look?.snapshot, let number = control.number else { return stopped(index, ArisDesktopBatch.missing(control.label) + shown) }
                    element = control
                    if case .ref(let named) = step.target, named.mark { ref = named } else { ref = ArisDesktopRef(snapshot: snapshot, element: number) }
                }
            }
            // Covered by the user's card: one was shown, and it named this very control (or the step names none: keys).
            let covered = card.map { names in element.map { names[index] == $0.label } ?? true } ?? false
            let composer = element.flatMap { look?.composer(for: $0) } ?? (step.verb == .press ? look?.composer(for: nil) : nil)
            // A control found by its label in a newer look that deletes, sends, pays or quits: only when the card named it (M2).
            if index > 0, case .label = step.target, let element, !covered,
               ArisDesktopBatch.riskyWords(element.label) || Self.sends(step, control: element, composer: composer, app: name) {
                return stopped(index, ArisDesktopBatch.uncoveredLine(element.label) + (look.map { "\n\n" + $0.render() } ?? ""))
            }
            // This step's gate again, with the control it really is, the taint as it is now: a card it would ask for must be
            // the one the user saw (M2).
            let single = step.request(ref: ref, app: name, window: window.id)
            let remembered = target.memoryKey.map { turn.ledger.allows($0, tainted: taint != .none) } ?? false
            switch ArisDesktopGate.decide(single, target: target, context: context, remembered: remembered, secureInput: apps.secureInput, element: element) {
            case .refuse(let why): return stopped(index, why)
            case .judge: return stopped(index, ArisDesktopBatch.oneAtATimeLine)
            case .ask:
                guard covered else {
                    return stopped(index, ArisDesktopBatch.uncoveredLine(element?.label ?? step.keys.joined(separator: " ")) + (look.map { "\n\n" + $0.render() } ?? ""))
                }
            case .run: break
            }
            // Return in a document's text area is a new line (the focus as it is now).
            let newline = ArisDesktopBatch.newline(step, into: look?.focusedElement, in: look, target: target, webAncestor: apps.focusedInWebArea(pid: target.pid))
            if !newline, Self.sends(step, control: element, composer: composer, app: name) {
                if index < steps.count - 1 { return stopped(index, ArisDesktopBatch.sendLastLine) }
                if target.sending, !held.send { return stopped(index, ArisDesktopBatch.notOnCardLine + (look.map { "\n\n" + $0.render() } ?? "")) }
            }
            let result: ArisDesktopResult
            // The notch's line for this step says which of how many it is (the steps are counted: they are on the card).
            held.step = ArisStepLine.Step(index: index, of: steps.count)
            switch performed(single, target: target, turn: turn, basis: held, openPause: ArisDesktopBatch.openWait) {
            case .refused(let outcome): return stopped(index, outcome.output)
            case .result(let found): result = found
            }
            guard result.ok else { return stopped(index, result.text) }
            turn.audit(["answer": "ran (step \(index + 1) of \(steps.count))", "action": "desktop batch \(step.verb.rawValue) · \(target.name)", "brain": turn.brainName])
            let paragraph = result.text.components(separatedBy: "\n\n").first ?? result.text
            guard index < steps.count - 1 else {
                lines.append("\(index + 1). \(result.text)")
                break
            }
            lines.append("\(index + 1). \(paragraph)")
            // The batch's own text may have renamed the window (a new TextEdit document): the steps after are held to
            // the field it typed into, as read back (ArisDesktopFocus.afterOwnText).
            if step.text != nil, let element, let now = turn.ledger.latestLook(window: window.id), let field = ArisDesktopVerify.find(element, in: now) {
                held = ArisDesktopFocus.afterOwnText(held, look: now, field: field, target: target)
            }
            // A sending app: what the field reads now must be what the card said, or nothing more runs.
            if target.sending, step.text != nil, let now = turn.ledger.latestLook(window: window.id) {
                guard let field = element.flatMap({ ArisDesktopVerify.find($0, in: now) }), let raw = field.rawValue,
                      expected.map({ ArisPeekabooCommands.composed(raw) == $0 }) ?? true else {
                    return stopped(index + 1, ArisDesktopSession.composerLine + "\n\n" + now.render())
                }
                held.composer = raw
            }
            if Set(windows.windows(of: target.pid).map(\.id)).subtracting(opening).isEmpty == false {
                let now = turn.ledger.latestLook(window: window.id).map { "\n\n" + $0.render() } ?? ""
                return stopped(index + 1, ArisDesktopBatch.openedLine + now)
            }
        }
        return ArisMCPOutcome(status: 0, output: ArisMCPPolicy.wrapped(lines.joined(separator: "\n"), server: target.name, tool: "desktop batch", secrets: [], isError: false))
    }
}
