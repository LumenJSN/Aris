//
//  ArisRouter.swift
//  Aris
//
//  The second guess at an everyday request, for words the keyword rules missed
//  ("노래 좀 바꿔줘", "turn it down a bit"). One call to TypeSafe's Jev picks an
//  action and an app, each with a confidence; Aris acts only when Jev is sure,
//  and anything else (a question, a doubt, an error) still goes to Claude.
//  The TypeSafe key lives in ~/.config/aris/typesafe-key.
//

import Foundation

enum ArisRouter {
    /// Pinned, so thresholds tuned against it keep meaning the same thing.
    static let model = "jev-1.14.0"
    /// Below this confidence Aris asks Claude instead of acting.
    static let threshold = 0.7
    /// Only this sure that a request is real work does it get the stronger (slower) model.
    static let workThreshold = 0.6
    /// This sure that it's critical (sending, deleting, money), it's handled as critical; less sure, as real work.
    static let criticalThreshold = 0.5
    /// Past this, Claude takes over rather than keeping you waiting.
    static let timeout: Duration = .milliseconds(600)
    static let keyName = "typesafe-key"
    static let noApp = "none"
    /// Where Aris looks for apps to open.
    static let appFolders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                             "/System/Applications/Utilities", UserHome.path + "/Applications"]
    private static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

    enum Action: String, CaseIterable {
        case playMusic = "play_music", pauseMusic = "pause_music", nextTrack = "next_track", previousTrack = "previous_track"
        case volumeUp = "volume_up", volumeDown = "volume_down", volumeSet = "volume_set", mute
        case brightnessUp = "brightness_up", brightnessDown = "brightness_down", brightnessSet = "brightness_set"
        case openApp = "open_app", tellTime = "tell_time", tellDate = "tell_date", askClaude = "ask_claude"

        var criterion: String {
            switch self {
            case .playMusic: return "Start or resume music (노래 틀어줘, 음악 다시 재생, play some music). Never for turning music off"
            case .pauseMusic: return "Pause or stop the music that is playing (음악 꺼, 노래 꺼줘, 잠깐 멈춰, 노래 그만, stop the music)"
            case .nextTrack: return "Skip to the next song (다음 곡, 노래 바꿔줘, 넘겨, skip this one)"
            case .previousTrack: return "Go back to the previous song (이전 곡, 전 노래 다시, go back a song)"
            case .volumeUp: return "Make the sound louder (소리 키워, 잘 안 들려, louder, turn it up)"
            case .volumeDown: return "Make the sound quieter (소리 줄여, 너무 시끄러워, turn it down a bit)"
            case .volumeSet: return "Set the volume to a number (볼륨 30, 소리 70 정도로, volume to 50)"
            case .mute: return "Mute or unmute the sound (음소거, 소리 꺼, mute)"
            case .brightnessUp: return "Make the screen brighter (화면 밝게, 너무 어두워, brighter)"
            case .brightnessDown: return "Make the screen dimmer (화면 어둡게, 눈부셔, dim the screen)"
            case .brightnessSet: return "Set the screen brightness to a number (밝기 40, brightness to 80)"
            case .openApp: return "Open or switch to an app (카톡 열어, 피그마 켜줘, open Safari)"
            case .tellTime: return "Ask what time it is right now (지금 몇 시야, what time is it). Not when something happens"
            case .tellDate: return "Ask today's date or today's weekday (오늘 며칠이야, 오늘 무슨 요일, what's the date). Not any other day, such as tomorrow or next week"
            case .askClaude:
                return "A question, advice, a recommendation, an explanation, a task with several steps, or anything not listed above (음악 추천해줘, 볼륨 크면 귀에 안 좋아?, 메일 정리해줘)"
            }
        }
    }

    struct Answers: Equatable {
        let intent: Action
        let intentConfidence: Double
        let app: String
        let appConfidence: Double
        let inputTokens: Int?
        /// Quick, real work (several steps, research, writing: the stronger model), or critical.
        var tier = ArisTier.quick
        /// Several steps on websites: handed to Aside, in the background.
        var browserWork = false
    }

    struct Failure: Error {
        let message: String
        /// TypeSafe's HTTP status, when it answered (ArisRouterKeyHealth reads a 401 as a key it refused).
        var status: Int? = nil
    }

    // MARK: - Request

    static func request(text: String, apps: [String], key: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let intent: [String: Any] = [
            "type": "choice",
            "instructions": "What does the user want their Mac voice assistant to do? The words come from speech recognition, may mix Korean and English, and may be slightly misheard.",
            "criteria": Dictionary(uniqueKeysWithValues: Action.allCases.map { ($0.rawValue, $0.criterion) }),
        ]
        let app: [String: Any] = [
            "type": "choice",
            "instructions": "Which installed Mac app do the words name, if any?",
            "criteria": appCriteria(apps),
        ]
        let effort: [String: Any] = [
            "type": "choice",
            "instructions": "If this goes to the assistant's AI, how much work is it?",
            "criteria": [
                "quick": "A quick answer or a single action: a fact, a definition, one command (프랑스 수도가 어디야, 음악 추천해줘)",
                "work": "Several steps, research, comparing, planning or writing something, or opening and arranging several windows or apps (이번 주 일정 정리해줘, 이 두 노트북 비교해줘, 메일 초안 써줘, 엑셀 4개 열어서 4등분 해줘)",
                "critical": "Sends, posts, deletes, pays for or changes something that is hard to undo (엄마한테 문자 보내줘, 이 메일 답장 보내, 다운로드 폴더 정리해서 지워줘, 이거 주문해줘)",
            ],
        ]
        let browser: [String: Any] = [
            "type": "choice",
            "instructions": "Does doing this take several steps on websites in a browser?",
            "criteria": [
                "browser": "Several steps on websites: logged-in sites, filling forms, searching or comparing across pages, booking, shopping carts (쿠팡에서 이어폰 찾아서 장바구니에 넣어줘, 이 사이트에서 신청서 작성해줘, 다음 주 부산 항공권 최저가 비교해줘)",
                "other": "Anything else: a question, a Mac action, opening one page or link, the weather (프랑스 수도가 어디야, 유튜브 열어줘, 소리 줄여줘)",
            ],
        ]
        let body: [String: Any] = ["model": model, "state": text,
                                   "questions": ["intent": intent, "app": app, "effort": effort, "browser": browser]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Each installed app, described by its Korean nicknames when it has some.
    static func appCriteria(_ apps: [String]) -> [String: String] {
        var nicknames: [String: [String]] = [:]
        for (nickname, app) in ArisIntent.appAliases { nicknames[app, default: []].append(nickname) }
        var criteria = [noApp: "No app is named, or the words aren't about opening an app"]
        for app in apps where app != noApp {
            let also = nicknames[app]?.sorted().joined(separator: ", ")
            criteria[app] = also.map { "\(app) (\($0))" } ?? app
        }
        return criteria
    }

    /// App names in these folders, for the app question (TypeSafe allows 255 options).
    static func installedApps(in folders: [String]) -> [String] {
        let names = folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
                .filter { $0.hasSuffix(".app") }
                .map { String($0.dropLast(4)) }
        }
        return Array(Set(names)).sorted().prefix(254).map { $0 }
    }

    // MARK: - Reply

    static func parse(_ data: Data) -> Answers? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = body["answers"] as? [String: Any],
              let intent = answers["intent"] as? [String: Any],
              let choice = (intent["choice"] as? String).flatMap(Action.init(rawValue:)),
              let confidence = intent["confidence"] as? Double else { return nil }
        let app = answers["app"] as? [String: Any]
        let effort = answers["effort"] as? [String: Any]
        let usage = body["usage"] as? [String: Any]
        var parsed = Answers(intent: choice, intentConfidence: confidence,
                             app: app?["choice"] as? String ?? noApp, appConfidence: app?["confidence"] as? Double ?? 0,
                             inputTokens: usage?["input_tokens"] as? Int)
        let effortConfidence = effort?["confidence"] as? Double ?? 0
        switch effort?["choice"] as? String {
        case "critical": parsed.tier = effortConfidence >= criticalThreshold ? .critical : .work
        case "work": parsed.tier = effortConfidence >= workThreshold ? .work : .quick
        default: break
        }
        let browser = answers["browser"] as? [String: Any]
        parsed.browserWork = browser?["choice"] as? String == "browser" && (browser?["confidence"] as? Double ?? 0) >= workThreshold
        return parsed
    }

    /// "제대로 해줘", "신중하게", "carefully": the user asks for the critical setup themselves.
    static func asksForCare(_ text: String) -> Bool {
        text.range(of: #"(?i)제대로|신중하게|신중히|꼼꼼하게|꼼꼼히|조심해서|carefully|thoroughly"#, options: .regularExpression) != nil
    }

    /// What to do on the Mac, or nil to ask Claude.
    static func decide(_ answers: Answers, text: String, threshold: Double = threshold) -> ArisIntent? {
        guard answers.intentConfidence >= threshold else { return nil }
        let number = ArisIntent.firstNumber(in: text).map { min(100, max(0, $0)) }
        switch answers.intent {
        case .playMusic: return ArisIntent.playsSomethingNamed(text) ? nil : .media(.play)
        case .pauseMusic: return .media(.pause)
        case .nextTrack: return .media(.next)
        // "되돌려" is undo, never the previous track, unless a song is named (QA BUG-42).
        case .previousTrack: return ArisIntent.saysUndo(text) ? .undo : .media(.previous)
        case .volumeUp: return .volume(.up)
        case .volumeDown: return .volume(.down)
        case .volumeSet: return number.map { .volume(.set($0)) }
        case .mute: return .volume(.mute)
        case .brightnessUp: return .brightness(.up)
        case .brightnessDown: return .brightness(.down)
        case .brightnessSet: return number.map { .brightness(.set($0)) }
        case .openApp:
            guard answers.app != noApp, answers.appConfidence >= threshold else { return nil }
            return .openApp(answers.app)
        case .tellTime: return .tellTime
        case .tellDate: return .tellDate
        case .askClaude: return nil
        }
    }

    // MARK: - Tuning record

    /// A private, local line per guess (words, choice, confidence) for tuning the threshold.
    static func record(_ text: String, _ answers: Answers, acted: Bool, milliseconds: Int) {
        ArisTuningLog.append([
            "words": text, "intent": answers.intent.rawValue,
            "confidence": answers.intentConfidence, "app": answers.app, "appConfidence": answers.appConfidence,
            "acted": acted, "ms": milliseconds,
        ], to: "router-log.jsonl")
    }

    // MARK: - Network

    static func ask(_ text: String, apps: [String], key: String) async throws -> Answers {
        let (data, response) = try await URLSession.shared.data(for: request(text: text, apps: apps, key: key))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // What the answer says about the key, for the settings' status line (ArisRouterKeyHealth).
        ArisRouterKeyHealth.note(status: status == 0 ? nil : status)
        guard status == 200 else {
            throw Failure(message: "TypeSafe answered \(status): \(String(decoding: data.prefix(300), as: UTF8.self))", status: status)
        }
        guard let answers = parse(data) else { throw Failure(message: "TypeSafe's reply didn't make sense") }
        return answers
    }
}
