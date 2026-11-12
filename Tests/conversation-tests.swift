// Tests for the always-on conversation (2026-11-05): the session's lifecycle, end phrases, the barge-in decision, the
// announcement queue, the pause rule and the hand-off line. Called from main.swift; uses its check().
import Foundation

func runConversationTests() {
    conversationLifecycleTests()
    endPhraseTests()
    bargeInTests()
    bargeInFileTests()
    announcementTests()
    pauseTests()
    handoffLineTests()
    handOutPlanTests()
    emptyAnswerTests()
    teammateWindowTests()
    handsFreeGateTests()
    spokenAnswerTests()
    echoTrimTests()
    otherAudioTests()
    handsFreeRoutingTests()
    cardKeyTests()
    conversationPromptTests()
}

private func conversationLifecycleTests() {
    typealias C = ArisConversation
    let closed = C()
    check(!closed.isOpen && !closed.isBetweenTurns && closed.stage == .closed, "conversation: starts closed")
    check(!closed.timedOut(at: 1_000, silenceSeconds: 30), "conversation: a closed one never times out")

    let open = closed.opened(at: 100)
    check(open.isOpen && open.stage == .turn && !open.isBetweenTurns, "conversation: a turn opens it")
    check(!open.timedOut(at: 1_000, silenceSeconds: 30), "conversation: never times out mid-turn")

    let between = open.settled(at: 110, reachedAI: true)
    check(between.isBetweenTurns && between.quietSince == 110, "conversation: an answer leaves it between turns, quiet from then")
    check(!between.timedOut(at: 139.9, silenceSeconds: 30) && between.timedOut(at: 140, silenceSeconds: 30),
          "conversation: 30 s with no speech between turns ends it")
    check(!between.timedOut(at: 500, silenceSeconds: 0), "conversation: silence 0 (off) never ends it by silence (only the cap does)")

    let again = between.turnStarted()
    check(again.stage == .turn && again.quietSince == 110, "conversation: a new turn doesn't move the quiet clock by itself")
    let noise = again.settled(at: 138, reachedAI: false)
    check(noise.isBetweenTurns && noise.quietSince == 110 && noise.timedOut(at: 140, silenceSeconds: 30),
          "conversation: a turn that never reached the AI (noise, a local command, Aris's news) never extends the session")
    check(again.settled(at: 135, reachedAI: true).quietSince == 135, "conversation: a turn to the AI restarts the quiet clock")
    // The 10-minute cap (security review C1), counted from the opening whatever the turns did.
    var busy = open
    for minute in 1...9 { busy = busy.turnStarted().settled(at: 100 + Double(minute) * 60, reachedAI: true) }
    check(!busy.timedOut(at: 100 + 599, silenceSeconds: 0) && busy.timedOut(at: 100 + 600, silenceSeconds: 0)
          && busy.timedOut(at: 100 + 600, silenceSeconds: 3600), "conversation: it ends 10 minutes after it opened, however busy, whatever the silence setting")
    check(!busy.turnStarted().timedOut(at: 100 + 700, silenceSeconds: 30), "conversation: the cap never cuts a turn under way")

    let reopened = between.opened(at: 200)
    check(reopened.stage == .turn && reopened.quietSince == 110, "conversation: opening an open one just starts a turn")
    let fresh = between.closed().opened(at: 300)
    check(fresh.quietSince == 300 && fresh.openedAt == 300, "conversation: closed then opened starts over")
    check(between.closed() == C(), "conversation: closing forgets everything")

    check(C.keyPress(betweenTurns: true, fromGesture: false) == .endConversation, "conversation: ⌥Space while idle-listening ends it")
    check(C.keyPress(betweenTurns: true, fromGesture: true) == .asUsual, "conversation: the circle gesture starts a turn instead")
    check(C.keyPress(betweenTurns: false, fromGesture: false) == .asUsual, "conversation: ⌥Space mid-turn works as before (finish, interrupt)")

    check(C.enabled(silenceSeconds: 30) && !C.enabled(silenceSeconds: 0), "conversation: 0 seconds turns the mode off")
    check(C.defaultSilenceSeconds == 30 && C.longestSeconds == 600, "conversation: 30 s of silence by default, 10 minutes at most")
}

private func endPhraseTests() {
    for done in ["됐어", "그만", "고마워", "끝", "ok that's all", "OK, that's all", "okay that's all", "끝내자", "이제 그만", "이제 됐어",
                 "그만할게", "끝났어", "됐어 고마워", "됐어, 고마워요.", "고마워 됐어", "감사해요", "that's it", "bye", "stop", "i'm done",
                 "오케이 됐어", "응 됐어", "그만해", "끝이야", "됐습니다", "괜찮아", "없어", "아니야"] {
        check(ArisFollowUp.isDone(done), "end phrase: \(done)")
    }
    // Right after Aris asked something, "괜찮아", "아니야" and "없어" answer it; the strong ones still end it (M7).
    for answer in ["괜찮아", "괜찮아요", "아니야", "없어", "없어요", "nope", "nothing"] {
        check(!ArisFollowUp.isDone(answer, afterQuestion: true), "end phrase: after a question \(answer) is an answer")
    }
    for done in ["됐어", "그만", "고마워", "끝", "ok that's all"] {
        check(ArisFollowUp.isDone(done, afterQuestion: true), "end phrase: after a question \(done) still ends it")
    }
    check(ArisFollowUp.asksSomething("다른 파일도 열까요?") && !ArisFollowUp.asksSomething("열었어요.") && !ArisFollowUp.asksSomething(""),
          "end phrase: an answer ending on ? asks something")
    for more in ["그만 틀고 다른 노래", "끝까지 읽어줘", "끝난 거 알려줘", "stop the music", "끝말잇기 하자", "그만두는 법 알려줘",
                 "고마워 근데 내일은?", "ok play some music", "bye bye song 틀어줘", "됐어 그럼 내일 일정은?", "네"] {
        check(!ArisFollowUp.isDone(more), "end phrase: not -> \(more)")
    }
}

/// Feeds `frames` of mic and playback RMS; the frame it fired at, or nil.
private func firstFire(_ watch: inout ArisBargeIn, mic: [Float], playback: [Float]) -> Int? {
    for i in mic.indices where watch.feed(mic: mic[i], playback: i < playback.count ? playback[i] : 0) { return i }
    return nil
}

