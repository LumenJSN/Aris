// Tests for echo-fix (the owner, 2026-11-16): through the speakers Aris heard its own answer as a new turn and
// answered it, endlessly; and after "작업할게요" (a hand-off) the notch stayed open instead of closing onto the jobs'
// pill. ArisEchoGuard (when listening may start, Aris's name in its own voice, a heard turn that is Aris's own words),
// ArisEchoMemory, ArisEchoLoop, barge-in on speakers without an echo canceller, and the hand-off's end of the notch.
// Called from main.swift; uses its check().
import Foundation

private let echoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func echoSource(_ path: String) -> String { (try? String(contentsOf: echoRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runEchoFixTests() {
    echoLoopReproductionTests()
    echoTailTests()
    echoNameTests()
    echoVerdictTests()
    echoMemoryTests()
    echoLoopBreakerTests()
    echoBargeInTests()
    handOffNotchTests()
    echoWiringTests()
}

/// The loop as it was: Aris's hand-off line comes back through the room, the old path keeps every word of it (the
/// leading trim only runs for a barge-in) and answers it, and its answer comes back again. With the guard the first
/// echo is dropped, never answered, and the second ends the conversation's listening.
private func echoLoopReproductionTests() {
    let line = "제가 맡았어요, 끝나면 알려줄게요."
    let heardBack = "끝나면 알려줄게요"
    // Before: between turns nothing is trimmed (echoWords 0), so the echo is a turn, answered every time.
    var answeredBefore = 0
    for _ in 0..<5 {
        let text = ArisEchoTrim.trimmed(heardBack, arisWasSaying: "", atMost: 0)
        if !text.isEmpty { answeredBefore += 1 }
    }
    check(answeredBefore == 5, "echo loop: reproduced: the old path answers Aris's own words every round (\(answeredBefore) of 5)")
    // After: a fake speaker says the line, the fake microphone's transcript is its tail, round after round.
    var memory = ArisEchoMemory()
    var loop = ArisEchoLoop()
    var answered = 0, dropped = 0, rounds = 0
    var listening = true
    var clock = 100.0
    while listening, rounds < 5 {
        rounds += 1
        memory = memory.starting(line, at: clock)
        clock += 3
        let verdict = ArisEchoGuard.verdict(heardBack, recent: memory.recent(at: clock))
        loop = loop.after(verdict)
        if verdict == .user { answered += 1 } else { dropped += 1 }
        if loop.stops { listening = false }
    }
    check(answered == 0 && dropped == 2 && !listening && rounds == 2,
          "echo loop: fixed: Aris's own words are never answered and two in a row stop listening (answered \(answered), dropped \(dropped), rounds \(rounds))")
    // The whole line heard back is Aris's own sentence: listening stops at once.
    let whole = ArisEchoGuard.verdict("제가 맡았어요 끝나면 알려줄게요", recent: [line])
    check(whole == .ownWords && ArisEchoLoop().after(whole).stops, "echo loop: Aris's whole sentence heard back stops listening at once")
    // A real follow-up after that is the user's, and resets the count.
    let follow = ArisEchoGuard.verdict("내일 아침 날씨는 어때", recent: [line])
    check(follow == .user && ArisEchoLoop().after(.echo).after(follow) == ArisEchoLoop(), "echo loop: the user's own follow-up is a turn and resets the count")
}

private func echoTailTests() {
    typealias G = ArisEchoGuard
    check(G.tail(outputLatency: nil, bluetooth: false) == G.floor && G.floor >= 0.3 && G.floor <= 0.4,
          "echo tail: an unread latency on speakers waits the floor (~350 ms)")
    check(G.tail(outputLatency: 0.01, bluetooth: false) == G.floor, "echo tail: a short built-in latency still waits the floor")
    check(abs(G.tail(outputLatency: 0.3, bluetooth: false) - 0.5) < 0.0001, "echo tail: a long output latency is waited out, plus the room")
    check(G.tail(outputLatency: 0.05, bluetooth: true) == G.bluetoothFloor && G.bluetoothFloor >= 0.5,
          "echo tail: Bluetooth waits at least its own floor, whatever it reports")
    check(abs(G.tail(outputLatency: 0.5, bluetooth: true) - 0.7) < 0.0001, "echo tail: Bluetooth's reported delay counts when longer")
    check(G.tail(outputLatency: 9, bluetooth: true) == G.longest && G.tail(outputLatency: -3, bluetooth: false) == G.floor,
          "echo tail: a wrong reading never holds listening off past the cap, or under the floor")
    check(G.waitBeforeListening(playing: true, sinceStopped: nil, tail: 0.5) == 0.5, "echo tail: while Aris plays, listening waits")
    check(abs(G.waitBeforeListening(playing: false, sinceStopped: 0.2, tail: 0.5) - 0.3) < 0.0001, "echo tail: right after Aris stops, only the rest of the tail")
    check(G.waitBeforeListening(playing: false, sinceStopped: 2, tail: 0.5) == 0 && G.waitBeforeListening(playing: false, sinceStopped: nil, tail: 0.5) == 0,
          "echo tail: long after, or never played: listening at once")
    // The fake speaker's last sound reaches the room `latency` after it reports finishing and rings `room` more: the
    // listener never opens before that, at any output latency.
    var late: [Double] = []
    for latency in stride(from: 0.0, through: 1.2, by: 0.05) {
        for bluetooth in [false, true] {
            let tail = G.tail(outputLatency: latency, bluetooth: bluetooth)
            let echoEnds = latency + 0.15
            if tail < echoEnds { late.append(latency) }
        }
    }
    check(late.isEmpty, "echo tail: the follow-up listener opens only after Aris's last sound left the room (too early at \(late))")
    // The turn's audio never reaches back before the watch was armed: no pre-roll of Aris's tail.
    check(G.turnStart(reached: 100_000, lookback: 8_000, armedAt: 95_000) == 95_000, "echo tail: the lookback is cut at the moment listening started")
    check(G.turnStart(reached: 100_000, lookback: 8_000, armedAt: 50_000) == 92_000 && G.turnStart(reached: 4_000, lookback: 8_000, armedAt: nil) == 0,
          "echo tail: a watch armed long ago keeps its whole lookback (never below 0)")
}

private func echoNameTests() {
    typealias G = ArisEchoGuard
    check(G.ownVoiceAudible(playing: true, sinceStopped: nil, window: 1) && G.ownVoiceAudible(playing: false, sinceStopped: 0.4, window: 1)
          && !G.ownVoiceAudible(playing: false, sinceStopped: 1.5, window: 1) && !G.ownVoiceAudible(playing: false, sinceStopped: nil, window: 1),
          "echo name: Aris's voice is audible while it plays and within the window after")
    check(G.ignoresName(headphones: false, ownVoiceAudible: true, saidName: true), "echo name: over speakers, 아리스 in Aris's own sentence never wakes or stops it")
    check(!G.ignoresName(headphones: true, ownVoiceAudible: true, saidName: true), "echo name: with headphones the microphone can't hear Aris: the name counts")
    check(!G.ignoresName(headphones: false, ownVoiceAudible: true, saidName: false) && !G.ignoresName(headphones: false, ownVoiceAudible: false, saidName: true),
          "echo name: the user's 아리스 counts when Aris didn't just say it, or once its voice is gone")
    check(G.namesAris("네, 아리스가 할게요.") && G.namesAris("I'm Aris.") && !G.namesAris("제가 맡았어요"), "echo name: Aris's own sentence is read for its name anywhere in it")
}

private func echoVerdictTests() {
    typealias G = ArisEchoGuard
    let reply = "오늘 서울은 맑고 기온은 12도예요. 저녁엔 조금 쌀쌀해요."
    check(G.verdict("저녁엔 조금 쌀쌀해요", recent: [reply]) == .ownWords, "echo verdict: the tail of Aris's answer is its own sentence")
    check(G.verdict("저녁 엔 조금 쌀 쌀해요!", recent: [reply]) == .ownWords, "echo verdict: spacing and punctuation never matter")
    check(G.verdict("조금 쌀쌀해요", recent: [reply]) == .echo, "echo verdict: two of Aris's words in a row are echo")
    check(G.verdict("기온은 12도예요 저녁엔 쌀쌀해요 음", recent: [reply]) == .echo, "echo verdict: mostly Aris's words (fuzzy, not only leading) is echo")
    check(G.verdict("어 그러니까 오늘 서울은 맑고 기온은 12도", recent: [reply]) == .echo, "echo verdict: a long run of Aris's words in the middle is echo")
    check(G.verdict("내일 부산 날씨는 어때", recent: [reply]) == .user, "echo verdict: a follow-up with one shared word is the user's")
    check(G.verdict("잠깐 그거 말고 내일 날씨", recent: [reply]) == .user, "echo verdict: a real barge-in is the user's")
    check(G.verdict("응", recent: ["응, 알겠어요."]) == .user && G.verdict("네네", recent: ["네네 알겠어요"]) == .user,
          "echo verdict: a short answer is never judged")
    check(G.verdict("저녁엔 조금 쌀쌀해요", recent: []) == .user, "echo verdict: nothing said lately: nothing is echo")
    check(G.verdict("I'll let you know when it's done", recent: ["I'm on it in the background. I'll let you know when it's done."]) == .ownWords,
          "echo verdict: English, case-insensitive")
    let older = "Claude Code가 맡았어요, 끝나면 알려줄게요."
    check(G.verdict("끝나면 알려줄게요", recent: [older, reply]) == .echo, "echo verdict: Aris's last two replies both count")
    check(G.tokens("맡았어요, 끝나면!") == ["맡았어요", "끝나면"] && G.longestRun("abcdef", "xxcdeyy") == 3 && G.longestRun("", "a") == 0,
          "echo verdict: tokens and the longest shared run")
}

private func echoMemoryTests() {
    var memory = ArisEchoMemory()
    memory = memory.starting("", at: 10).adding("첫 문장이에요.", at: 10.5).adding("두 번째예요.", at: 11)
    check(memory.recent(at: 12) == ["첫 문장이에요. 두 번째예요."], "echo memory: an answer's sentences are one utterance")
    memory = memory.starting("다음 줄", at: 20).starting("세 번째 줄", at: 30)
    check(memory.recent(at: 31) == ["다음 줄", "세 번째 줄"] && memory.said.count == ArisEchoMemory.kept, "echo memory: the last two utterances are kept")
    check(memory.recent(at: 30 + ArisEchoMemory.lasts + 1).isEmpty && memory.recent(at: 20 + ArisEchoMemory.lasts + 1) == ["세 번째 줄"],
          "echo memory: what was said long ago is forgotten")
    check(ArisEchoMemory().adding("혼자", at: 1).recent(at: 1) == ["혼자"], "echo memory: a sentence with nothing started starts one")
}

private func echoLoopBreakerTests() {
    let one = ArisEchoLoop().after(.echo)
    check(!one.stops && one.after(.echo).stops, "echo loop breaker: two echo turns in a row stop listening")
    check(!one.after(.user).after(.echo).stops, "echo loop breaker: a turn of the user's in between resets it")
    check(ArisEchoLoop().after(.ownWords).stops, "echo loop breaker: Aris's own sentence stops it at once")
}

private func echoBargeInTests() {
    typealias B = ArisBargeIn
    check(B.mode(headphones: false, speakersAllowed: true, echoCancelled: false) == nil,
          "echo barge-in: on speakers with no echo canceller the voice watch stays off (Aris's voice can't stop itself)")
    check(B.mode(headphones: false, speakersAllowed: true, echoCancelled: true) == .speakers && B.mode(headphones: false, speakersAllowed: false, echoCancelled: true) == nil,
          "echo barge-in: an echo canceller would let the setting decide again")
    check(B.mode(headphones: true, speakersAllowed: false, echoCancelled: false) == .headphones, "echo barge-in: headphones keep barge-in")
    check(!B.echoCancellerOn, "echo barge-in: the detector has no echo canceller (no voice processing: other apps' sound is never ducked)")
}

private func handOffNotchTests() {
    typealias N = ArisNotch
    check(N.endWait(handedOff: true, dictation: false, reply: String(repeating: "가", count: 300)) == .zero,
          "hand-off notch: once the hand-off line is said the notch doesn't wait a reading time")
    check(N.endWait(handedOff: false, dictation: false, reply: "맑아요.") == N.readingTime(for: "맑아요.") && N.endWait(handedOff: false, dictation: true, reply: "x") == .zero,
          "hand-off notch: any other answer keeps its reading time (dictation none)")
    check(N.ending(openedNotch: false, isOpen: true, handedOff: true) == .close && N.ending(openedNotch: true, isOpen: true, handedOff: true) == .close,
          "hand-off notch: after a hand-off the open notch closes whoever opened it")
    check(N.ending(openedNotch: false, isOpen: true, handedOff: false) == .restoreTab && N.ending(openedNotch: true, isOpen: false, handedOff: true) == .stay,
          "hand-off notch: other turns end as before; a closed notch stays closed")
    check(!N.waitsForHover(handedOff: true) && N.waitsForHover(handedOff: false), "hand-off notch: the pointer on the notch doesn't hold it after a hand-off")
    check(N.linger(handedOff: true) == .zero && N.linger(handedOff: false) == .seconds(1.5), "hand-off notch: the turn ends as the line ends; others linger as before")
    // Closed, nothing else under the notch: the room is the jobs' pill (it shows the job), not a notice stepping aside.
    check(ArisNoticePillRules.underNotch(closed: true, hidden: false, musicPeek: false, nowPlaying: false, noticeUp: false, noticeHere: true) == .jobs,
          "hand-off notch: closed after the hand-off, the jobs' pill has the room")
    check(ArisNoticePillRules.underNotch(closed: false, hidden: false, musicPeek: false, nowPlaying: false, noticeUp: false, noticeHere: false) == .none,
          "hand-off notch: while it was still open the pill waited (it shows once the notch closes)")
}

private func echoWiringTests() {
    let controller = echoSource("Aris/private/Aris/ArisController.swift")
    let conversation = echoSource("Aris/private/Aris/ArisController+Conversation.swift")
    let wake = echoSource("Aris/private/Aris/ArisController+Wake.swift")
    let detector = echoSource("Aris/private/Aris/ArisWakeDetector.swift")
    let speaker = echoSource("Aris/private/Aris/ArisSpeaker.swift")
    let team = echoSource("Aris/private/Aris/ArisController+Team.swift")
    let behaviour = echoSource("Aris/private/Notch/ArisNotchRoot+Behaviour.swift")
    let settings = echoSource("Aris/components/Settings/ArisSettingsBuilder.swift")
    check(controller.contains("ArisEchoGuard.verdict(") && controller.contains("echoHeard(") && conversation.contains("func echoHeard("),
          "wiring: every voice turn's words are judged against Aris's recent words before anything is routed")
    check(conversation.contains("ArisEchoGuard.waitBeforeListening(") && conversation.contains("echoTailWatch") && conversation.contains("ArisOutputLatency"),
          "wiring: the between-turn watch is armed only after the speaker finished plus the output's tail")
    check(conversation.contains("ArisBargeIn.mode(headphones: ArisDucking.outputIsHeadphones(), speakersAllowed: Defaults[.arisBargeInOnSpeakers], echoCancelled: ArisBargeIn.echoCancellerOn)"),
          "wiring: barge-in on speakers needs an echo canceller")
    check(conversation.contains("closeConversation(.echo)") && conversation.contains("echoLoop.after("), "wiring: the loop breaker ends the conversation")
    check(detector.contains("ArisEchoGuard.turnStart(") && detector.contains("armedAt"), "wiring: the detector never hands a turn audio from before its watch was armed")
    check(wake.contains("ArisEchoGuard.ignoresName("), "wiring: Aris's name in its own voice over the speakers is ignored")
    check(speaker.contains("echo = echo.starting(") && speaker.contains("echo.adding(") && speaker.contains("var isPlaying") && speaker.contains("stoppedAt"),
          "wiring: the speaker remembers what it said and when its voice stopped")
    check(team.contains("handedOff = true"), "wiring: a job dispatched in a turn marks the turn as handed off")
    check(behaviour.contains("ArisNotch.endWait(handedOff:") && behaviour.contains("ArisNotch.waitsForHover(handedOff:") && behaviour.contains("handedOff: handedOff)"),
          "wiring: the notch closes once the hand-off line ends")
    check(controller.contains("ArisNotch.linger(handedOff: handedOff)"), "wiring: the turn ends as the hand-off line ends")
    check(!settings.contains("\"aris.bargeIn\""), "wiring: the speakers' barge-in switch is gone while there is no echo canceller")
}
