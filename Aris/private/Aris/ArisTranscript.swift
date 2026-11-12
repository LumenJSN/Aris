//
//  ArisTranscript.swift
//  Aris
//
//  Two transcripts of one turn: Apple's live one (shown while you talk; good at
//  Korean, poor at English) and Whisper's, made from the recording once you stop
//  (good at English and mixed speech, but it sometimes misspells Korean, and it
//  makes things up in silence). Aris acts on whichever fits what was said.
//

import Foundation

enum ArisTranscript {
    /// Whisper returns nothing for clips under about a second; short ones get silence after them.
    static let shortestForWhisper = 1.5

    static func paddedForWhisper(_ samples: [Float], sampleRate: Double) -> [Float] {
        let shortest = Int(sampleRate * shortestForWhisper)
        return samples.count >= shortest ? samples : samples + [Float](repeating: 0, count: shortest - samples.count)
    }

    /// What Whisper tends to "hear" in silence or noise (it learned them from video subtitles).
    private static let silencePhrases: Set = [
        "시청해 주셔서 감사합니다", "시청해주셔서 감사합니다", "구독과 좋아요 부탁드립니다", "감사합니다",
        "thank you for watching", "thanks for watching", "thank you", "you",
    ]
    /// Silence kept after the last voice, so the end of a word isn't clipped.
    static let tailAfterVoice: Duration = .milliseconds(500)

    /// `heardVoice`: the microphone picked up speech at some point during the turn. `voiceFrames` and `loudest`: how
    /// much of the turn the level meter counted as voice (ArisTalkKey.isVoice) and its loudest level, the only
    /// evidence of speech when Apple (and Scribe) wrote nothing. `languages`: the ones turned on; `recognizer`: the
    /// language Apple's recogniser listened in (ArisHearingLocale).
    static func pick(whisper: String?, apple: String, heardVoice: Bool, voiceFrames: Int = 0, loudest: Float = 0,
                     languages: [String] = ArisLanguages.defaults, recognizer: String = ArisHearingLocale.fallback) -> String {
        guard heardVoice, let raw = whisper, case let whisper = speechOnly(raw), hasWords(whisper),
              !silencePhrases.contains(normalized(whisper)) else { return apple }
        // Speech all in the recogniser's own language (all-Korean, by default): Apple's is the better of the two.
        // Real speech Apple heard too keeps its brackets and parentheses ("report (final).pdf"): only *…* and ♪ go.
        if hasWords(apple) {
            return hearsAnotherLanguage(whisper, languages: languages, recognizer: recognizer) ? speechOnly(raw, keepingBrackets: true) : apple
        }
        // Apple and Scribe heard nothing (QA BUG-30: "*sad music*" in a silent room played Spotify): Whisper alone is a
        // turn only when it reads as speech and real voice was under it.
        return trustsAlone(whisper, voiceFrames: voiceFrames, loudest: loudest) ? whisper : apple
    }

    /// Whisper wrote in a script Apple's recogniser doesn't write, so another language was spoken and Apple's text
    /// is that language forced into its own letters: English words in Korean speech (Latin always counts, as it did),
    /// and Japanese, Chinese, Russian … once that language is turned on (audit voice-6: "明日の天気を教えて" lost to
    /// "아시타노 텐키오 오시에테"). A script of a language that isn't on is Whisper misreading the one that is (it hears
    /// short Korean as Japanese now and then), and Apple's text stands.
    static func hearsAnotherLanguage(_ whisper: String, languages: [String], recognizer: String) -> Bool {
        let allowed = languages.reduce(into: Set([ArisScript.latin])) { $0.formUnion(ArisScript.writing($1)) }
        return !ArisScript.used(in: whisper).subtracting(ArisScript.writing(recognizer)).isDisjoint(with: allowed)
    }

    // MARK: - Whisper alone (QA BUG-30)

    /// Voice this long, in level-meter frames (2048 samples, about 43 ms at 48 kHz): about half a second of speech.
    /// A click or a bump is a few frames.
    static let leastVoiceFramesAlone = 12
    /// The turn's loudest level must reach this: QA's silent room peaked at 0.1246 and Whisper wrote "*sad music*".
    static let leastLoudestAlone: Float = 0.2

    /// Whisper's words with no recognizer behind them are trusted only with real voice under them and nothing made up.
    static func trustsAlone(_ whisper: String, voiceFrames: Int, loudest: Float) -> Bool {
        voiceFrames >= leastVoiceFramesAlone && loudest >= leastLoudestAlone && !soundsMadeUp(whisper)
    }

