//
//  ArisAIVoices.swift
//  Aris
//
//  The voices AI 서비스 › 말하기 offers, each from its service's own list: the ElevenLabs account's voices
//  (GET /v1/voices, read by ArisElevenLabs), its Voice Library (GET /v1/shared-voices) with 추가 (POST /v1/voices/add),
//  a voice named by a link or an id, and the voices installed on this Mac. Requests and answers are plain functions,
//  and the calls go through a transport that is handed in, so the tests never reach ElevenLabs. Foundation only (tested).
//

import Foundation

/// One request out and its answer back: the body and the HTTP status, or nil when nothing answered.
typealias ArisAITransport = @Sendable (URLRequest) async -> (data: Data, status: Int)?

/// A voice in ElevenLabs' shared library.
struct ArisAILibraryVoice: Equatable, Identifiable, Sendable {
    let id: String
    /// Whose voice it is: 추가 needs it.
    let owner: String
    let name: String
    let desc: String
    let preview: String?
}

struct ArisAILibraryQuery: Equatable, Sendable {
    var search = ""
    /// "" (any), or ElevenLabs' own values: a language code, "female" / "male" / "neutral", a use case.
    var language = ""
    var gender = ""
    var use = ""

    static let languages: [(id: String, title: String)] = [("", "모든 언어"), ("ko", "한국어"), ("en", "영어"), ("ja", "일본어"), ("es", "스페인어")]
    static let genders: [(id: String, title: String)] = [("", "모든 성별"), ("female", "여성"), ("male", "남성"), ("neutral", "중성")]
    static let uses: [(id: String, title: String)] = [("", "모든 쓰임"), ("conversational", "대화"), ("narrative_story", "내레이션"),
                                                      ("informative_educational", "교육"), ("characters_animation", "캐릭터")]

    static func options(_ filter: String) -> [(id: String, title: String)] {
        filter == "language" ? languages : filter == "gender" ? genders : uses
    }

    func value(_ filter: String) -> String { filter == "language" ? language : filter == "gender" ? gender : use }

    func setting(_ filter: String, _ value: String) -> ArisAILibraryQuery {
        var next = self
        switch filter {
        case "language": next.language = value
        case "gender": next.gender = value
        default: next.use = value
        }
        return next
    }
}

enum ArisAIEleven {
    static let host = "https://api.elevenlabs.io"
    private static let timeout: TimeInterval = 15

    private static func request(_ path: String, key: String, query: [URLQueryItem] = []) -> URLRequest? {
        guard var components = URLComponents(string: host + path) else { return nil }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        return request
    }

    // MARK: The account's voices

    static func voicesRequest(key: String) -> URLRequest? { request("/v1/voices", key: key) }

    /// The account's voices as the menu lists them: its own first (ArisElevenLabs' order).
    static func voices(from data: Data) -> [ArisAIVoice]? {
        ArisElevenLabs.voices(from: data)?.map {
            ArisAIVoice(id: $0.id, name: $0.name, desc: $0.detail, own: $0.own, preview: $0.previewURL?.absoluteString)
        }
    }

    // MARK: The library

    static func libraryRequest(key: String, _ query: ArisAILibraryQuery) -> URLRequest? {
        var items = [URLQueryItem(name: "page_size", value: "30")]
        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty { items.append(URLQueryItem(name: "search", value: String(search.prefix(80)))) }
        if !query.language.isEmpty { items.append(URLQueryItem(name: "language", value: query.language)) }
        if !query.gender.isEmpty { items.append(URLQueryItem(name: "gender", value: query.gender)) }
        if !query.use.isEmpty { items.append(URLQueryItem(name: "use_cases", value: query.use)) }
        return request("/v1/shared-voices", key: key, query: items)
    }

    private static let words: [String: String] = [
        "female": "여성", "male": "남성", "neutral": "중성", "conversational": "대화", "narrative_story": "내레이션",
        "informative_educational": "교육", "characters_animation": "캐릭터", "social_media": "소셜", "entertainment_tv": "방송", "advertisement": "광고",
    ]

    /// A language code as Korean names it ("ko" → "한국어"), or English ("Korean"); what isn't a code is kept.
    static func languageName(_ code: String, english: Bool = false) -> String {
        Locale(identifier: english ? "en_US" : "ko_KR").localizedString(forLanguageCode: code) ?? code
    }

