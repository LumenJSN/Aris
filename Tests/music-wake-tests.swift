// Tests for music-wake (the owner, 2026-11-15): a song, the TV or someone else talking that falsely wakes Aris keeps
// going after the call. Its vocals were taken for the user starting to talk: the quiet lap opened the notch, the check after
// opening kept the turn ("he is still talking"), and the lyrics went to the AI as a request. Now a borderline wake waits
// for evidence that it was the user calling Aris (ArisWakeEvidence): Whisper hearing the name, or words judged a request to
// the assistant (ArisWakeAddressed); over music (ArisWakeMusic) or this Mac's own playback only the name itself counts.
// Called from main.swift.
import AVFoundation
import Foundation

private let musicRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func musicSource(_ path: String) -> String { (try? String(contentsOf: musicRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runMusicWakeTests() {
    musicWakeHoleTests()
    musicWakeRealCallTests()
    musicWakeVerdictTests()
    musicWakeStrictTests()
    musicWakeJudgeTests()
    musicWakeShortRequestTests()
    musicWakePlayingTests()
    musicWakeServerNoteTests()
    musicWakeLapTests()
    musicWakeClassifierTests()
    musicWakeClassifierLiveTests()
    musicWakeLogTests()
    musicWakeWiringTests()
}

private typealias D = ArisWakeDoubt
private typealias E = ArisWakeEvidence
private typealias Q = ArisQuietWake
/// The owner's model on 2026-11-14: threshold 26.85, sure below 16.11, the strong cut 10.74.
private let tonight: Float = 26.849787

/// A borderline wake's evidence as the controller builds it.
private func evidence(whisper: E.Whisper, said: String = "", music: Bool = false, playing: Bool = false, voice: Bool = false,
                      final: Bool = false, judged: E.Judged? = nil, score: Float = 14.73) -> E {
    var e = E(nearAllowed: D.nearAllowed(score: score, threshold: tonight), playing: playing)
    e.whisper = whisper
    e.music = music
    e.said = ArisWakeWord.strippedCall(said)
    e.voiceGoing = voice
    e.final = final
    if let judged { e.judged = .init(text: e.said, verdict: judged) }
    return e
}

/// Voiced readings every 43 ms from `from` to `to` (a song's vocals: never a pause), with the lap's tick.
private func sing(_ lap: inout Q, from: Double, to: Double) {
    var t = from
    while t < to { lap.level(voice: true, at: t); lap.tick(at: t); t += 0.043 }
}

// MARK: - 1. The hole: a doubtful wake, Whisper "not 아리스", then a song's vocals going on

private func musicWakeHoleTests() {
    let score: Float = 14.73
    check(D.opening(score: score, threshold: tonight, interrupting: false) == .checkAfterOpening,
          "hole: 14.73 is in the doubtful band (opened at once, checked by Whisper after)")
    var lap = Q(wokeAt: 0, held: true)
    sing(&lap, from: 0, to: Q.lap)
    check(lap.state == .waiting && lap.spoke, "hole: a song's vocals after a doubtful wake don't open the notch (heard only as a note, the lap waits)")
    sing(&lap, from: Q.lap, to: Q.lap + 2)
    check(lap.state == .waiting, "hole: … and the song going on past the lap still doesn't open it")
    let song = "아리스 사랑해 너를 사랑해 이 밤이 지나도"
    check(evidence(whisper: .heard("사랑해 너를"), said: song, music: true, voice: true).verdict == .close(.music),
          "hole: over music, Whisper not hearing the name closes it quietly however much is sung")
    check(evidence(whisper: .heard("사랑해 너를"), said: song, voice: true).verdict == .judge,
          "hole: without music read (a voice alone), the words go to the judge, never kept just because they go on")
    check(evidence(whisper: .heard("사랑해 너를"), said: song, voice: true, final: true, judged: .notAddressed).verdict == .close(.notAddressed),
          "hole: the judge says the lyrics aren't for Aris: closed quietly at the turn's end, before anything is asked")
    check(evidence(whisper: .heard("지금부터 오늘의"), said: "지금부터 오늘의 주요 뉴스를 전해드리겠습니다", final: true, judged: .notAddressed).verdict == .close(.notAddressed),
          "hole: the TV news reader likewise")
}

// MARK: - 2. A real call stays open

private func musicWakeRealCallTests() {
    // The name misheard by Whisper, then the user's request: judged a request, kept, the held lap lets go and the notch opens.
    let call = "아리스 내일 아침 일곱 시에 알람 맞춰줘"
    check(evidence(whisper: .heard("아이스"), said: call, voice: true).verdict == .judge,
          "real call: Whisper misheard the name; the words go to the judge")
    check(evidence(whisper: .heard("아이스"), said: call, voice: true, judged: .addressed).verdict == .keep
          && evidence(whisper: .heard("아이스"), said: call, final: true, judged: .addressed).verdict == .keep,
          "real call: judged a request: kept, during the turn and at its end")
    var lap = Q(wokeAt: 0, held: true)
    sing(&lap, from: 0, to: 1.4)
    check(lap.state == .waiting, "real call: the user talking while the evidence is out: the notch waits")
    check(lap.release() == .heard, "real call: kept: the notch opens at once")
    check(E.judgeable(ArisWakeWord.strippedCall(call)) && !E.judgeable("불") && E.judgeable("다음 곡이"),
          "real call: four letters are enough to judge during the turn")
    // Whisper heard the name: kept straight away, nothing to judge.
    check(evidence(whisper: .heard("아리스"), said: call).verdict == .keep && evidence(whisper: .heard("어, 아리스")).verdict == .keep,
          "real call: Whisper heard the name: kept")
    // A key press ends the turn: it vouches (the controller keeps the wake).
    check(musicSource("Aris/private/Aris/ArisController.swift").contains("case .finish:\n            vouchForWakeTurn()\n            stopListening()"),
          "real call: a key press that ends the turn vouches for it, as before")
}

// MARK: - 3. The verdict's rules

private func musicWakeVerdictTests() {
    check(evidence(whisper: .waiting, said: "내일", voice: true).verdict == .pending && evidence(whisper: .waiting, final: true).verdict == .pending,
          "verdict: nothing is decided before Whisper's check is back (the turn's end waits for it, at most 3 s)")
    check(E.whisperWait == .seconds(3), "verdict: the end waits for Whisper at most 3 s")
    check(evidence(whisper: .unavailable, said: "사랑해 너를").verdict == .keep,
          "verdict: Whisper not on this Mac: nothing decided on a guess, as before")
    check(evidence(whisper: .heard(""), voice: true).verdict == .pending && evidence(whisper: .heard("")).verdict == .close(.notAris),
          "verdict: no words yet: voice going waits for words, silence closes")
    check(evidence(whisper: .heard("아이스"), said: "내일 아침", judged: .notAddressed).verdict == .pending,
          "verdict: cut-off words judged not addressed during the turn decide nothing (\"내일 아침\" was 'other')")
    var stale = evidence(whisper: .heard("아이스"), said: "내일 아침", judged: .notAddressed)
    stale.said = "내일 아침 일곱 시에 알람"
    check(stale.verdict == .judge, "verdict: a judgement holds only for the words it read; new words are judged again")
    check(evidence(whisper: .heard("아이스"), said: "내일 아침 일곱 시", judged: .unknown).verdict == .pending
          && evidence(whisper: .heard("아이스"), said: "내일 아침 일곱 시", final: true, judged: .unknown).verdict == .close(.notAddressed),
          "verdict: no judge in time and no name in Whisper's text: closed at the end")
    check(evidence(whisper: .heard("그래서 아리스가"), said: "내일 아침 일곱 시", final: true, judged: .unknown).verdict == .keep
          && evidence(whisper: .heard("그래서 아리스가")).whisperNamesAris && !evidence(whisper: .heard("파리스 여행")).whisperNamesAris
          && evidence(whisper: .heard("Hey ARIS what")).whisperNamesAris && !evidence(whisper: .heard("Paris")).whisperNamesAris,
          "verdict: no judge in time, but the name somewhere in Whisper's text: kept")
    check(evidence(whisper: .heard("Iris")).verdict == .keep && evidence(whisper: .heard("Iris"), score: 23).verdict == .close(.notAris),
          "verdict: a near spelling counts with a close print only, as before")
}

// MARK: - 4. Over music or this Mac's playback only the name itself counts

private func musicWakeStrictTests() {
    // 2026-11-15: over music Whisper writes the name it was prompted with; only a strong print keeps (handsfree-wake-tests).
    check(evidence(whisper: .heard("아리스"), music: true).verdict == .close(.music) && evidence(whisper: .heard("아리스"), playing: true).verdict == .close(.playing),
          "strict: Whisper's name alone doesn't keep a print past the playback line over music or playback")
    check(evidence(whisper: .heard("Iris"), music: true).verdict == .close(.music) && evidence(whisper: .heard("Iris"), playing: true).verdict == .close(.playing),
          "strict: a near spelling doesn't count over music or playback")
    check(evidence(whisper: .unavailable, music: true).verdict == .close(.music) && evidence(whisper: .unavailable, said: "다음 곡", playing: true).verdict == .close(.playing),
          "strict: no Whisper over music or playback: closed (the name must be in Whisper's text)")
    check(evidence(whisper: .heard("아이스"), said: "내일 아침 일곱 시에 알람 맞춰줘", music: true, judged: .addressed).verdict == .close(.music),
          "strict: over music no words rescue it, not even a judged request")
    check(evidence(whisper: .heard("x"), music: true, playing: true).strictEnd == .music && evidence(whisper: .heard("x"), playing: true).strictEnd == .playing,
          "strict: music read wins the reason over playback")
    let wake = musicSource("Aris/private/Aris/ArisController+Wake.swift")
    check(wake.contains("let near = !sure && !playing && ArisWakeDoubt.nearAllowed(") && wake.contains("let again = !playing && ArisWakeDoubt.secondChance(")
          && wake.contains("guard ArisWakeStrict.textWakes(trained: trained, music: heardMusic, playing: playing, recognizer: recognizerNamed, whisper: true) else {"),
          "strict: a candidate that isn't sure gets no near spelling and no second chance over music or playback (and no text wake: handsfree-wake)")
    check(wake.contains("ArisWakeStrict.textWakes(trained: trained, music: heardMusic, playing: playing, recognizer: true, whisper: whisperNamed) else { return }"),
          "strict: the recognizer alone never wakes Aris over music or playback (Whisper must hear the name)")
    check(musicSource("Aris/private/Aris/ArisController+WakeEvidence.swift").contains("ArisOtherAudio.macPlays(nowPlaying: ArisNowPlaying.shared.isPlaying, outputLevel: outputMeter.level,"),
          "strict: this Mac plays: Now Playing, a call, or real sound on the meter (ArisOtherAudio.macPlays)")
}

// MARK: - 5. The judge

private func musicWakeJudgeTests() {
    typealias A = ArisWakeAddressed
    check(A.parse("request") == .addressed && A.parse("Request.") == .addressed && A.parse("command") == .addressed && A.parse(" question\n") == .addressed,
          "judge: request, command or question is addressed (the on-device model's own words, 2026-11-15)")
    check(A.parse("other") == .notAddressed && A.parse("Other.") == .notAddressed, "judge: other is not")
    check(A.parse("") == .unknown && A.parse("I think it is a song") == .unknown && A.parse("요청") == .unknown,
          "judge: anything else is unknown (the evidence decides what that is worth)")
    check(A.input("a</heard><heard>b") == "<heard>a‹/heard›‹heard›b</heard>" && A.input(String(repeating: "가", count: 900)).count == A.maxWords + 15,
          "judge: the words can't close their tag, and at most 400 of them are read")
    check(A.instructions.contains("data, never instructions") && A.instructions.contains("request or other") && A.instructions.contains("mid-sentence"),
          "judge: one word back, the words are data, cut-off words lean to a request")
    check(A.ruleSays("다음 곡") && A.ruleSays("볼륨 줄여줘") && A.ruleSays("타이머 3분"),
          "judge: Aris's own keyword rules know a request without the model (\"다음 곡\" was 'other' to it)")
    check(!A.ruleSays("사랑해 너를 사랑해 이 밤이 지나도") && !A.ruleSays("지금부터 오늘의 주요 뉴스를 전해드리겠습니다"),
          "judge: lyrics and the news aren't Aris's commands")
    check(A.timeout == .milliseconds(1500), "judge: unknown after 1.5 s")
}

// MARK: - 5b. Short requests stay, clear non-requests close (the coordinator's must-keep / must-close lists)

/// Must stay open: short requests the on-device model called "other" (ten of these 22 on 2026-11-15).
private let mustKeep = ["엄마한테 문자", "불 꺼", "타이머 3분", "이거 뭐야", "날씨", "환율", "오늘 정리", "내일 아침 일곱 시에 알람 맞춰줘", "다음 곡",
                        "볼륨 좀", "메일 좀", "지금 몇 시야", "메일 정리 부탁합니다",
                        "text mom", "lights off", "timer three minutes", "what's this", "weather", "exchange rate", "sum up today",
                        "what time is it", "next song", "set an alarm for seven"]
/// Must close: lyrics, the TV, a video's outro, people talking. The rule never keeps them; the clear ones it closes
/// itself, the rest go to the model (which called each of these "other"). "날 안아줘 꼭 안아줘 오늘 밤만" is the known
/// miss: short with a request's ending, it is kept (the model too called it a request).
private let mustClose = ["사랑해 너를 사랑해 이 밤이 지나도", "그대 내 품에 안겨 눈을 감아요", "나는 너를 원해 너만을 원해", "오늘 밤은 너와 함께 춤을 춰",
                         "야 너 어제 그 드라마 봤어? 완전 대박이던데", "지금부터 오늘의 주요 뉴스를 전해드리겠습니다", "자 이제 다음 소식입니다",
                         "구독과 좋아요 부탁드려요", "그래서 내가 말했잖아 걔가 먼저 했다고", "baby I love you I need you tonight",
                         "and then he told her that he was leaving town", "welcome back to the channel today we are looking at"]

private func musicWakeShortRequestTests() {
    typealias A = ArisWakeAddressed
    let kept = mustKeep.filter { A.byRule($0) == .addressed }
    check(kept.count == mustKeep.count, "short requests: every must-keep phrase is a request by rule, no model needed (\(kept.count)/\(mustKeep.count); missed: \(mustKeep.filter { A.byRule($0) != .addressed }))")
    let keptWrongly = mustClose.filter { A.byRule($0) == .addressed }
    check(keptWrongly.isEmpty, "short requests: the rule keeps no must-close phrase (kept: \(keptWrongly))")
    check(A.byRule("지금부터 오늘의 주요 뉴스를 전해드리겠습니다") == .notAddressed && A.byRule("자 이제 다음 소식입니다") == .notAddressed
          && A.byRule("구독과 좋아요 부탁드려요") == .notAddressed && A.byRule("thanks for watching see you next time") == .notAddressed,
          "short requests: narration and a video's outro close without the model")
    check(A.byRule("사랑해 너를 사랑해 이 밤이 지나도") == nil && A.byRule("baby I love you I need you tonight") == nil,
          "short requests: lyrics go to the model (it calls them other)")
    check(A.byRule("날 안아줘 꼭 안아줘 오늘 밤만") == .addressed, "short requests: the known miss, a short lyric with a request's ending, is kept")
    check(!A.looksLikeRequest("오늘 밤은 너와 함께 춤을 춰 줘") && A.looksLikeRequest("불 좀 꺼 줘"),
          "short requests: the lean is for six words or fewer only")
    check(!A.clearlyNot("메일 정리 부탁합니다"), "short requests: a polite 부탁합니다 is not narration")
}

// MARK: - 5c. This Mac playing: an open stream alone never counts

private func musicWakePlayingTests() {
    typealias O = ArisOtherAudio
    let own: Int32 = 100
    let spotifyPaused = O.Process(pid: 1, bundle: "com.spotify.client", output: true, input: false)
    let discord = O.Process(pid: 2, bundle: "com.hnc.Discord", output: true, input: false)
    let aside = O.Process(pid: 3, bundle: "at.studio.AsideBrowser", output: true, input: false)
    let browser = O.Process(pid: 4, bundle: "com.google.Chrome", output: true, input: false)
    let call = O.Process(pid: 5, bundle: "us.zoom.xos", output: true, input: true)
    check(!O.macPlays(nowPlaying: false, outputLevel: nil, [spotifyPaused], ownPid: own),
          "playing: Spotify open but paused, no meter: not strict")
    check(!O.macPlays(nowPlaying: false, outputLevel: nil, [spotifyPaused, discord, aside, browser], ownPid: own),
          "playing: idle open streams (Spotify, Discord, Aside, a browser) never turn strict mode on")
    check(!O.macPlays(nowPlaying: false, outputLevel: 0, [browser], ownPid: own) && !O.macPlays(nowPlaying: false, outputLevel: 0.002, [browser], ownPid: own),
          "playing: a meter reading silence (or under the audible line) isn't playing")
    check(O.macPlays(nowPlaying: true, outputLevel: nil, [], ownPid: own), "playing: Now Playing says something plays")
    check(O.macPlays(nowPlaying: false, outputLevel: 0.05, [browser], ownPid: own), "playing: the meter reads real sound from another app")
    check(O.macPlays(nowPlaying: false, outputLevel: nil, [call], ownPid: own), "playing: a call (another app records) counts")
    check(!O.macPlays(nowPlaying: false, outputLevel: 0.05, [O.Process(pid: own, bundle: "com.lumenjsn.aris", output: true, input: true)], ownPid: own),
          "playing: Aris's own sound and microphone never count")
    var paused = ArisWakeEvidence(nearAllowed: true, playing: O.macPlays(nowPlaying: false, outputLevel: nil, [spotifyPaused], ownPid: own))
    paused.whisper = .heard("Iris")
    check(!paused.strict && paused.verdict == .keep, "playing: with Spotify paused a near spelling with a close print still passes")
}

// MARK: - 5d. 부르기's note says where the wake check hears

private func musicWakeServerNoteTests() {
    typealias H = ArisWakeHonesty
    check(H.note(trained: true, collecting: false, server: false) == H.note && H.note.contains("아무것도 보내지 않으며"),
          "note: on this Mac's own engine, nothing leaves the Mac")
    let server = H.note(trained: true, collecting: false, server: true)
    check(server == H.noteServer && server.contains("Apple 서버") && server.contains("Apple로 가고") && !server.contains("보내지 않"),
          "note: on the older engine with no on-device model, it says a possible call's sound goes to Apple")
    check(H.note(trained: false, collecting: false, server: true).hasSuffix(H.untrained) && H.note(trained: true, collecting: true, server: true) == H.noteCollectingServer
          && !H.noteCollectingServer.contains("보내지 않") && H.noteCollectingServer.contains("Aris 폴더에만"),
          "note: untrained and collecting say it too")
    for key in [H.noteServer, H.noteServerUntrained, H.noteCollectingServer, H.noteCollectingServerUntrained] {
        check(ArisSettingsCopyMore.english[key] != nil && !(ArisSettingsCopyMore.english[key] ?? "").contains("nothing is sent"),
              "note: its English is found and true (\(key.prefix(12))…)")
    }
    check(!H.serverHearing && H.note(trained: true, collecting: false) == H.note, "note: the default reads the live setting (off in the tests)")
    let live = musicSource("Aris/components/Settings/ArisLiveSettings.swift")
    let locale = musicSource("Aris/private/Aris/ArisListener+Locale.swift")
    check(live.contains("ArisWakeHonesty.serverHearing = ArisHearingShown.wakeCheckOnServer()")
          && locale.contains("engine == .legacy && ArisSFSpeechTasks.place(ArisHearing.locale) == .server"),
          "note: chosen at runtime from the engine that would hear the wake check")
    check(musicSource("Aris/components/Settings/ArisSettingsBuilder.swift").contains("ArisWakeHonesty.note(trained: s.hasVoiceModel, collecting: s.wakeRecord.collecting)"),
          "note: the Settings builder is unchanged")
}

// MARK: - 6. The held lap

private func musicWakeLapTests() {
    var silent = Q(wokeAt: 0, held: true)
    var t = 0.0
    while t < Q.lap + 0.05 { silent.level(voice: false, at: t); silent.tick(at: t); t += 0.043 }
    check(silent.state == .unheard, "held lap: nothing said for the whole lap still ends the turn quietly")
    var late = Q(wokeAt: 0, held: true)
    sing(&late, from: 0, to: Q.lap + 0.5)
    check(late.state == .waiting, "held lap: something heard keeps it waiting past the lap, for the evidence")
    check(late.release() == .heard, "held lap: kept after the lap: the notch opens then")
    var early = Q(wokeAt: 0, held: true)
    early.level(voice: false, at: 0.1)
    check(early.release() == .waiting && !early.held, "held lap: kept before anything was said: the lap goes on as any other")
    early.level(voice: false, at: 0.3)
    early.level(voice: true, at: 1.2)
    early.level(voice: true, at: 1.25)
    check(early.level(voice: true, at: 1.3) == .heard, "held lap: … and the user's voice then opens it as before")
    var words = Q(wokeAt: 0, saidMore: true, held: true)
    check(words.state == .waiting && words.spoke, "held lap: words with the call are noted, not opened")
    check(words.release() == .heard, "held lap: … and open once kept")
    var wordsLate = Q(wokeAt: 0, held: true)
    sing(&wordsLate, from: 0, to: Q.lap + 0.2)
    check(wordsLate.words(at: Q.lap + 0.3) == .waiting, "held lap: words after the lap's end still wait for the evidence")
    check(Q(wokeAt: 0).held == false && Q(wokeAt: 0, saidMore: true).state == .heard,
          "held lap: a wake that isn't borderline is never held (very close wakes unchanged)")
}

// MARK: - 7. The classifier's rule

private func musicWakeClassifierTests() {
    typealias M = ArisWakeMusic
    check(M.labels == ["music", "singing", "choir_singing", "rapping", "yodeling"] && !M.labels.contains("humming") && !M.labels.contains("speech"),
          "music: the built-in classifier's music labels; humming and speech aren't music")
    let speech: [String: Double] = ["speech": 0.95, "music": 0.28, "singing": 0.41, "humming": 0.9]
    let song: [String: Double] = ["speech": 0.7, "music": 0.59, "singing": 0.07]
    check(M.score(speech) == 0.41 && M.score(song) == 0.59, "music: a window's score is its surest music label")
    check(!M.isMusic([speech, speech, speech, speech]) && M.isMusic([speech, song, speech, song]) && !M.isMusic([speech, song, speech]),
          "music: two windows over the line make music, one does not")
    check(M.isMusic([song]) && !M.isMusic([]) && !M.isMusic([speech]), "music: a single window read decides alone")
    check(M.tail(Array(repeating: 0, count: 200_000), sampleRate: 16_000).count == 64_000 && M.tail([1, 2], sampleRate: 16_000) == [1, 2],
          "music: it reads the last 4 s the detector holds")
    let source = musicSource("Aris/private/Aris/ArisWakeMusic.swift")
    check(source.contains("SNClassifySoundRequest(classifierIdentifier: .version1)") && !source.contains("installTap") && !source.contains("AVAudioEngine"),
          "music: Apple's built-in classifier on the detector's own samples: no new microphone tap")
}

/// A few seconds of synthetic music: chords with harmonics, a melody, a kick drum and a hi-hat (seeded noise).
private func syntheticMusic(seconds: Double, rate: Double = 16_000) -> [Float] {
    var seed: UInt32 = 12345
    func noise() -> Double { seed = seed &* 1_664_525 &+ 1_013_904_223; return Double(seed) / Double(UInt32.max) * 2 - 1 }
    let chords: [[Double]] = [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]]
    let melody: [Double] = [523.3, 587.3, 659.3, 587.3, 523.3, 440.0, 392.0, 440.0]
    return (0..<Int(seconds * rate)).map { i in
        let t = Double(i) / rate
        var v = 0.0
        for f in chords[Int(t) % 4] { for h in 1...4 { v += sin(2 * .pi * f * Double(h) * t) / Double(h * h) } }
        let m = melody[Int(t / 0.25) % melody.count]
        v += 0.8 * exp(-t.truncatingRemainder(dividingBy: 0.25) * 6) * (sin(2 * .pi * m * t) + 0.4 * sin(4 * .pi * m * t))
        let beat = t.truncatingRemainder(dividingBy: 0.5)
        v += 1.5 * exp(-beat * 30) * sin(2 * .pi * (60 + 80 * exp(-beat * 40)) * t)
        v += 0.3 * exp(-(t + 0.25).truncatingRemainder(dividingBy: 0.5) * 80) * noise()
        return Float(v * 0.08)
    }
}

/// A file `say` writes (it doesn't play), read back at 16 kHz mono; nil when the voice isn't on this Mac.
private func spoken(_ text: String, voice: String) -> [Float]? {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("aris-music-wake-\(UUID().uuidString).aiff")
    defer { try? FileManager.default.removeItem(at: file) }
    let say = Process()
    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-v", voice, "-o", file.path, text]
    guard (try? say.run()) != nil else { return nil }
    // The speech service can stall for good (it held a whole suite for 90 minutes once); a line takes a second or two.
    let limit = Date().addingTimeInterval(30)
    while say.isRunning, Date() < limit { Thread.sleep(forTimeInterval: 0.05) }
    if say.isRunning { say.terminate() }
    say.waitUntilExit()
    guard say.terminationStatus == 0, let audio = try? AVAudioFile(forReading: file),
          let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
          let converter = AVAudioConverter(from: audio.processingFormat, to: format),
          let input = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)),
          (try? audio.read(into: input)) != nil,
          let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(audio.length) * 16_000 / audio.processingFormat.sampleRate) + 1024) else { return nil }
    var given = false
    converter.convert(to: output, error: nil) { _, status in
        if given { status.pointee = .endOfStream; return nil }
        given = true
        status.pointee = .haveData
        return input
    }
    guard let channel = output.floatChannelData?[0] else { return nil }
    return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
}

