// Tests for wake-net phase 1: Settings › 대화 › 호출어 녹음 (the script of takes, each take judged, the labelled
// corpus on disk with its manifest, 0700/0600, 다 지우기), the opt-in 하루 소리 모으기 and its retention rules, the
// settings rows and their English, the privacy line that stays true while collecting, and the wiring (the waiting
// detector only read, never changed). Synthetic audio and a temporary folder: no microphone, no sound.
// Called from main.swift; uses its check().
import Foundation

private let wakeNetRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func wakeNetSource(_ path: String) -> String { (try? String(contentsOf: wakeNetRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runWakeNetTests() {
    wakeScriptTests()
    wakeTakeTests()
    wakeManifestTests()
    wakeStoreTests()
    wakeCollectTests()
    wakeRecordRowsTests()
    wakeHonestyCollectTests()
    wakeNetWiringTests()
}

// MARK: - The script

private func wakeScriptTests() {
    typealias S = ArisWakeScript
    check(S.callTakes == 100, "wake script: a hundred calls of the name (\(S.callTakes))")
    check(S.totalTakes - S.callTakes == 70, "wake script: seven words like it, ten times each")
    let confusables = Set(S.steps.filter { $0.prompt.label == .confusable }.map(\.prompt.phrase))
    check(confusables == ["아이스", "아리수", "어리스", "아리랑", "앨리스", "크리스", "아리스토텔레스"], "wake script: the confusable words are the hard negatives asked for")
    let phrases = Set(S.steps.filter { $0.prompt.label == .call }.map(\.prompt.phrase))
    check(["아리스", "어 아리스", "아리스야", "헤이 아리스", "Aris"].allSatisfy(phrases.contains), "wake script: plain, with a filler, with 야, with 헤이, in English")
    let calls = S.steps.filter { $0.prompt.label == .call }.map(\.prompt)
    check(calls.contains { $0.style == .quiet } && calls.contains { $0.distance == .far } && calls.contains { $0.background == .music } && calls.contains { $0.mic == .airPods },
          "wake script: quiet, far, over music and into AirPods are all asked for")
    check(Set(S.steps.map(\.key)).count == S.totalTakes, "wake script: every take has its own key (its file name)")
    check(S.steps.first?.key == "call-plain-aris-t01" && S.steps[19].key == "call-plain-aris-t20", "wake script: keys count the takes from 01")
    check(S.next(recorded: []) == S.steps.first, "wake script: nothing recorded → the first take")
    let firstTwenty = Set(S.steps.prefix(20).map(\.key))
    check(S.next(recorded: firstTwenty)?.block.id == "casual", "wake script: continues where it stopped")
    let upToMusic = Set(S.steps.filter { ["plain", "casual", "quiet", "far"].contains($0.block.id) }.map(\.key))
    check(S.next(recorded: upToMusic, skipping: ["music"])?.block.id == "airpods", "wake script: a skipped optional block is left out this time")
    check(S.next(recorded: Set(S.steps.map(\.key))) == nil, "wake script: all recorded → nothing left")
    let plain = S.blocks[0]
    check(S.progress(of: plain, recorded: firstTwenty) == (20, 20) && S.progress(of: S.blocks[1], recorded: firstTwenty) == (0, 20), "wake script: progress per block")
    check(S.counter(S.steps[2]) == "평소처럼 · 3/20", "wake script: the sheet's counter")
    check(S.blocks.filter(\.optional).map(\.id) == ["music", "airpods"], "wake script: only music and AirPods can be skipped")
    check(S.steps.allSatisfy { $0.prompt.seconds >= 2.5 } && S.steps.first { $0.prompt.phrase == "아리스, 타이머 삼 분 맞춰 줘" }?.prompt.seconds == 3.5,
          "wake script: a take is long enough for its line")
}

// MARK: - A take

private func wakeTone(seconds: Double, at start: Double, length: Double, level: Float, noise: Float = 0.0004) -> [Float] {
    var seed: UInt64 = 7
    return (0..<Int(seconds * 16000)).map { index in
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let hiss = (Float(seed >> 40) / Float(1 << 24) * 2 - 1) * noise
        let t = Double(index) / 16000
        let voiced = t >= start && t < start + length ? level * Float(sin(2 * .pi * 220 * t)) : 0
        return voiced + hiss
    }
}

private func wakeTakeTests() {
    let plain = ArisWakeScript.steps[0].prompt
    let quiet = ArisWakeScript.steps.first { $0.prompt.style == .quiet }!.prompt
    let music = ArisWakeScript.steps.first { $0.prompt.background == .music }!.prompt
    check(ArisWakeTake.verdict(wakeTone(seconds: 2.5, at: 0.6, length: 0.6, level: 0.1), prompt: plain) == .ok, "take: a call in the middle is kept")
    check(ArisWakeTake.verdict(wakeTone(seconds: 2.5, at: 0.6, length: 0.6, level: 0), prompt: plain) == .tooQuiet, "take: silence is asked again")
    check(ArisWakeTake.verdict(wakeTone(seconds: 2.5, at: 0.6, length: 0.6, level: 0.008), prompt: plain) == .tooQuiet, "take: a near call too quiet is asked again")
    check(ArisWakeTake.verdict(wakeTone(seconds: 2.5, at: 0.6, length: 0.6, level: 0.008), prompt: quiet) == .ok, "take: a quiet call may be quiet")
    check(ArisWakeTake.verdict(wakeTone(seconds: 2.5, at: 0.6, length: 0.6, level: 1.4), prompt: plain) == .clipped, "take: a clipped take is asked again")
    check(ArisWakeTake.verdict(wakeTone(seconds: 2.5, at: 0, length: 0.8, level: 0.1), prompt: plain) == .cutOff, "take: said before the window → cut off")
    check(ArisWakeTake.verdict(wakeTone(seconds: 2.5, at: 1.8, length: 1.0, level: 0.1), prompt: plain) == .cutOff, "take: still talking at its end → cut off")
    check(ArisWakeTake.verdict(wakeTone(seconds: 2.5, at: 0, length: 2.5, level: 0.1), prompt: music) == .ok, "take: over music the edges are not judged")
    check(ArisWakeTake.Verdict.allCasesForTest.allSatisfy { ($0 == .ok) == (ArisWakeTake.retryLine($0) == nil) }, "take: every refusal says why, a kept take says nothing")
}

private extension ArisWakeTake.Verdict {
    static var allCasesForTest: [ArisWakeTake.Verdict] { [.ok, .tooQuiet, .clipped, .cutOff] }
}

// MARK: - The manifest

private func wakeEntry(_ file: String, _ label: ArisWakeManifest.Label, prompt: String? = nil, take: Int? = nil) -> ArisWakeManifest.Entry {
    var entry = ArisWakeManifest.Entry(file: file, label: label, seconds: 2.5, recordedAt: "2026-11-14T10:00:00.000Z")
    entry.prompt = prompt
    entry.take = take
    return entry
}

private func wakeManifestTests() {
    let empty = ArisWakeManifest()
    let one = empty.adding(wakeEntry("calls/call-plain-aris-t01.wav", .call, prompt: "call-plain-aris", take: 1))
    check(empty.entries.isEmpty && one.entries.count == 1, "manifest: adding returns a new manifest, the old one unchanged")
    let again = one.adding(wakeEntry("calls/call-plain-aris-t01.wav", .call, prompt: "call-plain-aris", take: 1))
    check(again.entries.count == 1, "manifest: a take recorded again replaces its entry")
    let mixed = again.adding(wakeEntry("calls/near-ice-t02.wav", .confusable, prompt: "near-ice", take: 2)).adding(wakeEntry("ambient/x-speech.wav", .ambientSpeech))
    check(mixed.recordedTakes == ["call-plain-aris-t01", "near-ice-t02"], "manifest: recorded takes are the calls' and the confusables' keys, not ambient clips")
    check(mixed.count([.ambientSpeech, .ambientCandidate]) == 1 && mixed.count([.call]) == 1, "manifest: counts by label")
    check(mixed.removing(files: ["calls/near-ice-t02.wav"]).recordedTakes == ["call-plain-aris-t01"], "manifest: removing drops the entry")
    check(mixed.listening(120).listening(-5).listenedSeconds == 120, "manifest: listened time adds up, never down")
    let coder = JSONEncoder()
    let decoded = (try? coder.encode(mixed)).flatMap { try? JSONDecoder().decode(ArisWakeManifest.self, from: $0) }
    check(decoded == mixed, "manifest: JSON round trip")
    let json = (try? coder.encode(mixed)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    check(json.contains("\"ambient-speech\"") && json.contains("\"sampleRate\":16000"), "manifest: labels and rate as the bench reads them")
    check(ArisWakeManifest.timestamp(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00.000Z", "manifest: ISO 8601 times")
    // The WAV the bench and the trainer read.
    let tone = wakeTone(seconds: 0.5, at: 0, length: 0.5, level: 0.5)
    let wav = ArisWAV.encode(tone)
    check(wav.count == 44 + tone.count * 2 && String(decoding: wav[0..<4], as: UTF8.self) == "RIFF", "wav: 16-bit PCM with a 44-byte header")
    let back = ArisWAV.decode(wav) ?? []
    check(back.count == tone.count && zip(back, tone).allSatisfy { abs($0 - $1) < 0.0001 }, "wav: round trip")
    check(ArisWAV.decode(Data("nope".utf8)) == nil && ArisWAV.encode([2, -2]).count == 48, "wav: junk is no WAV, loud samples are clamped")
}

// MARK: - The folder

private func wakeMode(_ url: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1 }

private func wakeStoreTests() {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("aris-wake-corpus-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: base) }
    let store = ArisWakeCorpusStore(folder: base.appendingPathComponent("wake-corpus"))
    check(store.load() == ArisWakeManifest(), "store: nothing on disk → an empty manifest")
    let tone = wakeTone(seconds: 1, at: 0.2, length: 0.4, level: 0.1)
    let saved = try? store.save(tone, as: wakeEntry("calls/call-plain-aris-t01.wav", .call, prompt: "call-plain-aris", take: 1), into: store.load())
    check(saved?.recordedTakes == ["call-plain-aris-t01"] && store.load() == saved, "store: a saved take is listed in the manifest on disk")
    let clip = store.folder.appendingPathComponent("calls/call-plain-aris-t01.wav")
    check(wakeMode(store.folder) == 0o700 && wakeMode(clip.deletingLastPathComponent()) == 0o700, "store: the folders are 0700")
    check(wakeMode(clip) == 0o600 && wakeMode(store.manifestURL) == 0o600, "store: the clip and the manifest are 0600")
    check((try? Data(contentsOf: clip)).flatMap(ArisWAV.decode)?.count == tone.count, "store: the clip is the take")
    check(store.bytes(saved ?? ArisWakeManifest()) == 44 + tone.count * 2, "store: its bytes are counted")
    let two = (try? store.save(tone, as: wakeEntry("ambient/a-speech.wav", .ambientSpeech), into: saved ?? ArisWakeManifest())) ?? ArisWakeManifest()
    let pruned = try? store.remove(["ambient/a-speech.wav"], from: two)
    check(pruned?.entries.count == 1 && !FileManager.default.fileExists(atPath: store.folder.appendingPathComponent("ambient/a-speech.wav").path), "store: removing a clip deletes its file")
    try? store.removeAll()
    check(!FileManager.default.fileExists(atPath: store.folder.path) && store.load() == ArisWakeManifest(), "store: 다 지우기 removes the folder, every clip and the manifest")
    check((try? store.removeAll()) != nil, "store: 다 지우기 with nothing there is fine")
    check(wakeNetSource("Aris/private/Aris/ArisWakeCorpus.swift").contains("urls(for: .applicationSupportDirectory, in: .userDomainMask)")
          && wakeNetSource("Aris/private/Aris/ArisWakeCorpus.swift").contains("Aris/wake-corpus"), "store: the app's own Application Support (its container)")
}

// MARK: - 하루 소리 모으기

private func wakeCollectTests() {
    typealias C = ArisWakeCollect
    let now: TimeInterval = 1_800_000_000
    check(!C.isOn(setting: false, since: now, now: now) && !C.isOn(setting: true, since: nil, now: now), "collect: off unless switched on (with a start)")
    check(C.isOn(setting: true, since: now - 3600, now: now) && !C.isOn(setting: true, since: now - C.lasts, now: now), "collect: on for one day, then off")
    check(C.hoursLeft(since: now - 3600, now: now) == 23 && C.hoursLeft(since: now - 30 * 3600, now: now) == 0, "collect: hours left of the day")
    check(C.mayKeep(clips: 0, bytes: 0) && !C.mayKeep(clips: C.maxClips, bytes: 0) && !C.mayKeep(clips: 1, bytes: C.maxBytes), "collect: stops keeping at its caps")
    let second = 16_000
    check(C.speechWindow(start: 10 * second, end: 10 * second + 3200, oldest: 0) == nil, "collect: a sound under a quarter second is no phrase")
    check(C.speechWindow(start: 10 * second, end: 12 * second, oldest: 0) == (9 * second)..<(12 * second), "collect: a phrase with a second of room before it")
    check(C.speechWindow(start: 10 * second, end: 30 * second, oldest: 0)?.count == 5 * second, "collect: never more than five seconds")
    check(C.speechWindow(start: 10 * second, end: 12 * second, oldest: 9 * second + 100)?.lowerBound == 9 * second + 100, "collect: only what the detector still holds")
    check(C.candidateWindow(start: 10 * second, received: 20 * second, oldest: 0) == (9 * second + second / 2)..<(12 * second + second / 2), "collect: a candidate's three seconds from just before it")
    check(C.candidateWindow(start: 10 * second, received: 11 * second, oldest: 0)?.upperBound == 11 * second, "collect: cut at what has come in")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 23, minute: 15, second: 0))!
    check(C.file(at: date, candidate: true) == "ambient/20261114-231500-000-candidate.wav" && C.file(at: date, candidate: false).hasSuffix("-speech.wav"), "collect: clips named by time and kind")
    check(C.outcome(path: "rejected") == "rejected" && C.outcome(path: "voice") == "voice" && C.outcome(path: "heard 아리스 날씨") == "other", "collect: an outcome is the path's name, never words")
    check(C.outcome(path: C.falseWake) == "false-wake", "collect: a wake that came to nothing is kept as a false wake")
    check(UserDefaults(suiteName: testSuiteName("aris-wake-collect-tests"))?.bool(forKey: C.key) == false, "collect: off by default")
}

// MARK: - The settings rows

private func wakeRecordSection(_ summary: ArisWakeRecordSummary) -> ArisSettingSection? {
    var s = ArisSettingsSnapshot()
    s.wakeRecord = summary
    return ArisSettingsBuilder.sections(.aris, s).first { $0.id == ArisWakeRecordRows.sectionID }
}

private func wakeRecordRowsTests() {
    let sections = ArisSettingsBuilder.sections(.aris, ArisSettingsSnapshot()).map(\.id)
    check(sections.firstIndex(of: "aris.record") == (sections.firstIndex(of: "aris.call") ?? -2) + 1, "rows: 호출어 녹음 sits right under 부르기")
    let fresh = wakeRecordSection(ArisWakeRecordSummary(total: 170))
    let rows = fresh?.rows ?? []
    check(rows.map(\.id) == ["aris.recordCalls", "aris.collect", "aris.recordClear"], "rows: record, collect, delete")
    check(rows.first?.control == .buttons([ArisSettingButton(title: "녹음하기", action: .recordWakeCalls)]), "rows: nothing recorded → 녹음하기 opens the sheet")
    check(rows[1].control == .toggle(.wakeCollect, false), "rows: 하루 소리 모으기 is off unless turned on")
    check(rows[2].control == .buttons([ArisSettingButton(title: "다 지우기", action: .clearWakeRecordings, kind: .danger, enabled: false)]) && rows[2].danger,
          "rows: 다 지우기 is red, and greyed with nothing to erase")
    let some = wakeRecordSection(ArisWakeRecordSummary(takes: 34, total: 170, ambient: 5, bytes: 3_250_000, collecting: true, hoursLeft: 18))?.rows ?? []
    check(some.first?.desc == "34/170개 녹음했어요." && some.first?.control == .buttons([ArisSettingButton(title: "이어서 녹음하기", action: .recordWakeCalls)]), "rows: part way → 이어서 녹음하기")
    check(some[1].desc == "모으는 중 · 18시간 남음 · 조각 5개" && some[1].control == .toggle(.wakeCollect, true), "rows: collecting says so, how long and how much")
    check(some[2].desc == "녹음 34개 · 조각 5개 · 3.1 MB" && some[2].control == .buttons([ArisSettingButton(title: "다 지우기", action: .clearWakeRecordings, kind: .danger)]), "rows: what 다 지우기 erases")
    let asking = wakeRecordSection(ArisWakeRecordSummary(takes: 170, total: 170, confirmingClear: true))?.rows ?? []
    check(asking.first?.control == .buttons([ArisSettingButton(title: "다시 녹음하기", action: .recordWakeCalls)]), "rows: all recorded → 다시 녹음하기")
    check(asking[2].control == .buttons([ArisSettingButton(title: "취소", action: .keepWakeRecordings), ArisSettingButton(title: "정말 지우기", action: .clearWakeRecordings, kind: .danger)]),
          "rows: 다 지우기 asks twice")
    var busy = ArisSettingsSnapshot()
    busy.busy = true
    check(ArisSettingsBuilder.sections(.aris, busy).first { $0.id == "aris.record" }?.rows.first?.control == .buttons([ArisSettingButton(title: "녹음하기", action: .recordWakeCalls, enabled: false)]),
          "rows: not while Aris is busy")
    check(["aris.recordCalls", "aris.collect", "aris.recordClear"].allSatisfy { id in ArisSettingsIndex.entries.contains { $0.id == id } }, "rows: search finds all three")

    // Every line the rows and the sheet show has its English.
    let shown: [String] = [fresh, wakeRecordSection(ArisWakeRecordSummary(takes: 34, total: 170, ambient: 5, bytes: 3_250_000, collecting: true, hoursLeft: 18)),
                           wakeRecordSection(ArisWakeRecordSummary(takes: 170, total: 170, confirmingClear: true))].compactMap { $0 }.flatMap { section in
        [section.heading, section.note].compactMap { $0 } + section.rows.flatMap { row -> [String] in
            var words = [row.title] + [row.desc].compactMap { $0 }
            if case .buttons(let buttons) = row.control { words += buttons.map(\.title) }
            return words
        }
    }
    typealias Sheet = ArisWakeRecordRows.Sheet
    let sheet = [Sheet.title, Sheet.intro, Sheet.introPrivacy, Sheet.start, Sheet.resume, Sheet.listening, Sheet.ready, Sheet.saved, Sheet.stop, Sheet.skip,
                 Sheet.again, Sheet.close, Sheet.done, Sheet.doneLine, Sheet.noHeadset, Sheet.micFailed, Sheet.saveFailed, Sheet.busy,
                 ArisWakeRecordRows.clearedToast, ArisWakeRecordRows.collectOffToast]
        + ArisWakeScript.blocks.flatMap { [$0.title, $0.how] } + [ArisWakeTake.Verdict.tooQuiet, .clipped, .cutOff].compactMap(ArisWakeTake.retryLine)
    ArisSettingsCopy.install([:])
    let missing = (shown + sheet).filter { ArisSettingsCopy.english($0) == nil }
    check(missing.isEmpty, "rows: every line has its English" + (missing.isEmpty ? "" : " (\(missing.prefix(3)))"))
    check(ArisSettingsCopy.english("34/170개 녹음했어요.") == "34 of 170 recorded." && ArisSettingsCopy.english("평소처럼 · 3/20") == "As usual · 3/20",
          "rows: numbers carried into the English")
    check(ArisSettingsCopy.english("모으는 중 · 18시간 남음 · 조각 5개") == "Collecting · 18 h left · 5 clips", "rows: collecting's line in English")
    check(ArisWakeRecordRows.menuLine(english: false) == "하루 소리 모으는 중 — 끄기" && ArisWakeRecordRows.menuLine(english: true).contains("turn off"), "rows: the ✦ menu's line turns it off")
}

// MARK: - What is said about it

private func wakeHonestyCollectTests() {
    typealias H = ArisWakeHonesty
    check(H.note(trained: true, collecting: false) == H.note && H.note(trained: false, collecting: false) == H.noteUntrained, "honesty: off, the note is as before")
    let on = H.note(trained: true, collecting: true)
    check(!on.contains("남기지 않") && on.contains("하루 소리 모으기") && on.contains("이 Mac의 Aris 폴더에만 남겨요") && on.contains("보내지 않아요"),
          "honesty: collecting, the note no longer says nothing is kept, and says what is and where")
    check(H.note(trained: false, collecting: true).hasSuffix(H.untrained), "honesty: untrained and collecting says both")
    check(ArisSettingsCopyMore.english[on] == H.noteCollectingEnglish && !H.noteCollectingEnglish.contains("nothing is sent or kept"), "honesty: and in English")
    check(!H.line(english: false, collecting: true).contains("남기지 않") && !H.line(english: true, collecting: true).contains("or kept"), "honesty: the short line too")
    var s = ArisSettingsSnapshot()
    s.hasVoiceModel = true
    s.wakeRecord.collecting = true
    check(ArisSettingsBuilder.sections(.aris, s).first { $0.id == "aris.call" }?.note == on, "honesty: 부르기's note follows the switch")
}

// MARK: - Wiring

private func wakeNetWiringTests() {
    let wake = wakeNetSource("Aris/private/Aris/ArisController+Wake.swift")
    check(wake.contains("ArisWakeCollectLive.shared.voice(talking, detector: detector, waiting: self.session.phase == .idle && !self.conversation.isOpen"),
          "wiring: speech is kept only while Aris waits (no turn, no conversation)")
    check(wake.contains("if self.session.phase == .idle, !self.conversation.isOpen { ArisWakeCollectLive.shared.candidate(") && wake.contains("ArisWakeCollectLive.shared.outcome(path)"),
          "wiring: a candidate and its check's outcome")
    check(wakeNetSource("Aris/private/Aris/ArisController+FalseWake.swift").contains("ArisWakeCollectLive.shared.falseWake()"), "wiring: a false wake labels its clip (false-wake's quiet close)")
    check(wake.contains("training: training != nil || recordingCalls") && wake.contains("func beginRecordingCalls()") && wake.contains("stopWaitingForWakeWord()"),
          "wiring: the wake word stays closed while the sheet records")
    let collect = wakeNetSource("Aris/private/Aris/ArisWakeCollectLive.swift")
    check(!collect.contains("pause(") && !collect.contains("onCandidate") && collect.contains("detector.held()"), "wiring: the collector only reads the detector's memory")
    let core = wakeNetSource("Aris/private/Aris/ArisWakeCore.swift")
    check(!core.contains("Collect") && !core.contains("Corpus"), "wiring: stage 1 and its thresholds are untouched")
    let status = wakeNetSource("Aris/private/Aris/ArisStatusItem.swift")
    check(status.contains("ArisWakeRecordLive.shared.collecting") && status.contains("setCollecting(false)"), "wiring: the ✦ menu shows it is on, one choice turns it off")
    let live = wakeNetSource("Aris/components/Settings/ArisLiveSettings.swift")
    check(live.contains("case .recordWakeCalls: overlay.sheet = .wakeRecord") && live.contains("ArisWakeRecordSheet(model: .shared)") && live.contains("wakeRecord.setCollecting("),
          "wiring: the rows open the sheet and turn collecting on and off")
    let recorder = wakeNetSource("Aris/private/Aris/ArisWakeRecorderModel.swift")
    check(recorder.contains("ArisController.shared.endRecordingCalls()") && recorder.contains("ArisWakeTake.verdict"), "wiring: the sheet judges each take and gives the wake word back")
    let mic = wakeNetSource("Aris/private/Aris/ArisWakeRecorderMic.swift")
    check(mic.contains("ArisMicDevices.pin(engine, for: .setup)") && mic.contains("ArisMicDevices.pinHeadset(engine)") && mic.contains("ArisMicDevices.noteClosed(.setup"),
          "wiring: the recorder's microphone is pinned like the name's training (AirPods only for its AirPods group), and its close is logged")
    check(!mic.contains("write(") && !collect.contains("FileManager"), "wiring: only ArisWakeCorpus writes to disk")
}
