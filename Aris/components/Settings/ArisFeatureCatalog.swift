//
//  ArisFeatureCatalog.swift
//  Aris
//
//  What a feature's detail sheet says (ArisFeatureSheet): the hero's icon, title and line, the info strip's cells, the
//  two preview tiles' captions and the answer that lands in the notch, About, what to try saying, and the
//  information rows. Written in Korean; the English is in Settings.xcstrings. Foundation only, so the tests compile it.
//

import Foundation

/// A feature with a detail sheet, and the row that opens it.
enum ArisFeature: String, CaseIterable, Identifiable, Sendable {
    case control, skills, notify, savedSteps

    var id: Self { self }

    /// The section whose title carries the 알아보기 link (the 스킬 page's intro card carries its own), and the page.
    var sectionID: String {
        switch self {
        case .control: "control.seeing"
        case .skills: "skills.add"
        case .notify: "aris.alerts"
        case .savedSteps: "memory.saved"
        }
    }
    var page: ArisSettingsPage {
        switch self {
        case .control: .control
        case .skills: .skills
        case .notify: .aris
        case .savedSteps: .memory
        }
    }

    /// The setting the hero's switch turns on and off, if it has one (the skills switch is the skills page's own).
    var hasSwitch: Bool { self == .control || self == .skills }

    var content: ArisFeatureContent {
        switch self {
        case .control: Self.controlContent
        case .skills: Self.skillsContent
        case .notify: Self.notifyContent
        case .savedSteps: Self.savedContent
        }
    }

    /// The feature in one line (the sheet's hero line; kept for the search and the tests).
    var rowLine: String {
        switch self {
        case .control: "가리키고 물으면 화면을 보고, 시키면 대신 눌러요."
        case .skills: "일하는 방법을 말로 가르치면 다음부터 그대로 해요."
        case .notify: "Aris의 소식이 노치 아래 카드로 잠깐 떠요."
        case .savedSteps: "앱에서 한 일을 단계로 저장해 두고 그대로 다시 해요."
        }
    }

    private static let controlContent = ArisFeatureContent(
        icon: "mouse-pointer-click", title: "컴퓨터 제어", line: "가리키고 물으면 화면을 보고, 시키면 대신 눌러요.",
        cells: [.init(label: "화면", icon: "eye", value: nil, caption: "물을 때만"),
                .init(label: "가리키기", icon: "lasso", value: nil, caption: "동그라미로"),
                .init(label: "확인", icon: "shield-check", value: nil, caption: "보내기 전에"),
                .init(label: "권한", icon: nil, value: "3개", caption: "시스템 설정")],
        sceneCaption: "동그라미로 가리키고 물어요", answerCaption: "답은 노치에 떠요",
        query: "이 오류 뭐야?", answer: "파일 이름에 빈칸이 있어서 경로를 못 찾았어요. 따옴표로 감싸면 돼요.",
        about: "화면의 무언가를 동그라미로 감싸고 물으면 Aris가 그 부분을 보고 답해요. “이거 눌러 줘”처럼 시키면 앱을 대신 누르고 입력하고, 메일 보내기처럼 되돌리기 어려운 일은 하기 전에 물어봐요.",
        tries: ["“이 오류 뭐야?”", "“이 표를 메모에 정리해 줘”", "“설정에서 다크 모드 켜 줘”"],
        facts: [.init(label: "보내는 것", value: "물을 때 찍은 화면 한 장"), .init(label: "빼는 것", value: "암호 앱과 Aris 창"),
                .init(label: "필요한 권한", value: "손쉬운 사용, 화면 기록, 마이크")])

