// jv-hearing: the endpoint policy, the speculative turn, the second listen's budget and the stage clock
// (Shared/Core/Hearing), plus their wiring in the app files the tests can't compile.
import AVFoundation
import Foundation

func runHearingTests() {
    hearingPolicyTableTests()
    hearingDriverTests()
    hearingSpeculativeTurnTests()
    hearingSecondPassTests()
    hearingStageClockTests()
    hearingGateTests()
    hearingFeedTests()
    hearingWiringTests()
}

private func ms(_ value: Int) -> Duration { .milliseconds(value) }

// MARK: - The policy, case by case

private func hearingPolicyTableTests() {
    typealias P = ArisEndpointPolicy
    func decide(voice: Int?, words: Int? = 300, score: Float?, complete: Bool, hanging: Bool = false, start: Int = 4000) -> ArisEndpointDecision {
        P.decide(ArisEndpointInput(sinceStart: ms(start), sinceVoice: voice.map(ms), sinceWords: words.map(ms), score: score,
                                   complete: complete, hanging: hanging)).decision
    }
    // (case, score, complete, hanging, plausible voice ms, firm voice ms)
    let table: [(ArisEndpointCase, Float?, Bool, Bool, Int, Int)] = [
        (.confident, 0.9, true, false, 250, 500),
        (.finishedVoice, 0.9, false, false, 800, 2000),
        (.unsure, 0.5, true, false, 1400, 2000),
        (.midThought, 0.1, false, false, 3000, 3600),
        (.midThoughtWordsFinished, 0.1, true, false, 2000, 2600),
        (.hanging, 0.9, true, true, 3000, 3600),
        (.noScoreComplete, nil, true, false, 900, 1500),
        (.noScore, nil, false, false, 1400, 2000),
    ]
    for (endCase, score, complete, hanging, plausible, firm) in table {
        check(P.endCase(score: score, complete: complete, hanging: hanging) == endCase, "endpoint policy: \(endCase.rawValue) is recognised")
        check(decide(voice: plausible - 10, score: score, complete: complete, hanging: hanging) == .keepListening
              && decide(voice: plausible, score: score, complete: complete, hanging: hanging) == .plausibleEnd
              && decide(voice: firm - 10, score: score, complete: complete, hanging: hanging) == .plausibleEnd
              && decide(voice: firm, score: score, complete: complete, hanging: hanging) == .firmEnd,
              "endpoint policy: \(endCase.rawValue) -> plausible at \(plausible) ms, firm at \(firm) ms of quiet")
        let row = P.row(endCase)
        check(row.firm.voice >= row.before || endCase == .confident, "endpoint policy: \(endCase.rawValue) never commits before the old end (\(row.before))")
        check(row.plausible.voice <= row.firm.voice && row.plausible.words <= row.firm.words, "endpoint policy: \(endCase.rawValue) speculates before it commits")
    }
    check(P.row(.confident).firm.voice == P.row(.confident).before && P.row(.confident).plausible.voice < P.row(.confident).before,
          "endpoint policy: a confident end commits where it did (0.5 s) and starts the work at half of it")
    // The words clock, for a room that never goes quiet.
    check(decide(voice: 100, words: 2400, score: nil, complete: false) == .plausibleEnd && decide(voice: 100, words: 3000, score: nil, complete: false) == .firmEnd,
          "endpoint policy: no new words for 2.4 s is plausible, 3 s firm, even when the room is loud")
    check(decide(voice: 100, words: 1200, score: nil, complete: true) == .plausibleEnd, "endpoint policy: finished words, 1.2 s without a new one -> plausible")
    // No words yet, and the caps.
    check(decide(voice: 100, words: nil, score: nil, complete: false, start: 7000) == .keepListening
          && decide(voice: 100, words: nil, score: nil, complete: false, start: 8000) == .plausibleEnd
          && decide(voice: 600, words: nil, score: nil, complete: false, start: 8000) == .firmEnd,
          "endpoint policy: nothing said in 8 s -> plausible; 0.6 s quiet after -> over")
    check(decide(voice: 0, words: nil, score: nil, complete: false, start: 15_000) == .firmEnd, "endpoint policy: no word in 15 s -> over, whatever the room")
    check(decide(voice: 0, words: 0, score: 0.1, complete: false, start: 180_000) == .firmEnd, "endpoint policy: the 3-minute cap comes before everything (voice-4)")
    check(P.Caps.standard.waitForWords == ArisTalkKey.waitForWords && P.Caps.standard.longestTurn == ArisTalkKey.longestTurn
          && P.Caps.standard.longestWaitForWords == ArisTalkKey.longestWaitForWords && P.framesToResume == ArisTalkKey.framesToResume
          && P.window == ArisTalkKey.graceAfterUnsureEnd && P.finishedScore == ArisTalkKey.finishedScore && P.unsureScore == ArisTalkKey.unsureScore,
          "endpoint policy: its caps and scores are the talk key's")
    // The old table, as before: every new firm end is at or after the old end, so nobody is cut off sooner.
    for endCase in ArisEndpointCase.allCases where endCase != .noWords {
        let (score, complete, hanging): (Float?, Bool, Bool) = switch endCase {
        case .confident: (0.9, true, false)
        case .finishedVoice: (0.9, false, false)
        case .unsure: (0.5, false, false)
        case .midThought: (0.1, false, false)
        case .midThoughtWordsFinished: (0.1, true, false)
        case .hanging: (0.9, true, true)
        case .noScoreComplete: (nil, true, false)
        case .noScore, .noWords: (nil, false, false)
        }
        let old = (1...4000).first { ArisTalkKey.heardEnough(sinceStart: .seconds(4), sinceLastWords: ms(300), sinceLastVoice: ms($0), complete: complete,
                                                              turnScore: score, hanging: hanging) } ?? 0
        let grace = ArisTalkKey.isConfidentEnd(turnScore: score, complete: complete, hanging: hanging) ? 0 : 600
        check(old + grace == Int(P.row(endCase).before / ms(1)), "endpoint policy: \(endCase.rawValue)'s old end is \(old) + \(grace) ms, as recorded")
    }
    // The timer armed in a pause looks again exactly when the next threshold is due.
    let pause = ArisEndpointInput(sinceStart: ms(4000), sinceVoice: ms(100), sinceWords: ms(100), score: 0.9, complete: true)
    check(P.untilChange(pause) == ms(150), "endpoint policy: 100 ms into a confident pause, the next look is in 150 ms")
    check(P.untilChange(ArisEndpointInput(sinceStart: ms(4000), sinceVoice: ms(600), sinceWords: ms(1100), score: 0.9, complete: true)) == ms(176_000),
          "endpoint policy: past every threshold only the cap is left")
}