    /// `english`: the page is drawn in English, so ElevenLabs' own English words are kept and a language is named in English.
    static func library(from data: Data, english: Bool = false) -> [ArisAILibraryVoice]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let list = json["voices"] as? [[String: Any]] else { return nil }
        return list.compactMap { raw in
            guard let id = raw["voice_id"] as? String, let owner = raw["public_owner_id"] as? String, let name = raw["name"] as? String,
                  isID(id), isID(owner), !name.isEmpty else { return nil }
            let word = { (text: String) in english ? text.replacingOccurrences(of: "_", with: " ") : words[text] ?? text }
            let parts = [raw["descriptive"] as? String, (raw["gender"] as? String).map(word),
                         (raw["language"] as? String).map { languageName($0, english: english) }, (raw["use_case"] as? String).map(word)]
            return ArisAILibraryVoice(id: id, owner: owner, name: String(name.prefix(80)),
                                      desc: parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), preview: raw["preview_url"] as? String)
        }
    }

    /// 추가: the library voice joins the account under its own name.
    static func addRequest(key: String, voice: ArisAILibraryVoice) -> URLRequest? {
        guard isID(voice.owner), isID(voice.id), var request = request("/v1/voices/add/\(voice.owner)/\(voice.id)", key: key) else { return nil }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["new_name": voice.name])
        return request
    }

    /// The id of the voice now in the account (the answer to 추가).
    static func addedID(from data: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["voice_id"] as? String
    }

    // MARK: A link or an id

    /// Letters and digits only: an id goes into a path.
    static func isID(_ text: String) -> Bool {
        (8...64).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// The voice id in a library share link ("…/voice-library?voiceId=…", "…/voice/…"), or the id itself.
    static func voiceID(fromLink text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 12, isID(trimmed) { return trimmed }
        guard let range = trimmed.range(of: #"(?:voiceId=|voice/|voices/)([A-Za-z0-9]{12,64})"#, options: .regularExpression) else { return nil }
        let match = String(trimmed[range])
        return match.split(whereSeparator: { $0 == "=" || $0 == "/" }).last.map(String.init)
    }

    static func voiceRequest(key: String, id: String) -> URLRequest? {
        isID(id) ? request("/v1/voices/\(id)", key: key) : nil
    }

    /// One voice (GET /v1/voices/{id}): the same fields as a row of the account's list.
    static func voice(from data: Data) -> ArisAIVoice? {
        guard let object = try? JSONSerialization.jsonObject(with: data), let wrapped = try? JSONSerialization.data(withJSONObject: ["voices": [object]]) else { return nil }
        return voices(from: wrapped)?.first
    }

    // MARK: Calls

    /// What a link's voice turned out to be.
    enum Found: Equatable, Sendable {
        /// Already usable with this key.
        case mine(ArisAIVoice)
        /// In the library: 추가 brings it in.
        case shared(ArisAILibraryVoice)
    }

    static func loadVoices(key: String, transport: ArisAITransport) async -> [ArisAIVoice]? {
        guard let request = voicesRequest(key: key), let answer = await transport(request), answer.status == 200 else { return nil }
        return voices(from: answer.data)
    }

    static func loadLibrary(key: String, _ query: ArisAILibraryQuery, english: Bool = false, transport: ArisAITransport) async -> [ArisAILibraryVoice]? {
        guard let request = libraryRequest(key: key, query), let answer = await transport(request), answer.status == 200 else { return nil }
        return library(from: answer.data, english: english)
    }

    /// The voice a link names: one the account can already use, else the library's voice with that id.
    static func find(key: String, id: String, english: Bool = false, transport: ArisAITransport) async -> Found? {
        if let request = voiceRequest(key: key, id: id), let answer = await transport(request), answer.status == 200, let voice = voice(from: answer.data) {
            return .mine(voice)
        }
        guard let shared = await loadLibrary(key: key, ArisAILibraryQuery(search: id), english: english, transport: transport)?.first(where: { $0.id == id }) else { return nil }
        return .shared(shared)
    }

    /// Adds a library voice to the account; its id there, or nil when ElevenLabs said no.
    static func add(key: String, voice: ArisAILibraryVoice, transport: ArisAITransport) async -> String? {
        guard let request = addRequest(key: key, voice: voice), let answer = await transport(request), answer.status == 200 else { return nil }
        return addedID(from: answer.data)
    }
}

/// A voice installed on this Mac, as AVSpeechSynthesisVoice describes it.
struct ArisAISystemVoice: Equatable, Sendable {
    let identifier: String
    let name: String
    /// "ko-KR".
    let language: String
    /// 1 default, 2 enhanced, 3 premium.
    let quality: Int
    /// 1 male, 2 female, 0 not said.
    let gender: Int
}

enum ArisAISystemVoices {
    /// The Mac's voices for the menu: the languages Aris is set to first (in that order), the better voices of a
    /// language first, the old robotic ones last.
    /// `english`: what each voice is ("female · Korean (South Korea)") is said in English.
    static func list(_ voices: [ArisAISystemVoice], languages: [String], english: Bool = false) -> [ArisAIVoice] {
        let bases = languages.map(base)
        func robotic(_ voice: ArisAISystemVoice) -> Bool { voice.identifier.contains("eloquence") || voice.identifier.contains("speech.synthesis") }
        func order(_ voice: ArisAISystemVoice) -> (Int, Int, String, Int, String) {
            (robotic(voice) ? 1 : 0, bases.firstIndex(of: base(voice.language)) ?? bases.count, voice.language, -voice.quality, voice.name)
        }
        return voices.sorted { order($0) < order($1) }.map { voice in
            let gender = voice.gender == 2 ? (english ? "female" : "여성") : voice.gender == 1 ? (english ? "male" : "남성") : nil
            let language = Locale(identifier: english ? "en_US" : "ko_KR").localizedString(forIdentifier: voice.language) ?? voice.language
            return ArisAIVoice(id: voice.identifier, name: voice.name, desc: [gender, language].compactMap { $0 }.joined(separator: " · "),
                               tail: voice.quality >= 3 ? "프리미엄" : voice.quality == 2 ? "고급" : "")
        }
    }

    private static func base(_ code: String) -> String {
        String(code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }
}
