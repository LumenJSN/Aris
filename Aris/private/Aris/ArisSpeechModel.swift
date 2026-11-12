//
//  ArisSpeechModel.swift
//  Aris
//
//  The owner's pick ③ B (mockups/audit-3-whisper.html): the Whisper model is never downloaded unasked. It is asked for on
//  the setup's 받아쓰기 page (ArisModelLine; the card after the first turn is gone, pick 9-A of 2026-11-11) and in
//  Settings; while it comes in the right ear shows a mini bar and its percent (대기 offline, 멈춤 paused, 준비 끝 at the
//  end), and a tap opens its card. Wi-Fi only; offline it waits and
//  goes on by itself. A Mac that already has the large model keeps it without being asked. Pure: the words (in the
//  UI's language, ArisUIWords: the card was Korean on an English Mac, fresh install F5), the numbers and the rules;
//  ArisModelDownloader runs them.
//

import Foundation

enum ArisSpeechModel: String, CaseIterable, Equatable {
    case small, large

    var variant: String {
        switch self {
        case .small: "openai_whisper-small_216MB"
        case .large: "openai_whisper-large-v3-v20240930_turbo_632MB"
        }
    }

    var megabytes: Int { self == .small ? 216 : 632 }
    var name: String { name(english: ArisUIWords.english) }
    func name(english: Bool) -> String {
        self == .small ? ArisUIWords.text("작은 모델", "Small model", english: english) : ArisUIWords.text("큰 모델", "Large model", english: english)
    }

    var sizeText: String { sizeText(english: ArisUIWords.english) }
    func sizeText(english: Bool) -> String { self == .small ? ArisUIWords.text("약 220 MB", "220 MB", english: english) : "630 MB" }
    var memory: String { memory(english: ArisUIWords.english) }
    /// Short enough for the card's button in either language: "a few hundred MB" was cut off there (ArisModelOffer.cost).
    func memory(english: Bool) -> String {
        self == .small ? ArisUIWords.text("수백 MB", "under 1 GB", english: english) : ArisUIWords.text("1~2 GB", "1–2 GB", english: english)
    }
}

enum ArisModelDownload: Equatable {
    case idle
    case running(Double)
    /// Offline, or on a network it mustn't use: goes on by itself.
    case waiting(Double)
    case paused(Double)
    /// Not the network (a full disk, a bad file): 다시 받기, and tried again after the backoff.
    case failed(Double)
    case done

    var fraction: Double {
        switch self {
        case .idle: 0
        case let .running(f), let .waiting(f), let .paused(f), let .failed(f): f
        case .done: 1
        }
    }

    var earText: String? { earText(english: ArisUIWords.english) }

    func earText(english: Bool) -> String? {
        switch self {
        case .idle: nil
        case .running: "\(percent)%"
        case .waiting: ArisUIWords.text("대기", "Wait", english: english)
        case .paused: ArisUIWords.text("멈춤", "Paused", english: english)
        case .failed: ArisUIWords.text("실패", "Failed", english: english)
        case .done: ArisUIWords.text("준비 끝", "Ready", english: english)
        }
    }

    func status(remaining: TimeInterval?, english: Bool = ArisUIWords.english) -> String {
        switch self {
        case .idle, .running:
            guard let remaining else { return ArisUIWords.text("받는 중", "Downloading", english: english) }
            let s = Int(remaining.rounded(.up)), minutes = Int((Double(s) / 60).rounded(.up))
            return s > 60 ? ArisUIWords.text("약 \(minutes)분 남음", "About \(minutes) min left", english: english)
                : ArisUIWords.text("약 \(max(1, s))초 남음", "About \(max(1, s)) s left", english: english)
        case .waiting: return ArisUIWords.text("인터넷이 돌아오면 이어서 받을게요", "I'll go on when the internet is back", english: english)
        case .paused: return ArisUIWords.text("잠시 멈췄어요", "Paused", english: english)
        case .failed: return ArisUIWords.text("받지 못했어요 · 곧 다시 해 볼게요", "Couldn't download · trying again soon", english: english)
        case .done: return ArisUIWords.text("다 받았어요", "Downloaded", english: english)
        }
    }