// MARK: - The driver, event by event

private func hearingDriverTests() {
    typealias S = ArisEndpointDriver.Snapshot
    func quiet(_ driver: inout ArisEndpointDriver, from: Int, to: Int, voice: Int, words: Int, score: Float?, complete: Bool) -> [ArisEndpointDriver.Effect] {
        var effects: [ArisEndpointDriver.Effect] = []
        for now in stride(from: from, through: to, by: 43) {
            effects += driver.observe(S(now: ms(now), voiceNow: false, lastVoice: ms(voice), lastWords: ms(words), score: score, complete: complete))
        }
        return effects
    }
    var driver = ArisEndpointDriver()
    var effects = quiet(&driver, from: 3000, to: 3600, voice: 3000, words: 2900, score: 0.9, complete: true)
    check(effects == [.speculate(id: 1), .commit(id: 1)], "driver: a confident pause speculates at 0.25 s and commits at 0.5 s")

    driver = ArisEndpointDriver()
    effects = quiet(&driver, from: 3000, to: 4500, voice: 3000, words: 2900, score: 0.5, complete: false)
    check(effects == [.speculate(id: 1)] && driver.pendingId == 1, "driver: an unsure pause is plausible at 1.4 s")
    // A click: one voice reading does not restart the pause.
    effects = driver.observe(S(now: ms(4550), voiceNow: true, lastVoice: ms(4550), lastWords: ms(2900), score: nil, complete: false))
    check(effects.isEmpty && driver.pendingId == 1, "driver: a click in the window is no resume")
    effects = quiet(&driver, from: 4600, to: 5050, voice: 4550, words: 2900, score: nil, complete: false)
    check(effects == [.commit(id: 1)], "driver: the window is measured from the plausible end, so the click doesn't hold the commit")

    driver = ArisEndpointDriver()
    _ = quiet(&driver, from: 3000, to: 4500, voice: 3000, words: 2900, score: 0.5, complete: false)
    var resumed: [ArisEndpointDriver.Effect] = []
    for now in [4520, 4563, 4606, 4649] {
        resumed += driver.observe(S(now: ms(now), voiceNow: true, lastVoice: ms(now), lastWords: ms(2900), score: nil, complete: false))
    }
    check(resumed == [.cancel(id: 1)] && driver.phase == .listening && driver.cancellations == 1, "driver: ~0.2 s of voice in the window cancels the speculation")
    effects = quiet(&driver, from: 6000, to: 7600, voice: 6000, words: 5800, score: 0.9, complete: true)
    check(effects == [.speculate(id: 2), .commit(id: 2)] && driver.speculations == 2, "driver: the same turn goes on and ends on its next pause")

    driver = ArisEndpointDriver()
    _ = quiet(&driver, from: 3000, to: 3260, voice: 3000, words: 2900, score: 0.9, complete: true)
    check(driver.reply(.output, id: 1).isEmpty && driver.pendingId == 1, "driver: an answer's first words are held, not a commit")
    check(driver.reply(.action, id: 1) == [.commit(id: 1)] && driver.locked, "driver: a step or a card commits at once (it can't be taken back)")
    check(driver.observe(S(now: ms(3300), voiceNow: true, lastVoice: ms(3300))).isEmpty, "driver: nothing happens after the commit")

    driver = ArisEndpointDriver()
    _ = quiet(&driver, from: 3000, to: 3260, voice: 3000, words: 2900, score: 0.9, complete: true)
    check(driver.reply(.action, id: 7).isEmpty, "driver: a stale speculation's reply changes nothing")
    effects = driver.observe(S(now: ms(3300), voiceNow: false, lastVoice: ms(3000), lastWords: ms(2900), score: 0.9, complete: false, hanging: true))
    check(effects == [.cancel(id: 1)], "driver: words that turn out to hang drop the speculation")
    var fresh = ArisEndpointDriver()
    check(fresh.finish() == [.commit(id: nil)], "driver: the key pressed again commits")
}

