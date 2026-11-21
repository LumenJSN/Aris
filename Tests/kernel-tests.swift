// jv-kernel: turn ids and guarded session writes (ARCHITECTURE.md target 4), card waits as kernel continuations,
// and the countdown that sends only on silence or a clear yes. The controller needs AppKit and can't be compiled here:
// the bugs are replayed on a stand-in with the controller's shape (the real ArisKernel, ArisSession and ArisTurnScope,
// and the same setSession / openTurn / runTurn), and the wiring is checked in the controller's sources.
import Foundation

private func kernelSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private final class KernelFlag: @unchecked Sendable { var done = false }

/// The controller's turn mechanics, as ArisController+Kernel and ArisController.setSession have them.
@MainActor
private final class KernelStandIn {
    let kernel = ArisKernel()
    private(set) var session = ArisSession()
    var turn: Task<Void, Never>?
    var spoken: [String] = []
    var dropped = 0

    init() { kernel.cancelWork = { [weak self] _ in self?.turn?.cancel() } }

    var turnIsCurrent: Bool { kernel.state.admits(ArisTurnScope.current) }
    func setSession(_ next: ArisSession, from turn: ArisTurnID? = ArisTurnScope.current) {
        guard kernel.admitsWrite(from: turn) else { dropped += 1; return }
        session = next
    }
    func speak(_ line: String) { if turnIsCurrent { spoken.append(line) } }
    func openTurn(_ origin: ArisTurnOrigin) -> ArisTurnID { kernel.openTurn(origin) }
    func startTurn(_ origin: ArisTurnOrigin, _ work: @escaping @MainActor () async -> Void) {
        let id = openTurn(origin)
        turn = ArisTurnScope.within(id) { Task { @MainActor in await work() } }
    }
    /// askUser: the card's wait is the kernel's; nil when the card's turn ended (never a no).
    func askUser(_ ask: ArisConfirmation) async -> Bool? {
        guard turnIsCurrent else { return nil }
        let key = kernel.showCard(ask.id, turn: ArisTurnScope.current)
        defer { kernel.closeCard(key) }
        setSession(session.asking(ask))
        while true {
            switch await kernel.waitForCard(key, atMost: .milliseconds(20)) {
            case .answered(let allow)?: return allow
            case .covered?: return false
            case .cancelled?: return nil
            case nil: continue
            }
        }
    }
    func answerQuestion(_ allow: Bool) {
        guard let question = session.question else { return }
        kernel.answerCard(question.id, allow: allow)
    }
}