    private static let skillsContent = ArisFeatureContent(
        icon: "wand-sparkles", title: "스킬", line: "일하는 방법을 말로 가르치면 다음부터 그대로 해요.",
        cells: [.init(label: "만들기", icon: "message-circle", value: nil, caption: "말로"),
                .init(label: "검사", icon: "shield-check", value: nil, caption: "추가하기 전에"),
                .init(label: "시험", icon: "repeat", value: nil, caption: "모든 AI로"),
                .init(label: "보관", icon: nil, value: "이 Mac", caption: "스킬 폴더")],
        sceneCaption: "말하면 스킬대로 해요", answerCaption: "끝나면 노치에 알려요",
        query: "회의록 정리해 줘", answer: "회의록 스킬로 정리했어요. 정한 것 3개, 할 일 5개예요.",
        about: "자주 하는 일을 어떻게 하는지 말로 설명하면 Aris가 스킬로 만들어 둬요. 다음에 비슷한 일을 시키면 그 스킬을 꺼내 같은 순서로 하고, 인터넷에서 받은 스킬은 추가하기 전에 검사해요.",
        tries: ["“회의록을 이렇게 정리하는 스킬 만들어 줘”", "“주간 보고 스킬로 보고서 써 줘”", "“이 링크의 스킬 추가해 줘”"],
        facts: [.init(label: "저장 위치", value: "이 Mac의 스킬 폴더"), .init(label: "검사", value: "추가하기 전에 한 번"), .init(label: "끄기", value: "스킬마다 따로")])

    private static let notifyContent = ArisFeatureContent(
        icon: "bell", title: "알림 카드", line: "Aris의 소식이 노치 아래 카드로 잠깐 떠요.",
        cells: [.init(label: "위치", icon: "aris-notch", value: nil, caption: "노치 아래"),
                .init(label: "모양", icon: "sun-moon", value: nil, caption: "화면을 따라"),
                .init(label: "종류", icon: nil, value: "5가지", caption: "알림 · 완료 · 문제")],
        sceneCaption: "일이 끝나면 카드가 내려와요", answerCaption: "카드 하나에 소식 하나",
        query: "몽이가 일을 끝냈어요", answer: "주간 보고서를 만들어 문서 폴더에 저장했어요.",
        about: "팀원이 일을 끝냈을 때, 예약해 둔 일의 결과가 나왔을 때, 타이머가 끝났을 때, 고칠 것이 생겼을 때 Aris가 노치 아래에 카드 하나로 알려요. 카드는 화면의 밝기를 따라 밝게 또는 어둡게 보여요.",
        tries: ["“10분 뒤에 알려 줘”", "“몽이한테 보고서 맡겨 줘”", "“매일 아침 날씨 알려 줘”"],
        facts: [.init(label: "나오는 곳", value: "노치 바로 아래"), .init(label: "한 번에", value: "카드 하나씩, 차례로")])

    private static let savedContent = ArisFeatureContent(
        icon: "list-checks", title: ArisSavedStepsSettingsRows.heading, line: "앱에서 한 일을 단계로 저장해 두고 그대로 다시 해요.",
        cells: [.init(label: "다시 하기", icon: "repeat", value: nil, caption: "같은 말로"),
                .init(label: "확인", icon: "shield-check", value: nil, caption: "단계마다"),
                .init(label: "AI", icon: nil, value: "없이", caption: "저장된 대로")],
        sceneCaption: "같은 말을 하면 단계대로 해요", answerCaption: "끝난 단계를 하나씩 보여 줘요",
        query: "어제처럼 보고서 보내 줘", answer: "저장된 단계 4개로 했어요. 보내기 전에 카드를 띄울게요.",
        about: "앱에서 한 일이 다시 할 수 있는 단계로만 되어 있으면 Aris가 저장해 둬요. 같은 말을 하면 AI 없이 단계마다 다시 확인하며 그대로 하고, 카드가 필요한 단계는 카드를 띄워요.",
        tries: ["“어제처럼 보고서 보내 줘”", "“아까 한 대로 사진 정리해 줘”"],
        facts: [.init(label: "저장하지 않는 것", value: "보내기, 지우기, 결제, 비밀번호"), .init(label: "지우기", value: "기억 페이지에서 하나씩")])
}

/// Everything one detail sheet says.
struct ArisFeatureContent: Equatable, Sendable {
    /// The info strip's cell: an uppercase label, an icon or a short value, and a caption.
    struct Cell: Equatable, Sendable {
        let label: String
        let icon: String?
        let value: String?
        let caption: String
    }