// MARK: - The speculative turn, with fake requests

@MainActor
private final class FakeHelper {
    var asked: [String] = []
    var terminated = 0
    var feeds: [AsyncStream<String>.Continuation] = []
    var commits: [Int?] = []
    var cancels: [Int] = []
    var words = "내일 날씨 알려줘"
    var mayAsk = true

    func turn() -> ArisSpeculativeTurn<String, String> {
        // Weak: a turn's work can outlive the test that made it.
        ArisSpeculativeTurn(hooks: .init(
            finalWords: { [weak self] _ in self?.words },
            requestKey: { [weak self] words in self?.mayAsk == true ? "brain:\(words)" : nil },
            ask: { [weak self] words, _ in
                let (stream, feed) = AsyncStream.makeStream(of: String.self)
                guard let self else { feed.finish(); return stream }
                self.asked.append(words)
                feed.onTermination = { [weak self] reason in if case .cancelled = reason { Task { @MainActor in self?.terminated += 1 } } }
                self.feeds.append(feed)
                return stream
            },
            kind: { $0.hasPrefix("status:") ? .action : $0.hasPrefix("delta:") ? .output : .inert },
            commit: { [weak self] in self?.commits.append($0) },
            cancelled: { [weak self] in self?.cancels.append($0) }))
    }
}

@MainActor private func hearingSpin(_ seconds: Double = 0.05) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