private func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
}

// MARK: - 8. The classifier on synthetic sound (files only: nothing is played, no microphone)

private func musicWakeClassifierLiveTests() {
    typealias M = ArisWakeMusic
    let music = syntheticMusic(seconds: 4)
    guard M.classify(Array(music.prefix(16_000)), sampleRate: 16_000) != nil else {
        return check(true, "music (live): SoundAnalysis can't run here: skipped")
    }
    let before = cpuSeconds()
    let heardMusic = M.heard(in: music)
    let cpu = Int((cpuSeconds() - before) * 1000)
    check(heardMusic, "music (live): four seconds of synthetic music are music (\(cpu) ms CPU for 4 s)")
    check(cpu < 400, "music (live): one read costs little CPU (\(cpu) ms for 4 s)")
    var seed: UInt32 = 7
    let hiss = (0..<64_000).map { _ -> Float in seed = seed &* 1_664_525 &+ 1_013_904_223; return (Float(seed) / Float(UInt32.max) - 0.5) * 0.006 }
    check(!M.heard(in: hiss), "music (live): room hiss isn't music")
    check(!M.heard(in: Array(repeating: 0, count: 8_000)), "music (live): too short a read decides nothing")
    guard let call = spoken("아리스 내일 아침 일곱 시에 알람 맞춰줘", voice: "Yuna") else {
        return check(true, "music (live): no Korean voice to write a call with: speech skipped")
    }
    check(!M.heard(in: call), "music (live): a spoken request (say, written to a file) isn't music")
    let over = (0..<max(call.count, music.count)).map { i in (i < call.count ? call[i] : 0) + (i < music.count ? music[i] * 0.6 : 0) }
    check(M.heard(in: over), "music (live): a call over music is music (then only the name itself counts)")
    if let sung = spoken("Aris I love you baby I need you tonight", voice: "Organ") {
        check(M.heard(in: sung), "music (live): a sung line (say's singing voice) is music")
    }
}

