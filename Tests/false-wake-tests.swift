// Tests for false-wake (the owner, 2026-11-14: "왜 갑자기 못 들었어요 이지랄하냐"). Tonight's wake log: four "sure"
// wakes (voice-print scores 12.23, 14.73, 15.00, 15.91; sure below 16.11 = 0.6 × 26.85) opened a turn that heard
// nothing and said "못 들었어요"; real calls with scores 17–24 were rejected by a start-anchored name check; and after
// every turn of a conversation the wake word was closed for 15–30 s because another app's always-open output stream
// (Discord's helper) counted as sound. A wake-word turn that hears nothing now closes without a word; a borderline
// sure wake is checked by Whisper after opening; the check reads near spellings and a filler before the name; the
// wake word stays armed while another app's sound pauses a conversation's listening. Called from main.swift.
import Foundation

private let wakeRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func wakeSource(_ path: String) -> String { (try? String(contentsOf: wakeRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runFalseWakeTests() {
    falseWakeUnheardTests()
    falseWakeBandTests()
    falseWakeAfterOpeningTests()
    falseWakeLogTests()
    falseWakeNameTests()
    falseWakeClipTests()
    falseWakeOtherAudioTests()
    falseWakeWhisperCheckTests()
    falseWakeSecondChanceTests()
    falseWakeMeterTests()
    falseWakeBargeInTests()
    falseWakeWiringTests()
}

private typealias D = ArisWakeDoubt
/// Tonight's model: threshold 26.849787 (sure 16.11).
private let tonight: Float = 26.849787

// MARK: - 1. A wake-word turn with no speech closes without a word

private func falseWakeUnheardTests() {
    check(D.unheard(byWakeWord: true) == .closeQuietly && D.unheard(byWakeWord: false) == .notHeard,
          "false wake: a wake-word turn that heard nothing closes quietly; a key press or tap still says so")
    check(D.unheardLine(byWakeWord: true, korean: true) == nil && D.unheardLine(byWakeWord: true, korean: false) == nil,
          "false wake: the wake-word turn never reaches notHeard's line, in either language")
    check(D.unheardLine(byWakeWord: false, korean: true) == "못 들었어요" && D.unheardLine(byWakeWord: false, korean: false) == "I didn't catch that",
          "false wake: a key-press turn with nothing heard still says 못 들었어요 / I didn't catch that")
    // The soft tick at the end of listening ("I heard you"): never for a wake turn with no words, as before for a key turn.
    check(!D.ticks(byWakeWord: true, heardSoFar: "", voiceHeard: true) && !D.ticks(byWakeWord: true, heardSoFar: "아리스", voiceHeard: true)
          && !D.ticks(byWakeWord: true, heardSoFar: " 아리스. ", voiceHeard: true),
          "false wake: no tick for a wake turn that heard nothing but the name or noise")
    check(D.ticks(byWakeWord: true, heardSoFar: "아리스 날씨 알려 줘", voiceHeard: true) && D.ticks(byWakeWord: false, heardSoFar: "", voiceHeard: true)
          && !D.ticks(byWakeWord: false, heardSoFar: "", voiceHeard: false) && !D.ticks(byWakeWord: true, heardSoFar: "날씨", voiceHeard: false),
          "false wake: a wake turn with words ticks; a key turn ticks on voice as before; no voice, no tick")
    check(ArisConversation.EndReason.falseWake.rawValue == "false wake" && !ArisPendingFiles.clearedWhenConversationEnds(.falseWake),
          "false wake: the conversation it opened closes as a false wake, and files waiting for Aris stay")
}

// MARK: - 2. The borderline band

private func falseWakeBandTests() {
    let cut = D.strongCut(threshold: tonight)
    check(abs(cut - 10.7399) < 0.01 && abs(cut - tonight / 2.5) < 0.0001,
          "band: the strong cut is 0.4 × threshold (= the widest distance between the owner's own recordings): 10.74 tonight")
    // Tonight's sure wakes that were real and below the cut: instant, no check.
    for score: Float in [8.214, 9.281, 9.288, 9.936] {
        check(D.opening(score: score, threshold: tonight, interrupting: false) == .instant, "band: \(score) (real) opens at once, no check")
    }
    // The four false wakes, and the real ones in the same band: opened at once, checked by Whisper after.
    for score: Float in [12.23, 14.726, 15.004, 15.907, 14.791, 15.579, 15.976, 15.84] {
        check(D.opening(score: score, threshold: tonight, interrupting: false) == .checkAfterOpening, "band: \(score) opens, then Whisper checks it")
    }
    check(D.opening(score: cut, threshold: tonight, interrupting: false) == .instant
          && D.opening(score: cut + 0.01, threshold: tonight, interrupting: false) == .checkAfterOpening,
          "band: the cut itself is strong; just above it is checked")
    check(D.opening(score: 15.9, threshold: tonight, interrupting: true) == .instant,
          "band: a barge-in (Aris already stopped talking for it) is never checked again")
    check(D.opening(score: nil, threshold: tonight, interrupting: false) == .instant && D.opening(score: 15, threshold: nil, interrupting: false) == .instant,
          "band: no score or no model: nothing to doubt")
    // Near spellings count only when the voice print is fairly close: 0.8 × threshold (21.48 tonight).
    check(D.nearAllowed(score: 17.43, threshold: tonight) && D.nearAllowed(score: 21.4, threshold: tonight)
          && !D.nearAllowed(score: 21.77, threshold: tonight) && !D.nearAllowed(score: 23.7, threshold: tonight)
          && !D.nearAllowed(score: nil, threshold: tonight) && !D.nearAllowed(score: 15, threshold: nil),
          "band: a near spelling counts up to 0.8 × threshold, never without a voice print")
}

// MARK: - 2b. The check after opening (since music-wake: ArisWakeEvidence; sound going on never keeps it)

private func falseWakeAfterOpeningTests() {
    func after(_ whisper: String?, heard: String = "", voice: Bool = false, final: Bool = false, near: Bool = true) -> ArisWakeEvidence.Verdict {
        var evidence = ArisWakeEvidence(nearAllowed: near, playing: false)
        evidence.whisper = whisper.map(ArisWakeEvidence.Whisper.heard) ?? .unavailable
        evidence.said = ArisWakeWord.strippedCall(heard)
        evidence.voiceGoing = voice
        evidence.final = final
        return evidence.verdict
    }
    check(after("") == .close(.notAris) && after("감사합니다.") == .close(.notAris) && after("아이스 아메리카노") == .close(.notAris),
          "after opening: Whisper heard something else (or nothing) and nothing was said yet: the turn is cancelled")
    check(after("아리스") == .keep && after("Aris.") == .keep && after("어, 아리스") == .keep && after("Iris?") == .keep,
          "after opening: Whisper heard the name (or a near spelling with a close print): kept")
    check(after("Iris?", near: false) == .close(.notAris), "after opening: a near spelling without a close print isn't the name")
    check(after(nil) == .keep, "after opening: Whisper not ready: nothing is cancelled on a guess")
    check(after("", heard: "날씨 알려줘") == .judge && after("", voice: true) == .pending,
          "after opening: words after the name are judged, voice alone only waits for words (music-wake)")
    check(after("", heard: "  ") == .close(.notAris), "after opening: blank partial text isn't speech")
    check(after("", voice: true, final: true) == .close(.notAris), "after opening: a turn that stopped listening with no words closes quietly")
}

// MARK: - 3. Both outcomes logged, and in the wake log

private func falseWakeLogTests() {
    check(D.QuietEnd.nothingSaid.path == "quiet-close" && D.QuietEnd.notAris.path == "not-aris-after-open",
          "log: the two new wake-log path values")
    check(D.QuietEnd.nothingSaid.logLine == "wake word: closed quietly, nothing said"
          && D.QuietEnd.notAris.logLine == "wake word: not 아리스 after opening",
          "log: the two lines in the unified log")
    // The owner's own wake log (0600) keeps what Whisper wrote for every candidate, rejected ones too, for tuning.
    check(ArisWakeRest.kept("아이스", path: "rejected") == "아이스" && ArisWakeRest.kept("Iris", path: "not-aris-after-open") == "Iris"
          && ArisWakeRest.kept("아리스", path: "whisper") == "아리스" && ArisWakeRest.kept(nil, path: "voice") == "",
          "log: Whisper's text is kept for accepted and rejected candidates alike")
}

// MARK: - 5. The name check: a filler before it, near spellings, passing mentions still out

private func falseWakeNameTests() {
    let exact = ["아리스", "아리스.", "아리스 날씨", "Aris.", "aris", "헤이 아리스", "야 아리스", "아리스야",
                 "어, 아리스", "아 아리스", "음 아리스", "어 어 아리스", "Uh, Aris.", "hmm Aris", "어... 아리스"]
    for text in exact { check(ArisWakeWord.verified(text, nearAllowed: false), "name check: \"\(text)\" is the name") }
    let near = ["Arisa?", "아리사", "알리스", "어리스", "애리스", "에리스", "아리수", "아이리스", "앨리스", "Iris", "Iris?", "Alice.", "Ares", "アリス", "어, 알리스", "Uh, Alice"]
    for text in near {
        check(ArisWakeWord.verified(text, nearAllowed: true) && !ArisWakeWord.verified(text, nearAllowed: false),
              "name check: \"\(text)\" is a near spelling (only with a close voice print)")
    }
    let notName = ["아리스토텔레스", "오늘 아리스 봤어", "그거 아리스한테 물어봐", "앨리스한테 전화해", "아이스", "아이스 아메리카노", "감사합니다.",
                   "", "Paris", "Arizona", "Alicia", "어제 앨리스 만났어", "irish coffee", "아이리스한테"]
    for text in notName {
        check(!ArisWakeWord.verified(text, nearAllowed: true), "name check: \"\(text)\" is not a call")
    }
    // The strict pattern every turn uses to strip the name is unchanged; a wake turn strips the wider call.
    check(ArisWakeWord.heard("아리스 날씨") && !ArisWakeWord.heard("알리스 날씨") && ArisWakeWord.stripped("어, 아리스 메일 보내") == "어, 아리스 메일 보내",
          "name check: the turn's strict name is as before")
    check(ArisWakeWord.strippedCall("어, 알리스 날씨 알려 줘") == "날씨 알려 줘" && ArisWakeWord.strippedCall("아리스, 메일") == "메일"
          && ArisWakeWord.strippedCall("날씨 알려 줘") == "날씨 알려 줘" && ArisWakeWord.isOnlyTheCall("음, Iris.") && !ArisWakeWord.isOnlyTheCall("Iris 날씨"),
          "name check: a wake turn's words lose the call at their start, whatever spelling woke it")
}

// MARK: - 5b. The Whisper clip

private func falseWakeClipTests() {
    let rate = 16_000.0
    check(D.clipSeconds == ArisTranscript.shortestForWhisper && D.clipEnough(sampleRate: rate) == Int(rate * ArisTranscript.shortestForWhisper),
          "clip: the check waits for the 1.5 s Whisper reads (it read 1.2 s of audio and 0.3 s of padded zeros)")
    let enough = D.clipEnough(sampleRate: rate)
    check(ArisTranscript.paddedForWhisper([Float](repeating: 0.1, count: enough), sampleRate: rate).count == enough,
          "clip: a clip that long needs no zeros")
    check(D.clipWait >= .milliseconds(1500), "clip: the wait for it is long enough to fill it")
}

// MARK: - 6. Another app's sound: which app, and the wake word stays armed

private func falseWakeOtherAudioTests() {
    typealias O = ArisOtherAudio
    let me: Int32 = 1824
    let aris = O.Process(object: 1, pid: me, bundle: "com.lumenjsn.aris", output: false, input: true)
    let discord = O.Process(object: 2, pid: 2438, bundle: "com.hnc.Discord.helper", output: true, input: false)
    let spotify = O.Process(object: 3, pid: 1265, bundle: "com.spotify.client", output: true, input: false)
    let paused = O.pausedPlayers(nowPlaying: false)
    // Tonight's process list (read-only probe, 22:1x): Aris on the microphone, Discord's helper and Spotify with output open.
    check(O.culprits([aris, discord, spotify], ownPid: me, pausedPlayers: paused).isEmpty
          && !O.isPresent([aris, discord, spotify], ownPid: me, pausedPlayers: paused),
          "other audio: with no reading, Discord's always-open helper stream and a paused Spotify are not sound; Aris never counts")
    check(O.isPresent([discord], ownPid: me, outputLevel: 0.05) && O.culprits([aris, discord], ownPid: me, outputLevel: 0.05) == ["com.hnc.Discord.helper"],
          "other audio: Discord audibly playing still pauses listening, and says it was Discord")
    check(O.culprits([aris, spotify], ownPid: me, pausedPlayers: O.pausedPlayers(nowPlaying: true)) == ["com.spotify.client"]
          && O.culprits([.init(pid: 77, output: false, input: true)], ownPid: me) == ["pid 77"],
          "other audio: the log names the app (bundle id, else its pid)")
    check(O.culprits([aris, .init(pid: 5, bundle: "com.lumenjsn.aris.XPCHelper", output: true, input: true)], ownPid: me).isEmpty,
          "other audio: Aris's own processes are never named")
    typealias A = ArisWakeArm
    check(A.blocker(A.State(conversationOpen: true, otherAudio: true)) == nil
          && A.listensForName(conversationOpen: true, otherAudio: true) && !A.listensForName(conversationOpen: true, otherAudio: false)
          && A.listensForName(conversationOpen: false, otherAudio: false),
          "other audio: while another app plays, a conversation's listening for any voice pauses but the name still wakes Aris")
    check(A.blocker(A.State(conversationOpen: true, otherAudio: true, micInUse: true)) == .otherAudio,
          "other audio: another app recording (a call) still closes the microphone")
}

// MARK: - 5c. Whisper's check: the language, the name as its prompt, silence as no speech

private func falseWakeWhisperCheckTests() {
    check(D.checkLanguage(["ko", "en"]) == "ko" && D.checkLanguage(["en", "ko"]) == "en" && D.checkLanguage([]) == nil,
          "whisper check: in the first language turned on (it guessed English, Japanese, Russian for Korean: 3,673 of the wake log's 6,988 rejects were Latin script)")
    check(D.checkPrompt(language: "ko") == "아리스" && D.checkPrompt(language: "en") == "Aris" && D.checkPrompt(language: nil) == "Aris",
          "whisper check: the name is its prompt, spelled as that language writes it")
    typealias S = D.CheckedSegment
    check(D.checkedText([S(text: " 아리스", avgLogprob: -0.3)]) == "아리스", "whisper check: a confident name is read")
    check(D.checkedText([S(text: "Thank you.", avgLogprob: -0.2)]) == "" && D.checkedText([S(text: "ありがとうございました", avgLogprob: -0.4)]) == ""
          && D.checkedText([S(text: "시청해주셔서 감사합니다", avgLogprob: -0.3)]) == "" && D.checkedText([S(text: "-", avgLogprob: -0.3)]) == "",
          "whisper check: silence's subtitle phrases (1,167 \"Thank you.\" among the wake log's 6,988 rejects) are no speech")
    check(D.checkedText([S(text: "아리스", avgLogprob: -1.4)]) == "" && D.checkedText([]) == "",
          "whisper check: an unsure guess (average log-probability under -1, Whisper's own retry line) is no speech")
    check(D.checkedText([S(text: "아리스,", avgLogprob: -0.4), S(text: " 날씨", avgLogprob: -1.8)]) == "아리스,",
          "whisper check: only the confident pieces are kept")
}

// MARK: - 3. A second chance for a repeated call

private func falseWakeSecondChanceTests() {
    check(D.secondChance(lastRejectionAt: 100, now: 104.9) && !D.secondChance(lastRejectionAt: 100, now: 105.1)
          && !D.secondChance(lastRejectionAt: nil, now: 100) && !D.secondChance(lastRejectionAt: 100, now: 99),
          "second chance: for 5 s after a rejected candidate (tonight's repeats came 2–5 s apart)")
    check(D.nearAllowed(score: 24, threshold: tonight, secondChance: true) && !D.nearAllowed(score: 24, threshold: tonight, secondChance: false)
          && !D.nearAllowed(score: nil, threshold: tonight, secondChance: true),
          "second chance: a near spelling counts at any candidate score then (still never without a voice print)")
}

// MARK: - 6b. The meter: zeros are silence once the tap has heard anything this launch

private func falseWakeMeterTests() {
    typealias M = ArisMeterReading
    let zeros = M(startedAt: 100).reading(0, at: 100.5).reading(0, at: 101)
    check(zeros.level(at: 101) == nil && zeros.level(at: 101, tapProven: true) == 0,
          "meter: only zeros is unknown until the tap has read real sound once since launch; then it is silence")
    check(zeros.onlyZeros(at: 104) && !zeros.onlyZeros(at: 104, tapProven: true),
          "meter: a proven tap's zeros don't say the permission is missing")
    check(M(startedAt: 100).level(at: 100, tapProven: true) == nil, "meter: nothing read yet is still unknown")
    let zoom = ArisOtherAudio.Process(pid: 2438, bundle: "us.zoom.xos", output: true, input: false)
    check(!ArisOtherAudio.isPresent([zoom], ownPid: 1, outputLevel: zeros.level(at: 101, tapProven: true)),
          "meter: so an open but silent stream no longer pauses listening")
}

// MARK: - 5d. Barge-in over the speakers

private func falseWakeBargeInTests() {
    check(D.bargeInNeedsCheck(sure: true, headphones: false) && !D.bargeInNeedsCheck(sure: true, headphones: true)
          && D.bargeInNeedsCheck(sure: false, headphones: true),
          "barge-in: over the speakers Aris's own voice reaches the microphone, so even a sure match is checked by Whisper; with headphones it stops at once")
}

// MARK: - Wiring

private func falseWakeWiringTests() {
    let controller = wakeSource("Aris/private/Aris/ArisController.swift")
    let wake = wakeSource("Aris/private/Aris/ArisController+Wake.swift")
    let falseWake = wakeSource("Aris/private/Aris/ArisController+FalseWake.swift")
    let conversation = wakeSource("Aris/private/Aris/ArisController+Conversation.swift")
    check(controller.contains("switch ArisWakeDoubt.unheard(byWakeWord: turnByWakeWord)") && controller.contains("case .closeQuietly: return closeWakeTurnQuietly(.nothingSaid)")
          && controller.contains("case .notHeard: return notHeard()"),
          "wiring: an empty turn asks whether the wake word started it before saying 못 들었어요")
    check(controller.contains("ArisWakeDoubt.ticks(byWakeWord: turnByWakeWord, heardSoFar: session.heard, voiceHeard: lastVoiceAt != nil), ArisQuietLive.shared.heardUser()"),
          "wiring: the tick asks too")
    check(wake.contains("turnByWakeWord = true") && controller.contains("turnByWakeWord = false") && conversation.contains("turnByWakeWord = false"),
          "wiring: the wake word marks its turn; a key press and a conversation's voice turn don't")
    check(wake.contains("doubleCheckAfterOpening(detector: detector, score: score)")
          && falseWake.contains("self.settleWakeEvidence()") && wakeSource("Aris/private/Aris/ArisController+WakeEvidence.swift").contains("case .close(let end): closeWakeTurnQuietly(end)"),
          "wiring: a sure wake is opened, then checked; a no from Whisper closes it quietly")
    check(!falseWake.contains("failing(") && !falseWake.contains("ArisTranscript.notHeard") && !falseWake.contains("heardSound")
          && !falseWake.contains("remember(") && !falseWake.contains("recordTurn("),
          "wiring: the quiet close says nothing, plays nothing and keeps nothing in the history")
    check(falseWake.contains("ArisTuningLog.append(") && falseWake.contains("\"wake-log.jsonl\"") && falseWake.contains("end.logLine"),
          "wiring: both outcomes go to the unified log and the wake log")
    check(wake.contains("ArisWakeWord.verified(text, nearAllowed: near)") && wake.contains("ArisWakeDoubt.nearAllowed(score: score, threshold:"),
          "wiring: the wake check (recognizer and Whisper) reads the wider call, near spellings only with a close print")
    check(wake.contains("ArisWakeArm.listensForName(conversationOpen: self.conversation.isOpen, otherAudio: self.pausedForOtherAudio)"),
          "wiring: a candidate in a conversation paused for other audio is checked like an idle one")
    check(conversation.contains("ArisOtherAudio.culprits(") && conversation.contains("another app's audio: listening paused ("),
          "wiring: the pause names the app")
    let whisper = wakeSource("Aris/private/Aris/ArisWhisper.swift")
    check(whisper.contains("func checkName(") && whisper.contains("ArisWakeDoubt.checkedText(") && whisper.contains("promptTokens:")
          && whisper.contains("language: language") && whisper.contains("usePrefillPrompt: true"),
          "wiring: the wake check's Whisper runs in a set language, with the name as its prompt, confident pieces only")
    check(wake.contains("ArisWhisper.shared.checkName(") && falseWake.contains("ArisWhisper.shared.checkName(") && wake.contains("ArisWakeDoubt.bargeInNeedsCheck(")
          && wake.contains("lastWakeRejection"),
          "wiring: the wake check, the check after opening and the barge-in use it; a rejection opens the second chance")
    check(wakeSource("Aris/private/Aris/ArisOtherAudio.swift").contains("tapProven: Self.tapProven"),
          "wiring: the meter knows when its tap has proven itself")
}
