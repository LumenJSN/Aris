//
//  ArisNotchPreviewPlan.swift
//  Aris
//
//  What the notch preview at the top of a settings page shows (mockup C's stage), on the pages that have something to
//  show (the owner's pick 1-A: 대화, 목소리 · 언어, 노치, 컴퓨터 제어, AI 서비스, 스킬 with a skill; 팀원 plays its own): the
//  notch's size for the page and its settings, what is inside it, the line under it, and where the star sits. The
//  notch is r13 closed and r31 open, opens in 280 ms (0.2, 0.8, 0.2, 1) and closes in 200 ms (0.45, 0, 0.55, 1); the
//  waveform has 4 bars 2.5 wide, 2–17 tall, a step every 58 ms, grey 110 to white. Foundation only (tested).
//

import Foundation

struct ArisNotchPreviewInput: Equatable {
    var page = ArisSettingsPage.aris
    var wakeWord = true
    var talkCaps = ["⌥", "Space"]
    var speedTitle = "보통"
    var voiceName = ArisNotchPreviewInput.macVoice
    /// What the caption calls the voice when no ElevenLabs voice speaks.
    static let macVoice = "Mac 목소리"
    /// "real", "menubar" or "custom".
    var heightMode = "real"
    var customHeight = 32.0
    var hoverOpens = true
    var circleGesture = true
    var seesScreen = true
    var teammateNames: [String] = []
    /// 스킬: the feature is on, and the skills there are (titles).
    var skillsOn = false
    var skillTitles: [String] = []
    /// AI 서비스: who thinks, listens and speaks now ("Claude", "Whisper", "ElevenLabs · Geaun").
    var aiWho: [String] = []
}

struct ArisNotchPreviewPlan: Equatable {
    enum Content: Equatable {
        case none
        case wave
        case words([String])
        /// A window under the notch, circled when the gesture is on.
        case window(circle: Bool)
        /// An answer that followed a skill: its "<title> 스킬 사용 중" tag, then the answer's first line.
        case skillAnswer(tag: String, line: String)
        /// AI 서비스: the three names along the notch's bottom edge (mockup ai-services-D's `.notch.who`).
        case who([String])
    }

    enum Motion: Equatable { case open, close }

    static let closedSize = (width: 150.0, height: 29.0)
    static let line = "안녕하세요, 아리스예요. 이 속도로 말할게요."
    /// The 스킬 page's sample answer under its tag.
    static let skillLine = "축제 부스는 떡볶이로 정했고, 할 일이 4개 나왔어요."

    var width = closedSize.width
    var height = closedSize.height
    /// The open notch's corners (31) rather than the closed one's (13).
    var wide = false
    var content = Content.none
    var caption = ""
    /// Hovering the notch opens it (노치 page, with 포인터를 올리면 열기 on).
    var opensOnHover = false
    /// Teammates standing beside the star.
    var lineup = 0
    /// False on a page with nothing of its own to show (pick 1-A): no stage is drawn and the page starts at its title.
    var shown = true
    /// The stage's height; AI 서비스's is 100 (its notch fills it: no caption, no empty band under the names).
    var stageHeight = 150.0

    var radius: Double { wide ? 31 : 13 }

    static func make(_ input: ArisNotchPreviewInput) -> ArisNotchPreviewPlan {
        var plan = ArisNotchPreviewPlan()
        switch input.page {
        case .aris where input.wakeWord:
            plan.width = 270
            plan.height = 32
            plan.content = .wave
            plan.caption = "“아리스” 하고 부르면 바로 들어요"
        case .aris:
            plan.caption = ArisSettingsCaption.talk(input.talkCaps)
        case .voice:
            plan.width = 440
            plan.height = 76
            plan.wide = true
            plan.content = .words(line.split(separator: " ").map(String.init))
            // The Mac's voice is named by itself: after "목소리" it read "voice the Mac's voice" in English.
            plan.caption = input.voiceName == ArisNotchPreviewInput.macVoice ? "말하기 속도 · \(input.speedTitle) · \(input.voiceName)"
                : "말하기 속도 · \(input.speedTitle) · 목소리 \(input.voiceName)"
        case .notch:
            plan.height = input.heightMode == "menubar" ? 24 : input.heightMode == "custom" ? input.customHeight : 32
            plan.opensOnHover = input.hoverOpens
            plan.caption = input.hoverOpens ? "노치에 포인터를 올려 보세요" : "제스처나 단축키로 열어요"
        case .control:
            plan.content = .window(circle: input.circleGesture)
            plan.caption = input.circleGesture ? "⌥⇧를 누른 채 동그라미를 그리면 그 부분을 같이 봐요"
                : input.seesScreen ? "화면을 가리켜 말할 때만 화면을 같이 봐요" : "화면을 보내지 않아요"
        case .team:
            plan.lineup = input.teammateNames.count
            plan.caption = "팀원 \(input.teammateNames.count)명" + (input.teammateNames.isEmpty ? "" : " · " + input.teammateNames.joined(separator: ", "))
        case .skills where input.skillsOn && !input.skillTitles.isEmpty:
            plan.width = 400
            plan.height = 82
            plan.wide = true
            let title = input.skillTitles[0]
            plan.content = .skillAnswer(tag: "\(title) 스킬 사용 중", line: skillLine)
            plan.caption = "“\(title) 스킬로 해줘”라고 부르거나, 그런 얘기를 하면 알아서 써요"
        case .ai where !input.aiWho.isEmpty:
            plan.width = whoWidth(input.aiWho)
            plan.height = 74
            plan.wide = true
            plan.content = .who(input.aiWho)
            plan.stageHeight = 100
        default:
            // 스킬 with no skill to show, AI 서비스 before its names are known, and the pages that only list settings.
            plan.shown = false
        }
        return plan
    }