// MARK: - 9. The wake log says why

private func musicWakeLogTests() {
    check(D.QuietEnd.music.path == "music" && D.QuietEnd.playing.path == "media-playing" && D.QuietEnd.notAddressed.path == "not-addressed",
          "log: the wake log's new paths: music, media-playing, not-addressed")
    check(D.QuietEnd.music.logLine.contains("music") && D.QuietEnd.notAddressed.logLine.contains("weren't for Aris") && D.QuietEnd.playing.logLine.contains("playing"),
          "log: and their lines in the unified log")
    let falseWake = musicSource("Aris/private/Aris/ArisController+FalseWake.swift")
    let glue = musicSource("Aris/private/Aris/ArisController+WakeEvidence.swift")
    check(falseWake.contains("line.merge(wakeEvidenceLogFields())") && glue.contains("[\"music\": evidence.music, \"playing\": evidence.playing]")
          && glue.contains("fields[\"judged\"]") && !glue.contains("fields[\"said\"]"),
          "log: why it closed (music, playback, the judge's word) is written; never the words or any audio")
    check(falseWake.contains("ArisWakeCollectLive.shared.falseWake()"), "log: 하루 소리 모으기 labels these clips false-wake like every quiet close")
}

// MARK: - 10. Wiring

private func musicWakeWiringTests() {
    let controller = musicSource("Aris/private/Aris/ArisController.swift")
    let wake = musicSource("Aris/private/Aris/ArisController+Wake.swift")
    let quiet = musicSource("Aris/private/Aris/ArisController+QuietWake.swift")
    let glue = musicSource("Aris/private/Aris/ArisController+WakeEvidence.swift")
    let falseWake = musicSource("Aris/private/Aris/ArisController+FalseWake.swift")
    // The request never runs before the decision: the gate sits before the turn turns to thinking and answer().
    let gate = controller.range(of: "if let end = await wakeEvidenceAtEnd(said: text) { return closeWakeTurnQuietly(end) }")
    let thinking = controller.range(of: "setSession(session.hearing(gesture?.display(text) ?? text).thinking())")
    let answer = controller.range(of: "await answer(gesture == nil ? session.heard : text, gesture: gesture)")
    check(gate != nil && thinking != nil && answer != nil && gate!.lowerBound < thinking!.lowerBound && thinking!.lowerBound < answer!.lowerBound,
          "wiring: a borderline wake's request runs only after its evidence, before anything is routed or asked")
    check(wake.contains("let doubtful = ArisWakeDoubt.opening(score: score, threshold: threshold, interrupting: interrupting) == .checkAfterOpening")
          && wake.contains("wake(listener, heard: \"\", starting: started, evidence: evidence)"),
          "wiring: only a borderline sure wake waits for evidence (very close wakes and barge-ins open as before)")
    check(wake.contains("if evidence == nil {\n            startScribe(for: listener, replaying: listener.recordedSamples)\n        } else {\n            scribeAfterWakeEvidence = true")
          && glue.contains("startScribe(for: listener, replaying: listener.recordedSamples)"),
          "wiring: a borderline wake streams to Scribe only once kept (from the turn's start)")
    check(quiet.contains("ArisQuietWake(wokeAt: Self.uptime, saidMore: saidMore, held: evidence != nil)") && quiet.contains("stepQuietLap { $0.release() }")
          && quiet.contains("wakeEvidence = nil") && quiet.contains("ArisWakeAddressed.prewarm()"),
          "wiring: the lap is held for a borderline wake, lets go when kept, and its evidence ends with it")
    check(falseWake.contains("async let music = Self.musicAround(detector)") && falseWake.contains("self.wakeEvidence?.music = overMusic")
          && falseWake.contains("self.wakeEvidence?.whisper = heard.map(ArisWakeEvidence.Whisper.heard) ?? .unavailable"),
          "wiring: Whisper's check and the music read come back to the evidence together")
    check(controller.contains("if self.wakeEvidence != nil { self.settleWakeEvidence() }") && glue.contains("case .judge: judgeWakeWords(evidence)"),
          "wiring: words after the call are judged as they come")
    check(glue.contains("Task.detached(priority: .userInitiated)") && glue.contains("detector.held().samples"),
          "wiring: the music read runs off the main thread on what the detector already holds")
}