    /// The words without what isn't speech: `*sad music*`, `[Music]`, `(박수)`, ♪.
    static func speechOnly(_ text: String, keepingBrackets: Bool = false) -> String {
        let cut = (keepingBrackets ? sounds : nonSpeech).reduce(keepingBrackets ? withoutSoundTags(text) : text) { $0.replacingOccurrences(of: $1, with: " ", options: .regularExpression) }
        return cut.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let nonSpeech = [#"\*[^*]*\*"#, #"\[[^\]]*\]"#, #"\([^)]*\)"#, #"（[^）]*）"#, #"【[^】]*】"#, "[♪♩♫♬🎵🎶]"]
    /// What is never speech, even with Apple's words beside it.
    private static let sounds = [#"\*[^*]*\*"#, "[♪♩♫♬🎵🎶]"]
    /// Words that make a bracketed piece a sound tag ("[Music]", "(upbeat music)", "(박수)"), not something said.
    private static let soundWords = ["music", "blank_audio", "applause", "laughter", "laughs", "laughing", "silence", "noise", "inaudible",
                                     "cheering", "sigh", "음악", "박수", "웃음", "노래", "효과음", "침묵", "소음"]

    /// The text without bracketed sound tags; any other bracket or parenthesis stays (real speech: "report (final).pdf").
    private static func withoutSoundTags(_ text: String) -> String {
        guard let pattern = try? NSRegularExpression(pattern: #"\[[^\]]*\]|\([^)]*\)|（[^）]*）|【[^】]*】"#) else { return text }
        var out = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: out) else { continue }
            let inner = out[range].dropFirst().dropLast().lowercased()
            if soundWords.contains(where: inner.contains) { out.replaceSubrange(range, with: " ") }
        }
        return out
    }

    /// Whisper's subtitle phrases (it learned them from video captions), said whole: dropped when Whisper is alone.
    private static let madeUpAlone: Set = [
        "thank you", "thanks", "thank you very much", "thank you so much", "thanks a lot", "bye", "bye bye", "bye-bye",
        "goodbye", "see you next time", "see you in the next video", "subscribe", "please subscribe", "okay", "ok", "oh",
        "uh", "um", "hmm", "so", "yeah", "i'm sorry",
        "감사합니다", "고맙습니다", "시청 감사합니다", "안녕히 계세요", "다음 영상에서 만나요", "네", "아", "어", "음",
    ]
    /// Pieces only subtitles say ("MBC 뉴스 이덕영입니다", "자막 제공 및 자막 편집", "구독과 좋아요 부탁드립니다").
    private static let madeUpPatterns = [
        #"^(mbc|kbs|sbs|jtbc|ytn|mbn)\s*뉴스"#, "시청해 ?주셔서", "구독과 ?좋아요", "구독 ?좋아요", "좋아요와 ?구독", "알림 ?설정",
        "자막 ?제공", "자막 ?편집", "자막 ?by", "한글 ?자막", "다음 영상에서", "for watching", "subtitles by", "captions by",
        "transcribed by", "amara\\.org", "please subscribe", "like and subscribe", "subscribe to",
    ]

    static func soundsMadeUp(_ whisper: String) -> Bool {
        let said = normalized(whisper)
        return madeUpAlone.contains(said) || silencePhrases.contains(said)
            || madeUpPatterns.contains { said.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: - Nothing heard

    /// Shown when nothing in the turn was speech; never said aloud, routed or acted on.
    static func notHeard(korean: Bool) -> String { korean ? "못 들었어요" : "I didn't catch that" }

    static func isNotHeard(_ line: String) -> Bool { line == notHeard(korean: true) || line == notHeard(korean: false) }

    private static func hasWords(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains)
    }

    /// The recording up to just after the last voice: trailing silence is where Whisper invents words.
    static func trimmed(_ samples: [Float], voiceEndsAfter: Duration?, sampleRate: Double) -> [Float] {
        guard let voiceEndsAfter else { return samples }
        let keep = (voiceEndsAfter + tailAfterVoice) / .seconds(1) * sampleRate
        return Array(samples.prefix(Int(keep)))
    }

    private static func normalized(_ text: String) -> String {
        let marks = CharacterSet(charactersIn: ".!?。,~…'\" ").union(.whitespacesAndNewlines)
        return text.lowercased().trimmingCharacters(in: marks).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
