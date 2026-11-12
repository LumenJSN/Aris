//
//  ArisEditableAction.swift
//  aris-agent
//
//  The owner's ②A: a confirm card whose values they can change before they says yes. Which fields an action has is decided here,
//  by the action's kind as parsed from the command (one aris-tools message, remind or event), never by the model. A yes
//  with changes is checked again (every value, as aris-tools would read it), the changed command is judged by the risk
//  gate as if the AI had asked for it, and a change that raises the risk (a new recipient, a link added, a riskier
//  rating) comes back as a fresh card. The AI's own call is then declined and the agent runs the changed command itself,
//  word by word (no shell), so what runs is exactly what the card showed.
//

import Foundation

enum ArisEditKind: String {
    case message, remind, event

    /// The card's title, as the gate's own cards name these tools.
    var title: String {
        switch self {
        case .message: return "메시지 보내기"
        case .remind: return "미리 알림"
        case .event: return "일정 추가"
        }
    }
}

/// What the agent does with a yes to a changed card.
enum ArisEditVerdict: Equatable {
    case run
    /// A fresh card for the changed action, saying why.
    case reask(String)
    case refuse(String)
}

struct ArisEditableAction: Equatable {
    let kind: ArisEditKind
    let tools: String
    /// The card's fields; an event's length and calendar are fixed (shown, never changed).
    let fields: [ArisCardField]

    /// The editable action in `action`; nil when it has nothing the user may change.
    static func parse(_ action: ArisAction, tools: String) -> ArisEditableAction? {
        guard case .shell(let command) = action, (ArisCommandPolicy.segments(command) ?? []).count == 1,
              let words = ArisCommandPolicy.words(command), words.count >= 3, words[0] == tools,
              let kind = ArisEditKind(rawValue: words[1]) else { return nil }
        var rest = Array(words.dropFirst(2))
        let fields: [ArisCardField]
        switch kind {
        case .message:
            guard rest.count >= 2 else { return nil }
            fields = [field("to", rest[0]), field("text", rest.dropFirst().joined(separator: " "))]
        case .remind:
            let at = take("--at", from: &rest)
            fields = [field("text", rest.joined(separator: " "))] + (at.map { [field("at", $0)] } ?? [])
        case .event:
            guard let start = take("--start", from: &rest) else { return nil }
            let fixed = ["--minutes": "minutes", "--calendar": "calendar"].sorted { $0.value > $1.value }.compactMap { option, key in
                take(option, from: &rest).map { field(key, $0, fixed: true) }
            }
            fields = [field("title", rest.joined(separator: " ")), field("start", start)] + fixed
        }
        let action = ArisEditableAction(kind: kind, tools: tools, fields: fields)
        // What it starts with must pass the same checks as a change.
        return action.applying([:]) == nil ? nil : action
    }

    /// Each field's label and role, by its key.
    private static let schema: [String: (label: String, role: ArisCardField.Role)] = [
        "to": ("받는 사람", .recipient), "text": ("내용", .text), "title": ("제목", .text), "at": ("때", .time), "start": ("시작", .time),
        "minutes": ("길이 (분)", .text), "calendar": ("캘린더", .text),
    ]

    private static func field(_ key: String, _ value: String, fixed: Bool = false) -> ArisCardField {
        let (label, role) = schema[key] ?? (key, .text)
        return ArisCardField(key: key, label: label, role: role, value: value, fixed: fixed)
    }

    /// An option's value, taken out of `words` as aris-tools takes it.
    private static func take(_ option: String, from words: inout [String]) -> String? {
        guard let index = words.firstIndex(of: option), index + 1 < words.count else { return nil }
        let value = words[index + 1]
        words.removeSubrange(index...(index + 1))
        return value
    }

    func value(_ key: String) -> String? { fields.first { $0.key == key }?.value }

