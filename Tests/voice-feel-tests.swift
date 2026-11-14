// Tests for the ElevenLabs voice reading flat (2026-11-13): the voice's own saved settings sent with every line, fetched
// once per voice and kept; Eleven v4 offered; the sentences of one answer sent with what came before them; the text
// keeping the endings that carry intonation; and the 미리 듣기 button asking exactly as real speech does. No network:
// the cache is given a fake fetch. Called from main.swift; uses its check().
import Foundation

func runVoiceFeelTests() {
    savedSettingsParseTests()
    voiceSettingsBodyTests()
    voiceRequestTests()
    voiceEndingTests()
    voiceModelChoiceTests()
    voiceSameRequestWiringTests()
    final class Done: @unchecked Sendable { var value = false }
    let done = Done()
    Task {
        await voiceSettingsCacheTests()
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private func body(of request: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
}

private func savedSettingsParseTests() {
    let saved = ArisVoiceSettings.parse(Data(#"{"stability":0.3,"similarity_boost":0.8,"style":0.45,"use_speaker_boost":false,"speed":1.05}"#.utf8))
    check(saved == ArisVoiceSettings(stability: 0.3, similarityBoost: 0.8, style: 0.45, useSpeakerBoost: false),
          "voice feel: GET /v1/voices/{id}/settings reads the voice's four sliders (its own speed is not Aris's)")
    let odd = ArisVoiceSettings.parse(Data(#"{"stability":1.7,"similarity_boost":-2,"style":"x","use_speaker_boost":1}"#.utf8))
    check(odd == ArisVoiceSettings(stability: 1, similarityBoost: 0, style: nil, useSpeakerBoost: nil),
          "voice feel: a slider out of 0...1 is clamped, a value of the wrong type is left out")
    check(ArisVoiceSettings.parse(Data("nope".utf8)) == nil && ArisVoiceSettings.parse(Data(#"{"detail":"not found"}"#.utf8)) == nil
          && ArisVoiceSettings.parse(Data(#"{"stability":true}"#.utf8)) == nil,
          "voice feel: an answer that isn't settings gives none (the line is read without them)")
}

private func voiceSettingsBodyTests() {
    let saved = ArisVoiceSettings(stability: 0.3, similarityBoost: 0.8, style: 0.45, useSpeakerBoost: true)
    let turbo = saved.body(speed: 1.1, model: "eleven_v4_turbo")
    check(turbo["stability"] as? Double == 0.3 && turbo["similarity_boost"] as? Double == 0.8 && turbo["speed"] as? Double == 1.1
          && turbo["style"] == nil && turbo["use_speaker_boost"] == nil,
          "voice feel: Eleven v4 Turbo gets the voice's stability and similarity with Aris's speed (v4 takes no style)")
    check(Set(saved.body(speed: 1, model: "eleven_v4").keys) == ["stability", "similarity_boost", "speed"],
          "voice feel: Eleven v4 gets the same two sliders")
    let multilingual = saved.body(speed: 0.9, model: "eleven_multilingual_v2")
    check(multilingual["style"] as? Double == 0.45 && multilingual["use_speaker_boost"] as? Bool == true && multilingual["stability"] as? Double == 0.3
          && multilingual["speed"] as? Double == 0.9,
          "voice feel: the v2 models get all four sliders, style and speaker boost included")
    check(ArisVoiceSettings().body(speed: 3, model: "eleven_v4_turbo").count == 1 && ArisVoiceSettings().body(speed: 3, model: "x")["speed"] as? Double == 1.2,
          "voice feel: without saved settings only the speed goes, in ElevenLabs' range (as before)")
}

private func voiceRequestTests() {
    let saved = ArisVoiceSettings(stability: 0.25, similarityBoost: 0.7, style: 0.2, useSpeakerBoost: true)
    let asked = body(of: ArisElevenLabs.request(text: "좋아요", key: "k", voiceID: "v1", speed: 1.05, model: "eleven_v4_turbo", saved: saved,
                                                previous: "안녕하세요. 오늘 날씨를 볼게요."))
    let settings = asked["voice_settings"] as? [String: Any] ?? [:]
    check(settings["stability"] as? Double == 0.25 && settings["similarity_boost"] as? Double == 0.7 && settings["speed"] as? Double == 1.05,
          "voice feel: the speech request carries the voice's saved settings merged with Aris's speed")
    check(asked["previous_text"] as? String == "안녕하세요. 오늘 날씨를 볼게요." && asked["model_id"] as? String == "eleven_v4_turbo",
          "voice feel: a sentence goes with what was said before it in the same answer")
    let long = String(repeating: "가", count: 900)
    check((body(of: ArisElevenLabs.request(text: "네", key: "k", previous: long))["previous_text"] as? String)?.count == ArisElevenLabs.previousTextLimit,
          "voice feel: only the last of a long run before goes along")
    check(body(of: ArisElevenLabs.request(text: "네", key: "k"))["previous_text"] == nil
          && body(of: ArisElevenLabs.request(text: "네", key: "k", previous: "  "))["previous_text"] == nil,
          "voice feel: the first line of an answer has nothing before it")
    check(body(of: ArisElevenLabs.request(text: "네", key: "k"))["language_code"] == nil,
          "voice feel: no language is forced (each model hears Korean or English from the words)")
}

private func voiceEndingTests() {
    check(ArisElevenLabs.withEnding("안녕하세요") == "안녕하세요." && ArisElevenLabs.withEnding("3시예요 ") == "3시예요." && ArisElevenLabs.withEnding("") == "",
          "voice feel: a line that ends on a word gets a full stop, so it falls as a sentence")
    let kept = ["정말요?", "와, 대단해요!", "음… 글쎄요…", "좋아요~", "됐어요?!", "(조금 늦어요)", "\"네\""]
    check(kept.allSatisfy { ArisElevenLabs.withEnding($0) == $0 }, "voice feel: an ending that is there (? ! … ~ brackets, quotes) stays exactly as it is")
    let line = "정말요?! 음… 좋아요~ 그럼, 갈게요."
    check(ArisSpeakable.speakable(line) == line && ArisSpeech.spoken(line) == line,
          "voice feel: preparing a line for the voice keeps every mark that carries intonation")
    var splitter = ArisSentenceSplitter()
    let sentences = splitter.add("정말요?! 오늘은 쉬어요… 내일 봐요~\n") + splitter.finish()
    check(sentences == ["정말요?!", "오늘은 쉬어요… 내일 봐요~"],
          "voice feel: cutting an answer into sentences keeps their endings")
    check(ArisSpeech.spokenPart(of: "**정말요?** 네, 그래요! 세 번째예요.") == "정말요? 네, 그래요!",
          "voice feel: the spoken cut of an answer keeps its question and exclamation marks")
}

private func voiceModelChoiceTests() {
    check(ArisElevenLabs.models.contains("eleven_v4") && ArisElevenLabs.model(stored: "eleven_v4") == "eleven_v4"
          && ArisElevenLabs.modelID == "eleven_v4_turbo" && ArisElevenLabs.model(stored: nil) == "eleven_v4_turbo",
          "voice feel: Eleven v4 can be picked; v4 Turbo stays the default (real-time start)")
    check(ArisAIStore.voiceModels == ArisElevenLabs.models && ArisAIServicesBuilder.voiceModels.map(\.id) == ArisElevenLabs.models,
          "voice feel: the page, the store and the voice offer the same models")
    let v4 = ArisAIServicesBuilder.voiceModels.first { $0.id == "eleven_v4" }
    check(v4?.trait == "가장 자연스러워요 · 말 시작이 조금 늦어요"
          && ArisAIServicesBuilder.voiceModels.filter { $0.trait.hasPrefix("가장 자연스러워요") }.count == 1,
          "voice feel: v4 says what it is (most natural, starts a little later), and only it claims to be the most natural")
}

private func voiceSameRequestWiringTests() {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris").standardized
    func source(_ path: String) -> String { (try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)) ?? "" }
    let speaker = source("private/Aris/ArisSpeaker.swift")
    check(speaker.components(separatedBy: "ArisElevenLabs.speech(").count == 2 && speaker.components(separatedBy: "Self.cloudSpeech(").count == 3,
          "voice feel: a single line, an answer's sentences and the preview all ask ElevenLabs through one call")
    let eleven = source("private/Aris/ArisElevenLabs.swift")
    check(eleven.components(separatedBy: "request(text:").count == 3 && eleven.contains("ArisVoiceSettingsCache.shared.settings(for: voiceID, key: key)"),
          "voice feel: the streamed speech builds its one request with the voice's cached settings")
    let live = source("components/Settings/ArisAIServicesLive.swift")
    check(live.contains("speaker.speak(ArisVoiceSample.line, preview: true)") && !live.contains("ArisElevenLabs.request(") && !live.contains("ArisElevenLabs.speech("),
          "voice feel: 미리 듣기 speaks through the speaker, as real speech does, never a request of its own")
}

private func voiceSettingsCacheTests() async {
    final class Fetches: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var failing: Set<String> = []
        func ask(_ id: String) -> Bool { lock.withLock { asked.append(id); return !failing.contains(id) } }
        var list: [String] { lock.withLock { asked } }
    }
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = ContinuousClock.now
        var now: ContinuousClock.Instant { lock.withLock { value } }
        func pass(_ duration: Duration) { lock.withLock { value += duration } }
    }
    let fetches = Fetches(), clock = Clock()
    let cache = ArisVoiceSettingsCache(retryAfter: .seconds(60), now: { clock.now }) { id, key in
        try? await Task.sleep(for: .milliseconds(20))
        guard key == "k", fetches.ask(id) else { return nil }
        return ArisVoiceSettings(stability: id == "a" ? 0.3 : 0.6, similarityBoost: 0.75, style: 0, useSpeakerBoost: true)
    }
    async let first = cache.settings(for: "a", key: "k")
    async let second = cache.settings(for: "a", key: "k")
    let (one, two) = await (first, second)
    let third = await cache.settings(for: "a", key: "k")
    check(one?.stability == 0.3 && two == one && third == one && fetches.list == ["a"],
          "voice feel: a voice's settings are fetched once and kept, a second asker meanwhile waits on the same fetch")
    let other = await cache.settings(for: "b", key: "k")
    let back = await cache.settings(for: "a", key: "k")
    check(other?.stability == 0.6 && back?.stability == 0.3 && fetches.list == ["a", "b", "a"],
          "voice feel: another voice fetches its own settings, and going back fetches again (the voice changed)")
    fetches.failing = ["c"]
    let failed = await cache.settings(for: "c", key: "k")
    let soon = await cache.settings(for: "c", key: "k")
    check(failed == nil && soon == nil && fetches.list == ["a", "b", "a", "c"],
          "voice feel: a fetch that failed isn't tried again on every sentence")
    fetches.failing = []
    clock.pass(.seconds(61))
    let later = await cache.settings(for: "c", key: "k")
    check(later?.stability == 0.6 && fetches.list == ["a", "b", "a", "c", "c"], "voice feel: a minute later it is tried again")
}
