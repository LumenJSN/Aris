//
//  ArisJobClaim.swift
//  aris-agent
//
//  A background job's answer is not passed on as done when the job plainly did not do it (final VM run: "every day at
//  2:24 am, say good morning in one word" went out as a job, whose model answered "I've set that up to run every day
//  at 2:24." without calling any tool; the chip read "✓ 1 done" and nothing was scheduled).
//
//  The rule is narrow on purpose (security review 6, M3: a wider one replaced real answers, "The printing press was
//  created by Gutenberg…", "You have a dentist appointment scheduled for 3 pm", with a line that was itself untrue).
//  An answer is replaced only when all of this holds, and in any doubt it stands as it is, with nothing added:
//   · the request itself asked for such an act: to make a schedule (ArisOwnData), or to send, save, delete, add,
//     move, post or book something;
//   · the answer says, in the first person, that it did it ("I've set that up", "I sent the message", "메일을 보냈어요").
//     A sentence about someone or something else ("was created by", "are added to the flour", "scheduled for 3 pm")
//     is never a claim;
//   · and what the helper knows first-hand says otherwise: for a schedule, Aris's own list of schedules is as it was
//     and the job ran no command that schedules, used no other tool and ran nothing but Aris's own tool; for the
//     rest, the job did nothing at all (no command, no tool, no card).
//  One more thing the helper knows first-hand: what was answered on the job's cards. A job whose send card got a no
//  (or no answer) and that sent nothing any other way may still answer "I sent it" (security review 7, L8). That
//  answer is kept, and the plain truth is added after it: it was not allowed on the card, so it was not sent.
//  (A passive "The message was sent." from a job that ran nothing still stands: who sent what cannot be told from
//  such a sentence with any certainty, and a real answer is never traded for a guess.)
//
//  The line said instead claims only what was checked: that no schedule was made, or that nothing was sent or
//  changed. The job then ends as failed, and the notes it wanted kept are dropped (it had "learned" that the greeting
//  was scheduled). Pure.
//

import Foundation

enum ArisJobClaim {
    /// What the helper saw the job do.
    struct Record: Equatable {
        /// Something passed the gate (a command ran, a tool was used).
        var acted = false
        /// The shell commands it ran.
        var commands: [String] = []
        /// It used a tool that is not a shell command (a file tool, a connected service).
        var otherTools = false
        /// It put up a card.
        var showedCard = false

        /// What was answered on its cards.
        var cards = Cards()

        /// Nothing at all was done.
        var isEmpty: Bool { !acted && commands.isEmpty && !otherTools && !showedCard }
    }

    /// The answers the job's cards got, as the helper passed them on.
    struct Cards: Equatable {
        /// The shell commands whose card got a no, or no answer.
        var refused: [String] = []
        /// The shell commands whose card got a yes.
        var approved: [String] = []
        /// A yes went to something that is not a shell command (a connected service's tool, a file change, a card he
        /// changed and Aris ran for him): what it did is not read here.
        var approvedOther = false

        /// One card was answered.
        mutating func note(_ action: ArisAction, allowed: Bool) {
            guard case .shell(let command) = action else {
                if allowed { approvedOther = true }
                return
            }
            if allowed { approved.append(command) } else { refused.append(command) }
        }
    }

    /// The answer speaks of sending, in the first person or as Aris reports ("보냈어요", "보냈습니다").
    static let saysSent = #"(?i)(\bi(?:'ve| have)?\s+(?:now\s+|just\s+|already\s+|successfully\s+)?sent\b|보냈어요|보냈습니다)"#

