import XCTest
@testable import ArisCore

/// The task journal's format, replay, recovery plans and the silence clock (jv-tasks). The live parts (files, fake
/// brain processes, process groups) are in tests/tasks-tests.swift.
final class ArisTaskJournalTests: XCTestCase {
    private let job = "6F9619FF-8B86-D011-B42D-00C04FC964FF"

    private func created(at: Date = Date(), brain: String = "claude") -> ArisTaskRecord {
        .created(job: job, title: "보고서", request: "보고서 정리해 줘", prompt: "보고서 정리해 줘", brain: brain, model: "sonnet",
                 origin: ArisTaskOrigin(tier: "work"), at: at)
    }

    func testRecordsRoundTripWithTheirVersion() {
        let records: [ArisTaskRecord] = [created(), .started(), .session("s"), .step("shell: x", effect: true), .status("중"), .output("반"), .ended(.answered, line: "끝")]
        let back = ArisTaskRecord.records(in: records.map(\.line).reduce(Data(), +))
        XCTAssertEqual(back.map(\.line), records.map(\.line))
        XCTAssertTrue(back.allSatisfy { $0.v == ArisTaskRecord.version })
    }

    func testDamagedNewerAndUnversionedLinesAreSkipped() {
        var newer = ArisTaskRecord.started()
        newer.v = ArisTaskRecord.version + 1
        let data = created().line + Data("garbage\n".utf8) + newer.line + Data(#"{"kind":"started"}"#.utf8 + [0x0A]) + ArisTaskRecord.started().line
        XCTAssertEqual(ArisTaskRecord.records(in: data).map(\.kind), [.created, .started])
    }

    /// A stand-in chain seal: the line's place, the seal before it and its length.
    private func mark(_ json: Data, _ index: Int, _ previous: String) -> String { "s\(index)-\(previous.count)-\(json.count)" }

    private func chain(_ records: [ArisTaskRecord]) -> [Data] {
        var previous = ""
        return records.enumerated().map { index, record in
            let line = record.line(sealedWith: { self.mark($0, index, previous) })
            previous = ArisTaskRecord.sealed(Data(line.dropLast()))!.seal
            return line
        }
    }

    private func read(_ lines: [Data]) -> [ArisTaskRecord.Kind] {
        ArisTaskRecord.chained(in: lines.reduce(Data(), +)) { json, seal, index, previous in seal == self.mark(json, index, previous) }.records.map(\.kind)
    }

    func testTheChainHoldsOnlyLinesInTheirPlace() {
        let lines = chain([created(), .started(), .answer("c", allow: true), .ended(.answered)])
        XCTAssertEqual(read(lines), [.created, .started, .answer, .ended])
        XCTAssertEqual(read([lines[0], lines[2], lines[1]]), [.created], "reordered")
        XCTAssertEqual(read(lines + [lines[3]]), [.created, .started, .answer, .ended], "a repeat doesn't add")
        XCTAssertEqual(read([lines[0], lines[1], ArisTaskRecord.answer("c", allow: true).line]), [.created, .started], "unsealed")
        XCTAssertEqual(read([lines[0], lines[1], Data(lines[2].prefix(10))]), [.created, .started], "a cut tail")
        let cut = (Array(lines.prefix(2)) + [Data(lines[2].prefix(10))]).reduce(Data(), +)
        let result = ArisTaskRecord.chained(in: cut) { json, seal, index, previous in seal == self.mark(json, index, previous) }
        XCTAssertEqual(result.good, 2)
        XCTAssertEqual(result.goodBytes, lines[0].count + lines[1].count)
    }

    func testFieldsAreCutToActionsLogLimits() {
        let long = String(repeating: "가", count: 9_000)
        let record = ArisTaskRecord.created(job: job, title: long, request: long, prompt: long, brain: "claude", model: "m", origin: ArisTaskOrigin(tier: "work"))
        XCTAssertEqual(record.request?.count, ArisTaskLimits.words)
        XCTAssertEqual(record.title?.count, ArisTaskLimits.line)
        XCTAssertEqual(ArisTaskRecord.step(long, effect: true).text?.count, ArisTaskLimits.step)
        XCTAssertEqual(ArisTaskRecord.output(long).text?.count, ArisTaskLimits.words)
    }

    func testReplayTellsTheTask() throws {
        let card = ArisTaskCard(id: "k/1", title: "메일 보내기", detail: "교수님께", full: nil)
        let state = try XCTUnwrap(ArisTaskState.replay([created(), .started(), .session("s-1"), .step("tool: WebSearch", effect: false),
                                                       .tainted("outsideText"), .output("첫 줄"), .card(card)]))
        XCTAssertEqual(state.session, "s-1")
        XCTAssertEqual(state.openCard, card)
        XCTAssertEqual(state.taint, "outsideText")
        XCTAssertFalse(state.hadSideEffects)
        let answered = try XCTUnwrap(ArisTaskState.replay([created(), .card(card), .answer("k/1", allow: true), .ended(.answered)]))
        XCTAssertNil(answered.openCard)
        XCTAssertTrue(answered.hadSideEffects)
        XCTAssertFalse(answered.isOpen)
        XCTAssertNil(ArisTaskState.replay([.started()]))
    }

    func testRecoveryPlans() throws {
        let now = Date()
        let open = try XCTUnwrap(ArisTaskState.replay([created(at: now - 60), .started(), .session("sess"), .step("shell: aris-tools message 엄마 hi", effect: true)]))
        guard case .resume(let session, let note) = ArisTaskRecovery.plan(open, canResume: true, now: now) else { return XCTFail("resume") }
        XCTAssertEqual(session, "sess")
        XCTAssertTrue(note.contains("do not repeat"))
        guard case .restart(let prompt) = ArisTaskRecovery.plan(open, canResume: false, now: now) else { return XCTFail("restart") }
        XCTAssertTrue(prompt.hasPrefix("보고서 정리해 줘") && prompt.contains("aris-tools message"))
        let card = ArisTaskCard(id: "k", title: "t", detail: "d", full: nil)
        let waiting = try XCTUnwrap(ArisTaskState.replay([created(at: now - 60), .card(card)]))
        XCTAssertEqual(ArisTaskRecovery.plan(waiting, canResume: true, now: now), .waitCard(card))
        let looped = try XCTUnwrap(ArisTaskState.replay([created(at: now - 60), .recovered(.restarted), .recovered(.restarted), .recovered(.restarted)]))
        guard case .lost = ArisTaskRecovery.plan(looped, canResume: true, now: now) else { return XCTFail("lost") }
        let ended = try XCTUnwrap(ArisTaskState.replay([created(), .ended(.cancelled)]))
        XCTAssertEqual(ArisTaskRecovery.plan(ended, canResume: true, now: now), .none)
    }

    /// jv-fixhelper: a restart is told the steps, never answer text (an older journal's output is left out).
    func testARestartCarriesNoAnswerText() throws {
        let old = try XCTUnwrap(ArisTaskState.replay([created(), .started(), .step("shell: x", effect: false), .output("모델이 쓴 비밀 답")]))
        let prompt = ArisTaskRecovery.restartPrompt(old, answered: nil)
        XCTAssertTrue(prompt.contains("shell: x"))
        XCTAssertFalse(prompt.contains("비밀"))
    }

    /// jv-fixhelper: a job's quiet limit outlasts its brain's longest silent tool call, never below the base, same ceiling.
    func testAJobOutlastsItsLongestSilentCall() {
        XCTAssertEqual(ArisTurnLimits.job(longestSilentCall: 0), ArisTurnLimits.job)
        XCTAssertEqual(ArisTurnLimits.job(longestSilentCall: 1_800), ArisTurnLimits(silence: 1_800 + ArisTurnLimits.jobMargin, ceiling: 4 * 3_600))
        let clock = ArisSilenceClock(limits: .job(longestSilentCall: 1_800), at: Date(timeIntervalSince1970: 0))
        XCTAssertNil(clock.expired(at: Date(timeIntervalSince1970: 11 * 60)))
    }

    func testTheClockCountsSilenceNotTotalTime() {
        let t0 = Date(timeIntervalSince1970: 0)
        var clock = ArisSilenceClock(limits: ArisTurnLimits(silence: 10, ceiling: 100), at: t0)
        for second in stride(from: 5.0, through: 60, by: 5) { clock.heard(at: t0 + second) }
        XCTAssertNil(clock.expired(at: t0 + 65))
        XCTAssertEqual(clock.expired(at: t0 + 70), .silence)
        var held = ArisSilenceClock(limits: ArisTurnLimits(silence: 10, ceiling: 30), at: t0)
        held.hold(for: 300, at: t0 + 5)
        XCTAssertNil(held.expired(at: t0 + 314))
        XCTAssertEqual(held.expired(at: t0 + 315), .silence)
        var chatty = ArisSilenceClock(limits: ArisTurnLimits(silence: 10, ceiling: 30), at: t0)
        for second in stride(from: 1.0, through: 40, by: 1) { chatty.heard(at: t0 + second) }
        XCTAssertEqual(chatty.expired(at: t0 + 30), .ceiling)
    }
}
