//
//  ArisWhyCopy.swift
//  aris-agent
//
//  The words of the "왜 그렇게 했어?" answer (ArisWhyAnswer), in Korean (해요체, short) and English. Korean when the user's
//  question has any Korean in it, English otherwise. No sentence puts a particle after a name it didn't write, so a
//  title or an AI's name reads right whatever it ends in. Foundation only (tested).
//

import Foundation

struct ArisWhyCopy {
    let korean: Bool

    private func say(_ korean: String, _ english: String) -> String { self.korean ? korean : english }

    /// An AI's title as the record keeps it, in English (“API 브레인” is “API model”; the others are names).
    static func englishBrain(_ title: String) -> String { ArisBrain.allCases.first { $0.title == title }?.title(english: true) ?? title }


    // MARK: Shapes

    func quoted(_ text: String) -> String { "“" + text + "”" }

    func short(_ text: String, _ limit: Int) -> String { text.count > limit ? String(text.prefix(limit - 1)) + "…" : text }

    func label(_ name: String, _ words: String) -> String { "**" + name + "**: " + words }

    /// The first `limit` of `items`, then how many more there are (`total`: when more exist than were handed in).
    func list(_ items: [String], limit: Int, total: Int? = nil) -> String {
        let more = (total ?? items.count) - min(items.count, limit)
        return items.prefix(limit).joined(separator: "; ") + (more > 0 ? say(" 외 \(more)개", " and \(more) more") : "")
    }

    /// "‘메시지 보내기’" (English: "the ‘메시지 보내기’"), or "그" / "that" when the name isn't said.
    private func titled(_ title: String?) -> String { title.map { say("‘\(short($0, Self.inSentence))’", "the ‘\(short($0, Self.inSentence))’") } ?? say("그", "that") }

    /// How much of the user's words or a card's title one sentence carries: the sentence stays one the notch draws as the
    /// answer's first line (ArisAnswerDocument.leadLimit) and the voice reads in a breath.
    static let inSentence = 20
    /// How much of a quoted line (a failure's words, a reason as recorded) a sentence carries.
    static let quotedLine = 40
    /// The longest the sentence may get (the notch draws a longer first line as a paragraph: ArisAnswerDocument.leadLimit).
    static let sentenceLimit = 120

