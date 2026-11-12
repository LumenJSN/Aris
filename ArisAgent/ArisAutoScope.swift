//
//  ArisAutoScope.swift
//  aris-agent
//
//  Which actions the automatic check (ArisAutoCheck) may ever let run without a card. Only an action that asks today
//  for one reason, that outside text or the screen came into the conversation, and that runs by itself on a clean
//  turn (ArisGateReason.raised: the same rule that puts "외부 내용을 읽은 뒤라…" on its card); on the user's own turn, never a
//  background job's, a schedule's or a hands-free one; and only one plain aris-tools call of a kind listed here. Each
//  kind writes its own row in the 한 일 log with a working 되돌리기 (so a pass that was wrong can be seen and undone),
//  sends nothing off the Mac, and is read with a fixed verb and a fixed set of flags: a flag the kind doesn't take, a
//  flag given twice or without a value, or any other word that starts with a dash is not that kind (the tool would
//  read it another way than the checker is shown), and the card is today's. Everything else is as it was: what is
//  never done is never done, and what always asks (mail, a message, the Trash, a permanent delete, memory, keys and
//  typed text, the desktop, a first use, a link, Maps, a shortcut, the clipboard, a reminder, the calendar new events
//  go into, the home place, a browser task, a connected service's write) asks exactly as before, checked or not.
//  Pure, so the tests run it.
//

import Foundation

/// One kind of call the check may look at: how it starts, what the checker is told it does, and the flags it takes.
struct ArisAutoKind: Equatable {
    /// The call's first words ("todo", "add").
    let words: [String]
    /// The tool and the verb the checker and the ledger are told, fixed here (never read from the call's own words).
    let tool: String
    let verb: String
    /// The flags it takes, each with one value.
    let flags: Set<String>
    /// The flags it takes with no value (a conversion's --finder and --shelf).
    var bare: Set<String> = []
    /// Each plain word is a file of its own (a conversion); otherwise the plain words are one text.
    var files = false
}

/// A call read as its kind: every word accounted for, nothing the tool would read differently.
struct ArisAutoCall: Equatable {
    let kind: ArisAutoKind
    /// The words that are no flag, in order.
    let plain: [String]
    /// Each flag once, with its value ("" for a bare one), in the order given.
    let flags: [(name: String, value: String)]

    static func == (a: ArisAutoCall, b: ArisAutoCall) -> Bool {
        a.kind == b.kind && a.plain == b.plain && a.flags.map(\.name) == b.flags.map(\.name) && a.flags.map(\.value) == b.flags.map(\.value)
    }

    func value(_ flag: String) -> String? { flags.first { $0.name == flag }?.value }
}

enum ArisAutoScope {
    /// A to-do added or ticked off, a calendar event added, one of Aris's own schedules removed; and a conversion
    /// (ArisConvertWords.verbs), which only makes new files beside the originals. Every one of them leaves an undo in
    /// the log (ArisAutoMarks.undo). (A reminder, the calendar new events go into and the home place are not here: none
    /// of them can be undone from the log, and a reminder with a time is a notification of somebody's choosing.)
    static let kinds: [ArisAutoKind] = [
        ArisAutoKind(words: ["todo", "add"], tool: "todo", verb: "add", flags: ["--due", "--list", "--note"]),
        ArisAutoKind(words: ["todo", "done"], tool: "todo", verb: "done", flags: []),
        ArisAutoKind(words: ["event"], tool: "event", verb: "add", flags: ["--start", "--minutes", "--calendar"]),
        ArisAutoKind(words: ["schedule", "remove"], tool: "schedule", verb: "remove", flags: []),
    ] + ArisConvertWords.verbs.sorted().map {
        ArisAutoKind(words: [$0], tool: $0, verb: $0, flags: ArisConvertWords.flags($0), bare: ["--finder", "--shelf"], files: true)
    }

    /// The call's words after the program, when the action is exactly one aris-tools call read word by word; nil for
    /// anything else (a chained or piped line, another program, a file edit, a service's tool, the desktop, a site).
    static func argv(of action: ArisAction, tools: String) -> [String]? {
        guard case .shell(let command) = action, !tools.isEmpty, let pieces = ArisCommandPolicy.segments(command), pieces.count == 1,
              let words = ArisCommandPolicy.words(command), words.count > 1, words.first == tools,
              !ArisRiskPolicy.isDesktop(command, tools: tools) else { return nil }
        return Array(words.dropFirst())
    }

