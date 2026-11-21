// Tests for jv-voiceid (ARCHITECTURE Part 3, F1: the owner's voice), the app's and the helper's halves: the real
// on-device speaker model (Core ML, Aris/private/Aris/Hearing/VoiceIDModel) on synthesized speakers from files
// (tests/fixtures/voiceid, made with `say -o`: no microphone, no sound), the print learned from a held key and
// enrolment, the switch, forgetting, the settings rows, the enrolment rules, and the trust gate with a speaker
// (no grant from another voice, outward and permanent acts ask, an undo can't reach past its own turn). The pure
// scoring, update rule and provenance rows are tested with `swift test` (Tests/ArisCoreTests/ArisVoiceIDTests).
// Called from main.swift; uses its check().
import Foundation

func runVoiceIDTests() {
    // The clips are not in the public repository (Tests/fixtures/voiceid/README.txt says how to make them).
    let clips = FileManager.default.fileExists(atPath: voiceFixtures.appendingPathComponent("v8_p0_r170.wav").path)
    if !clips { print("skip voice id: no clips in Tests/fixtures/voiceid (see its README.txt): the model, learning and enrolment checks need them") }
    if clips { voiceIDModelTests() }
    if clips { voiceIDLearningTests() }
    voiceIDSettingsTests()
    if clips { voiceIDEnrolmentTests() }
    voiceIDGateTests()
}

private let voiceTests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let voiceFixtures = voiceTests.appendingPathComponent("fixtures/voiceid")
private let voiceModels = voiceTests.appendingPathComponent("../Aris/private/Aris/Hearing/VoiceIDModel").standardizedFileURL

/// 16 kHz mono 16-bit WAV, as `say --data-format=LEI16@16000` writes it.
private func voiceClip(_ voice: Int, _ phrase: Int) -> [Float] {
    guard let data = try? Data(contentsOf: voiceFixtures.appendingPathComponent("v\(voice)_p\(phrase)_r170.wav")) else { return [] }
    return ArisWAV.decode(data) ?? []
}

/// Voices in the fixtures: Grandpa, Rocko, Sandy, Yuna (the owner in these tests).
private let voiceOwner = 8
private let voiceOthers = [3, 5, 6]
private let voiceEnrolPhrases = [0, 5, 6, 7, 8, 9]
private let voiceTestPhrases = [11, 12, 13]

private let sharedEmbedder = ArisVoiceEmbedder(folder: voiceModels)

private func voiceID(on: Bool = true, store: ArisVoiceIDStoring = ArisVoiceIDMemoryStore()) -> ArisVoiceID {
    ArisVoiceID(store: store, embedder: sharedEmbedder, isOn: { on }, now: { Date(timeIntervalSince1970: 1_800_000_000) })
}

