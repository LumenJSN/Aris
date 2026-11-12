//
//  ArisMailReply.swift
//  aris-tools (also built into aris-agent, which makes the card from the same plan)
//
//  A reply to one mail: `mail reply <id> --text "<the reply>" [--all] [--to <address>]… [--cc <address>]…`. The AI gives
//  only the mail's number and the words; who the reply goes to and its subject are worked out here from Mail's own
//  record of that mail, never taken from what the mail's text says. The card (ArisMailReplyCard) shows every address
//  in full, the mail being answered and a line for anything odd about where it goes; on the user's yes aris-tools opens the
//  reply in Mail as a draft, and he presses Send there. Nothing here sends, and there is no way to attach a file.
//  Pure, so the tests run it.
//

import Foundation

/// The words of `mail reply`, as aris-tools and every gate read them.
struct ArisMailReplyWords: Equatable {
    let id: Int64
    let text: String
    let all: Bool
    let to: [String]
    let cc: [String]

    /// The longest reply (it travels to Mail in one address).
    static let maxText = 8_000
    static let maxAdded = 10

    /// Whether the words after `mail` begin a reply (well formed or not).
    static func isReply(_ words: [String]) -> Bool { words.first == "reply" }

    /// A plain mail address in ASCII: a name that only looks like another (other alphabets' letters) is no address here.
    static func isAddress(_ text: String) -> Bool {
        text.count <= 254 && text.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }

    /// One well-formed reply (the words after `mail`); nil for anything else: no number, no text, a word that is no
    /// address after --to or --cc, a flag it doesn't know (there is none for a file).
    static func parse(_ words: [String]) -> ArisMailReplyWords? {
        guard words.count >= 4, words[0] == "reply", let id = Int64(words[1].hasPrefix("#") ? String(words[1].dropFirst()) : words[1]), id > 0 else { return nil }
        var text: String?, all = false, to: [String] = [], cc: [String] = []
        var index = 2
        while index < words.count {
            let word = words[index]
            if word == "--all" {
                guard !all else { return nil }
                all = true
                index += 1
                continue
            }
            guard index + 1 < words.count else { return nil }
            let value = words[index + 1]
            switch word {
            case "--text":
                guard text == nil else { return nil }
                text = value.replacingOccurrences(of: "\\n", with: "\n")
            case "--to":
                guard isAddress(value) else { return nil }
                to.append(value)
            case "--cc":
                guard isAddress(value) else { return nil }
                cc.append(value)
            default: return nil
            }
            index += 2
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= maxText, to.count <= maxAdded, cc.count <= maxAdded else { return nil }
        return ArisMailReplyWords(id: id, text: text.trimmingCharacters(in: .whitespacesAndNewlines), all: all, to: to, cc: cc)
    }

    static let usage = "usage: mail reply <id> --text \"<the reply>\" [--all] [--to <address>] [--cc <address>]   (the id is the #number `mail recent`, `mail search` and `mail read` show; \\n for a new line; it opens as a draft in Mail, nothing is sent)"
}

/// A reply ready to show and to open: where it goes, its subject, its words, and what the user should look at twice.
struct ArisMailReplyPlan: Equatable {
    /// Something about where the reply goes that the card says in its own line.
    enum Note: Equatable {
        /// The mail asks for its answer at another address than it came from.
        case replyAddress(asked: ArisMailAddress, sender: ArisMailAddress)
        /// An address that wasn't on any mail of this thread and that the user didn't say themselves.
        case outsider(ArisMailAddress)
        /// The name shown for an address holds a different address.
        case nameShowsOther(ArisMailAddress)
        /// An address with letters outside plain English ones (it may only look like the one it copies).
        case oddLetters(ArisMailAddress)
        /// What Mail's record gives as one address doesn't read as one (a comma, a space, a bracket inside it).
        case notOneAddress(ArisMailAddress)
        /// It goes to everyone on the mail.
        case everyone(Int)
    }

    let original: ArisMailEnvelope
    let to: [ArisMailAddress]
    let cc: [ArisMailAddress]
    let subject: String
    let text: String
    let notes: [Note]
}

enum ArisMailReply {
    /// "Re: " before the subject, unless it already says it is a reply.
    /// One line whatever the mail's own subject holds: a line break in it is a space in the reply's.
    static func subject(_ original: String) -> String {
        let flat = String(String.UnicodeScalarView(original.unicodeScalars.map { ArisCommandPolicy.isLineBreak($0) ? " " : $0 }))
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^(re|aw|sv|답장|회신|回复|返信)\s*[:：]"#, options: [.regularExpression, .caseInsensitive]) != nil { return trimmed }
        return trimmed.isEmpty ? "Re:" : "Re: " + trimmed
    }

