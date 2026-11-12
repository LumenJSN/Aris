//
//  ArisSendClaim.swift
//  aris-agent
//
//  A conversation answer that says "I sent it" when nothing was sent (VM fourth re-check, #5): asked to "summarize the
//  following and send mom that summary as a text message", DeepSeek answered "The summary I sent mom: …" under a
//  "Sent · To: mom" heading without calling any tool. No message went out and no card came up, but the answer said a
//  send happened. ArisJobClaim covers background jobs; this covers the conversation's turns.
//
//  The model's text is never changed. Aris's own plain line is added after it ("보내지 않았어요. 실제로 보내려면 다시 말해
//  주세요."), and only when all of this holds, so that in any doubt nothing is added:
//   · the request asked for something to be sent (a message, a text, a mail);
//   · the answer says in the first person that it sent it (ArisJobClaim.saysSent: "I sent", "I've sent", a Korean
//     "보냈어요" with no one else as its subject), outside quotes, quoted lines and code, and not as a supposition
//     ("if I sent", "I would have sent");
//   · and what the helper saw the turn do rules a send out: no tool but Aris's own commands, none of them one that can
//     send (a message, a mail, keys typed, a Shortcut, a service, a skill, Aside, the desktop) unless its card got a no
//     or no answer, and no yes to anything whose doing is not read here.
//  Pure.
//

import Foundation

enum ArisSendClaim {
    /// What the helper saw the turn do.
    struct Record: Equatable {
        /// The shell commands it ran.
        var commands: [String] = []
        /// It used a tool that is not a shell command (a connected service, Aside, a skill, the desktop, a file tool).
        var otherTools = false
        /// What was answered on its cards.
        var cards = ArisJobClaim.Cards()
    }

    /// The line added after such an answer.
    static func notSentLine(korean: Bool) -> String {
        korean ? "보내지 않았어요. 실제로 보내려면 다시 말해 주세요." : "It was not sent. To send it for real, ask me again."
    }

    /// The request asked for something to be sent.
    static let asksToSend = #"(?i)(\b(send|text|e-?mail|mail|message|imessage|dm)\b|보내|문자|메일|메시지)"#

    /// Aris's own commands that can send something or act in another app: a turn that ran one of these (and was not
    /// refused on its card) may have sent, so nothing is added.
    static let maySend: Set<String> = ["message", "mail", "keys", "type", "shortcut", "mcp", "skill", "aside", "desktop"]
    /// `mail` reads with these: no send.
    static let mailReads: Set<String> = ["recent", "search"]

    /// The line to add after `answer`, or nil.
    static func note(_ answer: String, request: String, record: Record, tools: String, korean: Bool) -> String? {
        guard request.range(of: asksToSend, options: .regularExpression) != nil, claimsSent(answer),
              !record.otherTools, !record.cards.approvedOther else { return nil }
        let sends = { (command: String) in ArisJobClaim.sendsSomething(command, tools: tools) }
        guard !record.cards.approved.contains(where: sends) else { return nil }
        var refused = record.cards.refused.filter(sends)
        for command in record.commands {
            if let index = refused.firstIndex(of: command) {
                refused.remove(at: index)
                continue
            }
            guard cannotSend(command, tools: tools) else { return nil }
        }
        return notSentLine(korean: korean)
    }

    /// A command that is Aris's own tool, every part of it, and none that can send.
    static func cannotSend(_ command: String, tools: String) -> Bool {
        let inner = ArisCommandPolicy.unwrap(command)
        guard let parts = ArisCommandPolicy.segments(inner), !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            guard let words = ArisCommandPolicy.words(part), let first = words.first,
                  first == tools || (first as NSString).lastPathComponent == (tools as NSString).lastPathComponent,
                  words.count >= 2 else { return false }
            if words[1] == "mail" { return words.count >= 3 && mailReads.contains(words[2]) }
            return !maySend.contains(words[1])
        }
    }

    /// The answer says, in the first person and as a fact, that it sent something.
    static func claimsSent(_ answer: String) -> Bool {
        sentences(of: plain(answer).replacingOccurrences(of: "’", with: "'")).contains { sentence in
            guard let range = sentence.range(of: ArisJobClaim.saysSent, options: .regularExpression) else { return false }
            let before = String(sentence[..<range.lowerBound])
            if sentence[range].unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) {
                return !otherSubject(before) && !negated(before)
            }
            return before.range(of: supposing, options: .regularExpression) == nil
        }
    }

    /// Words that make what follows a supposition, not a report.
    static let supposing = #"(?i)\b(if|unless|whether|would|could|should|might|suppose|supposing|imagine|pretend|as though)\b|(?i)\bwhat\s+if\b"#

    /// A Korean sentence whose subject is someone else ("엄마가 사진을 보냈어요"): no claim of Aris's.
    static func otherSubject(_ before: String) -> Bool {
        let rest = before.replacingOccurrences(of: "제가", with: "").replacingOccurrences(of: "내가", with: "")
        return rest.range(of: #"[가-힣](가|이|께서)\s"#, options: .regularExpression) != nil
    }

    /// "못 보냈어요", "안 보냈어요": not sent.
    static func negated(_ before: String) -> Bool {
        let end = before.trimmingCharacters(in: .whitespaces)
        return end.hasSuffix("못") || end.hasSuffix("안")
    }

    /// The answer without what it quotes: fenced code, quoted lines ("> …") and text in quotation marks.
    static func plain(_ answer: String) -> String {
        var text = answer.replacingOccurrences(of: #"(?s)```.*?```"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s*>.*$"#, with: " ", options: .regularExpression)
        for pattern in [#""[^"\n]*""#, #"“[^”\n]*”"#, #"‘[^’\n]*’"#, #"«[^»\n]*»"#, #"「[^」\n]*」"#, #"『[^』\n]*』"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return text
    }

    /// Sentences and lines.
    static func sentences(of text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?\n。")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