    /// An information row: its label on the left, its value on the right.
    struct Fact: Equatable, Sendable {
        let label: String
        let value: String
    }

    let icon: String
    let title: String
    let line: String
    let cells: [Cell]
    let sceneCaption: String
    let answerCaption: String
    /// What is said in the demo, and the answer that lands in the notch.
    let query: String
    let answer: String
    let about: String
    let tries: [String]
    let facts: [Fact]

    /// Every Korean string the sheet shows (the English catalog must have each).
    var strings: [String] {
        [title, line, sceneCaption, answerCaption, query, answer, about] + tries + cells.flatMap { [$0.label, $0.caption] + ($0.value.map { [$0] } ?? []) }
            + facts.flatMap { [$0.label, $0.value] }
    }
}

/// The sheet's measurements (SETTINGS-REA.md §5.1–5.2).
enum ArisFeatureLook {
    /// The panel: at most 620 wide and 86% of the window tall, radius 20; the body 32 from the top, 36 from the left
    /// and 40 from the right; the close button 24 from the top right, a 20-pt X in a p-2 r12 box.
    static let width: CGFloat = 620
    static let maxHeightShare: CGFloat = 0.86
    static let radius: CGFloat = 20
    static let bodyTop: CGFloat = 32
    static let bodyLeading: CGFloat = 36
    static let bodyTrailing: CGFloat = 40
    static let closeInset: CGFloat = 24
    /// Its sections 28 apart; the hero's icon 88 (r20, its glyph 40), 24 from a 28 / 700 title (−0.02em) and its
    /// 15-pt line.
    static let sectionGap: CGFloat = 28
    static let icon: CGFloat = 88
    static let iconRadius: CGFloat = 20
    static let glyph: CGFloat = 40
    static let heroGap: CGFloat = 24
    static let titleSize: CGFloat = 28
    static let lineSize: CGFloat = 15
    /// The info strip: cells at least 104 wide, 12 × 16 inside; label 11 / 500 uppercase .08em, value 21 / 600, caption 11.
    static let cellMinWidth: CGFloat = 104
    /// A preview tile: 420 × 244, radius 26, 16 apart; its caption 11 pt 8 under it.
    static let tile = CGSize(width: 420, height: 244)
    static let tileRadius: CGFloat = 26
    static let tileGap: CGFloat = 16
    /// The demo's one loop, and its notch: collapsed 128 × 22, listening 292 × 34, answering 300 wide.
    static let loop: Double = 9
    static let notchClosed = CGSize(width: 128, height: 22)
    static let notchListening = CGSize(width: 292, height: 34)
    static let notchAnswerWidth: CGFloat = 300
    /// In: from scale .96 and 10 down over 300 ms ease-out (0, 0, .2, 1); backdrop .38 / .78 at once.
    static let enter = 0.3

    /// Where the notch is in the loop at `t` (0..<1 of the 9 s): 0 closed, 1 listening, 2 answering, with the share of
    /// the move toward the next state done (the measured timeline: closed to 7 %, listening by 11.5 %, answering by
    /// 24.5 %, held to 88.5 %, listening again by 92.5 %, closed by 97.5 %).
    static func notch(at t: Double) -> (from: Int, to: Int, progress: Double) {
        func ramp(_ a: Double, _ b: Double) -> Double { min(max((t - a) / (b - a), 0), 1) }
        switch t {
        case ..<0.07: return (0, 0, 0)
        case ..<0.115: return (0, 1, ramp(0.07, 0.115))
        case ..<0.20: return (1, 1, 0)
        case ..<0.245: return (1, 2, ramp(0.20, 0.245))
        case ..<0.885: return (2, 2, 0)
        case ..<0.925: return (2, 1, ramp(0.885, 0.925))
        case ..<0.935: return (1, 1, 0)
        case ..<0.975: return (1, 0, ramp(0.935, 0.975))
        default: return (0, 0, 0)
        }
    }
}