private func voiceIDModelTests() {
    check(FileManager.default.fileExists(atPath: voiceModels.appendingPathComponent("ArisVoiceEmbedding.mlmodelc/weights/weight.bin").path),
          "voice id: the speaker model is in the app's sources")
    check(!voiceClip(voiceOwner, 0).isEmpty, "voice id: the fixtures read")
    let start = Date()
    guard let one = sharedEmbedder.vector(ArisVoiceClip.trimmed(voiceClip(voiceOwner, 5))) else { return check(false, "voice id: the model gives a vector") }
    check(one.count == 256 && abs(one.reduce(0) { $0 + $1 * $1 } - 1) < 1e-3, "voice id: a unit vector of 256")
    let again = sharedEmbedder.vector(ArisVoiceClip.trimmed(voiceClip(voiceOwner, 5)))!
    check(ArisVoiceVector.cosine(one, again)! > 0.9999, "voice id: the same audio gives the same vector")
    check(Date().timeIntervalSince(start) < 20, "voice id: the model loads and runs in time")
    check(sharedEmbedder.vector([]) == nil, "voice id: no audio, no vector")

    let voice = voiceID()
    check(voice.check(voiceClip(voiceOwner, 11)) == nil, "voice id: no print: nothing is checked (today's behaviour)")
    let kept = voice.enrol(voiceEnrolPhrases.map { voiceClip(voiceOwner, $0) })
    check(kept == voiceEnrolPhrases.count, "voice id: every enrolment clip went in (\(kept))")
    check(voice.profile?.isEnrolled == true && voice.status.enrolled, "voice id: enrolled")
    var owner: [Float] = [], others: [Float] = []
    for phrase in voiceTestPhrases {
        let mine = voice.check(voiceClip(voiceOwner, phrase))
        check(mine?.verdict == .owner, "voice id: the owner's request p\(phrase) is the owner's: \(String(describing: mine))")
        owner += [mine?.score ?? 0]
        for other in voiceOthers {
            let theirs = voice.check(voiceClip(other, phrase))
            check(theirs?.verdict == .notOwner, "voice id: voice \(other)'s request p\(phrase) is not the owner's: \(String(describing: theirs))")
            others += [theirs?.score ?? 1]
        }
    }
    print("voice id: owner \(owner.map { String(format: "%.2f", $0) }) others max \(String(format: "%.2f", others.max() ?? 0))")
    // A spoken yes: the owner's counts; another voice's is refused, or at least never taken as the owner's.
    for phrase in [3, 4] {
        check(ArisVoiceDecisions.yesCounts(voice.check(voiceClip(voiceOwner, phrase))), "voice id: the owner's spoken yes p\(phrase) counts")
        for other in voiceOthers {
            let theirs = voice.check(voiceClip(other, phrase))
            check(theirs?.verdict != .owner, "voice id: voice \(other)'s yes p\(phrase) is never the owner's: \(String(describing: theirs))")
        }
    }
    let refused = voiceOthers.flatMap { other in [3, 4].map { voice.check(voiceClip(other, $0)) } }.filter { !ArisVoiceDecisions.yesCounts($0) }.count
    check(refused >= 4, "voice id: most of another voice's spoken yeses are refused (\(refused) of 6)")
    // The wake word alone in another voice, and silence.
    for other in voiceOthers { check(voice.check(voiceClip(other, 0))?.verdict != .owner, "voice id: voice \(other)'s lone call is never the owner's") }
    check(voice.check([Float](repeating: 0, count: 16_000)) == .unsure("too-short"), "voice id: silence is unsure, never another voice")
    // The switch off: nothing checked, whatever the print.
    let off = voiceID(on: false, store: ArisVoiceIDMemoryStore(voice.profile?.encoded()))
    check(off.check(voiceClip(5, 11)) == nil && off.turnEnded(voiceClip(5, 11), entry: .wakeWord) == nil, "voice id: off checks nothing")
}