private func hearingSpeculativeTurnTests() {
    MainActor.assumeIsolated {
        typealias S = ArisEndpointDriver.Snapshot
        @MainActor func pause(_ turn: ArisSpeculativeTurn<String, String>, from: Int, to: Int, voice: Int, score: Float? = 0.9, complete: Bool = true) {
            for now in stride(from: from, through: to, by: 43) {
                turn.observe(S(now: ms(now), lastVoice: ms(voice), lastWords: ms(voice - 100), score: score, complete: complete))
            }
            hearingSpin()
        }
        @MainActor func talk(_ turn: ArisSpeculativeTurn<String, String>, at times: [Int]) {
            for now in times { turn.observe(S(now: ms(now), voiceNow: true, lastVoice: ms(now), lastWords: ms(now - 100))) }
            hearingSpin()
        }

        // Voice stops, plausible end, voice resumes before the first delta: one request cancelled, one utterance.
        let helper = FakeHelper()
        helper.words = "내일 날씨"
        let turn = helper.turn()
        pause(turn, from: 3000, to: 3260, voice: 3000)
        check(helper.asked == ["내일 날씨"] && turn.requestsSent == 1 && helper.commits.isEmpty,
              "speculative turn: at the plausible end the request goes out, the microphone still listening")
        talk(turn, at: [3280, 3323, 3366, 3409])
        hearingSpin(0.1)
        check(helper.cancels == [1] && turn.requestsCancelled == 1 && helper.terminated == 1,
              "speculative turn: the user talked again before any answer -> that request is cancelled (its connection dropped)")
        helper.words = "내일 날씨 알려주고 우산 필요한지도"
        pause(turn, from: 5000, to: 5600, voice: 5000)
        check(helper.asked == ["내일 날씨", "내일 날씨 알려주고 우산 필요한지도"] && helper.commits == [2],
              "speculative turn: the same utterance goes on, its words joined, and commits on its next end")
        var words: String?
        var replies: [String] = []
        Task { @MainActor in
            words = await turn.committedWords()
            helper.feeds[1].yield("delta:비가")
            helper.feeds[1].yield("answer:비가 와요")
            helper.feeds[1].finish()
            if let held = turn.takeRequest(for: "brain:\(words ?? "")") { for await reply in held { replies.append(reply) } }
        }
        hearingSpin(0.2)
        check(words == "내일 날씨 알려주고 우산 필요한지도" && replies == ["delta:비가", "answer:비가 와요"] && turn.requestsSent == 2 && turn.requestsCancelled == 1,
              "speculative turn: the committed turn takes the request already sent: one answer, no duplicate")

        // Firm end: the held replies come in order, none shown before.
        let firm = FakeHelper()
        let firmTurn = firm.turn()
        pause(firmTurn, from: 3000, to: 3260, voice: 3000)
        firm.feeds[0].yield("delta:맑")
        firm.feeds[0].yield("delta:아요")
        hearingSpin()
        check(firm.commits.isEmpty && !firmTurn.committed, "speculative turn: the brain's first words before the firm end are held")
        pause(firmTurn, from: 3300, to: 3520, voice: 3000)
        var held: [String] = []
        firm.feeds[0].finish()
        if let stream = firmTurn.takeRequest(for: "brain:\(firm.words)") { Task { @MainActor in for await reply in stream { held.append(reply) } } }
        hearingSpin()
        check(firm.commits == [1] && held == ["delta:맑", "delta:아요"], "speculative turn: firm end -> commit, and the held words come first, in order")

        // A step started before the firm end: committed at once, never cancelled by later voice.
        let acting = FakeHelper()
        let actingTurn = acting.turn()
        pause(actingTurn, from: 3000, to: 3260, voice: 3000)
        acting.feeds[0].yield("status:웹 검색 중")
        hearingSpin()
        talk(actingTurn, at: [3300, 3343, 3386, 3429])
        check(acting.commits == [1] && acting.cancels.isEmpty && actingTurn.locked && acting.terminated == 0,
              "speculative turn: a status line (a step) commits the turn; voice after it cancels nothing")

        // A request that may not go early (a local intent, memory words): the end still speculates the words only.
        let local = FakeHelper()
        local.mayAsk = false
        local.words = "타이머 5분"
        let localTurn = local.turn()
        pause(localTurn, from: 3000, to: 3600, voice: 3000)
        var localWords: String?
        Task { @MainActor in localWords = await localTurn.committedWords() }
        hearingSpin()
        check(local.asked.isEmpty && local.commits == [1] && localWords == "타이머 5분" && localTurn.takeRequest(for: "brain:타이머 5분") == nil,
              "speculative turn: a request that must wait is never sent early; its words are still ready at the commit")

        // A request sent for other words (the router made it critical, files were given) is dropped, not used.
        let other = FakeHelper()
        let otherTurn = other.turn()
        pause(otherTurn, from: 3000, to: 3600, voice: 3000)
        check(otherTurn.takeRequest(for: "brain:critical") == nil && otherTurn.requestsCancelled == 1, "speculative turn: a request for another key is cancelled, never used")
        hearingSpin(0.1)
        check(other.terminated == 1, "speculative turn: ... and its connection is dropped")
        let gone = FakeHelper()
        let goneTurn = gone.turn()
        pause(goneTurn, from: 3000, to: 3260, voice: 3000)
        goneTurn.drop()
        hearingSpin(0.1)
        check(gone.terminated == 1, "speculative turn: a turn that ended without taking its request drops it")
    }
}