    /// The reply worked out from Mail's record. It goes to the address the mail asks answers at (its Reply-To), else
    /// to who wrote it; with `--all`, also to everyone else the mail went to, never to the user. `--to` names
    /// other people instead, `--cc` adds some. `thread`: the mails of the conversation (whoever is on one belongs to
    /// it). `own`: the user's addresses. `request`: the user's own words this turn (an address they said themselves is their choice).
    static func plan(_ words: ArisMailReplyWords, original: ArisMailEnvelope, replyTo: ArisMailAddress?, thread: [ArisMailEnvelope],
                     own: Set<String>, request: String) -> ArisMailReplyPlan {
        let known = Dictionary((thread + [original]).flatMap(\.people).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let named = { (address: String) in known[address.lowercased()] ?? ArisMailAddress(name: "", address: address) }
        // A mail the user wrote themselves is answered to the people they wrote to.
        let mine = own.contains(original.from.key)
        let asked = replyTo.flatMap { $0.key == original.from.key ? nil : $0 }
        var to = !words.to.isEmpty ? words.to.map(named) : mine ? original.to : [asked ?? original.from]
        var cc: [ArisMailAddress] = []
        if words.all {
            if !mine { to += original.to.filter { !own.contains($0.key) } }
            cc += original.cc.filter { !own.contains($0.key) }
        }
        cc += words.cc.map(named)
        to = unique(to, without: [])
        cc = unique(cc, without: Set(to.map(\.key)))
        var notes: [ArisMailReplyPlan.Note] = words.all ? [.everyone(to.count + cc.count)] : []
        for person in to + cc {
            let named = says(request, person.key)
            // An answer asked for somewhere else than the mail came from is said every time, also when that address
            // is among the mail's own recipients (whoever wrote the mail chose those too); only the user naming it themselves
            // makes it his choice.
            if let asked, person.key == asked.key { if !named { notes.append(.replyAddress(asked: asked, sender: original.from)) } }
            else if known[person.key] == nil, !named { notes.append(.outsider(person)) }
            if !isOneAddress(person.address) { notes.append(.notOneAddress(person)) }
            else if !person.address.unicodeScalars.allSatisfy(\.isASCII) { notes.append(.oddLetters(person)) }
            if nameHidesAddress(person) { notes.append(.nameShowsOther(person)) }
        }
        return ArisMailReplyPlan(original: original, to: to, cc: cc, subject: subject(original.subject), text: words.text, notes: notes)
    }

    private static func unique(_ people: [ArisMailAddress], without taken: Set<String>) -> [ArisMailAddress] {
        var seen = taken
        return people.filter { !$0.address.isEmpty && seen.insert($0.key).inserted }
    }

    /// A shown name that carries an address other than the real one ("prof@uni.edu" <someone@else.com>), anywhere in it.
    private static func nameHidesAddress(_ person: ArisMailAddress) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"[^\s<>"'(),;]+@[^\s<>"'(),;]+"#) else { return false }
        let name = person.name
        return regex.matches(in: name, range: NSRange(name.startIndex..., in: name)).contains { match in
            Range(match.range, in: name).map { name[$0].lowercased() != person.key } ?? false
        }
    }

    /// Whether the user's own words hold this address, whole (never as a piece of a longer one).
    private static func says(_ request: String, _ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        let pattern = "(?<![a-z0-9._%+-])" + NSRegularExpression.escapedPattern(for: address) + "(?![a-z0-9_%+-]|\\.[a-z0-9])"
        return request.lowercased().range(of: pattern, options: .regularExpression) != nil
    }

    /// Whether what Mail's record gives as an address reads as one address: one "@", and nothing that separates
    /// addresses or opens another part of a message's address (a space, a comma, a bracket, "?", "&").
    static func isOneAddress(_ text: String) -> Bool {
        let breaking = Set(",;<>()[]\"\\:?&".unicodeScalars)
        return text.filter { $0 == "@" }.count == 1 && !text.unicodeScalars.contains { scalar in
            breaking.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
        }
    }

    // MARK: - The card's words

    /// An address as a card shows it: the real address first and whole, then the name it gives itself.
    static func shown(_ person: ArisMailAddress) -> String {
        let name = person.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? person.address : "\(person.address) (\(name.count > 60 ? String(name.prefix(59)) + "…" : name))"
    }