private func voiceIDLearningTests() {
    let store = ArisVoiceIDMemoryStore()
    let voice = voiceID(store: store)
    // Held-key turns start the print, with no setup step.
    for phrase in [5, 6, 7, 9, 13] { check(voice.turnEnded(voiceClip(voiceOwner, phrase), entry: .keyHeld) == nil, "voice id: a held key is never checked") }
    check(voice.profile?.samples == 5 && voice.profile?.isEnrolled == true,
          "voice id: five held-key sentences enrol (\(voice.profile?.samples ?? 0), \(String(format: "%.1f", voice.profile?.seconds ?? 0)) s)")
    check(store.load() != nil, "voice id: the print is stored")
    // Another voice heard while the key is held does not teach the print.
    _ = voice.turnEnded(voiceClip(5, 8), entry: .keyHeld)
    check(voice.profile?.samples == 5, "voice id: another voice under the key is not learned")
    _ = voice.turnEnded(voiceClip(voiceOwner, 8), entry: .keyHeld)
    check(voice.profile?.samples == 6, "voice id: the owner under the key is")
    // Hands-free turns are checked, never learned.
    let wake = voice.turnEnded(voiceClip(5, 12), entry: .wakeWord)
    check(wake?.verdict == .notOwner && voice.profile?.samples == 6, "voice id: another voice's wake turn: not the owner, not learned")
    check(ArisVoiceDecisions.wake(wake, entry: .wakeWord, lastClose: nil, now: 10) == .closeNotOwner, "voice id: the wake turn closes")
    check(ArisVoiceDecisions.speaker(.followUp, match: voice.turnEnded(voiceClip(voiceOwner, 12), entry: .followUp)) == .voiceMatched,
          "voice id: the owner's follow-up is voice-matched")
    check(voice.turnEnded(voiceClip(voiceOwner, 12), entry: .typed) == nil, "voice id: typed turns are not checked")
    // The print holds only numbers: no audio, no words.
    let json = String(decoding: store.load() ?? Data(), as: UTF8.self)
    check(!json.contains("아리스") && json.count < 12_000, "voice id: the stored print is small and holds no words (\(json.count) bytes)")
    // Speakers per turn.
    voice.note(.unverified, for: ArisTurnID(7))
    check(voice.speaker(for: ArisTurnID(7)) == .unverified && voice.speaker(for: ArisTurnID(8)) == nil && voice.speaker(for: nil) == nil, "voice id: a turn's speaker")
    for turn in 0..<40 { voice.note(.keyHeld, for: ArisTurnID(UInt64(100 + turn))) }
    check(voice.speaker(for: ArisTurnID(7)) == nil, "voice id: old turns' speakers are dropped")
    voice.closedForVoice(at: 42)
    check(voice.lastVoiceClose == 42, "voice id: the last voice close")
    // Forget: the print is gone, and nothing is checked.
    check(voice.forget() && voice.profile == nil && store.load() == nil, "voice id: forgotten")
    check(voice.check(voiceClip(5, 11)) == nil && voice.lastVoiceClose == nil, "voice id: after forgetting, as before")
    // A print the store won't keep is not used.
    let refusing = RefusingVoiceStore()
    let unstored = voiceID(store: refusing)
    _ = unstored.enrol([5, 6, 7].map { voiceClip(voiceOwner, $0) })
    check(unstored.profile == nil, "voice id: a print the Keychain refused is not used")
    // A print from another model is no print.
    let otherModel = ArisVoiceProfile.empty(model: "other", at: Date()).adding(Array(repeating: 0.1, count: 256), seconds: 9, at: Date())!
    check(voiceID(store: ArisVoiceIDMemoryStore(otherModel.encoded())).profile == nil, "voice id: another model's print is ignored")
}

private final class RefusingVoiceStore: ArisVoiceIDStoring, @unchecked Sendable {
    func load() -> Data? { nil }
    func save(_ data: Data) -> Bool { false }
    func delete() -> Bool { true }
}