    /// The call as one of the kinds, or nil: not a listed kind (an event found, deleted or changed is none), or with a
    /// word the kind doesn't account for.
    static func call(_ argv: [String]) -> ArisAutoCall? {
        guard let kind = kinds.first(where: { argv.starts(with: $0.words) }) else { return nil }
        let rest = Array(argv.dropFirst(kind.words.count))
        if kind.words == ["event"], ["find", "delete", "change"].contains(rest.first ?? "") { return nil }
        if kind.files, ArisConvertWords.parse(argv) == nil { return nil }
        var plain: [String] = [], flags: [(name: String, value: String)] = []
        var index = 0
        while index < rest.count {
            let word = rest[index]
            if kind.bare.contains(word) {
                guard !flags.contains(where: { $0.name == word }) else { return nil }
                flags.append((word, ""))
                index += 1
            } else if kind.flags.contains(word) {
                guard !flags.contains(where: { $0.name == word }), index + 1 < rest.count, !rest[index + 1].hasPrefix("-"), !rest[index + 1].isEmpty else { return nil }
                flags.append((word, rest[index + 1]))
                index += 2
            } else {
                // Any other word with a dash in front could be a flag to the tool: not this kind as the checker would see it.
                guard !word.hasPrefix("-"), !word.isEmpty else { return nil }
                plain.append(word)
                index += 1
            }
        }
        return plain.isEmpty && !kind.files ? nil : ArisAutoCall(kind: kind, plain: plain, flags: flags)
    }

    static func covers(_ argv: [String]) -> Bool { call(argv) != nil }

    /// The one aris-tools call the check may look at, or nil when the action is none of its business: it must ask only
    /// because outside content was read (`blocked`: the taint keeps it with the user; no hard line; on a clean turn of this
    /// tier it runs by itself; it is a kind asked after outside text), on the user's own conversation turn, and it is not a
    /// countdown (a message is always his) nor a write to his memory.
    static func eligible(_ action: ArisAction, tools: String, home: String, request: String, critical: Bool, blocked: Bool, hardLine: Bool,
                         task: Bool, handsFree: Bool, countdown: Bool) -> [String]? {
        guard !task, !handsFree, !countdown, !ArisMemoryLearning.isMemoryWrite(action, tools: tools),
              ArisGateReason.raised(outside: blocked, hardLine: hardLine,
                                    cleanRisk: ArisRiskPolicy.risk(of: action, tools: tools, home: home, critical: critical, request: request),
                                    asksAfter: ArisRiskPolicy.asksAfterOutsideText(action, tools: tools)) else { return nil }
        return argv(of: action, tools: tools)
    }
}

/// The owner's rule for anything that goes out to a person (a message, a mail): when they did not name who it goes to in their
/// own words, it asks on a card whatever the checker thinks. "Named" is decided here, by code, and strictly: a name
/// must be a whole word he said (with a Korean particle allowed: 엄마 in 엄마한테), an address or a handle must appear in
/// their words exactly, a number digit for digit, and every recipient of several must be named.
/// A list or a calendar may be shared with other people, so what is put in one is a send to them too: the list of a
/// to-do (`--list`) and the calendar of an event (`--calendar`) must be named in his own words the same way.
enum ArisAutoSend {
    /// Who the call sends to: `message <to> …`, `mail <to> …` or its `--to`; nil when it sends nothing to a person.
    static func recipient(_ argv: [String]) -> String? {
        guard let tool = argv.first, ["message", "mail"].contains(tool), !ArisLocalReadPolicy.isRead(argv) else { return nil }
        if let flag = argv.firstIndex(of: "--to"), flag + 1 < argv.count { return argv[flag + 1] }
        return argv.dropFirst().first { !$0.hasPrefix("-") } ?? ""
    }

    /// The list or the calendar the call writes into, when it names one.
    static func place(_ call: ArisAutoCall) -> String? { call.value("--list") ?? call.value("--calendar") }

    /// A turn of his longer than ArisRiskPolicy.maxCoveringWords (a paste) names nobody and no list or calendar.
    static func named(_ recipient: String, in ownerTurns: [String]) -> Bool {
        let ownerTurns = ownerTurns.filter { !ArisRiskPolicy.coversNothing($0) }
        let each = recipient.split(whereSeparator: { ",;".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return !each.isEmpty && each.allSatisfy { one in ownerTurns.contains { names(one, in: $0) } }
    }

    private static func names(_ one: String, in turn: String) -> Bool {
        let said = turn.precomposedStringWithCanonicalMapping.lowercased()
        let who = one.precomposedStringWithCanonicalMapping.lowercased()
        let digits = who.filter(\.isNumber)
        // A phone number: its digits, all of them, somewhere in their words' digits (at least seven).
        if digits.count >= 7, who.allSatisfy({ $0.isNumber || " +-().".contains($0) }) { return said.filter(\.isNumber).contains(digits) }
        // An address or a handle: exactly as he wrote it, standing on its own.
        if who.contains("@") || who.contains(".") || who.contains(where: \.isNumber) {
            return said.split(whereSeparator: { $0.isWhitespace || ",;()<>\"'".contains($0) }).contains { $0 == who }
        }
        return ArisRiskPolicy.named(who, in: said)
    }

    /// The one line the card opens with.
    static func reason(_ recipient: String, english: Bool) -> String {
        let who = String(ArisAutoCheck.field(recipient).prefix(80))
        return english ? "This goes to someone you didn't name: \(who)" : "이름을 말하지 않은 사람에게 보내요: \(who)"
    }
}