    /// The action with `edits` applied, every value checked; nil when a key isn't one of its fields or a value is
    /// refused. Each changed field keeps the AI's first value (for 원래).
    func applying(_ edits: [String: String]) -> ArisEditableAction? {
        let keys = Set(fields.filter { !$0.fixed }.map(\.key))
        guard Set(edits.keys).isSubset(of: keys) else { return nil }
        var changed: [ArisCardField] = []
        for field in fields {
            let value = edits[field.key] ?? field.value
            // Checked as the app checks it before it lets the user say yes (one rule for both: ArisCardEdit.accepts).
            guard field.fixed ? !value.isEmpty : ArisCardEdit.accepts(value, role: field.role) else { return nil }
            let original = value == field.first ? nil : field.first
            changed.append(ArisCardField(key: field.key, label: field.label, role: field.role, value: value, original: original, fixed: field.fixed))
        }
        return ArisEditableAction(kind: kind, tools: tools, fields: changed)
    }

    /// aris-tools' arguments, word by word.
    var arguments: [String] {
        func value(_ key: String) -> String { self.value(key) ?? "" }
        switch kind {
        case .message: return ["message", value("to"), value("text")]
        case .remind: return ["remind", value("text")] + (self.value("at").map { ["--at", $0] } ?? [])
        case .event:
            return ["event", value("title"), "--start", value("start")] + (self.value("minutes").map { ["--minutes", $0] } ?? [])
                + (self.value("calendar").map { ["--calendar", $0] } ?? [])
        }
    }

    /// The command as the risk gate reads it: every word single-quoted (a ' inside one is closed, put in double quotes,
    /// and reopened), so ArisCommandPolicy.words reads back exactly `arguments`.
    var command: String {
        ([tools] + arguments).map(Self.quoted).joined(separator: " ")
    }

