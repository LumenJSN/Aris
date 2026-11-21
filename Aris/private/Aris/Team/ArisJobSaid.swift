//
//  ArisJobSaid.swift
//  Aris
//
//  What a job's answer says about the job itself, as against what it reports (ArisJobVerdict). The owner, 2026-11-19:
//  a correct list of the Canvas assignments he hadn't submitted ("아직 제출하지 않았어요", "마감이 지났는데 안 낸") was
//  shown as a failure, because any negative anywhere in an answer counted as "it couldn't". A negative about what was
//  found is the answer's subject; the job saying it couldn't is a sentence about its own doing (finding, opening,
//  signing in, typing: "Canvas에 로그인할 수 없었어요", "I couldn't access Canvas"), and a word the task itself uses in
//  a negation ("안 읽은 메일") is the subject, never a failure. Foundation only (tested).
//

import Foundation

enum ArisJobSaid {
    /// What an answer holds, sentence by sentence.
    struct Reading: Equatable {
        /// Sentences in which the job says it couldn't do something it was doing.
        var failures: [String] = []
        /// The first sentence is one of those.
        var leadsWithFailure = false
        /// A failure sentence that also says what was done ("세 과목은 확인했고 한 과목은 못 봤어요").
        var partial = false
        /// Lines that carry a result (list items, table rows, dated lines), outside failure and plan sentences.
        var results = 0
        /// Letters outside failure and plan sentences.
        var rest = 0
        /// Sentences that only plan or promise ("할게요", "I'll …", "[ ]").
        var plans = 0
    }

    /// A report this long besides its failure sentences is a report with a caveat, not a failure.
    static let longReport = 240
    /// Past this, what isn't a plan is more than a plan's few words.
    static let planRest = 80

    /// The answer read against its task.
    static func read(task: String, answer: String) -> Reading {
        let subject = negatedStems(in: task)
        var reading = Reading()
        let parts = sentences(answer)
        for (index, sentence) in parts.enumerated() {
            if saysItCouldNot(sentence, subject: subject) {
                reading.failures.append(sentence)
                if index == 0 { reading.leadsWithFailure = true }
                if saysSomeDone(sentence) { reading.partial = true }
                continue
            }
            if isPlan(sentence) {
                reading.plans += 1
                continue
            }
            if isResultLine(sentence) { reading.results += 1 }
            reading.rest += sentence.filter(\.isLetter).count
        }
        return reading
    }

    // MARK: - Sentences