    /// A command that sends with Aris's own tool: a message, or a mail sent or answered.
    static func sendsSomething(_ command: String, tools: String) -> Bool {
        let name = (tools as NSString).lastPathComponent
        return command.range(of: #"(^|[\s/'"])"# + NSRegularExpression.escapedPattern(for: name) + #"['"]?\s+(message\b(?!s)|mail\s+(send|reply)\b)"#, options: .regularExpression) != nil
    }

    /// Added after an answer that says it sent something whose card was not allowed.
    static func notAllowedLine(korean: Bool) -> String {
        korean ? "확인 카드에서 허용되지 않아서 보내지 않았어요." : "It wasn't allowed on the confirm card, so it was not sent."
    }

    /// The line to add after `answer`, or nil. Added only when the helper is certain nothing was sent: a send of
    /// Aris's own tool was refused on its card, no send got a yes, no yes went to anything whose doing is not read
    /// here, and every send the job tried at all is one of the refused ones (a send that ran without a card, by a
    /// standing permission, is in the record and on no card).
    static func refusedNote(_ answer: String, record: Record, tools: String, korean: Bool) -> String? {
        guard answer.range(of: saysSent, options: .regularExpression) != nil else { return nil }
        let sends = { (command: String) in sendsSomething(command, tools: tools) }
        var refused = record.cards.refused.filter(sends)
        guard !refused.isEmpty, !record.cards.approvedOther, !record.cards.approved.contains(where: sends) else { return nil }
        for tried in record.commands.filter(sends) {
            guard let index = refused.firstIndex(of: tried) else { return nil }
            refused.remove(at: index)
        }
        return notAllowedLine(korean: korean)
    }

    /// "I" said it scheduled something: a schedule, a reminder or a recurring run was set up by the one answering.
    static let saysScheduled = #"(?i)(\bi(?:'ve| have)?\s+(?:now\s+|just\s+|already\s+)?(?:scheduled|set\s+(?:it|that|this|them|you|one|a|the|your)\b[^.\n]{0,30}?\bup|set\s+up)\b|\bi'?ll\s+(?:now\s+)?(?:run|say|send|do|remind)\b[^.\n]{0,60}\b(?:every|each|daily)\b|예약했어요|예약했습니다|예약해\s?(?:뒀|두었|놨|놓았)(?:어요|습니다)|(?:매일|매주|평일마다)[^.\n]{0,30}(?:실행되도록|하도록)\s?(?:했어요|설정했어요|예약했어요))"#

    /// "I" said it did something outside the conversation. Each form names the one who did it and, where the verb
    /// alone could be about words on the page ("I added a paragraph", "I deleted the second line"), what it was done to.
    static let saysChanged = #"(?i)(\bi(?:'ve| have)?\s+(?:now\s+|just\s+|already\s+|successfully\s+)?(?:sent\b|posted\b|uploaded\b|booked\b|(?:saved|moved)\b[^.\n]{0,60}\b(?:to|in|on|into)\s+(?:your|the)\b|(?:deleted|removed|trashed|renamed|cancell?ed|added|created|made)\b[^.\n]{0,40}\b(?:files?|folders?|events?|reminders?|to-?dos?|schedules?|messages?|mails?|emails?|notes?|calendar|list)\b)|(?:메시지|메일|문자|파일|폴더|일정|알림|할 일|메모)[^.\n]{0,20}(?:보냈|저장했|삭제했|지웠|추가했|만들었|옮겼|취소했|올렸)어요)"#

    /// The request asked for something to be sent, saved, removed, added, moved, posted or booked.
    static let asksForChange = #"(?i)(\b(send|text|e-?mail|mail|message|save|delete|remove|trash|add|create|make|move|rename|post|upload|book|cancel)\b|보내|저장|삭제|지워|추가|만들|옮겨|취소|올려)"#

    /// A command that schedules with Aris's own tool.
    static func schedulesSomething(_ command: String, tools: String) -> Bool {
        let name = (tools as NSString).lastPathComponent
        return command.range(of: #"(^|[\s/'"])"# + NSRegularExpression.escapedPattern(for: name) + #"['"]?\s+(schedule\s+add|remind)\b"#, options: .regularExpression) != nil
    }

    /// A command that runs Aris's own tool and nothing else: what such a command can do is known.
    static func isOwnTool(_ command: String, tools: String) -> Bool {
        guard let words = ArisCommandPolicy.words(command), let first = words.first else { return false }
        return (ArisCommandPolicy.segments(command)?.count ?? 1) == 1 && (first == tools || (first as NSString).lastPathComponent == (tools as NSString).lastPathComponent)
    }

    /// Said in place of "I've set that up": checked against Aris's own list of schedules.
    static func notScheduledLine(korean: Bool) -> String {
        korean ? "그건 백그라운드 작업으로는 예약하지 못했어요. 확인해 보니 만들어진 예약이 없어요. 대화에서 다시 말해 주시면 여기서 바로 할게요."
            : "I couldn't set that up from a background job: I checked, and no schedule was made. Ask me again here and I'll do it in the conversation."
    }

    /// Said in place of "I sent it" from a job that did nothing at all.
    static func nothingDoneLine(korean: Bool) -> String {
        korean ? "그건 백그라운드 작업으로는 하지 못했어요. 보내지거나 바뀐 건 없어요. 대화에서 다시 말해 주시면 여기서 바로 할게요."
            : "I couldn't do that from a background job: nothing was sent or changed. Ask me again here and I'll do it in the conversation."
    }

    /// The line to say instead of `answer`, or nil when the answer stands (which it does in any doubt).
    /// `request`: the user's own words for the job. `schedulesUnchanged`: Aris's list of schedules is as it was when the
    /// job began; nil when that could not be read.
    static func unbacked(_ answer: String, request: String, record: Record, schedulesUnchanged: Bool?, tools: String, korean: Bool) -> String? {
        let says = { (pattern: String) in answer.range(of: pattern, options: .regularExpression) != nil }
        let asked = ArisMemoryText.ownWords(request)
        // A request to make a schedule: Aris's own data by the rules that read making, and by none of the others
        // (under "list my schedules" the word "scheduled" is the list itself).
        let asksToSchedule = ArisOwnData.kind(of: asked) == .schedule && ArisOwnData.kind(of: asked, making: false) == nil
        if asksToSchedule, says(saysScheduled), schedulesUnchanged == true, !record.otherTools,
           record.commands.allSatisfy({ isOwnTool($0, tools: tools) && !schedulesSomething($0, tools: tools) }) {
            return notScheduledLine(korean: korean)
        }
        if asked.range(of: asksForChange, options: .regularExpression) != nil, says(saysChanged), record.isEmpty {
            return nothingDoneLine(korean: korean)
        }
        return nil
    }
}