    static func quoted(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// An editable card's details: whatever the card said before the AI's own words (why it asks: outside text came in),
    /// then the fields' text, which the app shows as rows and a yes with changes echoes. `described`: the plain card's
    /// words for the command (ArisCodexDriver.describe); when they aren't at the end, all of `asked` stays above.
    static func detail(_ asked: String, described: String, fields: [ArisCardField]) -> String {
        let above = asked.hasSuffix(described) ? String(asked.dropLast(described.count)) : asked
        let note = above.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = ArisCardEdit.shown(fields, ArisCardEdit.values(fields))
        return note.isEmpty ? shown : note + "\n" + shown
    }

    // MARK: - Judging the change

    /// Why a change needs a fresh yes; nil when the yes the user gave covers it.
    static func raise(from base: ArisEditableAction, to edited: ArisEditableAction) -> String? {
        if base.value("to") != edited.value("to") { return "받는 사람이 바뀌어서 한 번 더 확인할게요." }
        let before = Set(base.fields.filter { $0.role == .text }.flatMap { links(in: $0.value) })
        let after = Set(edited.fields.filter { $0.role == .text }.flatMap { links(in: $0.value) })
        if !after.isSubset(of: before) { return "링크가 들어가서 한 번 더 확인할게요." }
        return nil
    }

    /// Web addresses in `text`, lowercased: whatever the system's link detector finds (a scheme, www., a bare domain,
    /// a mail address), and bare IPv4 addresses (with a port or path or not).
    static func links(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        let detected = (try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue))?
            .matches(in: text, range: range).compactMap { $0.url?.absoluteString.lowercased() } ?? []
        let ips = (try? NSRegularExpression(pattern: #"(?<![\d.])\d{1,3}(\.\d{1,3}){3}(?![\d.]*\d)(:\d+)?(/\S*)?"#))?
            .matches(in: text, range: range).compactMap { Range($0.range, in: text).map { "ip:" + text[$0].lowercased() } } ?? []
        return detected + ips
    }

    /// How careful the gate is: a countdown shown as a card is a question like any other.
    private static func rank(_ risk: ArisRisk) -> Int {
        switch risk {
        case .auto: return 0
        case .countdown, .confirm: return 1
        case .never: return 2
        }
    }

    /// The change against the card it was made on: refused when the gate never allows it, asked again when it raises
    /// the risk, run otherwise. `risk`/`baseRisk`: the gate's rating of each command; `hardLine`: a line Aris refuses
    /// applies (money, a mail it can't show); `asksUser`: the change crosses a line that is the user's card every time and
    /// the card he answered didn't (a deletion, something that looks like a send): asked afresh, never refused.
    static func verdict(base: ArisEditableAction, edited: ArisEditableAction, risk: ArisRisk, baseRisk: ArisRisk,
                        hardLine: Bool, asksUser: Bool = false) -> ArisEditVerdict {
        if hardLine || risk == .never { return .refuse("고친 내용은 할 수 없는 일이라 하지 않았어요.") }
        if let why = raise(from: base, to: edited) { return .reask(why) }
        if asksUser { return .reask("고친 내용은 꼭 확인받는 일이라 한 번 더 확인할게요.") }
        if rank(risk) > rank(baseRisk) { return .reask("고친 내용은 더 조심할 일이라 한 번 더 확인할게요.") }
        return .run
    }

    /// What Aris says once it ran the changed command (`status` nil: it didn't start, or was stopped at the time limit,
    /// so it may have gone out).
    /// `english`: for a request in English (ArisGateWords: audit gate-24).
    func outcome(status: Int32?, error: String, english: Bool = false) -> String {
        if english { return englishOutcome(status: status, error: error) }
        guard let status else {
            return kind == .message ? "고친 내용으로 보내다가 시간이 다 돼서 멈췄어요. 보냈는지 확인해 주세요."
                                    : "고친 내용으로 하다가 시간이 다 돼서 멈췄어요. 들어갔는지 확인해 주세요."
        }
        guard status == 0 else {
            // Handed to Messages but not seen as sent (ArisMessageResult): never "sent", and not "couldn't" either.
            if kind == .message, error.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(ArisMessageResult.notConfirmedLead) {
                return "고친 내용을 Messages에 넘겼는데, 보내졌는지는 확인하지 못했어요. Messages에서 확인해 주세요."
            }
            let why = error.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
            return "고친 내용으로 하지 못했어요" + (why.isEmpty ? "." : ": \(why)")
        }
        switch kind {
        case .message: return "\(value("to") ?? "")한테 고친 내용으로 보냈어요."
        case .remind: return "고친 내용으로 미리 알림을 넣었어요."
        case .event: return "고친 내용으로 일정을 넣었어요."
        }
    }

    private func englishOutcome(status: Int32?, error: String) -> String {
        guard let status else {
            return kind == .message ? "Sending your changed version ran out of time and was stopped. Please check whether it went out."
                                    : "Doing your changed version ran out of time and was stopped. Please check whether it went in."
        }
        guard status == 0 else {
            if kind == .message, error.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(ArisMessageResult.notConfirmedLead) {
                return "Your changed version was handed to Messages, but I couldn't confirm it was sent. Please check Messages."
            }
            let why = error.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
            return "I couldn't do your changed version" + (why.isEmpty ? "." : ": \(why)")
        }
        switch kind {
        case .message: return "Sent your changed version to \(value("to") ?? "")."
        case .remind: return "Added the reminder with your changes."
        case .event: return "Added the event with your changes."
        }
    }

    /// The turn's answer once the agent ran changed cards: each outcome first (as they were spoken, a blank line after
    /// each), then the AI's own answer, so a task's result or a widget's card stays.
    static func answer(_ answer: String, outcomes: [String]) -> String {
        guard !outcomes.isEmpty else { return answer }
        let rest = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return outcomes.joined(separator: "\n\n") + (rest.isEmpty ? "" : "\n\n" + rest)
    }

    /// What the AI is told once its call was declined because the agent ran the user's changed card itself (turn/steer), so
    /// it neither tries again nor tells the user it was refused.
    static func steer(outcome: String) -> String {
        "[Aris] the user changed that action on their confirm card, and Aris already carried out their changed version itself: "
            + "\(outcome) The decline you just got is not a refusal. Don't run it again and don't say it was refused or "
            + "cancelled; Aris tells the user the outcome. Carry on with anything else the request needs, or finish without "
            + "repeating this."
    }
}