    /// Tried again by itself after the backoff (and by 다시 받기).
    var retries: Bool { if case .failed = self { return true }; return false }

    /// The nearest whole percent, 100 only once it's done.
    var percent: Int { self == .done ? 100 : min(99, Int((fraction * 100).rounded())) }

    func numbers(_ model: ArisSpeechModel) -> String {
        let f = fraction
        return "\(percent)% · \(Int((f * Double(model.megabytes)).rounded(.down)))/\(model.megabytes) MB"
    }
}

/// Whether a model's folder holds everything WhisperKit loads. A download cut short leaves the compiled models without
/// their weights (seen on the user's Mac: AudioEncoder.mlmodelc with no weights/weight.bin), so one file is not enough.
enum ArisModelInstall: Equatable {
    case complete, partial, none

    static let required = [
        "AudioEncoder.mlmodelc/coremldata.bin", "AudioEncoder.mlmodelc/weights/weight.bin",
        "TextDecoder.mlmodelc/coremldata.bin", "TextDecoder.mlmodelc/weights/weight.bin",
        "MelSpectrogram.mlmodelc/coremldata.bin", "generation_config.json",
    ]

    /// `present`: the folder's files, as paths relative to it.
    static func state(present: Set<String>) -> Self {
        let have = required.filter(present.contains).count
        return have == required.count ? .complete : have == 0 ? .none : .partial
    }
}

/// What a failed load does: a complete model is kept and loaded again after the backoff (memory pressure while it
/// compiles is passing); only a model missing files is removed and offered again.
enum ArisModelLoadFailure: Equatable {
    case retry, redownload

    static func action(install: ArisModelInstall) -> Self { install == .complete ? .retry : .redownload }
}

enum ArisModelOffer {
    /// What `stored` holds after 나중에.
    static let later = "later"
    static var prepLine: String { ArisUIWords.text("음성 인식 준비 중", "Getting speech recognition ready") }
    static var prepNote: String { ArisUIWords.text(" · 처음 한 번만 잠깐 걸려요", " · only takes a moment the first time") }

    /// Failed loads of a complete model in a row before the notch says so.
    static let troubleAfter = 3
    static var troubleEar: String { ArisUIWords.text("오류", "Error") }
    static var troubleLine: String {
        ArisUIWords.text("잠시 뒤 다시 해 볼게요. 계속되면 Mac을 다시 시작해 주세요.", "I'll try again in a moment. If it keeps happening, restart your Mac.")
    }
    static func troubleTitle(_ model: ArisSpeechModel) -> String {
        ArisUIWords.text("\(model.name)을 열지 못하고 있어요", "The \(model.name.lowercased()) won't open")
    }

    // MARK: - The card's words

    static func title(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("받아쓰기를 더 정확하게 할까요?", "Make dictation more accurate?", english: english)
    }
    static var body: String {
        ArisUIWords.text("지금은 Apple 음성 인식으로 듣고 있어요. 모델을 한 번 받아 두면 더 잘 알아들어요. 이 Mac 안에만 저장돼요.",
                         "Right now I listen with Apple's speech recognition. Download a model once and I'll understand you better. It stays on this Mac.")
    }
    /// A model's button: its name (the small one recommended), then its size and the memory it takes.
    static func choice(_ model: ArisSpeechModel) -> String {
        model.name + (model == .small ? ArisUIWords.text(" · 추천", " · Recommended") : "")
    }
    /// One line under the name, and it must fit the button (choiceTextRoom): the card hangs in a fixed room under the
    /// notch, so a longer line is cut with "…", not wrapped (VM run 2026-11-10: "About 220 MB · a few hundred…").
    static func cost(_ model: ArisSpeechModel, english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("\(model.sizeText(english: english)) · 메모리 \(model.memory(english: english))",
                         "\(model.sizeText(english: english)) · \(model.memory(english: english)) of memory", english: english)
    }

    // MARK: - The card's measures (ArisModelCard draws with them; the tests check the words fit)