    /// The answer's lines, each cut at its sentence ends; empty ones dropped.
    static func sentences(_ answer: String) -> [String] {
        answer.split(whereSeparator: \.isNewline).flatMap { line -> [String] in
            let text = String(line)
            guard let ends = try? NSRegularExpression(pattern: #"(?<=[.!?。])\s+"#) else { return [text] }
            let range = NSRange(text.startIndex..., in: text)
            var pieces: [String] = []
            var start = text.startIndex
            for match in ends.matches(in: text, range: range) {
                guard let cut = Range(match.range, in: text) else { continue }
                pieces.append(String(text[start..<cut.lowerBound]))
                start = cut.upperBound
            }
            pieces.append(String(text[start...]))
            return pieces
        }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }

    // MARK: - The job's own "couldn't"

    /// What a job does on its way to an answer, as the stems of Korean verbs and nouns ("찾지 못했어요", "로그인할 수
    /// 없었어요", "접속에 실패했어요"). A negative of any other verb ("제출하지 않았어요", "답장하지 않았어요") is about
    /// what it found.
    static let koreanStems = ["찾", "확인", "접속", "접근", "로그인", "인증", "가져오", "가져와", "가져올", "불러오", "불러와", "불러올",
                              "읽", "열", "들어가", "들어갈", "연결", "조회", "검색", "다운로드", "처리", "완료", "끝내", "끝낼", "마치",
                              "진행", "실행", "입력", "누르", "누를", "눌", "클릭", "저장", "보내", "전송", "작업", "정리", "알아내",
                              "알아볼", "파악", "로드", "열람"]
    /// After a stem (and up to three letters of its ending): it couldn't ("못", "수 없", "실패", "안 됐", "되지 않았").
    private static let koreanNot = #"[가-힣]{0,3}\s?(지\s?못|지를\s?못|을\s?못|를\s?못|\s못|수\s?(가\s?)?없|에\s?실패|데\s?실패|실패했|실패하였|되지\s?않았|되지\s?않습|리지\s?않았|이\s?안\s?[되됐돼]|가\s?안\s?[되됐돼]|안\s?됐|안\s?돼)"#
    /// "못 찾았어요", "못 봤어요", "못 들어갔어요": the "couldn't" before the verb.
    private static let koreanNotBefore = #"못\s?(찾|봤|보았|본\s|열었|열어|읽었|들어가|들어갔|가져|불러|끝냈|끝내|마쳤|봐요|봐서)"#
    /// Said with no verb of its own: nothing was done, it couldn't at all, or Aris's agent said so.
    private static let koreanWhole = #"(아무것도|아무 것도|하나도)\s?(못|안\s?[했됐])|(^|\s)할\s?수\s?(가\s?)?없|(^|\s)(제가|저는|내가|나는)\s[^.!?\n]{0,40}(못|수\s?없|실패)|(aside|어사이드)[가-힣]{0,2}\s[^.!?\n]{0,40}(못|실패|수\s?없)|오류가\s?(났|발생)|에러가\s?(났|발생)|권한이\s?없|로그인이\s?필요|인증이\s?필요"#
    /// English: the job about itself ("I couldn't", "I was unable to"), or a bare "Couldn't access …" with no other subject.
    private static let englishFirstPerson = #"\b(i|we)\b[^.!?\n]{0,30}\b(couldn't|could not|can't|cannot|wasn't able|was not able|weren't able|were not able|was unable|were unable|am unable|failed to|didn't manage|did not manage|didn't find|did not find|didn't get|did not get|don't have access|do not have access|have no access)"#
    private static let englishVerbs = "access|find|open|load|log ?in|sign ?in|reach|connect|read|get|retrieve|fetch|complete|finish|do|check|see|view|type|press|click|save|send|enter"
    private static var englishBare: String {
        #"(^|[,;:]\s*|\b(but|so|and|sorry,?)\s+)(couldn't|could not|can't|cannot|unable to|not able to|failed to)\s+("# + englishVerbs + #")\b"#
    }
    private static let englishWhole = #"\b(access (was )?denied|permission denied|(login|sign-in|sign in) (is )?required|nothing was done|not typed|aside (couldn't|could not|didn't finish|did not finish|failed|was unable))\b"#

    /// Whether `sentence` is the job saying it couldn't do something it was doing; `subject`: stems the task itself
    /// negates (their negatives are what was asked about).
    static func saysItCouldNot(_ sentence: String, subject: Set<String> = []) -> Bool {
        let lowered = sentence.lowercased()
        if matches(lowered, koreanWhole) || matches(lowered, englishFirstPerson) || matches(lowered, englishBare) || matches(lowered, englishWhole) {
            return true
        }
        if matches(lowered, koreanNotBefore), !subject.contains(where: { lowered.contains("못 " + $0) || lowered.contains("못" + $0) }) { return true }
        return koreanStems.contains { stem in
            !subject.contains(stem) && matches(lowered, NSRegularExpression.escapedPattern(for: stem) + koreanNot)
        }
    }

    /// The stems a task uses in a negation ("안 읽은 메일", "제출 안 한", "확인 못 한"): in its answer those negatives
    /// are the subject.
    static func negatedStems(in task: String) -> Set<String> {
        let lowered = task.lowercased()
        return Set(koreanStems.filter { stem in
            let escaped = NSRegularExpression.escapedPattern(for: stem)
            return matches(lowered, #"(안|못)\s?"# + escaped) || matches(lowered, escaped + #"[가-힣]{0,3}\s?(지\s?않|지\s?못|안\s?한|못\s?한|안\s?된|되지\s?않)"#)
        })
    }

    /// A failure sentence that also says something was done.
    private static func saysSomeDone(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()
        let korean = ["확인했고", "확인했지만", "확인했는데", "찾았고", "찾았지만", "봤고", "봤지만", "가져왔고", "가져왔지만", "정리했고",
                      "정리했지만", "읽었고", "읽었지만", "은 확인했", "는 확인했"]
        return korean.contains(where: lowered.contains)
            || matches(lowered, #"\b(checked|found|got|listed|read|opened|pulled)\b[^.!?\n]{0,80}\bbut\b"#)
    }

    // MARK: - Plans and results

    /// "…할게요", "I'll …", a checklist: a plan or a promise.
    static let planWords = ["할게요", "할께요", "하겠습니다", "하겠어요", "진행할게", "드릴게요", "알려드릴게", "알려 드릴게", "예정이에요", "예정입니다",
                            "[ ]", "i'll ", "i will ", "i'm going to", "will do", "let you know when", "plan:"]

    static func isPlan(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()
        return planWords.contains(where: lowered.contains)
    }

    /// A list item, a table row, or a line with a date or a time in it.
    static func isResultLine(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains("[ ]") else { return false }
        if let first = trimmed.first, "-*•·|".contains(first) { return true }
        if matches(trimmed, #"^\d{1,2}[.)]\s"#) { return true }
        return matches(trimmed, #"\d{1,2}/\d{1,2}|\d{1,2}월\s?\d{1,2}일|\b\d{1,2}:\d{2}\b|\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.? \d{1,2}\b"#)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