// MARK: - The second listen's budget, and late words

private func hearingSecondPassTests() {
    MainActor.assumeIsolated {
        var fast: String??
        var slow: String??
        var late: [String] = []
        Task { @MainActor in
            fast = await ArisSecondPass.within(ms(300)) { "scribe" }
            slow = await ArisSecondPass.within(ms(50), {
                try? await Task.sleep(for: .milliseconds(200))
                return "whisper"
            }, late: { late.append($0) })
        }
        hearingSpin(0.5)
        check(fast == .some("scribe"), "second listen: a quick result is used")
        check(slow == .some(nil) && late == ["whisper"], "second listen: past its budget the turn goes on; the late result is handed over")
        check(ArisSecondPass.scribeBudget < .milliseconds(2500) && ArisSecondPass.whisperBudget < .seconds(3),
              "second listen: the budgets are well under the old waits (2.5 s, 3 s)")
    }
    var words = ArisLateWords()
    words.wentOn(with: "내일 날시")
    check(words.arrived("내일 날씨 알려줘"), "late words: before the request is sent, a better transcript is kept")
    check(words.send("내일 날시") == "내일 날씨 알려줘", "late words: ... and it is what the request says")
    var sent = ArisLateWords()
    sent.wentOn(with: "내일 날시")
    check(sent.send("내일 날시") == "내일 날시" && !sent.arrived("내일 날씨 알려줘") && sent.better == nil,
          "late words: a second-pass text after the request was sent is ignored")
    var other = ArisLateWords()
    other.wentOn(with: "a")
    other.arrived("b")
    check(other.send("a [img 1]") == "a [img 1]", "late words: only exactly the words that went on are replaced")
}

// MARK: - The stage clock

private func hearingStageClockTests() {
    var clock = ArisStageClock()
    let start = ContinuousClock.now
    clock.begin(at: start)
    clock.mark(.firstVoice, at: start.advanced(by: ms(300)))
    clock.mark(.voiceEnd, at: start.advanced(by: ms(2000)))
    clock.mark(.plausibleEnd, at: start.advanced(by: ms(2250)))
    clock.mark(.requestSent, at: start.advanced(by: ms(2400)))
    clock.mark(.firstVoice, at: start.advanced(by: ms(900)))
    clock.mark(.firmEnd, at: start.advanced(by: ms(2500)))
    clock.mark(.firstDelta, at: start.advanced(by: ms(3100)))
    clock.mark(.firstSentence, at: start.advanced(by: ms(3200)))
    clock.mark(.firstAudio, at: start.advanced(by: ms(3350)))
    let fields = clock.fields()
    check(fields["firstVoiceAtMs"] == 300 && fields["plausibleEndAtMs"] == 2250 && fields["firstAudioAtMs"] == 3350,
          "stage clock: each stage in ms since the key or the wake word, the first time only")
    check(fields["speechEndToRequestMs"] == 400 && fields["speechEndToAudioMs"] == 1350, "stage clock: the gaps the targets name are in the line")
    clock.forgetSpeculation()
    clock.mark(.voiceEnd, at: start.advanced(by: ms(4000)), again: true)
    check(clock.fields()["plausibleEndAtMs"] == nil && clock.fields()["voiceEndAtMs"] == 4000, "stage clock: a cancelled speculation's marks go; the real end replaces them")
    check(Set(fields.keys).isSubset(of: ArisStageClock.fieldNames) && ArisStageClock.fieldNames.isSubset(of: ArisTurnLog.stageFields),
          "stage clock: aris-agent keeps every stage field in turns.jsonl")
    let kept = ArisTurnLog.clean(["totalMs": 10, "speechEndToAudioMs": 1350, "firstDeltaAtMs": 3100, "endCase": "confident", "speculations": 2])
    check(kept?["speechEndToAudioMs"] as? Int == 1350 && kept?["endCase"] as? String == "confident" && kept?["speculations"] as? Int == 2,
          "stage clock: turns.jsonl keeps the stages, the end's case and the speculation counts")
    var stats = ArisTurnStats(startedAt: .now)
    stats.hearing(stages: fields, endCase: "confident", speculations: 2, cancelled: 1)
    let line = stats.line(outcome: "ok", at: .now)
    check(line["speechEndToAudioMs"] as? Int == 1350 && line["speculationsCancelled"] as? Int == 1 && line["endCase"] as? String == "confident",
          "stage clock: the turn's line carries them")
}