    static let cardWidth: Double = 440
    /// The card's own inset at each side.
    static let cardInset: Double = 16
    /// Between the two models' buttons.
    static let choiceGap: Double = 6
    /// Inside a button, at each side.
    static let choiceInset: Double = 12
    /// A button's second line: system 11.
    static let costFontSize: Double = 11
    /// The width one button leaves its lines: the card shared by the two buttons, less each one's inset.
    static var choiceTextRoom: Double {
        (cardWidth - 2 * cardInset - choiceGap * Double(ArisSpeechModel.allCases.count - 1)) / Double(ArisSpeechModel.allCases.count) - 2 * choiceInset
    }
    static var accept: String { ArisUIWords.text("받기", "Download") }
    static var notNow: String { ArisUIWords.text("나중에", "Later") }
    static var wifiOnly: String { ArisUIWords.text("Wi-Fi에서만 받아요", "Downloads on Wi-Fi only") }
    static func progressTitle(_ model: ArisSpeechModel, state: ArisModelDownload) -> String {
        if state.retries { return ArisUIWords.text("\(model.name)을 받지 못했어요", "Couldn't download the \(model.name.lowercased())") }
        if state == .done { return ArisUIWords.text("\(model.name) 준비 끝", "\(model.name) ready") }
        return ArisUIWords.text("\(model.name) 받는 중", "Downloading the \(model.name.lowercased())")
    }
    static func progressBody(done: Bool) -> String {
        done ? ArisUIWords.text("이제 받아쓰기가 이 모델을 써요.", "Dictation uses this model now.")
            : ArisUIWords.text("받는 동안에도 Apple 음성 인식으로 계속 말할 수 있어요.", "You can keep talking with Apple's speech recognition while it downloads.")
    }
    static var close: String { ArisUIWords.close }
    static var retry: String { ArisUIWords.text("다시 받기", "Try again") }
    static var cancel: String { ArisUIWords.text("취소", "Cancel") }
    static var hide: String { ArisUIWords.text("숨기기", "Hide") }
    static var resume: String { ArisUIWords.text("이어 받기", "Resume") }
    static var pause: String { ArisUIWords.text("멈춤", "Pause") }
    /// VoiceOver: the ear's bar.
    static func earLabel(_ text: String) -> String { ArisUIWords.text("음성 모델 \(text)", "Speech model \(text)") }

    /// The model to load: the owner's pick, else (none, or 나중에) the complete large one a Mac already has.
    static func chosen(stored: String?, largeInstalled: Bool) -> ArisSpeechModel? {
        if let pick = stored.flatMap(ArisSpeechModel.init(rawValue:)) { return pick }
        return largeInstalled ? .large : nil
    }

    /// A lost or missing network: wait for it. Anything else is a failure (다시 받기, then the backoff).
    static func waitsForNetwork(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        let network: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                                           .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed]
        return network.contains(error.code)
    }

    /// Wi-Fi only: never offline or on an expensive network (a phone's hotspot).
    static func mayDownload(online: Bool, expensive: Bool) -> Bool { online && !expensive }

    /// Seconds left at the rate since this run started at `from`; nil until there is a rate (2 s in, some progress).
    static func remaining(fraction: Double, elapsed: TimeInterval, from: Double = 0) -> TimeInterval? {
        let gained = fraction - from
        guard gained > 0, elapsed >= 2 else { return nil }
        return (1 - fraction) * elapsed / gained
    }
}

/// No nudge while the user is busy (a drag, a turn, a card, the first-run guide): it waits for idle and shows then (QA VM:
/// "받아쓰기를 더 정확하게 할까요?" came up mid-drag and blocked the drop). An open card he asked for still shows. Pure.
enum ArisModelOfferQuiet {
    /// `settings`: Aris's Settings window is in front and in view. The offer hangs under the notch, over whatever is
    /// there, so it waits until that window is closed or covered (the second VM run: it opened over the Settings window).
    static func mayShow(dragging: Bool, turn: Bool, card: Bool, onboarding: Bool, settings: Bool = false) -> Bool {
        !(dragging || turn || card || onboarding || settings)
    }
}
