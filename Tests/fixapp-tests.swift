// Tests for the app-side review fixes on the Jarvis branch (jv-fixapp): the countdown's one decision (a ring that ran
// out in silence sends; nothing else is left as a dead card), the endpoint's look armed on every reading (a stalled
// audio feed still ends the turn), the cut-off note kept to its own turn, and which status lines lock a speculative
// request. Called from main.swift; uses its check().
import Foundation

func runFixappTests() {
    fixappCountdownTests()
    fixappStallTests()
    fixappCutOffTests()
    fixappStatusTests()
    fixappWiringTests()
}

private func fxMs(_ value: Int) -> Duration { .milliseconds(value) }

// MARK: - The countdown's decision

private func fixappCountdownTests() {
    typealias C = ArisCountdownStep
    let silence = C.Words.silence, yes = ArisConfirmReply.countdownWords("응"), no = ArisConfirmReply.countdownWords("취소")
    let wait = ArisConfirmReply.countdownWords("잠깐만")
    /// As the controller asks it: before the microphone closes, then with the final words.
    func ends(outcome: ArisCardOutcome? = nil, said: Bool? = nil, paused: Bool = false, final: C.Words, current: Bool = true,
              currentAfter: Bool? = nil) -> C? {
        let soon = C.decide(outcome: outcome, said: said, paused: paused, final: nil, current: current)
        return soon ?? C.decide(outcome: outcome, said: said, paused: paused, final: final, current: currentAfter ?? current)
    }
    check(ends(final: silence) == .send, "countdown: silence until the ring ran out sends (it was a dead card)")
    check(C.decide(outcome: nil, said: nil, paused: false, final: nil, current: true) == nil,
          "countdown: with nothing settled, it waits for the final words instead of returning early")
    check(ends(final: yes) == .send && ends(final: no) == .stop && ends(final: wait) == .pause,
          "countdown: the final words: a clear yes sends, a clear no stops, other words pause")
    check(ends(said: true, final: silence) == .send && ends(said: false, final: silence) == .stop,
          "countdown: a spoken yes or no mid-ring settles it before the microphone closes")
    check(C.decide(outcome: nil, said: true, paused: false, final: nil, current: true) == .send
          && C.decide(outcome: nil, said: false, paused: false, final: nil, current: true) == .stop,
          "countdown: the card says sent or stopped at once, not once the microphone has closed")
    check(ends(paused: true, final: silence) == .pause && C.decide(outcome: nil, said: nil, paused: true, final: nil, current: true) == .pause,
          "countdown: “잠깐만” held still pauses it, whatever came after")
    check(ends(outcome: .answered(true), final: silence) == .send && ends(outcome: .answered(false), final: yes) == .stop,
          "countdown: 보내기 or ↩ sends, esc or 취소 stops, whatever was said")
    check(ends(outcome: .covered, final: silence) == .covered && ends(outcome: .cancelled, final: silence) == .turnEnded,
          "countdown: a covered card is nobody's answer; a card whose turn ended follows with nothing")
    check(ends(outcome: .answered(true), final: silence, current: false) == .send,
          "countdown: a click the kernel took for the card counts (it already knows a turn that ended)")
    check(ends(said: true, final: yes, current: false) == .turnEnded && ends(final: silence, current: false) == .turnEnded,
          "countdown: a turn that is over sends nothing, not even on a spoken yes or silence")
    check(ends(final: silence, currentAfter: false) == .turnEnded,
          "countdown: a turn that ended while the microphone closed sends nothing")
    check(C.send.sent == true && C.stop.sent == false && C.pause.sent == nil && C.covered.sent == nil && C.turnEnded.sent == nil,
          "countdown: only a send or a stop settles the card into its one line")
    check(C(.answered(true)) == .send && C(.answered(false)) == .stop && C(.covered) == .covered && C(.cancelled) == .turnEnded,
          "countdown: the kernel's outcomes map one to one")
    check(ArisConfirmReply.countdownEnd(final: "") == .send && ArisConfirmReply.countdownEnd(final: "아니") == .stop
          && ArisConfirmReply.countdownEnd(final: "음") == .pause,
          "countdown: the ring's end from the final words, through the one decision")
}