// MARK: - Which requests may go early

private func hearingGateTests() {
    typealias G = ArisSpeculationGate
    let plain = G.Turn(words: "내일 날씨 알려줘", plainBrainPath: true)
    check(G.block(plain) == nil, "gate: a plain question to the brain may go early")
    check(G.block(G.Turn(words: "타이머 5분", plainBrainPath: false)) == .notPlain, "gate: anything the Mac does itself waits (it acts at once)")
    for words in ["내 생일 기억해 줘", "그거 잊어 줘", "출근 루틴 해 줘", "remember my birthday", "forget that", "run my morning routine"] {
        check(G.block(G.Turn(words: words, plainBrainPath: true)) == .helperWords, "gate: \(words) may act in aris-agent before a step line -> waits")
    }
    check(G.block(G.Turn(words: "이거 뭐야", plainBrainPath: true, pointsAtScreen: true)) == .screen, "gate: the screen waits")
    check(G.block(G.Turn(words: "응", plainBrainPath: true, cardUp: true)) == .card, "gate: words while a card is up wait")
    check(G.block(G.Turn(words: "고마워", plainBrainPath: true, echoDoubt: true)) == .echo, "gate: words that may be Aris's own echo wait")
    check(G.block(G.Turn(words: "   ", plainBrainPath: true)) == .noWords, "gate: nothing to send")
    check(G.block(G.Turn(words: "이 파일 요약해", plainBrainPath: true, filesWaiting: true)) == .files
          && G.block(G.Turn(words: "a", plainBrainPath: true, gesture: true)) == .gesture
          && G.block(G.Turn(words: "a", plainBrainPath: true, wakeEvidence: true)) == .wakeEvidence,
          "gate: files, a drawing and a borderline wake wait")
    let kinds: [(ArisAgentReply, ArisReplyKind)] = [
        (.status(ArisThinking.lookingStatus), .output), (.status("웹 검색 중"), .action), (.delta("a"), .output), (.answer("a"), .output),
        (.failure("x"), .output), (.turn("1"), .inert), (.untrusted(screen: false), .inert), (.helperAnswers, .inert), (.savedSteps, .action),
        (.stepFailed(nil), .action), (.file("/tmp/x"), .action), (.skill("x"), .inert), (.refusedJobs, .inert), (.shownOnly, .inert),
    ]
    for (reply, kind) in kinds { check(reply.speculationKind == kind, "gate: \(reply) counts as \(kind)") }
}

// MARK: - The first word on the talk key