private func voiceIDSettingsTests() {
    let off = ArisSettingSection(id: "test", rows: ArisVoiceIDRows.rows(ArisVoiceIDSummary(), busy: false))
    check(off.rows.map(\.id) == ["aris.voiceID", "aris.voiceEnrol", "aris.voiceForget"], "voice settings: the three rows")
    check(off.rows[0].control == .toggle(.voiceID, false), "voice settings: the switch, off by default")
    if case .buttons(let buttons) = off.rows[1].control { check(!buttons[0].enabled, "voice settings: no enrolment while off") } else { check(false, "voice settings: enrol is a button") }
    if case .buttons(let buttons) = off.rows[2].control { check(!buttons[0].enabled, "voice settings: nothing to delete") } else { check(false, "voice settings: delete is a button") }
    let on = ArisSettingSection(id: "test", rows: ArisVoiceIDRows.rows(ArisVoiceIDSummary(on: true, enrolled: true, samples: 12), busy: false))
    if case .buttons(let buttons) = on.rows[1].control { check(buttons[0].enabled && buttons[0].title == "더 들려주기", "voice settings: enrolled, more") }
    let asking = ArisSettingSection(id: "test", rows: ArisVoiceIDRows.rows(ArisVoiceIDSummary(on: true, enrolled: true, samples: 12, confirmingForget: true), busy: false))
    if case .buttons(let buttons) = asking.rows[2].control {
        check(buttons.map(\.action) == [.keepVoice, .forgetVoice] && buttons[1].kind == .danger, "voice settings: delete asks twice")
    }
    check(ArisVoiceIDRows.switchLine(ArisVoiceIDSummary(available: false)).contains("모델"), "voice settings: the model missing is said")
    // Every row is in the search index and in its part, under 부르기.
    for row in on.rows {
        check(ArisSettingsIndex.entries.contains { $0.id == row.id }, "voice settings: \(row.id) is indexed")
        check(ArisSettingsParts.holding(row.id)?.id == "talk.call", "voice settings: \(row.id) is in 부르기")
    }
    let built = ArisSettingsBuilder.sections(part: "talk.call", ArisSettingsSnapshot())
    let call = built.first { $0.id == "aris.call" }?.rows.map(\.id) ?? []
    // 내 목소리 익히기 (the wake word) and 내 목소리 등록하기 are one row since the VM run of 2026-11-18 (aris.voiceEnrol).
    check(call.suffix(3) == ["aris.voiceID", "aris.voiceEnrol", "aris.voiceForget"] && !call.contains("aris.train"),
          "voice settings: the builder draws the rows, one of them teaching the voice (\(call))")
    // Every Korean line has its English.
    let korean = [ArisVoiceIDRows.forgottenToast, ArisVoiceIDRows.enrolledToast] + on.rows.flatMap { [$0.title, $0.desc ?? ""] }
        + off.rows.compactMap(\.desc) + asking.rows.flatMap { row -> [String] in
            if case .buttons(let buttons) = row.control { return buttons.map(\.title) }
            return []
        } + [ArisVoiceIDRows.Sheet.title, ArisVoiceIDRows.Sheet.intro, ArisVoiceIDRows.Sheet.introPrivacy, ArisVoiceIDRows.Sheet.done,
             ArisVoiceIDRows.Sheet.doneLine, ArisVoiceIDRows.Sheet.failed, ArisVoiceIDRows.Sheet.again, ArisVoiceIDRows.Sheet.learning]
    for line in Set(korean) where !line.isEmpty {
        check(ArisSettingsCopyMore.english[line] != nil, "voice settings: “\(line)” has its English")
    }
    check(ArisVoiceIDRows.sentences.count == ArisVoiceIDRows.englishSentences.count && ArisVoiceIDRows.sentences.count == 5, "voice settings: five sentences each way")
}

private func voiceIDEnrolmentTests() {
    check(ArisVoiceEnrolment.keeps(voiceClip(voiceOwner, 7)), "voice enrol: a read sentence is kept")
    check(!ArisVoiceEnrolment.keeps([Float](repeating: 0.0001, count: 72_000)), "voice enrol: silence is asked again")
    func entry(_ file: String, _ label: ArisWakeManifest.Label = .call, style: String = "normal", distance: String = "near", background: String = "quiet",
               mic: String = "built-in", speaker: String? = nil) -> ArisWakeManifest.Entry {
        var entry = ArisWakeManifest.Entry(file: file, label: label, seconds: 1.5, recordedAt: "2026-11-18T00:00:00Z")
        entry.style = style
        entry.distance = distance
        entry.background = background
        entry.mic = mic
        entry.speaker = speaker
        return entry
    }
    var manifest = ArisWakeManifest()
    manifest.entries = [entry("calls/a.wav"), entry("calls/b.wav", .confusable), entry("calls/c.wav", style: "quiet"), entry("calls/d.wav", distance: "far"),
                        entry("calls/e.wav", background: "music"), entry("calls/f.wav", mic: "airpods"), entry("calls/g.wav", speaker: "owner"),
                        entry("../x.wav"), entry("/etc/passwd"), entry("calls/h.wav")]
    check(ArisVoiceEnrolment.wakeCalls(manifest) == ["calls/a.wav", "calls/h.wav"], "voice enrol: only plain near calls of the owner (\(ArisVoiceEnrolment.wakeCalls(manifest)))")
    manifest.entries = (0..<30).map { entry("calls/t\($0).wav") }
    check(ArisVoiceEnrolment.wakeCalls(manifest).count == ArisVoiceEnrolment.mostCalls, "voice enrol: at most ten calls")
    // The wake word's own takes go in after the sentences; one in another voice is kept out.
    let voice = voiceID()
    _ = voice.enrol([5, 6, 7, 8, 9].map { voiceClip(voiceOwner, $0) })
    check(voice.enrol([voiceClip(voiceOwner, 0), voiceClip(5, 9)]) == 1, "voice enrol: the owner's call goes in, another voice's does not")
}