// MARK: - A stalled audio feed

/// A hands-free turn whose readings are voice every 43 ms up to `stallAt` (words changing all along when `words`), then
/// stop: from there only the looks the driver arms come. When it committed (ms), nil if it never did.
private func fixappStalled(stallAt: Int, words: Bool, score: Float?, complete: Bool) -> Int? {
    typealias S = ArisEndpointDriver.Snapshot
    func committed(_ effects: [ArisEndpointDriver.Effect]) -> Bool {
        effects.contains { if case .commit = $0 { return true } else { return false } }
    }
    var driver = ArisEndpointDriver()
    var last = S(now: .zero)
    for now in stride(from: 0, through: stallAt, by: 43) {
        last = S(now: fxMs(now), voiceNow: true, lastVoice: fxMs(now), lastWords: words ? fxMs(now) : nil, score: score, complete: complete)
        if committed(driver.observe(last)) { return now }
    }
    var at = last.now
    // As the controller arms it: 5 ms after it is due.
    while let wait = driver.nextLook(last), at < .seconds(200) {
        at += wait + fxMs(5)
        last = S(now: at, voiceNow: false, lastVoice: last.lastVoice, lastWords: last.lastWords, score: score, complete: complete)
        if committed(driver.observe(last)) { return Int(at / fxMs(1)) }
    }
    return nil
}

private func fixappStallTests() {
    typealias S = ArisEndpointDriver.Snapshot
    let driver = ArisEndpointDriver()
    check(driver.nextLook(S(now: fxMs(2000), voiceNow: true, lastVoice: fxMs(2000), lastWords: fxMs(1900), score: 0.9, complete: true)) != nil,
          "endpoint stall: a voice reading arms a look too (it armed none, so a feed that stopped there never ended)")
    var over = ArisEndpointDriver()
    _ = over.finish()
    check(over.nextLook(S(now: fxMs(2000))) == nil, "endpoint stall: nothing is armed once the turn is over")
    func near(_ value: Int?, _ expected: Int) -> Bool { value.map { $0 >= expected && $0 <= expected + 120 } ?? false }
    let confident = fixappStalled(stallAt: 2021, words: true, score: 0.9, complete: true)
    check(near(confident, 2021 + 500), "endpoint stall: a confident end commits at its firm end after the feed stopped (\(confident ?? -1) ms)")
    let unsure = fixappStalled(stallAt: 2021, words: true, score: 0.5, complete: true)
    check(near(unsure, 2021 + 2000), "endpoint stall: an unsure end commits at its firm end after the feed stopped (\(unsure ?? -1) ms)")
    let noWords = fixappStalled(stallAt: 2021, words: false, score: nil, complete: false)
    check(near(noWords, 8000), "endpoint stall: with no word heard the first-words wait still ends the turn (\(noWords ?? -1) ms)")
    let lateNoise = fixappStalled(stallAt: 14_964, words: false, score: nil, complete: false)
    check(near(lateNoise, 15_000), "endpoint stall: the longest wait for words still fires (\(lateNoise ?? -1) ms)")
}

// MARK: - The cut-off note

private func fixappCutOffTests() {
    let spoken = ArisTurnID(4), typed = ArisTurnID(5)
    check(ArisCutOffNote.applies(cancelled: 1, hearingTurn: spoken, turn: spoken),
          "cut-off note: the turn whose early request was cancelled says so")
    check(!ArisCutOffNote.applies(cancelled: 1, hearingTurn: spoken, turn: typed),
          "cut-off note: a later turn (typed: it never listens, so the old hearing stays) has none")
    check(!ArisCutOffNote.applies(cancelled: 0, hearingTurn: spoken, turn: spoken) && !ArisCutOffNote.applies(cancelled: 2, hearingTurn: nil, turn: nil),
          "cut-off note: none without a cancelled request, or without the turn the hearing was for")
}