private func bargeInTests() {
    typealias B = ArisBargeIn
    check(B.mode(headphones: true, speakersAllowed: false) == .headphones && B.mode(headphones: false, speakersAllowed: true) == .speakers
          && B.mode(headphones: false, speakersAllowed: false) == nil, "barge-in: headphones always; speakers unless turned off")

    // Headphones: ~150 ms of voice stops Aris (well inside 200 ms), a click or a cough doesn't.
    var phones = B(mode: .headphones)
    let quiet = [Float](repeating: 0.002, count: 50)
    let voice = [Float](repeating: 0.08, count: 40)
    let fired = firstFire(&phones, mic: quiet + voice, playback: [Float](repeating: 0.1, count: 90))
    check(fired.map { $0 - 50 + 1 } == B.framesHeadphones && B.framesHeadphones * 10 <= 200, "barge-in: headphones stop within ~150 ms of voice")
    var clicks = B(mode: .headphones)
    let typing = (0..<400).map { $0 % 12 < 2 ? Float(0.2) : 0.002 }
    check(firstFire(&clicks, mic: quiet + typing, playback: []) == nil, "barge-in: typing (short clicks) never interrupts")
    var cough = B(mode: .headphones)
    check(firstFire(&cough, mic: quiet + [Float](repeating: 0.3, count: 8) + quiet, playback: []) == nil, "barge-in: an 80 ms cough doesn't interrupt")
    var breathy = B(mode: .headphones)
    let gappy = (0..<30).map { $0 % 6 == 5 ? Float(0.002) : 0.08 }
    check(firstFire(&breathy, mic: quiet + gappy, playback: []) != nil, "barge-in: speech with tiny dips still counts as one run")
    var once = B(mode: .headphones)
    _ = firstFire(&once, mic: quiet + voice, playback: [])
    check(firstFire(&once, mic: voice, playback: []) == nil, "barge-in: fires once")

    // Speakers: Aris's own echo, however loud, never interrupts; a voice well above it for 300 ms does.
    var echoOnly = B(mode: .speakers)
    let aris = (0..<600).map { i -> Float in i % 40 < 30 ? 0.12 : 0.01 }
    let echo = aris.enumerated().map { i, _ in i >= 4 ? aris[i - 4] * 0.5 : 0 }
    check(firstFire(&echoOnly, mic: echo, playback: aris) == nil, "barge-in: speakers: Aris's echo alone never interrupts")
    var loudEcho = B(mode: .speakers)
    let hotEcho = aris.enumerated().map { i, _ in i >= 3 ? aris[i - 3] * 1.3 : 0 }
    check(firstFire(&loudEcho, mic: hotEcho, playback: aris) == nil, "barge-in: speakers: even an echo louder than the voice itself doesn't")
    var talker = B(mode: .speakers)
    let talking = echo.enumerated().map { i, e in i >= 300 ? e + 0.5 : e }
    let at = firstFire(&talker, mic: talking, playback: aris)
    check(at.map { $0 >= 300 + B.framesSpeakers - 1 && $0 <= 300 + B.framesSpeakers + 20 } == true,
          "barge-in: speakers: a voice clearly over the echo interrupts after ~300 ms (frame \(at.map(String.init) ?? "-"))")
    var soft = B(mode: .speakers)
    let mumbling = echo.enumerated().map { i, e in i >= 300 ? e + 0.06 : e }
    check(firstFire(&soft, mic: mumbling, playback: aris) == nil, "barge-in: speakers: a voice not clearly over the echo doesn't")
    var short = B(mode: .speakers)
    let burst = echo.enumerated().map { i, e in (300..<320).contains(i) ? e + 0.5 : e }
    check(firstFire(&short, mic: burst, playback: aris) == nil, "barge-in: speakers: 200 ms isn't enough (300 ms needed)")
    var afterAris = B(mode: .speakers)
    let silentPlayback = [Float](repeating: 0, count: 100)
    let reply = quiet + [Float](repeating: 0.05, count: 60)
    check(firstFire(&afterAris, mic: reply, playback: silentPlayback) != nil, "barge-in: speakers: talking once Aris is quiet works at a normal voice")

    var between = B(mode: .between)
    check(firstFire(&between, mic: quiet + voice, playback: []).map { $0 - 50 + 1 } == B.framesBetween, "voice start: between turns 100 ms of voice starts a turn")
    var noisy = B(mode: .between)
    check(firstFire(&noisy, mic: quiet + typing, playback: []) == nil, "voice start: typing between turns starts nothing")
    var fan = B(mode: .between)
    let hum = [Float](repeating: 0.03, count: 3000)
    for level in quiet + hum { _ = fan.feed(mic: level, playback: 0) }
    var learned = B(mode: .between, floor: fan.floor)
    check(fan.floor > 0.0075 && firstFire(&learned, mic: hum, playback: []) == nil,
          "voice start: a steady fan is learned as the room (floor \(fan.floor)), and the next watch starts nothing on it")
    var room = B(mode: .between, floor: fan.floor)
    check(firstFire(&room, mic: hum + [Float](repeating: 0.002, count: 80) + voice, playback: []) != nil,
          "voice start: after the fan stops, a voice starts a turn again")
    // The turn starts where the voice did: over Aris exactly there (less of its echo), between turns a little before.
    var overAris = B(mode: .speakers)
    _ = firstFire(&overAris, mic: quiet + [Float](repeating: 0.5, count: 40), playback: [Float](repeating: 0.01, count: 90))
    check(abs(overAris.lookback - Double(B.framesSpeakers) * 0.01) < 0.001, "barge-in: over Aris the turn's audio starts at the voice (\(overAris.lookback) s)")
    var calm = B(mode: .between)
    _ = firstFire(&calm, mic: quiet + voice, playback: [])
    check(abs(calm.lookback - (Double(B.framesBetween) * 0.01 + B.leadBetween)) < 0.001, "voice start: between turns a quarter second before the voice")
    var dips = B(mode: .headphones)
    _ = firstFire(&dips, mic: quiet + gappy + gappy, playback: [])
    check(dips.lookback > Double(B.framesHeadphones) * 0.01, "barge-in: the voice's dips are part of its run (\(dips.lookback) s)")
    // The echo is learned up fast and down slowly, never from a hop well over it.
    var learner = B(mode: .speakers)
    for _ in 0..<400 { _ = learner.feed(mic: 0.02, playback: 0.1) }
    let settled = learner.echoGain
    for _ in 0..<5 { _ = learner.feed(mic: 0.03, playback: 0.1) }
    let rose = learner.echoGain - settled
    var falling = learner
    for _ in 0..<5 { _ = falling.feed(mic: 0.01, playback: 0.1) }
    check(settled < 0.3 && rose > 0.015 && learner.echoGain - falling.echoGain < rose / 3,
          "barge-in: the echo rises fast (+\(rose)) and falls slowly (-\(learner.echoGain - falling.echoGain))")
    var unlearned = learner
    for _ in 0..<5 { _ = unlearned.feed(mic: 0.06, playback: 0.1) }
    check(unlearned.echoGain - learner.echoGain < rose / 2, "barge-in: a hop 1.5× over the echo (maybe the user) raises it only slowly")
    // M3: the volume turned up mid-answer (echo 3.5× what was learned): followed within seconds, and never taken for the user.
    var louder = learner
    var louderFired = false
    for _ in 0..<400 where louder.feed(mic: settled * 3.5 * 0.1, playback: 0.1) { louderFired = true }
    check(!louderFired && louder.echoGain > settled * 2.5, "barge-in: a real jump in the echo is learned (\(settled) → \(louder.echoGain)) with no false stop")
}