private func hearingFeedTests() {
    let mic = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    let recogniser = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    final class Got: @unchecked Sendable { var frames: [Int] = []; var firsts: [Float] = [] }
    let got = Got()
    let feed = ArisRecognizerFeed()
    func buffer(_ value: Float, format: AVAudioFormat = mic) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        buffer.frameLength = 4800
        for i in 0..<4800 { buffer.floatChannelData![0][i] = value }
        return buffer
    }
    feed.take(buffer(0.1))
    feed.take(buffer(0.2))
    check(feed.passed == 0, "first word: before the recogniser is ready the microphone's buffers are held")
    feed.attach(ArisRecognizerInput(format: recogniser, append: { converted in
        got.frames.append(Int(converted.frameLength))
        got.firsts.append(converted.floatChannelData![0][Int(converted.frameLength) - 200])
    }))
    feed.take(buffer(0.3))
    check(feed.passed == 3 && got.frames.count == 3 && got.frames.allSatisfy { $0 > 1000 && $0 <= 1601 },
          "first word: on attach the held buffers go first, converted to the recogniser's format, then the live ones")
    check(got.firsts.count == 3 && abs(got.firsts[0] - 0.1) < 0.02 && abs(got.firsts[1] - 0.2) < 0.02 && abs(got.firsts[2] - 0.3) < 0.02,
          "first word: in the order they were spoken")
    let same = ArisRecognizerFeed()
    final class Count: @unchecked Sendable { var value = 0 }
    let count = Count()
    same.take(buffer(0.5, format: recogniser))
    same.attach(ArisRecognizerInput(format: recogniser, append: { _ in count.value += 1 }))
    check(count.value == 1, "first word: a buffer already in the recogniser's format is passed as it is")
}

// MARK: - The wiring, in files the tests can't compile

private func hearingWiringTests() {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris").standardized
    func source(_ name: String) -> String { (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    let controller = source("ArisController.swift")
    let listener = source("ArisListener.swift")
    let start = listener.range(of: "func start(locale: Locale")
    let body = start.map { String(listener[$0.lowerBound...].prefix(4000)) } ?? ""
    let micAt = body.range(of: "try await startMicrophone(feed: micFeed)")?.lowerBound, recogniserAt = body.range(of: "try await recognizer.start(locale:")?.lowerBound
    check(micAt != nil && recogniserAt != nil && micAt! < recogniserAt!, "first word: on the talk key the microphone opens before the recogniser starts")
    check(body.contains("micFeed.attach(input)"), "first word: the recogniser gets what the microphone held once it is ready")
    let handsFree = controller.range(of: "func listenHandsFree()").map { String(controller[$0.lowerBound...].prefix(1500)) } ?? ""
    check(!handsFree.contains("Task.sleep(for: .milliseconds(200))") && handsFree.contains("beginEndpointing()"),
          "endpoint: no 200 ms poll; the turn's end is driven by its audio and words")
    let ask = controller.range(of: "func askAndSpeak(").map { String(controller[$0.lowerBound...].prefix(6000)) } ?? ""
    check(ask.contains("let early = await takeEarlyRequest(") && ask.contains("let asked = early?.replies ?? ArisAgentClient.ask(sendingWords(text)"),
          "speculative turn: the brain's turn takes the request already sent, or sends one")
    let runner = (try? String(contentsOf: folder.appendingPathComponent("../../../ArisAgent/ArisAgentRunner.swift").standardized, encoding: .utf8)) ?? ""
    let abandon = runner.range(of: "func abandon(owner: AnyObject) {\n        queue.async").map { String(runner[$0.lowerBound...].prefix(1_000)) } ?? ""
    check(abandon.contains("interruptOrStop(dropTurn: true)") && !abandon.contains("stopProcess()"),
          "speculative turn: a dropped /ask interrupts the brain's turn and keeps its process (the whole question finds it warm)")
    check(ask.contains("let context = withCutOffNote(gathered)") && source("ArisController+Endpoint.swift").contains("turnHearing.earlyContext = withCutOffNote("),
          "speculative turn: after a cancelled request, the next one tells the brain the cut-off question is not to be answered")
    let endpoint = source("ArisController+Endpoint.swift")
    check(endpoint.contains("ArisSpeculationGate.block(") && endpoint.contains("ArisIntent.parse(") && endpoint.contains("ArisEchoGuard.verdict("),
          "speculative turn: what may go early is decided by the gate, the local parse and the echo guard")
}