// MARK: - Which status lines lock a speculative request

private func fixappStatusTests() {
    func kind(_ status: String) -> ArisReplyKind { ArisAgentReply.status(status).speculationKind }
    check(kind(ArisThinking.lookingStatus) == .output, "speculation status: “알아보는 중” is output (said at once), no step")
    var fallbacks: [String] = []
    for from in ArisBrain.allCases { for to in ArisBrain.allCases { for missing in [true, false] {
        fallbacks.append(ArisTurnFallback.status(from: from, to: to, missing: missing))
    } } }
    check(fallbacks.allSatisfy { kind($0) == .output }, "speculation status: another brain taking the turn is a note, not an act")
    let shot = ArisTurnImage(kind: .gesture, name: "gesture-screenshot-1.jpg", format: .jpeg, data: Data([0xFF]), badge: 1, app: nil, title: nil)
    let cursor = ArisTurnImage(kind: .cursor, name: "cursor-screen.png", format: .png, data: Data([1]), badge: nil, app: nil, title: nil)
    typealias R = ArisImageRouting
    let routes = [
        R.route(requested: .antigravity, images: [], screenText: false, claudeInstalled: true, screenConversation: true),
        R.route(requested: .antigravity, images: [], screenText: false, claudeInstalled: false, screenConversation: true),
        R.route(requested: .antigravity, images: [shot], screenText: false, claudeInstalled: false),
        R.route(requested: .api, images: [cursor], screenText: false, claudeInstalled: true, api: .init(vision: false, claude: true)),
        R.route(requested: .api, images: [cursor], screenText: false, claudeInstalled: false, api: .init(vision: false, codex: true)),
    ]
    let notes = Set(routes.compactMap(\.status))
    check(notes.count == 4 && notes.allSatisfy { kind($0) == .output },
          "speculation status: every hand-over note of the image routing is a note, not an act (\(notes.sorted()))")
    let tools = "/Users/me/.config/aris/aris-tools"
    let acts = [ArisAgentStatus.forCommand("\(tools) todo add 우유", tools: tools), ArisAgentStatus.forCommand("\(tools) weather", tools: tools),
                ArisAgentStatus.forCommand("ls ~", tools: tools), ArisAgentStatus.anyTool, ArisAgentStatus.longJob(minutes: 0),
                "웹 검색 중", ArisEscalation.judgedNote, "Claude Code 여는 중", "작업 중"]
    check(acts.allSatisfy { kind($0) == .action },
          "speculation status: a tool starting, an auto-approval, a teammate or any line the helper can't vouch for still locks it")
}

// MARK: - The wiring, in files the tests can't compile

private func fixappWiringTests() {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris").standardized
    func source(_ name: String) -> String { (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    let countdown = source("ArisController+Countdown.swift")
    check(!countdown.contains("Bool??") && countdown.components(separatedBy: "ArisCountdownStep.decide(").count == 3
          && countdown.contains("final: nil, current: !Task.isCancelled && turnIsCurrent")
          && countdown.contains("final: ArisConfirmReply.countdownWords(final)"),
          "countdown wiring: the controller asks the one decision before the microphone closes and after, with no double optional")
    let endpoint = source("ArisController+Endpoint.swift")
    check(endpoint.contains("let wait = turn.driver.nextLook(snapshot)") && !endpoint.contains("guard !snapshot.voiceNow"),
          "endpoint wiring: a look is armed on every reading, a voice one too")
    check(endpoint.contains("ArisCutOffNote.applies(cancelled: turnHearing.turn?.requestsCancelled ?? 0, hearingTurn: turnHearing.turnId,"),
          "cut-off wiring: the note is the turn's own")
    let controller = source("ArisController.swift")
    let take = controller.range(of: "let early = await takeEarlyRequest("), note = controller.range(of: "let context = withCutOffNote(gathered)")
    check(take != nil && note != nil && take!.upperBound <= note!.lowerBound,
          "cut-off wiring: the note is made after the turn took (or cancelled) the early request")
}