private func voiceIDGateTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-voiceid-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let home = URL(fileURLWithPath: folder.path).resolvingSymlinksInPath().path
    let world = ArisWorldFacts(contacts: [.init(name: "엄마", addresses: ["mom@example.com"])], home: home)
    let gate = ArisTrustGate(home: home, world: { _ in world })
    // Another voice can't make a grant.
    check(gate.ownerTurn(session: "v1", text: "앞으로 엄마한테 보내는 건 묻지 마", speaker: .unverified) == nil, "voice gate: no grant from another voice")
    check(ArisTrustSettings.load(home: home).grants.isEmpty, "voice gate: nothing was kept")
    // Its outward request is read back; the owner's own, fully said, goes after the spoken moment.
    gate.ownerTurn(session: "v1", text: "엄마한테 늦어요라고 메일 보내 줘", speaker: .unverified)
    let theirs = gate.decide(session: "v1", call: "a1", capability: "mail.send", effect: .outward, arguments: ["to": "mom@example.com", "body": "늦어요"])
    check(theirs.decision == .readBackThenAsk && theirs.verdict.speaker == .unverified, "voice gate: another voice's mail is read back: \(theirs.decision)")
    gate.ownerTurn(session: "v2", text: "엄마한테 늦어요라고 메일 보내 줘", speaker: .keyHeld)
    let mine = gate.decide(session: "v2", call: "a2", capability: "mail.send", effect: .outward, arguments: ["to": "mom@example.com", "body": "늦어요"])
    check(!mine.decision.waitsForOwner, "voice gate: the owner's own mail goes as before: \(mine.decision)")
    // Unenrolled: exactly as before.
    gate.ownerTurn(session: "v3", text: "엄마한테 늦어요라고 메일 보내 줘")
    check(gate.decide(session: "v3", call: "a3", capability: "mail.send", effect: .outward, arguments: ["to": "mom@example.com", "body": "늦어요"]).decision == mine.decision,
          "voice gate: nothing checked decides as the owner")
    // An undo: another voice reaches only its own conversation's entries, and a permanent undo asks.
    let now = Date()
    let made = ArisRecordEntry.call(at: now.addingTimeInterval(-60), session: "elsewhere", task: nil, capability: "file.write", effect: .changeReversible,
                                    provenance: .ownerSaid, decision: .runWithUndo(announce: false), arguments: [.init(kind: .path, value: home + "/a.txt")],
                                    result: nil, ok: true, undo: .fileCreated(path: home + "/a.txt"))
    let event = ArisRecordEntry.call(at: now.addingTimeInterval(-30), session: "v4", task: nil, capability: "calendar.add", effect: .changeReversible,
                                     provenance: .ownerSaid, decision: .runWithUndo(announce: false), arguments: [], result: nil, ok: true,
                                     undo: .itemCreated(kind: "calendar", id: "E1"))
    check(ArisRecordJournal.append(made, home: home) && ArisRecordJournal.append(event, home: home), "voice gate: the record has entries")
    gate.ownerTurn(session: "v5", text: "아까 그거 되돌려", speaker: .unverified)
    let farUndo = gate.decide(session: "v5", call: "u1", capability: "record.undo", effect: .changeReversible, arguments: ["id": made.id])
    if case .refuse = farUndo.decision {} else { check(false, "voice gate: another voice can't undo another conversation's entry: \(farUndo.decision)") }
    gate.ownerTurn(session: "v6", text: "아까 그거 되돌려", speaker: .keyHeld)
    let ownUndo = gate.decide(session: "v6", call: "u2", capability: "record.undo", effect: .changeReversible, arguments: ["id": made.id])
    check(!ownUndo.decision.waitsForOwner, "voice gate: the owner's undo reaches it: \(ownUndo.decision)")
    gate.ownerTurn(session: "v4", text: "아까 그거 되돌려", speaker: .unverified)
    let permanent = gate.decide(session: "v4", call: "u3", capability: "record.undo", effect: .changeReversible, arguments: ["id": event.id])
    check(permanent.decision == .ask, "voice gate: another voice's permanent undo asks, as any permanent change in it: \(permanent.decision)")
    try? FileManager.default.removeItem(atPath: home)
}