/// A 16 kHz mono float WAV from the fixtures (afconvert LEF32), as samples.
private func wavSamples(_ name: String) -> [Float] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/conversation/\(name).wav")
    guard let data = try? Data(contentsOf: url), data.count > 12 else { return [] }
    var offset = 12
    while offset + 8 <= data.count {
        let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
        let size = Int(data[offset + 4..<offset + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        if id == "data" {
            let body = data[(offset + 8)..<min(data.count, offset + 8 + size)]
            return body.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        offset += 8 + size + (size % 2)
    }
    return []
}

/// RMS per 10 ms hop (160 samples), as the detector measures.
private func hops(_ samples: [Float]) -> [Float] {
    stride(from: 0, to: samples.count - 160, by: 160).map { start in
        let slice = samples[start..<start + 160]
        return (slice.reduce(0) { $0 + $1 * $1 } / 160).squareRoot()
    }
}

private func bargeInFileTests() {
    let aris = wavSamples("aris"), user = wavSamples("user")
    check(aris.count > 16_000 * 5 && user.count > 16_000, "barge-in files: fixtures read (\(aris.count), \(user.count) samples)")
    guard !aris.isEmpty, !user.isEmpty else { return }
    // The speaker's voice reaches the Mac's mic 30 ms later, quieter, with a room tail; plus a little noise.
    func room(_ voice: [Float], gain: Float) -> [Float] {
        var out = [Float](repeating: 0, count: voice.count)
        for i in voice.indices {
            let direct = i >= 480 ? voice[i - 480] : 0
            let tail = i >= 2400 ? voice[i - 2400] * 0.35 : 0
            out[i] = (direct + tail) * gain + Float((i * 7919) % 101 - 50) * 0.00002
        }
        return out
    }
    let playback = hops(aris)
    let echoed = hops(room(aris, gain: 0.45))
    for mode in [ArisBargeIn.Mode.speakers] {
        var watch = ArisBargeIn(mode: mode)
        check(firstFire(&watch, mic: echoed, playback: playback) == nil, "barge-in files: Aris's recorded line through the room never interrupts itself")
    }
    // The user starts 2 s in, at a normal voice near the Mac.
    let start = 16_000 * 2
    var mixed = room(aris, gain: 0.45)
    for i in user.indices where start + i < mixed.count { mixed[start + i] += user[i] * 3 }
    var watch = ArisBargeIn(mode: .speakers)
    let fired = firstFire(&watch, mic: hops(mixed), playback: playback)
    check(fired.map { $0 >= 200 && $0 <= 200 + 120 } == true,
          "barge-in files: the user talking over Aris on speakers stops it within ~1.2 s (fired at hop \(fired.map(String.init) ?? "never"))")
    var phones = ArisBargeIn(mode: .headphones)
    var leak = room(aris, gain: 0.01)
    for i in user.indices where start + i < leak.count { leak[start + i] += user[i] }
    let heard = firstFire(&phones, mic: hops(leak), playback: playback)
    check(heard.map { $0 >= 200 && $0 <= 200 + 40 } == true,
          "barge-in files: on headphones the user's voice stops Aris within ~0.4 s of his first sound (hop \(heard.map(String.init) ?? "never"))")
}

private func announcementTests() {
    let empty = ArisAnnouncements()
    let (one, first) = empty.adding()
    let (two, second) = one.adding()
    check(two.count == 2 && two.isFirst(first) && !two.isFirst(second), "announcements: first come, first said")
    check(empty.count == 0 && one.count == 1, "announcements: adding returns a new queue")
    let afterFirst = two.removing(first)
    check(afterFirst.isFirst(second) && afterFirst.count == 1, "announcements: the next one goes once the first is done")
    let cancelled = two.removing(second)
    check(cancelled.isFirst(first) && cancelled.count == 1, "announcements: one that gave up leaves the others in order")
    check(first != second && !empty.isFirst(first), "announcements: tickets are distinct; none is first in an empty queue")
}

private func pauseTests() {
    typealias P = ArisPause
    check(P.isPause(idle: true, training: false, conversationOpen: false, userTalking: false, sinceVoice: nil, sinceAris: nil),
          "pause: no session, idle is free (as before)")
    check(!P.isPause(idle: false, training: false, conversationOpen: false, userTalking: false, sinceVoice: nil, sinceAris: nil)
          && !P.isPause(idle: true, training: true, conversationOpen: false, userTalking: false, sinceVoice: nil, sinceAris: nil),
          "pause: never mid-turn or while training")
    check(P.isPause(idle: true, training: false, conversationOpen: true, userTalking: false, sinceVoice: 3, sinceAris: 3),
          "pause: in a session, quiet between turns is a pause")
    check(!P.isPause(idle: true, training: false, conversationOpen: true, userTalking: true, sinceVoice: 0, sinceAris: 3),
          "pause: never while the user is talking")
    check(!P.isPause(idle: true, training: false, conversationOpen: true, userTalking: false, sinceVoice: 0.4, sinceAris: 3),
          "pause: not right after the user's voice")
    check(!P.isPause(idle: true, training: false, conversationOpen: true, userTalking: false, sinceVoice: 5, sinceAris: 0.5),
          "pause: not right after Aris finished (the user gets the first word)")
    check(P.isPause(idle: true, training: false, conversationOpen: true, userTalking: false, sinceVoice: nil, sinceAris: nil),
          "pause: nothing heard or said yet is quiet")
}

private func handoffLineTests() {
    typealias H = ArisHandoffLine
    check(H.line([nil], korean: true) == "제가 맡았어요, 끝나면 알려줄게요.", "handoff: a clone job")
    check(H.line(["Claude Code"], korean: true) == "Claude Code가 맡았어요, 끝나면 알려줄게요.", "handoff: a teammate by name")
    check(H.line(["민준"], korean: true) == "민준이 맡았어요, 끝나면 알려줄게요." && H.line(["코디"], korean: true) == "코디가 맡았어요, 끝나면 알려줄게요.",
          "handoff: 이/가 follows the name's last sound")
    check(H.line(["Aside"], korean: true) == "Aside가 맡았어요, 끝나면 알려줄게요.", "handoff: Aside")
    check(H.line([nil, nil], korean: true) == "제가 2개 맡았어요, 끝나면 알려줄게요.", "handoff: several clone jobs")
    check(H.line(["코디", "코디", "코디"], korean: true) == "코디가 3개 맡았어요, 끝나면 알려줄게요.", "handoff: several jobs for one teammate")
    check(H.line(["Claude Code", nil], korean: true) == "Claude Code하고 제가 맡았어요, 끝나면 알려줄게요.", "handoff: a teammate and a clone")
    check(H.line([nil], korean: false) == "I'm on it in the background. I'll let you know when it's done.", "handoff: English clone")
    check(H.line(["Claude Code"], korean: false) == "Claude Code took it. I'll let you know when it's done.", "handoff: English teammate")
    check(H.line(["Claude Code", nil, nil], korean: false) == "Claude Code and I took 3 jobs. I'll let you know when they're done.", "handoff: English several")
    check(H.line([], korean: true) == "제가 맡았어요, 끝나면 알려줄게요.", "handoff: no names still says who")
    // The agent's refusal is its own line, never the notice's words (security review I1).
    check(ArisAgentReply.parse(String(decoding: ArisAgentReply.refusedJobs.line, as: UTF8.self)) == .refusedJobs && !ArisAgentReply.refusedJobs.isLast,
          "handoff: refusedJobs is a line of its own that round-trips")
    check(ArisAgentReply.parse(#"{"answer":"이 일은 지금 팀원한테 못 넘겨요."}"#) == .answer("이 일은 지금 팀원한테 못 넘겨요."),
          "handoff: the notice's words are only an answer")
    let block = "```json\n{\"jobs\":[{\"title\":\"t\",\"prompt\":\"p\"}]}\n```"
    check(ArisImageRouting.refusesJobs(answer: block, untrusted: true, taint: .none) && ArisImageRouting.refusesJobs(answer: block, untrusted: false, taint: .outsideText)
          && !ArisImageRouting.refusesJobs(answer: block, untrusted: false, taint: .screenSeen) && !ArisImageRouting.refusesJobs(answer: "맑아요.", untrusted: true, taint: .outsideText),
          "handoff: the agent says refusedJobs exactly when answerPlan takes a jobs block out")
}

private func conversationPromptTests() {
    let prompts = [("claude", ArisAgentPrompt.system(tools: "/t")), ("codex", ArisAgentPrompt.system(tools: "/t", notion: true, gated: true)),
                   ("agy", ArisAgentPrompt.system(tools: "/t", gated: false)), ("sealed", ArisAgentPrompt.sealed(tools: "/t"))]
    for (name, prompt) in prompts {
        check(prompt.contains(ArisAgentPrompt.handOutRule) && prompt.contains("10 seconds") && prompt.contains("\"jobs\""),
              "prompt (\(name)): anything over about 10 s goes out as a job")
    }
    let task = ArisAgentPrompt.system(tools: "/t", gated: true, task: true)
    check(!task.contains(ArisAgentPrompt.handOutRule) && !task.contains("\"jobs\""), "prompt (task): a background job never hands work on")
    check(ArisAgentPrompt.handOutRule.contains("research") && ArisAgentPrompt.handOutRule.contains("coding")
          && ArisAgentPrompt.handOutRule.contains("browsing") && ArisAgentPrompt.handOutRule.contains("files"),
          "prompt: research, coding, browsing and file work are named")
    check(!ArisAgentPrompt.sealed(tools: "/t").contains("\"assignee\":\"claude-code\"") && ArisAgentPrompt.sealed(tools: "/t").contains("\"clone\""),
          "prompt (sealed): the screen brain's jobs rule names only clone jobs (the untrusted flag is ArisHandOutPlan's, tested there)")
}

private func handOutPlanTests() {
    typealias P = ArisHandOutPlan
    let spec = { (title: String, assignee: ArisJobAssignee) in ArisJobSpec(title: title, prompt: "brief: " + title, assignee: assignee, cwd: nil, appHint: nil) }
    let words = "아이폰 가격 조사해서 정리해 줘"
    // A clean turn: one job for Aris itself goes as the user's own words, trusted, with the conversation.
    let clean = P.Turn(words: words, brain: .claude, turnId: "t1")
    let one = P.plan([spec("모델이 지은 제목", .clone)], turn: clean)
    check(one.count == 1 && one[0].spec.prompt == words && one[0].spec.title == ArisHandoff.title(of: words) && one[0].brain == .claude
          && one[0].provenance.fields.isEmpty && !one[0].cleanContext && one[0].request == words,
          "hand-out (clean): one clone job is the user's words, titled from them, sent with no untrusted flag")
    let several = P.plan([spec("a", .clone), spec("b", .teammate("claude-code"))], turn: clean)
    check(several.count == 2 && several.allSatisfy { $0.provenance.fields["untrusted"] == true && $0.brain == .codex && $0.request == words }
          && several[1].turn == "t1" && several[0].spec.prompt.hasPrefix("brief: a") && several[0].spec.prompt.contains("“\(words)”"),
          "hand-out (clean): several jobs go as the model wrote them, untrusted, and a clean turn still vouches")
    // C2: any unclean turn: every job untrusted on Codex, clean context, the conversation's claims sent.
    for (name, turn) in [("screen", P.Turn(words: words, brain: .claude, turnId: "t1", untrustedTurn: true)),
                         ("screen conversation", P.Turn(words: words, brain: .claude, turnId: "t1", screenConversation: true)),
                         ("outside text", P.Turn(words: words, brain: .antigravity, turnId: "t1", outsideConversation: true))] {
        for specs in [[], [spec("x", .clone)], [spec("x", .clone), spec("y", .teammate("claude-code"))]] {
            let plans = P.plan(specs, turn: turn)
            check(!plans.isEmpty && plans.allSatisfy { plan in
                plan.brain == .codex && plan.provenance.fields["untrusted"] == true && plan.request == words && plan.cleanContext && plan.turn == nil
                    && plan.spec.title.hasPrefix(ArisHandoff.title(of: words))
                    && plan.provenance.fields["screenConversation"] == (turn.screenConversation ? true : nil)
                    && plan.provenance.fields["outsideConversation"] == (turn.outsideConversation ? true : nil)
            }, "hand-out (\(name), \(specs.count) spec(s)): untrusted on Codex, no web, clean context, the user's words as request, claims sent")
        }
    }
    check(P.plan([], turn: P.Turn(words: words, brain: .codex, turnId: nil, outsideConversation: true)).first?.spec.prompt == words,
          "hand-out: a refused jobs block becomes one job of the user's own words")
    // A hands-free turn: marked on every job; alone it doesn't make the turn unclean, but it never vouches.
    let heard = P.Turn(words: words, brain: .claude, turnId: "t1", handsFree: true)
    let heardOne = P.plan([], turn: heard), heardSeveral = P.plan([spec("a", .clone), spec("b", .teammate("claude-code"))], turn: heard)
    check(heardOne[0].provenance.fields == ["handsFree": true] && heardOne[0].brain == .claude && !heardOne[0].cleanContext,
          "hand-out (hands-free, clean): one job stays trusted on its brain, marked hands-free (the agent restricts it)")
    check(heardSeveral.allSatisfy { $0.turn == nil && $0.provenance.fields["handsFree"] == true && $0.provenance.fields["untrusted"] == true },
          "hand-out (hands-free): no vouch, so a Claude Code launch always shows its card")
    let heardUnclean = P.plan([], turn: P.Turn(words: words, brain: .claude, turnId: nil, screenConversation: true, handsFree: true))
    check(heardUnclean[0].provenance.fields == ["untrusted": true, "screenConversation": true, "handsFree": true],
          "hand-out (hands-free, unclean): untrusted with every claim")
    check(ArisProvenance().fields.isEmpty && ArisProvenance(untrusted: true, handsFree: true).fields == ["untrusted": true, "handsFree": true],
          "provenance: only true claims go into /ask")
}

// 2026-11-07 (ad session): Codex's empty answer left the notch blank after 생각 중 — never again an empty notch.
private func emptyAnswerTests() {
    let S = ArisSpeakable.self
    let reason = S.emptyAnswer(korean: true)
    check(!reason.isEmpty && S.visible("", shown: "", card: false, korean: true) == reason
          && S.visible("  \n", shown: "  \n", card: false, korean: true) == reason,
          "empty answer: nothing written shows and says the short reason, never a blank notch")
    let data = "```json\n{\"a\": 1}\n```"
    check(S.shown(data, korean: true).isEmpty && S.visible(data, shown: S.shown(data, korean: true), card: false, korean: true) == reason,
          "empty answer: an answer that was only data shows the reason")
    check(S.visible("", shown: "", card: true, korean: true) == "", "empty answer: a card-only answer stays as it is (the card shows)")
    check(S.visible("x", shown: "내일 3시예요.", card: false, korean: true) == "내일 3시예요.", "empty answer: an answer with words is untouched")
    let sayOnly = "<say>세 문장 써 뒀어요.</say>"
    check(S.visible(sayOnly, shown: "", card: false, korean: true) == "세 문장 써 뒀어요.",
          "empty answer: an answer that was only its <say> line shows those words")
    check(S.emptyAnswer(korean: false) != reason, "empty answer: in English for an English turn")
}

// The figure leaves the notch only when its job names a running app's window (ArisDirector): the hint survives a
// clean single job, and the Korean Mac's localised app names don't hide the English one the model writes.
private func teammateWindowTests() {
    let apps = [ArisRunningApp(pid: 7, bundleId: "com.apple.TextEdit", name: "텍스트 편집기", bundleName: "TextEdit"),
                ArisRunningApp(pid: 8, bundleId: "com.apple.Terminal", name: "터미널", bundleName: "Terminal"),
                ArisRunningApp(pid: 99, bundleId: "com.lumenjsn.aris", name: "Aris", bundleName: "Aris")]
    check(ArisAppHint.pid(for: "TextEdit", in: apps, excluding: 99) == 7 && ArisAppHint.pid(for: "텍스트 편집기", in: apps, excluding: 99) == 7
          && ArisAppHint.pid(for: "textedit.app", in: apps, excluding: 99) == 7 && ArisAppHint.pid(for: "com.apple.textedit", in: apps, excluding: 99) == 7
          && ArisAppHint.pid(for: "Terminal", in: apps, excluding: 99) == 8,
          "director hint: the bundle's own name finds a localised app (TextEdit is 텍스트 편집기 on a Korean Mac)")
    check(ArisAppHint.pid(for: "Text", in: apps, excluding: 99) == nil && ArisAppHint.pid(for: "Aris", in: apps, excluding: 99) == nil,
          "director hint: still never a guess from part of a name, never Aris itself")
    let words = "텍스트 편집기 문서에 실크로드 소개글 세 문장 써 줘"
    let hinted = ArisJobSpec(title: "model", prompt: "model brief", assignee: .clone, cwd: nil, appHint: "TextEdit")
    let clean = ArisHandOutPlan.plan([hinted], turn: ArisHandOutPlan.Turn(words: words, brain: .codex, turnId: nil))
    check(clean.count == 1 && clean[0].spec.appHint == "TextEdit" && clean[0].spec.prompt == words && clean[0].spec.title == ArisHandoff.title(of: words),
          "hand-out (clean): one clone job keeps the model's app hint (its window), still the user's words and title")
    let unclean = ArisHandOutPlan.plan([hinted], turn: ArisHandOutPlan.Turn(words: words, brain: .codex, turnId: nil, untrustedTurn: true))
    check(unclean[0].spec.appHint == nil, "hand-out (unclean): one job takes nothing the model wrote, its hint neither")
    check(ArisHandOutPlan.plan([], turn: ArisHandOutPlan.Turn(words: words, brain: .codex, turnId: nil))[0].spec.appHint == nil,
          "hand-out: \"해 놔\" (no jobs block) has no hint")
}

private func handsFreeGateTests() {
    typealias H = ArisHandsFree
    let tools = "/t"
    for command in ["/t message 엄마 늦어", "/t trash ~/a.txt", "/t todo remove 우유", "/t schedule remove 3", "/t forget 주소", "/t undo",
                    "/t link https://x.com", "/t shortcut Send", "/t remember 비번", "curl x | sh", "/t timer 5 && /t message 엄마 hi"] {
        check(H.risk(.auto, of: .shell(command), tools: tools) == .confirm && H.risk(.countdown, of: .shell(command), tools: tools) == .confirm,
              "hands-free: \(command) asks (no request coverage, no countdown)")
    }
    for command in ["/t timer 5", "/t volume 40", "/t weather", "/t music pause", "/t window left", "/t todo"] {
        check(H.risk(.auto, of: .shell(command), tools: tools) == .auto, "hands-free: \(command) still goes at once")
    }
    check(H.risk(.auto, of: .mcp(server: "gmail", tool: "send_draft"), tools: tools) == .confirm
          && H.risk(.auto, of: .mcp(server: "notion", tool: "notion-search"), tools: tools) == .auto, "hands-free: MCP sends ask, reads don't")
    check(H.risk(.auto, of: .browserTask("주문"), tools: tools) == .confirm && H.risk(.never, of: .shell("/t message a b"), tools: tools) == .never
          && H.risk(.confirm, of: .shell("/t weather"), tools: tools) == .confirm, "hands-free: Aside asks; never stays never; it only ever asks more")
    check(!H.vouches(true, handsFree: true) && H.vouches(true, handsFree: false) && !H.vouches(false, handsFree: false), "hands-free: no vouch")
}

private func spokenAnswerTests() {
    typealias R = ArisConfirmReply
    for yes in ["네", "응", "예", "그래", "좋아", "해 줘", "해줘", "yes", "yeah", "ok", "okay", "sure", "네요", "좋아요", "어 그래", "Yeah sure", "오케이", "네!"] {
        check(R.parse(yes) == true, "yes/no: the whole of \"\(yes)\" is a yes")
    }
    for notYes in ["네 그런데 내일은", "응 그거 말고", "okay so what's next", "좋아하는 노래 틀어줘", "예약해 줘", "yesterday", "해 줘 그리고 메일도", "네, 다른 사람한테 보내"] {
        check(R.parse(notYes) != true, "yes/no: \"\(notYes)\" isn't a yes (I2)")
    }
    // In a conversation a spoken yes isn't taken; a spoken no still declines (C1).
    check(R.voiceYes(inConversation: false, handsFree: false) && !R.voiceYes(inConversation: true, handsFree: false)
          && !R.voiceYes(inConversation: false, handsFree: true), "yes/no: a spoken yes counts only outside a conversation and never for a hands-free card (N3a)")
    check(R.spoken("네", voiceYes: false) == nil && R.spoken("네", voiceYes: true) == true
          && R.spoken("아니", voiceYes: false) == false && R.spoken("취소", voiceYes: false) == false,
          "yes/no: without a spoken yes only a click or Y says yes; a spoken no still works")
    let ask = ArisConfirmation(id: "c", title: "메시지 보내기", detail: "엄마 늦어요")
    check(R.question(for: ask, voiceYes: false).contains("Y") && R.question(for: ask, voiceYes: true) == R.question(for: ask),
          "yes/no: when a spoken yes won't count, the question says how to say yes")
    // N3b: a streaming "네" isn't a yes until it held still 0.6 s; a no counts at once.
    let partial = ArisSpokenAnswer().heard("네", at: 10)
    check(partial.answer(at: 10.3, voiceYes: true) == nil && partial.answer(at: 10.61, voiceYes: true) == true,
          "yes/no: a yes only once its words held still for 0.6 s")
    let grew = partial.heard("네 근데 그거 말고", at: 10.4)
    check(grew.answer(at: 11.5, voiceYes: true) == nil && grew.text == "네 근데 그거 말고", "yes/no: a partial yes that grew into more is no yes")
    let changing = partial.heard("네요", at: 10.5)
    check(changing.answer(at: 10.9, voiceYes: true) == nil && changing.answer(at: 11.2, voiceYes: true) == true, "yes/no: every change restarts the 0.6 s")
    check(ArisSpokenAnswer().heard("아니", at: 1).answer(at: 1, voiceYes: true) == false && partial.answer(at: 20, voiceYes: false) == nil,
          "yes/no: a no counts at once; a still yes is still no yes when voice can't say yes")
}

private func echoTrimTests() {
    typealias E = ArisEchoTrim
    let said = "오늘 일정은 세 개예요. 아침 아홉 시에 팀 회의가 있어요."
    check(E.trimmed("있어요. 잠깐 내일 날씨 알려줘", arisWasSaying: said, atMost: 2) == "잠깐 내일 날씨 알려줘", "echo: Aris's own last words at the start go")
    check(E.trimmed("회의가 있어요", arisWasSaying: said, atMost: 2) == "", "echo: a turn that was only Aris's voice is empty")
    check(E.trimmed("내일 회의가 몇 시야", arisWasSaying: said, atMost: 2) == "내일 회의가 몇 시야", "echo: the user's own words, even ones Aris used later, stay")
    check(E.trimmed("내일 날씨", arisWasSaying: "", atMost: 2) == "내일 날씨", "echo: nothing to trim when Aris wasn't talking")
    // M2: only as many words as the lookback holds, and none on headphones (atMost 0).
    check(E.trimmed("회의가 있어요 회의가 몇 시야", arisWasSaying: said, atMost: 2) == "회의가 몇 시야",
          "echo: words past the lookback stay, even Aris's (\(E.trimmed("회의가 있어요 회의가 몇 시야", arisWasSaying: said, atMost: 2)))")
    check(E.trimmed("회의가 있어요", arisWasSaying: said, atMost: 0) == "회의가 있어요", "echo: nothing is trimmed off speakers")
    check(E.words(in: 0.3) == 2 && E.words(in: 0) == 1, "echo: about three and a half words a second fit in the lookback")
}

private func otherAudioTests() {
    typealias O = ArisOtherAudio
    let me: Int32 = 100
    let asideHelper = O.Process(object: 11, pid: 2546, bundle: "at.studio.AsideBrowser.helper", output: true, input: false)
    let agent = O.Process(object: 12, pid: 300, bundle: "com.lumenjsn.aris.aris-agent", output: true, input: true)
    let own = O.Process(object: 10, pid: me, output: true, input: true)
    let music = O.Process(object: 13, pid: 7, bundle: "com.spotify.client", output: true, input: false)
    // Aris itself never counts; Aside is measured like any app (its silent stream reads 0).
    check(!O.isPresent([own, agent], ownPid: me) && O.isOwn(.init(pid: 5, bundle: "com.lumenjsn.aris.XPCHelper", output: true, input: false), ownPid: me),
          "other audio: Aris, its helpers and its agent never count")
    check(O.ownObjects([own, agent, asideHelper, music], ownPid: me) == [10, 12], "other audio: the tap leaves out only Aris's processes (Aside is measured)")
    check(!O.isPresent([asideHelper], ownPid: me, outputLevel: 0) && O.isPresent([asideHelper], ownPid: me, outputLevel: 0.05),
          "other audio: Aside's open stream is silent (0) on the meter; Aside playing a video pauses listening")
    check(!O.isPresent([music, asideHelper], ownPid: me, outputLevel: 0.0001) && O.isPresent([music], ownPid: me, outputLevel: 0.05),
          "other audio: an open but silent stream doesn't pause listening; audible sound does")
    // No reading (no tap yet, or only zeros: a denied permission): fail closed on every open stream but Aside's.
    check(O.isPresent([music], ownPid: me, outputLevel: nil) && !O.isPresent([asideHelper, own], ownPid: me, outputLevel: nil),
          "other audio: without a reading an open stream counts, except Aside's always-open one")
    check(O.isPresent([.init(pid: 8, bundle: "us.zoom.xos", output: false, input: true)], ownPid: me, outputLevel: 0),
          "other audio: another app on the microphone pauses listening, whatever the meter")
    check(O.needsMeter([asideHelper], ownPid: me) && !O.needsMeter([own, agent], ownPid: me), "other audio: the meter runs while any other app has output open")
    // Bug hunt 11-06 #4: only a conversation (whose close stops it) runs the meter; a lone wake turn over YouTube doesn't.
    check(O.meterStep([music], ownPid: me, forConversation: true) == .ensure && O.meterStep([own], ownPid: me, forConversation: true) == .stop,
          "other audio: a conversation's check starts the meter while another app plays, and stops it when none does")
    check(O.meterStep([music], ownPid: me, forConversation: false) == .leave,
          "other audio: with 계속 듣기 off, a wake turn over another app's sound never starts the meter")
    // Bundle ids match exactly, or inside them, never by a shared start.
    check(O.matches("com.lumenjsn.aris", O.ownBundles) && O.matches("com.lumenjsn.aris.XPCHelper", O.ownBundles)
          && !O.matches("com.lumenjsn.arisx", O.ownBundles) && !O.matches("at.studio.AsideBrowserX", O.alwaysOpen) && !O.matches(nil, O.ownBundles),
          "other audio: bundle ids match exactly or with a dot")
    check(O.permissionMissing(onlyZeros: true, [music], ownPid: me) && !O.permissionMissing(onlyZeros: true, [asideHelper], ownPid: me)
          && !O.permissionMissing(onlyZeros: false, [music], ownPid: me), "other audio: only zeros while a real player is open means no permission")
    // The tap's reading: unknown until real sound came; only zeros for 3 s is suspect.
    typealias M = ArisMeterReading
    let started = M(startedAt: 100)
    check(started.level(at: 100) == nil && !started.onlyZeros(at: 200), "meter: nothing read yet is unknown")
    let zeros = started.reading(0, at: 100.5).reading(0, at: 101)
    check(zeros.level(at: 101) == nil && !zeros.onlyZeros(at: 102) && zeros.onlyZeros(at: 103), "meter: only zeros is unknown (fail closed), suspect after 3 s")
    let sound = zeros.reading(0.04, at: 101.2)
    check(sound.level(at: 101.3) == 0.04 && !sound.onlyZeros(at: 110) && sound.level(at: 102) == 0, "meter: real sound reads its peak, then 0 once it's old")
    let quietAfter = sound.reading(0, at: 101.8)
    check(quietAfter.level(at: 101.85) == 0, "meter: silence after sound is a known 0, not unknown")
}

private func handsFreeRoutingTests() {
    typealias R = ArisImageRouting
    // N1 (the owner: users without GPT must still be able to use Aris): a hands-free turn or job keeps its brain, gated.
    for task in [false, true] {
        let codex = R.route(requested: .codex, images: [], screenText: false, claudeInstalled: true, task: task, handsFree: true)
        check(codex.brain == .codex && !codex.sealed && codex.refusal == nil, "profile (Codex, task \(task)): Codex as ever, its gate asks")
        let claude = R.route(requested: .claude, images: [], screenText: false, claudeInstalled: true, task: task, handsFree: true)
        check(claude.brain == .claude && claude.sealed && claude.refusal == nil, "profile (Claude, task \(task)): the sealed, hands-free Claude")
        // The user: every feature on every brain. agy answers hands-free itself, sealed (no tools; Aris runs things for it).
        for installed in [true, false] {
            let agy = R.route(requested: .antigravity, images: [], screenText: false, claudeInstalled: installed, task: task, handsFree: true)
            check(agy.brain == .antigravity && agy.sealed && agy.refusal == nil, "profile (agy, Claude installed \(installed), task \(task)): the sealed agy")
        }
        check(R.route(requested: .claude, images: [], screenText: false, claudeInstalled: true, task: task).sealed == false,
              "profile (not hands-free, task \(task)): the open Claude as before")
    }
    check(R.runnerName(.claude, sealed: true, handsFree: true) == "claude-handsfree" && R.runnerName(.claude, sealed: true) == "claude-sealed",
          "profile: the hands-free Claude is a process of its own")
    // The restricted Claude: no web or files, only the sealed aris-tools list, every outbound or destructive command refused.
    for task in [false, true] {
        let driver = ArisClaudeDriver(model: "m", tools: "/t", task: task, handsFree: true)
        let arguments = driver.arguments
        let tools = arguments.firstIndex(of: "--tools").map { arguments[$0 + 1] }
        check(driver.sealed && tools == "Bash,WebSearch,WebFetch" && driver.environment[ArisSealedTools.environmentKey] == "1",
              "profile (Claude hands-free, task \(task)): Bash for the sealed list, the web through the judge, aris-tools sealed")
        check(!ArisSealedTools.allows(["mail", "kim@x.com", "hi"]), "profile (Claude hands-free, task \(task)): a mail send stays off its list")
        for refused in ["message", "trash", "keys", "type", "link", "shortcut", "clipboard set", "todo remove", "todo done", "remind", "schedule add"] {
            check(arguments.contains("Bash(/t \(refused):*)"), "profile (Claude hands-free, task \(task)): `\(refused)` refused")
        }
        let prompt = arguments.firstIndex(of: "--system-prompt").map { arguments[$0 + 1] } ?? ""
        check(prompt.contains(ArisHandsFree.askAgainLine) && prompt.contains("hands-free") && prompt.contains(task ? ArisTaskResult.instruction : "One or two short sentences"),
              "profile (Claude hands-free, task \(task)): anything more is answered \"\(ArisHandsFree.askAgainLine)\"")
        check(!prompt.contains("looking at the screen") && !prompt.contains("what you see") && !prompt.contains("seen the user's screen"),
              "profile (Claude hands-free, task \(task)): nothing about looking at the screen")
    }
    check(!ArisAgentPrompt.sealed(tools: "/t").contains(ArisHandsFree.askAgainLine) && ArisAgentPrompt.sealed(tools: "/t").contains("seen the user's screen"),
          "profile: the screen's sealed Claude keeps its own wording")
    check(ArisHandsFree.profile(.antigravity) == (.antigravity, true) && ArisHandsFree.profile(.codex) == (.codex, false)
          && ArisHandsFree.profile(.claude) == (.claude, true), "profile: ArisHandsFree.profile")
    // The open Claude and agy refuse ticking off and removing to-dos too (agy's deny list in install-aris-agent.sh mirrors it).
    check(ArisClaudeDriver.ungatedRefused.contains("todo remove") && ArisClaudeDriver.ungatedRefused.contains("todo done"),
          "profile: the ungated brains can't remove or finish to-dos")
    // N2: a learned shortcut never replays for a hands-free or untrusted turn.
    check(ArisHandsFree.mayReplayShortcut(untrusted: false, handsFree: false) && !ArisHandsFree.mayReplayShortcut(untrusted: false, handsFree: true)
          && !ArisHandsFree.mayReplayShortcut(untrusted: true, handsFree: false), "shortcuts: replayed only for a key or wake-word turn")
}

private func cardKeyTests() {
    typealias K = ArisCardKeys
    // A lone Y on a fresh card after a quiet keyboard approves, 250 ms later.
    let card = K(presentedAt: 100, lastKeyAt: 90)
    let (held, holding) = card.key(.y, at: 102)
    check(holding == .holdYes && held.holdsYes, "card keys: a Y is held back, not approved at once")
    check(held.due(at: 102.2).1 == nil && held.due(at: 102.25).1 == true && !held.due(at: 102.25).0.holds, "card keys: a Y alone for 250 ms approves")
    // Typing "you" in another app: the Y is followed by a letter, so nothing is approved and "yo" goes on in order.
    let (typing, next) = held.key(.other, at: 102.08)
    check(next == .passHeldThenThis && !typing.holds && typing.due(at: 103).1 == nil, "card keys: Y then another key is typing: both go on, no yes")
    check(typing.key(.y, at: 102.2).1 == .pass, "card keys: a Y right after typing passes (the keyboard isn't quiet)")
    // Not quiet: a keystroke less than 1.5 s before.
    check(K(presentedAt: 100, lastKeyAt: 101).key(.y, at: 102).1 == .pass && K(presentedAt: 100, lastKeyAt: 101).key(.n, at: 102).1 == .pass,
          "card keys: Y and N within 1.5 s of other typing pass through")
    check(K(presentedAt: 100, lastKeyAt: 100.4).key(.y, at: 102).1 == .holdYes, "card keys: 1.6 s of quiet is enough")
    // A stale card: 15 s after it appeared, Y and N are just letters.
    check(K(presentedAt: 100).key(.y, at: 115).1 == .pass && K(presentedAt: 100).key(.n, at: 116).1 == .pass && K(presentedAt: 100).key(.y, at: 114.9).1 == .holdYes,
          "card keys: only within 15 s of the card")
    // Bug hunt 11-06 #13: N is held like Y, so "now" or "nice" typed in another app keeps its n and declines nothing.
    let (heldNo, holdingNo) = card.key(.n, at: 102)
    check(holdingNo == .holdNo && heldNo.holds && !heldNo.holdsYes, "card keys: an N is held back, not declined at once")
    check(heldNo.due(at: 102.2).1 == nil && heldNo.due(at: 102.25).1 == false, "card keys: an N alone for 250 ms declines")
    let (typingNow, nowNext) = heldNo.key(.other, at: 102.07)
    check(nowNext == .passHeldThenThis && !typingNow.holds && typingNow.due(at: 103).1 == nil,
          "card keys: N then another key is typing (\"now\"): both go on, the card stays")
    // Other keys always pass and count as typing.
    let (other, passed) = card.key(.other, at: 102)
    check(passed == .pass && other.key(.y, at: 103).1 == .pass && other.key(.y, at: 103.6).1 == .holdYes,
          "card keys: any other key passes and restarts the quiet")
    check(K(presentedAt: 100).listens(at: 100) && !K(presentedAt: 100, lastKeyAt: 99.5).listens(at: 100), "card keys: listens")
}