/// Lets the main actor run until `done` or `seconds` pass.
@MainActor
private func kernelSpin(_ seconds: Double = 2, until done: () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !done(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
}

@MainActor
private func kernelStaleWriteTests() async {
    let thinking = ArisSession().listening().hearing("엄마한테 문자 보내 줘").thinking()

    // askAndSpeak's .confirm: the old turn finished its voice and went on to ask, though a new turn had begun.
    do {
        let aris = KernelStandIn()
        var asked: Bool?? = .none
        let release = AsyncStream<Void>.makeStream()
        aris.startTurn(.key) {
            aris.setSession(thinking)
            for await _ in release.stream { break } // the voice finishing
            asked = .some(await aris.askUser(ArisConfirmation(id: "send", title: "메시지 보내기", detail: "엄마")))
            aris.speak("보낼게요")
        }
        await kernelSpin { aris.session == thinking }
        ArisTurnScope.within(aris.openTurn(.typed)) { aris.setSession(ArisSession().listening().hearing("날씨 어때").thinking()) }
        let newTurn = aris.session
        release.continuation.yield()
        await kernelSpin { asked != nil }
        check(aris.session == newTurn && aris.session.question == nil && asked == .some(nil) && aris.spoken.isEmpty,
              "kernel: a replaced turn that goes on from its voice to a card shows no card over the new turn, and its card is no no")
    }

    // countdownSend: the old turn's countdown was waiting when a new turn began; its counted write lands nowhere.
    do {
        let aris = KernelStandIn()
        var sent: Bool?? = .none
        aris.startTurn(.key) {
            sent = .some(await aris.askUser(ArisConfirmation(id: "countdown", title: "엄마", detail: "곧 갈게", countdown: true)))
            if sent == .some(true) { aris.setSession(aris.session.counted(sent: true)) }
        }
        await kernelSpin { aris.session.question?.id == "countdown" }
        ArisTurnScope.within(aris.openTurn(.wake)) { aris.setSession(ArisSession().listening()) }
        await kernelSpin { sent != nil }
        check(sent == .some(nil) && aris.session == ArisSession().listening(),
              "kernel: a countdown whose turn was replaced neither sends nor writes its card over the new turn")
    }

    // The countdown's microphone failed and it fell back to the plain card after an await: the asking write is dropped.
    do {
        let aris = KernelStandIn()
        var done = false
        let micFailed = AsyncStream<Void>.makeStream()
        aris.startTurn(.key) {
            for await _ in micFailed.stream { break }
            _ = await aris.askUser(ArisConfirmation(id: "send", title: "메시지 보내기", detail: "엄마 곧 갈게"))
            done = true
        }
        await Task.yield()
        ArisTurnScope.within(aris.openTurn(.key)) { aris.setSession(ArisSession().listening()) }
        micFailed.continuation.yield()
        await kernelSpin { done }
        check(done && aris.session == ArisSession().listening(), "kernel: the countdown's fallback card from a replaced turn never comes up")
    }

    // undoSay after a card whose turn was stopped: the cancelled card is no "no", so "그대로 둘게요" is neither shown nor said.
    do {
        let aris = KernelStandIn()
        var finished = false
        aris.startTurn(.key) {
            guard let yes = await aris.askUser(ArisConfirmation(id: "undo-1", title: "되돌리기", detail: "할 일 추가")) else { finished = true; return }
            let reply = yes ? "되돌렸어요." : "그대로 둘게요."
            aris.setSession(aris.session.answering(reply))
            aris.speak(reply)
            finished = true
        }
        await kernelSpin { aris.session.question != nil }
        // cancel(): the turn ends, and the cancel's own write is the kernel's.
        aris.kernel.endTurn(nil, .cancelled)
        aris.turn?.cancel()
        aris.setSession(aris.session.done(), from: nil)
        let stopped = aris.session
        await kernelSpin { finished }
        check(finished && aris.session == stopped && aris.spoken.isEmpty,
              "kernel: a card stopped with its turn leaves nothing behind (no “그대로 둘게요” written or said)")
        // And an undo that awaited the agent when the turn was replaced: its late answering write is dropped.
        let late = KernelStandIn()
        let agent = AsyncStream<Void>.makeStream()
        var wrote = false
        late.startTurn(.key) {
            for await _ in agent.stream { break }
            late.setSession(late.session.answering("되돌렸어요."))
            wrote = true
        }
        await Task.yield()
        ArisTurnScope.within(late.openTurn(.typed)) { late.setSession(thinking) }
        agent.continuation.yield()
        await kernelSpin { wrote }
        check(wrote && late.session == thinking && late.dropped == 1, "kernel: an undo's late reply from a replaced turn is dropped")
    }

    // ArisPreview's answer runs as a turn of its own: the next turn cancels it and its late reply is dropped.
    do {
        let aris = KernelStandIn()
        var ended = false
        aris.startTurn(.preview) {
            try? await Task.sleep(for: .milliseconds(30))
            aris.setSession(aris.session.answering("미리 보기 답"))
            ended = true
        }
        let previewTask = aris.turn
        ArisTurnScope.within(aris.openTurn(.key)) { aris.setSession(ArisSession().listening()) }
        await kernelSpin { ended }
        check(previewTask?.isCancelled == true && aris.session == ArisSession().listening(),
              "kernel: the preview's answer is a cancellable turn whose late reply never lands on the next one")
    }

    // A watch task started for a turn that was replaced (ArisController+Watch) writes nothing late; one for no turn does.
    do {
        let aris = KernelStandIn()
        let old = aris.openTurn(.key)
        let watch = ArisTurnScope.within(old) { Task { @MainActor in aris.setSession(aris.session.done()) } }
        _ = aris.openTurn(.typed)
        aris.setSession(thinking)
        await watch.value
        let background = ArisTurnScope.within(old) { ArisTurnScope.outside { Task { @MainActor in aris.setSession(aris.session.answering("작업 끝")) } } }
        await background.value
        check(aris.session == thinking.answering("작업 끝"),
              "kernel: a replaced turn's watch can't idle the new turn; work started outside any turn (a job) still writes")
    }

    // The card answered with a click while it is read out resumes the kernel's wait at once, keyed to its showing.
    do {
        let aris = KernelStandIn()
        var answer: Bool?? = .none
        aris.startTurn(.key) { answer = .some(await aris.askUser(ArisConfirmation(id: "c", title: "t", detail: "d"))) }
        await kernelSpin { aris.session.question != nil }
        aris.answerQuestion(true)
        await kernelSpin { answer != nil }
        aris.answerQuestion(false)
        check(answer == .some(true), "kernel: a click resumes the card's wait once, with its answer")
    }
}

private func kernelCountdownWordTests() {
    for word in ["잠깐만", "잠깐", "wait", "hold on", "음", "엄마한테 말고"] {
        check(ArisConfirmReply.countdownEnd(final: word) == .pause, "countdown: “\(word)” at the ring's end pauses it, never sends")
        check(ArisConfirmReply.countdownPauses(word, heldFor: 0.7), "countdown: “\(word)” held still mid-ring pauses it at once")
    }
    check(!ArisConfirmReply.countdownPauses("잠깐만", heldFor: 0.2), "countdown: words still coming don't pause it yet")
    check(ArisConfirmReply.countdownEnd(final: "") == .send && ArisConfirmReply.countdownEnd(final: "  ") == .send,
          "countdown: silence until the ring ends sends, as designed")
    for yes in ["응", "보내", "yes", "yep", "yup", "okay", "go ahead", "send it", "sure"] {
        check(ArisConfirmReply.countdownEnd(final: yes) == .send && !ArisConfirmReply.countdownPauses(yes, heldFor: 1), "countdown: “\(yes)” sends")
    }
    for no in ["취소", "아니", "no", "nope", "nah", "cancel", "stop", "never mind", "don't send it"] {
        check(ArisConfirmReply.countdownEnd(final: no) == .stop, "countdown: “\(no)” stops it")
    }
    check(ArisConfirmReply.parse("yep") == true && ArisConfirmReply.parse("go ahead") == true && ArisConfirmReply.parse("nah") == false
          && ArisConfirmReply.parse("never mind") == false && ArisConfirmReply.parse("yes but not now") == false
          && ArisConfirmReply.parse("send it to dad instead") == nil,
          "confirm reply: the English yes and no words added, a whole short yes still required")
}

private func kernelWiringTests() {
    let controller = kernelSource("Aris/private/Aris/ArisController.swift")
    check(controller.contains("@Published private(set) var session = ArisSession()")
          && controller.contains("guard kernel.admitsWrite(from: turn) else"),
          "kernel wiring: `session` is written only through setSession, which drops a write from a turn that is over")
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris")
    let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
        .filter { $0.pathExtension == "swift" }
    let raw = try! NSRegularExpression(pattern: #"(^|[^.\w])(self\.|aris\.)?session = "#, options: .anchorsMatchLines)
    let writers = files.filter { url in
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.contains("URLSession") && !$0.contains("let session") && !$0.contains("var session") }
        let hits = lines.filter { raw.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        return url.lastPathComponent == "ArisController.swift" ? hits != ["        session = next"] : !hits.isEmpty
    }
    check(writers.isEmpty, "kernel wiring: no session write outside setSession (\(writers.map(\.lastPathComponent)))")
    check(!controller.contains("typedAnswer") && controller.contains("kernel.answerCard(question.id, allow: allow)"),
          "kernel wiring: answerQuestion resumes the kernel's card wait; the polled typedAnswer is gone")
    let tasks = kernelSource("Aris/private/Aris/ArisController+Tasks.swift")
    check(!tasks.contains("typedAnswer") && tasks.contains("let key = kernel.showCard(ask.id, turn: ArisTurnScope.current)")
          && tasks.contains("kernel.waitForCard(key, atMost: .milliseconds(200))") && tasks.contains("return wait.cancelled ? nil : wait.allow"),
          "kernel wiring: a card waits on the kernel's continuation, and askUser tells a cancelled card from a no")
    check(tasks.contains("if covered || cancelled { return .covered }"),
          "kernel wiring: a job's card whose turn ended waits in 확인 대기, as a covered one did")
    let countdown = kernelSource("Aris/private/Aris/ArisController+Countdown.swift")
    check(!countdown.contains("ArisConfirmReply.parse(final) == false ? false : true") && countdown.contains("ArisConfirmReply.countdownWords(final)")
          && countdown.contains("case .pause: return await pausedCountdown(ask, key: key)"),
          "kernel wiring: the countdown no longer sends on anything that isn't a no")
    let ask = controller.components(separatedBy: "case .confirm(let ask):").last ?? ""
    check(ask.contains("if said == nil, let speaking { await speak { await speaking.value } }\n                // Stopped or replaced while the voice finished: no card comes up for a turn that is over.\n                guard turnIsCurrent, !Task.isCancelled else { return nil }")
          && ask.contains("guard let allow = await askUser(ask, handsFree: turnHandsFree, waiter: true, ownerContent: ownerContent, after: said), !Task.isCancelled else { return nil }"),
          "kernel wiring: the confirm path checks its turn between the voice and the card, and a cancelled card ends it")
    let undo = kernelSource("Aris/private/Aris/ArisController+Undo.swift")
    check(undo.contains("handsFree: turnHandsFree) else { return \"\" }\n            guard yes else { return await leftAsItIs() }"),
          "kernel wiring: an undo card stopped with its turn never says “그대로 둘게요”")
    check(kernelSource("Aris/private/Aris/ArisPreview.swift").contains("aris.startTurn(.preview) {"),
          "kernel wiring: the preview's answer runs as a turn the next one cancels")
    check(controller.contains("guard turnIsCurrent else { return }\n        guard !silentSpeech else { return }\n        guard ArisQuietGate.maySpeak(heard: session.heard) else { return }"),
          "kernel wiring: a turn that is over says nothing more")
    let turnStarts = files.map { (try? String(contentsOf: $0, encoding: .utf8)) ?? "" }.joined()
    check(!turnStarts.contains("turn = Task {\n") && turnStarts.components(separatedBy: "turn?.cancel()").count == 4,
          "kernel wiring: turns are opened, run and ended through the kernel (only fail() cancels its own work)")
    let team = kernelSource("Aris/private/Aris/ArisController+Team.swift")
    check(team.contains("run.task = ArisTurnScope.outside { Task { [weak self] in"),
          "kernel wiring: a job runs for no turn, so its news and cards aren't dropped with the turn that handed it out")
}

func runKernelTests() {
    kernelCountdownWordTests()
    kernelWiringTests()
    let flag = KernelFlag()
    Task { @MainActor in
        await kernelStaleWriteTests()
        flag.done = true
    }
    while !flag.done { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}