    private func sentence(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    // MARK: Labels

    var factsTitle: String { say("방금 한 일", "What happened") }
    var unrecordedTitle: String { say("기록에 없는 이유", "Why there is no record") }
    var requestLabel: String { say("요청", "You asked") }
    var brainLabel: String { "AI" }
    var memoryLabel: String { say("기억", "Memory") }
    var readLabel: String { say("읽은 것", "Read") }
    var doneLabel: String { say("한 일", "Done") }
    var cardLabel: String { say("확인 카드", "Cards") }
    var ruleLabel: String { say("규칙", "Rule") }
    var insteadLabel: String { say("대신", "Instead") }

    // MARK: The sentence

    func didLead(asked: String?, brain: String, tail: String) -> String {
        let said = asked.map { say("“\(short($0, Self.inSentence))”라고 하셔서 ", "You said “\(short($0, Self.inSentence))”, so ") } ?? say("방금 하신 말에 ", "For what you just said, ")
        return said + brain + say(", ", ", and ") + tail + "."
    }

    var noBrainClause: String { say("AI 없이 Aris가 바로 답했고", "Aris answered it itself, without an AI") }
    func brainClause(_ brain: String) -> String { say("\(brain)에게 맡겼고", "\(brain) took it") }
    func tookOverClause(_ brain: String, from passed: String) -> String { say("\(passed) 대신 \(brain)에게 맡겼고", "\(brain) took over from \(passed)") }

    func askedFirstClause(_ title: String?) -> String { say("\(titled(title)) 카드로 먼저 여쭤봤어요", "it asked first (\(titled(title)) card)") }
    var standingClause: String { say("전에 그냥 하라고 하신 일이라 묻지 않고 했어요", "it went ahead because you had said not to ask for that") }
    func memoryClause(_ first: String?, count: Int) -> String {
        guard let first else { return say("기억 \(count)개도 함께 건넸어요", "\(count) memor\(count == 1 ? "y" : "ies") went along") }
        return count > 1 ? say("기억 ‘\(first)’ 외 \(count - 1)개도 함께 건넸어요", "the memory ‘\(first)’ and \(count - 1) more went along")
            : say("기억 ‘\(first)’도 함께 건넸어요", "the memory ‘\(first)’ went along")
    }
    var plainClause: String { say("기억이나 확인 카드 없이 답했어요", "no memory or card was part of it") }
    var plainLocalClause: String { say("기억이나 확인 카드는 쓰지 않았어요", "no memory or card was part of it") }

    private func refused(_ label: String?) -> String {
        label.map { say("‘\(short($0, Self.inSentence))’ 일은 하지 않았어요", "‘\(short($0, Self.inSentence))’ wasn't done") } ?? say("그 일은 하지 않았어요", "that wasn't done")
    }
    func refusedLead(_ label: String?, rule: String) -> String { sentence(refused(label)) + ": " + rule + "." }
    func askedLead(_ title: String?, why: String) -> String { say("\(titled(title)) 카드는 \(why).", sentence("\(titled(title)) card came up because \(why).")) }

    // MARK: Why a card asked (in the sentence: short; in the list: the whole rule)

    var askAfterOutsideShort: String { say("바깥 글을 읽은 뒤라 한 번 더 여쭤본 거예요", "outside content had been read, so it asked once more") }
    var askCountdownShort: String { say("직접 말씀하신 메시지라, 묻는 대신 읽어 드리고 잠깐 기다렸다 보내려던 거예요", "you dictated it, so it is read back and sent after a short wait") }
    func askProposalShort(_ streak: Int) -> String {
        say("같은 일을 \(streak)번 연달아 허락하셔서, 앞으로 그냥 할지 여쭤본 거예요", "after \(streak) yeses in a row it asked whether to stop asking")
    }
    var askMemoryShort: String { say("기억을 넣거나 지우는 일이라 여쭤본 거예요", "it writes to your memory, so it asked") }
    var askHandsFreeShort: String { say("키나 이름 없이 들린 말이라 꼭 여쭤봐야 했어요", "it was heard hands-free, so it had to ask") }
    var askPlainShort: String { say("보내거나 바꾸거나 지우는 일이라 하기 전에 여쭤본 거예요", "it sends, changes or deletes something, so it asked first") }

    var askAfterOutside: String {
        say("바깥 글(웹, 메일, 화면)을 읽은 뒤라서, 평소엔 그냥 하던 일도 한 번 더 확인해요. 새 대화를 시작하면 다시 평소대로 해요.",
            "Outside content (the web, mail, the screen) had been read, so even things that usually just run are checked once more. A new conversation goes back to normal.")
    }
    var askCountdown: String {
        say("직접 말씀하신 메시지라서, 묻는 대신 읽어 드리고 잠깐 기다렸다가 보내요. 그 사이에 멈출 수 있어요.",
            "It was a message you dictated, so instead of asking it is read back and sent after a short wait. You can stop it in that time.")
    }
    func askProposal(_ streak: Int) -> String {
        say("같은 일을 \(streak)번 연달아 허락하셔서, 앞으로는 묻지 않고 할지 여쭤본 거예요. ‘네’ 하시면 다음부터 그 일은 묻지 않아요.",
            "You said yes to the same thing \(streak) times in a row, so it asked whether to stop asking. A yes means that one thing no longer asks.")
    }
    var askMemory: String {
        say("기억에 넣거나 지우는 일은 직접 하신 말이 아니면 확인받게 돼 있어요.", "Writing to or removing from your memory is confirmed unless you said it yourself.")
    }
    var askHandsFree: String {
        say("키나 이름 없이 들린 말(핸즈프리)이라서, 보내거나 지우는 일은 꼭 확인받게 돼 있어요.",
            "It was heard hands-free (no key, no name), so anything that sends or deletes must be confirmed.")
    }
    var askPlain: String {
        say("보내거나 바꾸거나 지우는 일은 하기 전에 확인받게 돼 있어요. 읽기만 하는 일은 묻지 않아요.",
            "Anything that sends, changes or deletes is confirmed before it runs. Reading never asks.")
    }

    // MARK: Refusals

    var declined: String { say("카드에 ‘아니요’라고 하셨어요", "you said no on the card") }
    var unanswered: String { say("카드에 답이 없어서 하지 않았어요 (‘아니요’ 하신 건 아니에요)", "the card wasn't answered in time, so it wasn't done (that is not a no from you)") }
    var declinedInstead: String { say("다시 말씀해 주시면 새 카드로 여쭤볼게요.", "Ask again and a new card comes up.") }
    var stopped: String { say("AI가 허용되지 않은 일을 하려고 해서 Aris가 멈췄어요", "the AI tried something it isn't allowed, so Aris stopped it") }
    var askAgainInstead: String { say("다시 한 번 말씀해 주세요.", "Please ask once more.") }
    func failed(_ line: String?) -> String {
        line.map { say("답 대신 “\(short($0, Self.quotedLine))”라는 말로 끝났어요. 그 밖의 이유는 기록에 없어요",
                       "it ended with “\(short($0, Self.quotedLine))”; the record holds no other reason") }
            ?? say("답이 오지 않고 끝났어요. 이유는 기록에 없어요", "it ended without an answer, and the record holds no reason")
    }
    var noReasonKept: String { say("막았다는 것만 기록에 있고 이유는 없어요", "the record says it was refused but holds no reason") }
    func asRecorded(_ why: String) -> String {
        say("기록에 남은 이유는 “\(short(why, Self.quotedLine))”예요", "the reason on record is “\(short(why, Self.quotedLine))”")
    }
    var reasonHeld: String {
        say("이유는 기록에 있지만, 바깥 글을 읽은 턴의 것이라 이 대화에는 옮기지 않아요", "the reason is on record, but it comes from a turn that read outside content and isn't repeated here")
    }

    // MARK: The list

    var secretWords: String { say("(비밀로 보이는 말이라 옮겨 적지 않았어요)", "(it looked like a secret, so it isn't repeated)") }
    func ago(_ minutes: Int) -> String {
        minutes >= 120 ? say("(\(minutes / 60)시간 전)", "(\(minutes / 60) hours ago)") : say("(\(minutes)분 전)", "(\(minutes) min ago)")
    }
    var withFile: String { say("(파일과 함께)", "(with a file)") }
    var stillGoing: String { say("(아직 하는 중)", "(still going)") }

    var noBrain: String {
        say("거치지 않았어요. Aris가 바로 답했어요 (기억에 대한 말, 전에 배운 지름길은 그렇게 해요).",
            "None. Aris answered itself (it does for words about your memory and for a shortcut it learned).")
    }
    func tookOver(_ brain: String, from passed: String) -> String {
        say("\(passed) → \(brain) (앞의 AI가 한도에 걸렸거나 답하지 못해서 넘겼어요)", "\(passed) → \(brain) (the first was out of quota or couldn't answer)")
    }
    func routed(from wanted: String, why: String) -> String { say("(평소 설정은 \(wanted). \(why))", "(your setting is \(wanted). \(why))") }
    var routedScreen: String { say("화면이 들어간 대화는 정해진 AI가 맡아요", "A conversation with the screen in it goes to a set AI") }
    var routedHandsFree: String { say("핸즈프리로 들은 말은 정해진 AI가 맡아요", "Words heard hands-free go to a set AI") }
    var routedUnknown: String { say("바뀐 이유는 기록에 없어요", "The record doesn't say why it changed") }

    var becauseHandsFree: String { say("핸즈프리로 들은 말이라", "it was heard hands-free") }
    var becauseScreen: String { say("화면을 본 대화라", "the conversation had seen the screen") }
    var becauseOutside: String { say("바깥 글을 읽은 대화라", "the conversation holds outside content") }
    var becauseOther: String { say("기억을 쓰지 않는 턴이라", "it was a turn that gets no memories") }
    func memoryNotGiven(_ why: String) -> String { say("AI에게 건네지 않았어요 (\(why))", "None went to the AI (\(why))") }
    var memoryNone: String { say("건넨 게 없어요 (이 말과 맞는 기억이 없었어요)", "None went along (nothing remembered fit these words)") }
    func memoryGiven(_ list: String) -> String { say("AI에게 함께 건넨 건 \(list)", "What went to the AI: \(list)") }
    func memoryHeld(_ count: Int) -> String {
        say("\(count)개를 건넸어요. 지금은 화면이나 바깥 글이 들어온 대화라 내용은 다시 말하지 않아요 (설정 › 기억에서 볼 수 있어요)",
            "\(count) went along. Their words aren't repeated in a conversation that holds the screen or outside content (they are in Settings › Memory)")
    }
    func memoryHeldHandsFree(_ count: Int) -> String {
        say("\(count)개를 건넸어요. 키나 이름 없이 들린 말이라 내용은 말하지 않아요. 키를 누르고 다시 물어보시면 말해 드려요",
            "\(count) went along. This was heard hands-free, so their words aren't said. Hold the key and ask again to hear them")
    }
    func source(_ source: ArisMemorySource) -> String? {
        switch source {
        case .said: return say("직접 기억하라고 하신 것", "you told me to remember it")
        case .learned: return say("대화에서 제가 배운 것", "I picked it up from a conversation")
        case .tool, .imported: return nil
        }
    }

    func read(_ kind: ArisWhySteps.Read) -> String {
        switch kind {
        case .web: return say("웹 검색", "a web search")
        case .page: return say("웹 페이지", "a web page")
        case .mail: return say("메일", "mail")
        case .messages: return say("메시지", "messages")
        case .notes: return say("메모", "notes")
        case .files: return say("파일", "files")
        case .screen: return say("화면", "the screen")
        case .selection: return say("선택한 글", "the selection")
        case .clipboard: return say("클립보드", "the clipboard")
        case .browser: return say("브라우저 탭", "the browser tab")
        case .service: return say("연결된 서비스", "a connected service")
        }
    }
    var attachedFile: String { say("함께 온 파일", "the attached file") }
    var readNothing: String { say("화면도 바깥 글도 읽지 않았어요", "Neither the screen nor outside content") }
    func readClean(_ what: String) -> String { say("\(what) 단계가 있었어요", "Steps for \(what)") }
    func readScreen(_ what: String?) -> String {
        say("\(what ?? "화면"). 화면을 본 대화라서, 직접 말씀하신 것 말고는 여쭤보고 해요",
            "\(what ?? "the screen"). The conversation has seen the screen, so anything you didn't say yourself is asked first")
    }
    func readOutside(_ what: String?) -> String {
        say("\(what.map { $0 + ". " } ?? "")바깥 글이 들어온 대화라서, 새 대화 전까지는 보내거나 바꾸는 일을 매번 여쭤봐요 (닫기를 누르면 새 대화가 돼요)",
            "\(what.map { $0 + ". " } ?? "")Outside content is in the conversation, so until a new one starts everything that sends or changes is asked (Close starts a new one)")
    }

    var doneUnread: String { say("한 일 기록을 읽지 못해서 몰라요", "Unknown: the activity log couldn't be read") }
    var doneNothing: String { say("한 일 기록에 남은 게 없어요 (Mac에서 바꾼 게 없어요)", "Nothing in the activity log (nothing on the Mac was changed)") }
    func doneHeld(_ count: Int) -> String {
        say("\(count)건이 한 일 기록에 있어요 (바깥 글을 읽은 턴이라 이름은 ‘한 일’ 목록에서 보세요)",
            "\(count) in the activity log (that turn read outside content, so see their names in the activity list)")
    }

    var aCard: String { say("카드", "a card") }
    func answered(_ answer: ArisWhyCardAnswer) -> String {
        switch answer {
        case .yes: return say("→ 허락하셨어요", "→ you said yes")
        case .no: return say("→ ‘아니요’ 하셨어요", "→ you said no")
        case .unanswered: return say("→ 답이 없었어요", "→ it wasn't answered")
        }
    }
    var answerUnknown: String { say("→ 답은 기록에 없어요", "→ the answer isn't on record") }
    func cardsHeld(_ count: Int) -> String {
        say("\(count)개가 떴어요 (바깥 글을 읽은 턴이라 이름은 옮기지 않아요)", "\(count) came up (that turn read outside content, so their names aren't repeated)")
    }

    var ruleStanding: String { say("전에 ‘앞으로 이건 그냥 해’라고 하신 일은 묻지 않았어요.", "What you had said never to ask about went ahead without a card.") }
    var ruleJudged: String { say("Aris가 요청과 맞는지 보고 묻지 않고 진행한 일이 있어요.", "Aris judged one step to fit the request and let it run.") }
    func ruleAuto(_ count: Int) -> String {
        say("읽기처럼 되돌릴 게 없는 일 \(count)건은 ‘묻지 않음’으로 분류돼서 그냥 했어요.", "\(count) step\(count == 1 ? "" : "s") rated safe (reads and the like) ran without asking.")
    }
    var ruleHandsFree: String { say("핸즈프리로 들은 말이라 전에 받은 허락은 쓰지 않았어요.", "It was heard hands-free, so no earlier yes was used.") }
    var ruleNothing: String { say("확인 카드도 거절도 없었어요.", "No card and no refusal.") }

    // MARK: No record

    func unrecordedLead(_ heard: String?) -> String {
        heard.map { say("방금 “\($0)”라고 하신 건 제 기록에 없어요.", "“\($0)” isn't in my record.") } ?? say("방금 일은 제 기록에 없어요.", "That last one isn't in my record.")
    }
    var unrecordedWhy: String {
        say("타이머, 볼륨, 앱 열기, 할 일처럼 Aris 앱이 바로 하는 일과 백그라운드 작업으로 넘긴 일은 여기에 남지 않아요.",
            "What the Aris app does by itself (a timer, the volume, opening an app, a to-do) and what goes to a background job isn't kept here.")
    }
    var unrecordedLocal: String {
        say("앱이 바로 한 일이라면 기억도 AI도 거치지 않았어요.", "If the app did it by itself, no memory and no AI was involved.")
    }
    func latestRecorded(_ asked: String?, minutes: Int) -> String {
        let when = ago(max(minutes, 1))
        return asked.map { say("기록에는 “\($0)” \(when)까지 남아 있어요.", "The last request on record is “\($0)” \(when).") }
            ?? say("기록에는 \(when) 요청까지 남아 있어요.", "The last request on record is from \(when).")
    }
    var nothingLead: String { say("아직 기록된 요청이 없어요.", "No request is on record yet.") }
    func nothingSince(_ since: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let at = formatter.string(from: since)
        return say("Aris 에이전트가 \(at)에 시작한 뒤로 AI에게 간 요청이 없었어요.", "No request has gone to an AI since the Aris agent started at \(at).")
    }
    var memoryOnly: String {
        say("이 기록은 메모리에만 두고 파일로 남기지 않아서, 에이전트가 다시 시작하면 그 전 일은 답할 수 없어요.",
            "This record is kept in memory only, never in a file, so after the agent restarts it can't answer for what came before.")
    }
}