    static func line(_ note: ArisMailReplyPlan.Note, english: Bool) -> String {
        switch note {
        case .replyAddress(let asked, let sender):
            return english ? "Check: this mail asks for replies at \(asked.address), not at its sender \(sender.address)."
                           : "주의: 이 메일은 보낸 사람(\(sender.address))이 아닌 \(asked.address)로 답장을 받겠다고 적혀 있어요."
        case .outsider(let person):
            return english ? "Check: \(person.address) wasn't on this conversation and you didn't name it."
                           : "주의: \(person.address)는 이 대화에 없던 주소이고, 직접 말씀하신 주소도 아니에요."
        case .nameShowsOther(let person):
            return english ? "Check: the name shown for \(person.address) holds a different address."
                           : "주의: \(person.address)의 이름 칸에 다른 주소가 적혀 있어요."
        case .oddLetters(let person):
            return english ? "Check: \(person.address) has letters that aren't plain English ones; it may only look like another address."
                           : "주의: \(person.address)에 영문이 아닌 글자가 섞여 있어요. 다른 주소처럼 보이게 만든 것일 수 있어요."
        case .notOneAddress(let person):
            return english ? "Check: \(person.address) doesn't read as one mail address; Mail may take it as more than one recipient."
                           : "주의: \(person.address)는 메일 주소 하나로 읽히지 않아요. Mail이 여러 사람에게 가는 것으로 받아들일 수 있어요."
        case .everyone(let count):
            return english ? "Reply to all: it goes to the \(count) people above." : "전체 답장: 위 \(count)명에게 가요."
        }
    }

    /// The card's lines: every address whole, what to look at twice right under them (before the subject, which is
    /// the mail's own words at any length and could push it out of sight), the subject, the mail being answered, the
    /// whole text, and what a yes does. Each line above the text is one line: a line break inside a name, an address
    /// or a subject is shown as a mark, so nothing of the mail's can start a line that passes for one of the card's.
    static func cardLines(_ plan: ArisMailReplyPlan, english: Bool, zone: TimeZone = .current) -> [String] {
        let original = plan.original
        let answered = "#\(original.id) · \(ArisLocalStore.stamp(original.date, zone: zone)) · \(shown(original.from)) · "
            + (original.subject.isEmpty ? (english ? "(no subject)" : "(제목 없음)") : original.subject)
        var lines = [(english ? "To: " : "받는 사람: ") + plan.to.map(shown).joined(separator: ", ")]
        if !plan.cc.isEmpty { lines.append((english ? "Cc: " : "참조: ") + plan.cc.map(shown).joined(separator: ", ")) }
        lines += plan.notes.map { line($0, english: english) }
        lines.append((english ? "Subject: " : "제목: ") + plan.subject)
        lines.append((english ? "Replying to: " : "답장할 메일: ") + answered)
        lines = lines.map { $0.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\\u{000A}") }
        lines.append(english ? "Text:" : "내용:")
        lines.append(plan.text)
        lines.append(english ? afterYesEnglish : afterYes)
        return lines
    }

    static let afterYes = "허용하면 Mail에 답장 초안으로 열려요. 보내는 건 Mail에서 직접 눌러요."
    static let afterYesEnglish = "Yes opens it in Mail as a draft. You press Send there."

    // MARK: - Opening it in Mail

    /// The reply as an address Mail opens in a new message window (RFC 6068), every part percent-encoded.
    static func mailto(_ plan: ArisMailReplyPlan) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encode = { (text: String) in text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        let at = { (people: [ArisMailAddress]) in people.map { encode($0.address).replacingOccurrences(of: "%40", with: "@") }.joined(separator: ",") }
        guard !plan.to.isEmpty else { return nil }
        var fields = ["subject=" + encode(plan.subject), "body=" + encode(plan.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n"))]
        if !plan.cc.isEmpty { fields.insert("cc=" + at(plan.cc), at: 0) }
        return URL(string: "mailto:" + at(plan.to) + "?" + fields.joined(separator: "&"))
    }

    // MARK: - What aris-tools answers (fixed words; read exactly, like a message's answer)

    static let draftedLead = "DRAFTED, NOT SENT:"
    static let notDraftedLead = "NOT DRAFTED:"

    static func drafted(_ plan: ArisMailReplyPlan) -> String {
        "\(draftedLead) the reply to \((plan.to + plan.cc).map(\.address).joined(separator: ", ")) is open in Mail as a draft. Nothing was sent. "
            + "Tell the user it is in Mail as a draft (\"Mail에 초안으로 넣어 뒀어요\") and that they look it over and press Send there. Never say it was sent."
    }

    static let noMail = "\(notDraftedLead) Mail isn't on this Mac, so the draft couldn't be opened. Nothing was sent. Tell the user, and give them the reply's text to send themselves."
    static let couldntOpen = "\(notDraftedLead) Mail didn't open the draft. Nothing was sent. Tell the user it couldn't be put in Mail, and give them the reply's text to send themselves."
    static func noSuchMail(_ id: Int64) -> String {
        "\(notDraftedLead) there is no mail #\(id) to reply to (it may have been moved or deleted; find it again with `mail search`). Nothing was sent."
    }
    static let noRecipient = "\(notDraftedLead) that mail has no address to reply to. Nothing was sent. Ask the user who it should go to."
}
