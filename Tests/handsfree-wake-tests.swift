// Tests for handsfree-wake (the owner, 2026-11-15). Live, deployed c985e451, their music playing:
// - "아리스, 어사이드 시켜…" got "보내기·지우기 같은 건 ⌥Space로 다시 말해 주면 할게요.": a wake turn over another app's audio was
//   hands-free, and hands-free turns refused every outward action. The user: "what is the point of calling it by name if it
//   then says to re-say it with ⌥Space?" No turn is hands-free any more; the risk gate and its cards stay.
// - While music played Aris kept waking without being called (prints 15.00, 16.27, 16.34; Whisper, prompted with the
//   name, wrote "아리스" over lyrics that had nothing like it) and every false wake paused the music. Over real
//   playback only a strong voice print wakes Aris (ArisWakeStrict), Whisper only vetoes, the text path never wakes, and
//   the music is paused only once the wake is kept.
// Called from main.swift.
import Foundation

private let handsFreeRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func handsFreeSource(_ path: String) -> String { (try? String(contentsOf: handsFreeRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runHandsFreeWakeTests() {
    handsFreeStrictLineTests()
    handsFreeAdmitTests()
    handsFreeEvidenceTests()
    handsFreeCardVoiceTests()
    handsFreeMusicPauseTests()
    handsFreeWiringTests()
}

private typealias S = ArisWakeStrict
private typealias HE = ArisWakeEvidence
/// The owner's model: threshold 26.85, sure below 16.11, the borderline cut 10.74.
private let owner: Float = 26.849787
/// 2026-11-15 18:11–18:28, real playback: the owner's own calls and the music's false wakes.
private let realCalls: [Float] = [10.92, 9.11, 12.29, 9.82]
private let musicWakes: [Float] = [14.78, 14.94, 15.00, 15.40, 15.86, 15.92, 15.99, 16.27, 16.34, 17.90, 19.73, 20.13]

// MARK: - The playback line

private func handsFreeStrictLineTests() {
    let line = S.playbackLine(threshold: owner)
    check(line != nil && abs(line! - 13.42) < 0.01, "strict line: half the threshold (13.42 for the owner's model)")
    check(S.playbackLine(threshold: nil) == nil, "strict line: no voice print, no line")
    check(realCalls.allSatisfy { S.isStrong(score: $0, threshold: owner) }, "strict line: every real call of the night is strong (≤ 12.29)")
    check(musicWakes.allSatisfy { !S.isStrong(score: $0, threshold: owner) }, "strict line: every music false wake is above it (≥ 14.78)")
    check(!S.isStrong(score: nil, threshold: owner) && !S.isStrong(score: 9, threshold: nil), "strict line: no score or no model is never strong")
    check(S.isStrong(score: line!, threshold: owner) && !S.isStrong(score: line! + 0.01, threshold: owner), "strict line: the line itself counts")
    let doubtful = ArisWakeDoubt.strongFraction * owner, sure = 0.6 * owner
    check(doubtful < line! && line! < sure, "strict line: between the borderline cut (10.74) and the sure line (16.11)")
}

// MARK: - What may wake Aris over real playback

private func handsFreeAdmitTests() {
    check(realCalls.allSatisfy { S.admits(playing: true, score: $0, threshold: owner) }, "admit: over playback the real calls wake Aris")
    check(musicWakes.allSatisfy { !S.admits(playing: true, score: $0, threshold: owner) },
          "admit: over playback no music false wake gets as far as a check (15.00, 16.27, 16.34 included)")
    check(!S.admits(playing: true, score: nil, threshold: nil), "admit: over playback, without a voice print nothing wakes Aris")
    check(musicWakes.allSatisfy { S.admits(playing: false, score: $0, threshold: owner) } && S.admits(playing: false, score: nil, threshold: nil),
          "admit: with nothing playing everything is as before")
    check(!S.textWakes(music: true, playing: false) && !S.textWakes(music: false, playing: true) && !S.textWakes(music: true, playing: true),
          "admit: over music or playback Whisper's or the recognizer's text alone never wakes Aris")
    check(S.textWakes(music: false, playing: false), "admit: in a quiet room the text path wakes as before")
}

// MARK: - The evidence: the voice print decides, Whisper only vetoes

private func strictEvidence(_ whisper: HE.Whisper, score: Float, music: Bool = false, playing: Bool = false, said: String = "") -> HE {
    var e = HE(nearAllowed: ArisWakeDoubt.nearAllowed(score: score, threshold: owner), playing: playing,
               strongPrint: S.isStrong(score: score, threshold: owner))
    e.whisper = whisper
    e.music = music
    e.said = said
    return e
}

private func handsFreeEvidenceTests() {
    // 18:22:08: the owner's 12.29 over his music; Whisper read the name.
    check(strictEvidence(.heard("아리스"), score: 12.29, playing: true).verdict == .keep, "evidence: 12.29 over playback, the name read: kept")
    check(strictEvidence(.unavailable, score: 12.29, playing: true).verdict == .keep, "evidence: a strong print over playback with no Whisper: kept")
    check(strictEvidence(.heard("어 알리스"), score: 12.29, playing: true).verdict == .keep, "evidence: a strong print and a near spelling: no veto")
    check(strictEvidence(.heard("사랑해 오늘 밤"), score: 12.29, playing: true).verdict == .close(.playing)
          && strictEvidence(.heard("사랑해 오늘 밤"), score: 12.29, music: true).verdict == .close(.music),
          "evidence: Whisper heard something else: it vetoes even a strong print")
    check(strictEvidence(.heard(""), score: 12.29, playing: true).verdict == .close(.playing), "evidence: Whisper heard nothing of the name: a veto")
    check(strictEvidence(.waiting, score: 12.29, playing: true).verdict == .pending, "evidence: waits for Whisper")
    // 18:25:24: 15.00 over the music, Whisper "read it" (the prompt's own word): kept, then nothing said. Never again.
    check(strictEvidence(.heard("아리스"), score: 15.00, playing: true).verdict == .close(.playing)
          && strictEvidence(.heard("아리스"), score: 15.00, music: true).verdict == .close(.music),
          "evidence: over music or playback Whisper's name never keeps a print above the line (15.00)")
    check(strictEvidence(.heard("아리스"), score: 14.78, music: true, said: "내일 알람 맞춰줘").verdict == .close(.music),
          "evidence: nor do words after it")
    // Nothing playing and no music: as before.
    check(strictEvidence(.heard("아리스"), score: 15.00).verdict == .keep && strictEvidence(.unavailable, score: 15.00).verdict == .keep,
          "evidence: in a quiet room a borderline wake is as before")
    check(strictEvidence(.heard("감사합니다"), score: 15.00).verdict == .close(.notAris), "evidence: in a quiet room Whisper's no still closes")
    check(HE(nearAllowed: false, playing: true).strongPrint == false, "evidence: a print is not strong unless the check says so")
}

// MARK: - Cards: a spoken answer counts on every card

private func handsFreeCardVoiceTests() {
    typealias R = ArisConfirmReply
    check(R.voiceYes(inConversation: true, handsFree: false) && R.voiceYes(inConversation: false, handsFree: false),
          "cards: a spoken yes counts in a conversation too (the user: answered by voice)")
    check(R.spoken("응", voiceYes: R.voiceYes(inConversation: true, handsFree: false)) == true, "cards: \"응\" in a conversation is a yes")
    check(R.spoken("보내", voiceYes: true) == true && R.spoken("보내 줘", voiceYes: true) == true && R.spoken("응 보내", voiceYes: true) == true,
          "cards: \"보내\" is a yes")
    check(R.spoken("보내지 마", voiceYes: true) == false && R.spoken("아니", voiceYes: true) == false && R.spoken("아니 보내지 마", voiceYes: true) == false,
          "cards: \"보내지 마\" and \"아니\" are a no")
    check(R.spoken("보내는 거 맞아?", voiceYes: true) == nil && R.spoken("엄마한테 보내", voiceYes: true) == nil && R.spoken("안 보내", voiceYes: true) != true,
          "cards: a sentence that merely has 보내 in it is no yes")
}

// MARK: - The music is touched only once the wake is kept

private func handsFreeMusicPauseTests() {
    check(S.pausesMusic(lap: .heard) && !S.pausesMusic(lap: .waiting) && !S.pausesMusic(lap: .unheard) && !S.pausesMusic(lap: nil),
          "music: paused when the lap is heard (the wake kept), never while it waits or when it ends unheard")
    var held = ArisQuietWake(wokeAt: 0, held: true)
    held.level(voice: false, at: 0.2)
    held.level(voice: false, at: 0.4)
    held.level(voice: true, at: 0.5)
    held.level(voice: true, at: 0.6)
    check(held.spoke && held.state == .waiting, "music: the vocals were heard while held")
    check(!S.pausesMusic(lap: held.state), "music: a borderline wake's vocals while its evidence waits never pause the music")
    held.release()
    check(S.pausesMusic(lap: held.state), "music: paused once its evidence keeps it")
    var silent = ArisQuietWake(wokeAt: 0)
    silent.tick(at: ArisQuietWake.lap)
    check(!S.pausesMusic(lap: silent.state), "music: a lap that ends with nothing never touched the music")
}

// MARK: - Wiring

private func handsFreeWiringTests() {
    let wake = handsFreeSource("Aris/private/Aris/ArisController+Wake.swift")
    let controller = handsFreeSource("Aris/private/Aris/ArisController.swift")
    let conversation = handsFreeSource("Aris/private/Aris/ArisController+Conversation.swift")
    let wakeBody = wake.components(separatedBy: "func wake(_ listener: ArisListener").last ?? ""
    check(!wakeBody.contains("pauseMusic()") && !wakeBody.contains("otherAudioPresent("),
          "wiring: wake() no longer pauses the music nor reads other audio up front")
    check(wakeBody.contains("turnHandsFree = false") && !wake.contains("wakeTurnIsHandsFree"), "wiring: a wake turn is never hands-free")
    check(conversation.contains("turnHandsFree = false") && !conversation.contains("turnHandsFree = true"),
          "wiring: a conversation's follow-up is not hands-free either")
    check(wake.contains("ArisWakeStrict.admits(playing: playing, score: score, threshold: threshold)"),
          "wiring: over playback the check turns a weak print away before anything listens")
    check(wake.contains("ArisWakeStrict.textWakes(music: heardMusic, playing: playing)"), "wiring: the Whisper path never wakes over music")
    check(wake.contains("strongPrint: ArisWakeStrict.isStrong(score: score, threshold: threshold)"), "wiring: the evidence knows the print")
    check(controller.contains("if ArisWakeStrict.pausesMusic(lap: wakeLap), oldValue != wakeLap, turnByWakeWord { pauseMusic() }"),
          "wiring: the music pauses when the wake's lap is heard")
    let kept = controller.range(of: "if turnByWakeWord { pauseMusic() }")
    let answer = controller.range(of: "await answer(gesture == nil ? session.heard : text, gesture: gesture)")
    check(kept != nil && answer != nil && kept!.lowerBound < answer!.lowerBound, "wiring: a kept wake's request pauses the music before it is answered")
}