    /// The who notch: at least 502 wide, else its line (13 pt: about 13 a Hangul syllable, 7.4 a Latin letter; 24
    /// around each dot) and 28 each side.
    static func whoWidth(_ names: [String]) -> Double {
        let letters = names.joined().unicodeScalars.reduce(0.0) { $0 + ((0xAC00...0xD7A3).contains($1.value) ? 13 : 7.4) }
        return max(502, letters + Double(max(names.count - 1, 0)) * 24 + 56)
    }

    /// The star's left edge: 8 points right of the notch (mockup `.star`, a 20-point box).
    static func starX(stageWidth: Double, notchWidth: Double) -> Double { stageWidth / 2 + notchWidth / 2 + 8 }

    /// Growing uses the open curve, shrinking the close one.
    static func motion(from old: Double, to new: Double) -> Motion { new < old ? .close : .open }

    /// A word lights every 300 ms at normal speed, faster when Aris speaks faster.
    static func wordInterval(speed: Double) -> Double { 0.3 / max(speed, 0.1) }
}

enum ArisNotchPreviewWave {
    struct Bar: Equatable {
        let height: Double
        /// 110 (quiet) to 255 (loud): the bar's grey.
        let grey: Double
    }

    static let tick = 0.058
    /// About two and a half seconds of voice, then the bars rest (nothing runs while the page sits still).
    static let burstTicks = 42
    static let rest = [Bar(height: 4, grey: 130), Bar(height: 8, grey: 160), Bar(height: 6, grey: 145), Bar(height: 3, grey: 120)]

    /// A voice-like level per bar for `tick`: a slow swell times a hashed flicker, the same every time.
    static func bars(tick: Int) -> [Bar] {
        (0..<4).map { n in
            let swell = 0.35 + 0.6 * abs(sin(Double(tick) * 0.058 / 0.26 + Double(n) * 1.3))
            let level = min(1, max(0, swell * noise(tick &* 4 &+ n)))
            return Bar(height: ((2 + 15 * level) * 10).rounded() / 10, grey: (110 + 145 * level).rounded())
        }
    }

    /// 0…1 from an integer, deterministic (a small integer hash).
    private static func noise(_ x: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 32
        return Double(h % 10_000) / 10_000
    }
}

/// The 팀원 page's 미리보기 strip (the owner's "Settings A", mockups/face/sa.html): Aris's face at rest beside the camera,
/// listening in the widened band, and working in the pill under the notch, in turn (자동) or held on one. 모션 줄이기
/// holds 자동 at rest.
enum ArisFaceStage {
    enum Mode: CaseIterable, Equatable { case rest, listen, work }

    enum Pin: String, CaseIterable, Equatable {
        case auto, rest, listen, work

        var title: String {
            switch self {
            case .auto: ArisTeamCopy.faceStageAuto
            case .rest: ArisTeamCopy.faceStageRest
            case .listen: ArisTeamCopy.faceStageListen
            case .work: ArisTeamCopy.faceStageWork
            }
        }
    }

    /// Each mode's time on 자동.
    static let interval = 2.2
    /// The working pill's line.
    static var workLine: String { ArisTeamCopy.faceStageWorkLine }

    static func next(_ mode: Mode) -> Mode {
        let all = Mode.allCases
        return all[(all.firstIndex(of: mode)! + 1) % all.count]
    }

    /// What shows `tick` intervals into 자동, or the pinned mode.
    static func mode(pin: Pin, tick: Int, reduced: Bool = false) -> Mode {
        switch pin {
        case .auto: reduced ? .rest : Mode.allCases[((tick % 3) + 3) % 3]
        case .rest: .rest
        case .listen: .listen
        case .work: .work
        }
    }

    static func caption(_ mode: Mode) -> String {
        switch mode {
        case .rest: ArisTeamCopy.faceStageRestCaption
        case .listen: ArisTeamCopy.faceStageListenCaption
        case .work: ArisTeamCopy.faceStageWorkCaption
        }
    }

    /// The band: the closed notch's 150 × 29 (r10), widened to the listening band's 270 × 32 (r13).
    static func notchWidth(_ mode: Mode) -> Double { mode == .listen ? 270 : 150 }
    static func notchHeight(_ mode: Mode) -> Double { mode == .listen ? 32 : 29 }
    static func notchRadius(_ mode: Mode) -> Double { mode == .listen ? 13 : 10 }
}
