//
//  ArisSettingsCatalog.swift
//  Aris
//
//  The settings window's pages and a search index of every setting in them: its id (the row the page draws with
//  that id, so a result can scroll to it), its page, its title and the Korean words people might type for it.
//  Foundation only, so the tests compile it.
//

import Foundation

/// The sidebar's three groups (the owner's pick 6-B): what Aris is, what it works with, and the screen and the app.
enum ArisSettingsGroup: String, CaseIterable {
    case aris = "아리스"
    case tools = "도구"
    case app = "화면 · 앱"

    var pages: [ArisSettingsPage] { ArisSettingsPage.allCases.filter { $0.group == self } }
}

/// The window's 14 pages, in the sidebar's order (the list scrolls when the window is too short for it). 할 일 and 캘린더
/// are one page (its rows keep their `todo.` and `calendar.` ids), and what the 모양 page held is in 일반 and 노치 (its
/// rows keep their `look.` ids), so a search or a link that names a row still lands on it.
enum ArisSettingsPage: String, CaseIterable, Identifiable {
    case aris, ai, voice, memory, team, skills, dictation, todo, control, notch, features, general, keys, about

    var id: Self { self }

    /// The page a stored or spoken name means: a page's own name, or the page that took an older one's rows.
    static func named(_ raw: String) -> ArisSettingsPage? {
        switch raw {
        case "calendar": .todo
        case "look": .general
        default: ArisSettingsPage(rawValue: raw)
        }
    }

    /// A page added lately carries a small 새 in the sidebar.
    var isNew: Bool { self == .skills }

    var group: ArisSettingsGroup {
        switch self {
        case .aris, .ai, .voice, .memory, .team, .skills: .aris
        case .dictation, .todo, .control: .tools
        case .notch, .features, .general, .keys, .about: .app
        }
    }

    var title: String {
        switch self {
        case .aris: "대화"
        case .ai: "AI 서비스"
        case .voice: "목소리 · 언어"
        case .memory: "기억"
        case .team: "팀원"
        case .skills: "스킬"
        case .dictation: "받아쓰기"
        case .todo: "할 일 · 캘린더"
        case .control: "컴퓨터 제어"
        case .notch: "노치 · 사이드 노치"
        case .features: "음악 · 선반"
        case .general: "일반"
        case .keys: "단축키"
        case .about: "정보"
        }
    }

    /// What the page is for, in one line (its title's help; the measured pages carry no line under their title).
    var subtitle: String {
        switch self {
        case .aris: "부르는 방법과 대화가 이어지는 시간을 정해요."
        case .ai: "생각하고 듣고 말하는 곳을 골라요"
        case .voice: "알아들을 언어와 Aris의 목소리를 골라요."
        case .memory: "Aris가 나에 대해 기억하는 것들이에요."
        case .team: "이름을 부르면 그 팀원이 일을 맡아요."
        case .skills: "Aris에게 말로 가르치는 일하는 방법이에요."
        case .dictation: "아무 입력칸에서나 말로 받아 적어요."
        case .todo: "사이드 노치에 보여 줄 할 일과 일정을 골라요."
        case .control: "화면을 보고 누르는 데 필요한 것들이에요."
        case .notch: "노치가 열리는 방식과 크기예요."
        case .features: "노치의 음악과 선반이에요."
        case .general: "켜고 끄기, 모양, 화면, 언어예요."
        case .keys: "Aris를 부르는 키를 모아 뒀어요."
        case .about: "버전, 문제 해결, 내 데이터예요."
        }
    }

    /// The page's line icon in the sidebar (ArisLineIconData): the measured names where a measured page matches, Aris's
    /// own glyphs (aris-…) where the measured one is that app's own drawing.
    var lineIcon: String {
        switch self {
        case .aris: "aris-star"
        case .ai: "blocks"
        case .voice: "audio-lines"
        case .memory: "brain"
        case .team: "users"
        case .skills: "wand-sparkles"
        case .dictation: "mic"
        case .todo: "list-checks"
        case .control: "mouse-pointer-click"
        case .notch: "aris-notch"
        case .features: "layout-grid"
        case .general: "settings"
        case .keys: "keyboard"
        case .about: "info"
        }
    }

    /// An SF Symbol close to the page's line icon.
    var symbol: String {
        switch self {
        case .aris: "bubble.left"
        case .ai: "sparkles"
        case .voice: "mic"
        case .memory: "brain"
        case .team: "person.2"
        case .skills: "wand.and.stars"
        case .dictation: "text.alignleft"
        case .todo: "checklist"
        case .control: "cursorarrow.click"
        case .notch: "rectangle.topthird.inset.filled"
        case .features: "square.grid.2x2"
        case .general: "gearshape"
        case .keys: "keyboard"
        case .about: "info.circle"
        }
    }
}

/// The window and its sidebar, as measured (SETTINGS-REA.md §2–3): a 1080 × 710 window rounded 20 with its traffic
/// lights at 18, 18; a 220 sidebar `px-4` whose header is `pt-10`; nav items 44 tall, r12, 4 apart, a 20-pt icon 12
/// from a 14 / 500 label, 15.5 in from the left and 16 from the right. With 14 pages in three groups the list is
/// taller than the window, so it scrolls and fades at its end.
enum ArisSidebarMetrics {
    /// The settings window's default and smallest sizes, its corner radius and where its traffic lights sit.
    static let windowSize = (width: 1080.0, height: 710.0)
    static let windowMinimum = (width: 900.0, height: 620.0)
    static let windowRadius = 20.0
    static let trafficLights = (x: 18.0, y: 18.0)
    /// The content card: 7 from the window's top, bottom and right, radius 13 (7 + 13 = the window's 20).
    static let cardInset = 7.0
    static let cardRadius = 13.0
    static let width = 220.0
    /// The sidebar's side padding (`px-4`).
    static let padding = 16.0
    /// Above the star (the header's `pt-10`, under the traffic lights), and under the list.
    static let top = 40.0
    static let bottom = 12.0
    /// The star and the two lines beside it, and the gap under them.
    static let greeting = 34.0
    static let greetingGap = 16.0
    static let searchHeight = 36.0
    static let searchGap = 8.0
    /// A group's name: 11 pt, 13 tall; 12 above (2 for the first) and 4 below.
    static let groupLabel = 13.0
    static let groupTop = 12.0
    static let firstGroupTop = 2.0
    static let groupBottom = 4.0
    static let row = 44.0
    static let rowGap = 4.0
    static let rowRadius = 12.0
    static let rowLeading = 15.5
    static let rowTrailing = 16.0
    static let iconGap = 12.0
    static let labelSize = 14.0
    static let iconSize = 20.0
    static let groupLabelSize = 11.0
    /// Where an overflowing list fades out (a window at its smallest height).
    static let fade = 44.0

    /// The height the sidebar needs to show every page of `groups`.
    static func height(_ groups: [ArisSettingsGroup] = ArisSettingsGroup.allCases) -> Double {
        top + greeting + greetingGap + searchHeight + searchGap + pagesHeight(groups) + bottom
    }

    /// The list of pages alone: its group names and rows.
    static func pagesHeight(_ groups: [ArisSettingsGroup] = ArisSettingsGroup.allCases) -> Double {
        let labels = groups.indices.reduce(0.0) { $0 + ($1 == 0 ? firstGroupTop : groupTop) + groupLabel + groupBottom }
        let rows = groups.reduce(0.0) { $0 + Double($1.pages.count) * row + Double(max(0, $1.pages.count - 1)) * rowGap }
        return labels + rows
    }

    /// Where `page`'s row lies in the list of pages, from the list's own top: the group names and rows above it.
    static func rowSpan(_ page: ArisSettingsPage, groups: [ArisSettingsGroup] = ArisSettingsGroup.allCases) -> (top: Double, bottom: Double)? {
        var y = 0.0
        for (index, group) in groups.enumerated() {
            y += (index == 0 ? firstGroupTop : groupTop) + groupLabel + groupBottom
            for (place, shown) in group.pages.enumerated() {
                if place > 0 { y += rowGap }
                if shown == page { return (y, y + row) }
                y += row
            }
        }
        return nil
    }

    /// Whether the list's end fades out: only while more of the list lies below what its box shows (a list that fits,
    /// or one scrolled to its end, has none), and never over the chosen row (twelfth VM pass: 정보, chosen and scrolled
    /// to, stayed faded). `listTop` is the list's top in the box (0, less once scrolled down); `chosen` is the chosen
    /// row's span in the box.
    static func fades(listHeight: Double, boxHeight: Double, listTop: Double, chosen: (top: Double, bottom: Double)?) -> Bool {
        guard listTop + listHeight > boxHeight + 1 else { return false }
        if let chosen, chosen.bottom > boxHeight - fade, chosen.top < boxHeight { return false }
        return true
    }

    /// The room a page's name has on its row: the row less its insets, the icon and the gap after it (the name is never
    /// cut: an English name that doesn't fit here at 14 pt is a shorter one; twelfth VM pass, "Notch · Side notch…").
    static var labelRoom: Double { width - 2 * padding - rowLeading - rowTrailing - iconSize - iconGap }
    /// The 새 / New mark after a page added lately: its side padding, and the gap before it.
    static let newPadding = 6.0
    static let newSize = 9.5
}

/// The window's measurements, the same on every page (§4.2–4.3): sections `mb-8` (32) with a 20/700 title `mb-4` (16)
/// over their cards, one card per row 16 apart (`mt-4`), each row `p-5` (20) with a 20-pt icon 12 from its words; the
/// page's 22/600 title `mb-5` (20) over its first section; a card radius of 18.
enum ArisSettingsMetrics {
    /// A section's title to what is above it; the title to its card; a card to the next.
    static let sectionGap: CGFloat = 32
    static let headingGap: CGFloat = 16
    static let cardGap: CGFloat = 16
    /// The page's title to its first section (`mb-5`).
    static let titleGap: CGFloat = 20
    /// Section titles: `text-xl` 20 / 700, −0.01em.
    static let sectionTitleSize: CGFloat = 20
    static let sectionTitleTracking: CGFloat = -0.2
    /// The page title: 22 / 600, −0.02em.
    static let pageTitleSize: CGFloat = 22
    static let pageTitleTracking: CGFloat = -0.44
    /// The page column inside the content card: 6 + 18 + 16 from the card's top, 48 from its left, at most 800 wide.
    static let columnTop: CGFloat = 40
    static let columnLeading: CGFloat = 48
    static let columnTrailing: CGFloat = 32
    static let columnMaxWidth: CGFloat = 800
    /// The bottom fade over the card: 80 tall.
    static let bottomFade: CGFloat = 80
    /// A row inside its card: 20 all round, a 20-pt icon column, 12 to the text, the control after it.
    static let rowInset: CGFloat = 20
    static let iconBox: CGFloat = 20
    static let iconGap: CGFloat = 12
    static let rowMinHeight: CGFloat = 60
    static let cardRadius: CGFloat = 18
    /// The small line under a card (mockup `.fine`: 12 pt, 8 above, 4 in).
    static let fineGap: CGFloat = 8
    static let fineInset: CGFloat = 4
}

/// One thing the search can find.
struct ArisSettingsEntry: Identifiable, Equatable {
    /// The row (or section) the page draws with this id.
    let id: String
    let page: ArisSettingsPage
    let title: String
    let keywords: [String]
}

enum ArisSettingsIndex {
    private static func e(_ id: String, _ page: ArisSettingsPage, _ title: String, _ keywords: String = "") -> ArisSettingsEntry {
        ArisSettingsEntry(id: id, page: page, title: title, keywords: keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    /// Every setting, page by page.
    static let entries: [ArisSettingsEntry] = [
        e("aris.wake", .aris, "“아리스”라고 부르기", "호출어, 웨이크 워드, wake word, 깨우기, 부르기, 음성 호출, 아리스"),
        e("aris.train", .aris, "내 목소리 익히기", "목소리 학습, 화자 인식, 다시 익히기, 내 목소리"),
        e("aris.talkKey", .aris, "말하기 단축키", "단축키, 핫키, 키, 말하기, 옵션 스페이스"),
        e("aris.minutes", .aris, "대화 이어가기", "대화 시간, 이어서 묻기, 후속 질문, 새 대화"),
        e("aris.silence", .aris, "계속 듣기", "대화 모드, 계속 듣기, 핸즈프리, 다시 듣기, 끝내기, 침묵"),
        e("aris.bargeIn", .aris, "스피커로 들을 때도 끼어들기", "끼어들기, 말 끊기, 바지인, 스피커, 멈추기"),
        e("aris.systemAudio", .aris, "다른 앱 소리 확인", "시스템 오디오, 권한, 보라색 표시, 녹음 표시, 다른 앱 소리"),
        e("aris.sounds", .aris, "알림 효과음", "소리, 효과음, 알림음, 사운드"),
        ArisDayEndSetting.entry,
        e("aris.mute", .aris, "음소거", "음소거, 조용히, 무음, 말하지 않기, 글로만, mute, 소리 끄기"),
        e("aris.quietHours", .aris, "밤에는 조용히", "조용한 시간, 밤, 야간, 방해 금지, 집중 모드, 화면 잠금, quiet, 알림 읽지 않기"),
        e("aris.claudeRing", .aris, "귀에 보일 사용량", "Claude Code, 클로드 코드, 사용량, 한도, 5시간, 주간, 자동, 고리, 링, 귀"),
        e("aris.claudeBudget", .aris, "API 키로 쓸 때 하루 예산", "Claude Code, 클로드 코드, API 키, 예산, 달러, 비용, 쓴 돈, 요금"),
        e("memory.auto", .memory, "자동으로 기억하기", "기억, 메모리, 학습, 자동, 배우기"),
        e("memory.search", .memory, "기억 찾기", "기억, 메모리, 검색, 찾기, 지우기, 잊기"),
        e("memory.clear", .memory, "기억 모두 지우기", "기억, 메모리, 전부 지우기, 초기화, 잊기"),
        e("memory.consolidate", .memory, ArisMemoryReviewRows.tidyTitle, "정리, 요약, 매주, 사람, 프로젝트, 기억 정리, 되돌리기, 메모리"),
        e("memory.import", .memory, ArisMemoryImportCopy.rowTitle, "가져오기, 다른 AI, 옮기기, 이전, 내보내기, import, 기억 가져오기, 메모리"),
        e("memory.work", .memory, ArisWorkSettingsRows.toggleTitle, "한 일, 작업 기억, 배운 것, 방법, 학습, 사용량, 토큰, 일하면서 배운 것"),
        e("memory.work.clear", .memory, ArisWorkSettingsRows.clearTitle, "한 일, 작업 기억, 배운 것, 전부 지우기, 초기화, 잊기"),
        e("team.add", .team, "팀원 추가", "팀, 새 팀원, 팀원 빼기"),
        e("team.detail", .team, "팀원 이름 · 언제 부를까요", "이름, 역할, 하는 일, 언제 부를까요, 어떻게 일할까요, 지시, 두뇌, 쓸 수 있는 것, 권한, 기억, 팀원 편집, 코디"),
        e("team.look", .team, "팀원 캐릭터", "캐릭터, 종류, 색, 질감, 패브릭, 모양"),
        e("team.make", .team, "말로 팀원 만들기", "만들기, 새 팀원, 말로, 템플릿, 문서 담당, 리서처, 일정 비서"),
        e("team.knowhow", .team, "앱 노하우", "앱, 노하우, 배운 것, 카카오톡, 단축키, 팁"),
        ArisTerminalSetting.entry,
        ArisDropLearnedSetting.entry,
        e("skills.feature", .skills, "스킬 기능", "스킬, skill, 스킬 켜기, SkillSpector, 파이썬, 보안 검사"),
        e("skills.add", .skills, "스킬 추가 · 말로 만들기", "스킬, 링크, GitHub, 깃허브, skill-creator, 만들기, 폴더, 가르치기"),
        e("skills.list", .skills, "내 스킬", "스킬 목록, 끄기, 삭제, 모든 AI로 시험, 테스트, SKILL.md"),
        e("voice.languages", .voice, "쓰는 언어", "언어, 언어 추가, 한국어, 영어, 다국어"),
        e("voice.scribe", .voice, "ElevenLabs Scribe로 듣기", "받아 적기, 클라우드, 음성 인식, Whisper, 일레븐랩스"),
        e("voice.voice", .voice, "목소리", "음성, 보이스, ElevenLabs, 목소리 바꾸기"),
        e("voice.speed", .voice, "말하기 속도", "속도, 빠르게, 느리게, 들어 보기"),
        e("dictation.key", .dictation, "누르고 있는 동안 받아쓰기", "받아쓰기, 오른쪽 옵션, 딕테이션, 받아 적기"),
        e("dictation.pasteLast", .dictation, "마지막 받아쓰기 다시 넣기", "다시 넣기, 붙여 넣기, 컨트롤 커맨드 V, 받아쓰기 단축키"),
        e("dictation.pill", .dictation, "받아쓰기 알약 보이기", "알약, 받아쓰기 표시, 화면 아래, 파형, 노치 조용히"),
        e("dictation.pillIdle", .dictation, "쉴 때도 보이기", "알약, 쉴 때, 대기, 숨기기, 받아 쓸 때만"),
        e("dictation.brainPolish", .dictation, "Mac에서 못 다듬을 때 AI로 다듬기", "다듬기, 교정, 맞춤법, Claude, AI 다듬기"),
        e("dictation.style.chat", .dictation, "채팅 앱 문체", "문체, 말투, 채팅, 카카오톡, 편하게"),
        e("dictation.style.mail", .dictation, "메일 문체", "문체, 메일, 이메일, 격식"),
        e("dictation.style.code", .dictation, "개발 도구 · 터미널 문체", "문체, 코드, 터미널, 개발, 그대로"),
        e("dictation.style.other", .dictation, "그 밖의 앱 문체", "문체, 메모, 문서, 보통"),
        e("dictation.words", .dictation, "단어장", "내 단어, 사전, 고유명사, 어휘, 배운 단어"),
        e("todo.access", .todo, "미리 알림 접근", "권한, 미리 알림, 리마인더"),
        e("todo.lists", .todo, "할 일 목록", "목록, 미리 알림 목록, 포함할 목록"),
        e("todo.default", .todo, "새 항목 넣을 목록", "기본 목록, 새 항목"),
        e("todo.newList", .todo, "새 목록 만들기", "목록 추가, 새 목록"),
        e("calendar.access", .todo, "캘린더 접근", "권한, 달력, 일정"),
        e("calendar.google", .todo, "Google 캘린더", "구글, 계정, 인터넷 계정"),
        e("calendar.include", .todo, "포함할 캘린더", "캘린더 목록, 달력, 일정"),
        e("calendar.allDay", .todo, "종일 일정 표시", "하루 종일, 종일"),
        e("calendar.join", .todo, "일정을 누르면 회의 참가", "회의, 줌, 미트, 참가 링크"),
        e("calendar.openIn", .todo, "일정 열기", "Apple 캘린더, Google 캘린더, 열 앱"),
        e("ai.brain", .ai, "생각 · 기본으로 답하는 AI", "두뇌, 답하는 AI, Claude, Codex, ChatGPT, Gemini, GPT, 모델, 클로드, API 키, API key, OpenAI, Anthropic, OpenRouter, Groq, xAI, Mistral, DeepSeek, Ollama, LM Studio, 로컬 모델, 다른 AI 연결, 내 연결"),
        e("ai.jev", .ai, "짧은 명령 빨리 알아듣기", "TypeSafe, Jev, 타입세이프, API 키, API key, 키체인, 짧은 명령"),
        e("ai.hear", .ai, "듣기", "받아 적기, 음성 인식, Whisper, 위스퍼, Apple 받아쓰기, ElevenLabs Scribe, 일레븐랩스, 큰 모델, 작은 모델, 모델 받기"),
        e("ai.speak", .ai, "말하기 · 목소리", "목소리, 음성, 보이스, ElevenLabs, 일레븐랩스, macOS 목소리, 라이브러리, 링크로 추가, 미리 듣기, API 키, API key"),
        e("ai.computerEngine", .ai, "다른 앱을 다루는 방식", "컴퓨터 사용, 앱 조작, Peekaboo, GPT, Codex"),
        e("ai.teamBrain", .ai, "팀원의 두뇌", "팀원, 두뇌, Codex"),
        e("ai.services", .ai, "연결된 서비스", "사용량, 로그인, 계정, Claude, Codex, Antigravity"),
        e("ai.mcp.composio", .ai, "Composio", "Composio, 컴포지오, Gmail, Slack, Notion, 구글 캘린더, 외부 서비스, 연결, API 키, API key, 키체인"),
        e("ai.mcp.add", .ai, "MCP 서버 추가", "MCP, 서버, 도구, 외부 서비스, 토큰, 연결"),
        e("control.ax", .control, ArisFix.Pane.accessibility.title(english: false), "권한, 접근성, 손쉬운 사용, 기기 제어, 누르기, 입력"),
        e("control.screen", .control, ArisFix.Pane.screen.title(english: false), "권한, 스크린, 화면 기록, 화면 녹화"),
        e("control.mic", .control, "마이크", "권한, 마이크로폰, 듣기"),
        e("control.sees", .control, "질문할 때 화면 같이 보기", "화면, 스크린샷, 같이 보기, 이거, 화면 봐 줘, 가리킬 때만"),
        e("control.circle", .control, "동그라미로 가리키기", "제스처, 그리기, 가리키기, 동그라미, 원"),
        e("control.standing", .control, "묻지 않고 하는 일", "허락, 승인, 자동, 취소, 상시 허용"),
        e("notch.hover", .notch, "포인터를 올리면 열기", "호버, 마우스, 포인터"),
        e("notch.haptics", .notch, "진동", "햅틱, 트랙패드"),
        e("notch.gestures", .notch, "제스처", "스와이프, 두 손가락, 쓸기"),
        e("notch.height", .notch, "노치 크기", "높이, 메뉴 막대, 실제 노치"),
        e("notch.customHeight", .notch, "직접 정한 높이", "높이, 슬라이더"),
        e("notch.unhide", .notch, "숨긴 사이드 노치", "다시 보이기, 숨기기"),
        e("notch.clipKey", .notch, "왼쪽 사이드 노치 열기", "클립보드, 단축키"),
        e("notch.rightKey", .notch, "오른쪽 사이드 노치 열기", "할 일, 캘린더, 단축키"),
        e("notch.tab.history", .notch, "기록 탭", "사이드 노치, 왼쪽, 기록, 세션, 지난 대화, 탭 끄기, 숨기기"),
        e("notch.tab.activity", .notch, "한 일 탭", "사이드 노치, 왼쪽, 한 일, 활동, 되돌리기, 탭 끄기, 숨기기"),
        e("notch.tab.clipboard", .notch, "클립보드 탭", "사이드 노치, 왼쪽, 클립보드, 복사 기록, 탭 끄기, 숨기기"),
        e("notch.tab.usage", .notch, "사용량 탭", "사이드 노치, 왼쪽, 사용량, 한도, 비용, 탭 끄기, 숨기기"),
        e("notch.tab.todo", .notch, "할 일 탭", "사이드 노치, 오른쪽, 할 일, 마감, 미리 알림, 탭 끄기, 숨기기"),
        e("notch.tab.calendar", .notch, "캘린더 탭", "사이드 노치, 오른쪽, 캘린더, 일정, 달력, 탭 끄기, 숨기기"),
        e("notch.advanced", .notch, "열기와 움직임", "고급 설정, 노치 설정, 세부 설정"),
        e("notch.hoverDelay", .notch, "열리기까지 머무는 시간", "호버 시간, 지연, 대기, 포인터"),
        e("notch.rememberTab", .notch, "보던 탭으로 열기", "마지막 탭, 탭 기억"),
        e("notch.animation", .notch, "열고 닫는 애니메이션", "애니메이션, 움직임, 효과"),
        e("notch.animationSpeed", .notch, "애니메이션 속도", "속도, 빠르게, 느리게"),
        e("notch.gestureDetail", .notch, "제스처 세부", "제스처, 고급 설정"),
        e("notch.closeGesture", .notch, "쓸어 올려 닫기", "제스처, 닫기, 스와이프"),
        e("notch.mediaSwipe", .notch, "옆으로 쓸어 곡 넘기기", "제스처, 다음 곡, 이전 곡, 음악, 스와이프"),
        e("notch.fixedDirection", .notch, "제스처 방향 고정", "자연스러운 스크롤, 방향, 반대"),
        e("notch.sensitivity", .notch, "제스처 감도", "민감도, 예민하게, 둔하게"),
        e("notch.window", .notch, "창", "노치 창, 고급 설정"),
        e("notch.flatHeight", .notch, "노치 없는 화면", "외장 모니터, 높이, 메뉴 막대"),
        e("notch.flatCustomHeight", .notch, "노치 없는 화면의 높이", "외장 모니터, 높이, 슬라이더"),
        e("notch.cornerScaling", .notch, "높이에 맞춘 모서리", "모서리, 둥글기, 라운드"),
        e("notch.chin", .notch, "메뉴 막대 아래 띠까지", "띠, 메뉴 막대, 타이틀 바"),
        e("notch.lockScreen", .notch, "잠금 화면에서도 보이기", "잠금 화면, 잠금"),
        e("notch.hideFromRecording", .notch, "화면 기록에서 숨기기", "녹화, 화면 공유, 스크린샷"),
        e("notch.hideFromMissionControl", .notch, "미션 컨트롤에서 숨기기", "미션 컨트롤, 데스크탑, 스페이스"),
        e("look.theme", .general, "설정 창 모양", "라이트, 다크, 자동, 테마, 다크 모드"),
        e("look.accent", .general, "강조 색", "색, 액센트, 컬러"),
        e("look.reduceMotion", .general, "모션 줄이기", "애니메이션, 동작 줄이기, 움직임"),
        e("look.settingsIcon", .notch, "노치에 설정 아이콘", "아이콘, 톱니바퀴"),
        e("look.alwaysTabs", .notch, "탭 항상 보이기", "탭, 탭 줄"),
        ArisNotchLookSetting.entries[0],
        ArisNotchLookSetting.entries[1],
        ArisNotchLookSetting.entries[2],
        e("features.music", .features, "음악", "재생, 스펙트럼, 미디어, 플레이어"),
        e("features.musicSource", .features, "음악 가져올 곳", "지금 재생 중, Apple Music, Spotify, 스포티파이, 음악 앱"),
        e("features.musicActivity", .features, "닫힌 노치에 재생 중인 곡", "앨범 아트, 재생 중, 라이브 액티비티"),
        e("features.fullScreen", .features, "전체 화면일 때", "전체 화면, 숨기기, 영상"),
        e("features.peek", .features, "곡이 바뀌면 잠깐 보여 주기", "미리 보기, 새 곡, 알림"),
        e("features.peekStyle", .features, "보여 주는 곳", "미리 보기, 노치 아래, 노치 안"),
        e("features.idleWait", .features, "멈춘 뒤 남아 있는 시간", "일시 정지, 대기, 사라지기"),
        e("features.coloredBars", .features, "앨범 색 막대", "스펙트럼, 막대, 색"),
        e("features.tinting", .features, "플레이어에 앨범 색", "색, 틴트, 앨범 아트"),
        e("features.shelf", .features, "선반", "파일, 공유, 에어드롭"),
        e("features.shelfOn", .features, "선반 쓰기", "선반 켜기, 파일, 탭"),
        e("features.shelfOnHome", .features, "첫 화면에도 보이기", "선반, 첫 화면, 홈, 칩, 파일"),
        e("features.wideDrop", .features, "노치 근처에서도 받기", "끌어 놓기, 드래그, 넓게"),
        e("features.copyOnDrag", .features, "끌어낼 때 복사", "복사, 드래그, 옮기기"),
        e("features.removeAfterDrag", .features, "끌어낸 뒤 선반에서 빼기", "자동 삭제, 드래그, 빼기"),
        e("features.reverseOrder", .features, "순서 거꾸로", "순서, 정렬, 반대"),
        e("features.quickShare", .features, "빠른 공유", "에어드롭, AirDrop, 공유, 보내기"),
        e("general.login", .general, "로그인할 때 열기", "자동 실행, 시작할 때"),
        e("general.onboarding", .general, "처음 안내 다시 보기", "온보딩, 안내, 권한"),
        e("general.name", .general, "부르는 이름", "이름, 호칭, 닉네임"),
        e("general.display", .general, "표시 방식", "화면, 모니터, 디스플레이"),
        e("general.screen", .general, "선호하는 화면", "화면, 모니터, 디스플레이"),
        e("general.language", .general, "앱 언어", "언어, English, 한국어"),
        e("general.restart", .general, "Aris 다시 시작", "재시작, 껐다 켜기"),
        e("general.quit", .general, "Aris 종료", "끄기, 종료"),
        e("keys.talk", .keys, "Aris에게 말하기", "단축키, 말하기"),
        e("keys.dictation", .keys, "받아쓰기", "단축키, 오른쪽 옵션"),
        e("keys.pasteLast", .keys, "마지막 받아쓰기 다시 넣기", "단축키, 다시 넣기, 받아쓰기"),
        e("keys.answer", .keys, "Claude에게 답하기", "단축키, 승인, 질문 카드"),
        e("keys.clipboard", .keys, "클립보드 기록", "단축키, 클립보드"),
        e("keys.notch", .keys, "노치 열고 닫기", "단축키, 노치"),
        e("keys.peek", .keys, "음악 미리 보기", "단축키, 음악"),
        e("about.version", .about, "버전 정보", "버전, 정보, Aris"),
        e("about.folder", .about, "기록 폴더 열기", "Finder, 로그, 폴더"),
        e("about.export", .about, "데이터 내보내기", "JSON, 백업, 내보내기"),
        e("about.diagnostics", .about, "진단 내보내기", "문제, 로그, 버그, 진단"),
        e("about.wipe", .about, "데이터 지우기", "삭제, 초기화, 기록 지우기"),
        e("about.uninstall", .about, "Aris 제거", "삭제, 언인스톨, 제거"),
    ]

    static func entry(_ id: String) -> ArisSettingsEntry? { entries.first { $0.id == id } }

    /// The tags the 팀원 page draws itself (its roster, the picked one's fields, the character picker).
    static let teamAnchors = ["team.add", "team.detail", "team.look", "team.make", "team.knowhow", ArisTerminalSetting.id]

    /// The tags the 스킬 page draws itself (its switch, its chat, its list).
    static let skillsAnchors = ["skills.feature", "skills.add", "skills.list"]

    /// Lowercased, with spaces and punctuation gone ("“아리스”라고 부르기" → "아리스라고부르기").
    static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) })
    }

    private static let leads: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")

    /// Each syllable's first consonant (초성), other letters kept ("말하기 속도" → "ㅁㅎㄱㅅㄷ").
    static func initials(_ text: String) -> String {
        String(normalized(text).map { ch -> Character in
            guard let v = ch.unicodeScalars.first?.value, (0xAC00...0xD7A3).contains(v) else { return ch }
            return leads[Int(v - 0xAC00) / 588]
        })
    }

    private static func isInitials(_ q: String) -> Bool {
        !q.isEmpty && q.allSatisfy { leads.contains($0) }
    }

    /// What a setting and its page are called in the UI's other language (the English window: ArisSettingsCopy), so
    /// typing "restart" finds Aris 다시 시작.
    struct Alias {
        let title: String
        let page: String
    }

    /// How well `entry` matches the normalized query (lower is better) and, when it was one of its keywords that
    /// matched and not its name, that keyword; or nil.
    private static func rank(_ entry: ArisSettingsEntry, _ q: String, alias: Alias?) -> (rank: Int, why: String?)? {
        let titles = [entry.title, alias?.title].compactMap { $0 }.map(normalized)
        if titles.contains(where: { $0.hasPrefix(q) }) { return (0, nil) }
        if titles.contains(where: { $0.contains(q) }) { return (1, nil) }
        if isInitials(q), initials(entry.title).contains(q) { return (2, nil) }
        if let word = entry.keywords.first(where: { normalized($0).hasPrefix(q) }) { return (3, word) }
        if let word = entry.keywords.first(where: { normalized($0).contains(q) }) { return (4, word) }
        if [entry.page.title, alias?.page].compactMap({ $0 }).contains(where: { normalized($0).contains(q) }) { return (5, nil) }
        return nil
    }

    /// A setting the search found, and the keyword it was found by when its own name doesn't say why ("다크" finds 설정
    /// 창 모양 by 다크: the result shows it after the page's name).
    struct Match: Equatable {
        let entry: ArisSettingsEntry
        let why: String?
    }

    /// The settings matching what was typed, best first (in page order within a rank); none for an empty query.
    /// With `among`, only the ones a page is drawing right now (ArisSettingsBuilder.searchable): a row another setting
    /// hides (애니메이션 속도 while the animation is off) isn't offered, since landing on it would find nothing.
    /// `alias`: each setting's other name, matched like its own (nil: none).
    static func matches(_ query: String, limit: Int = 20, among shown: Set<String>? = nil, alias: ((ArisSettingsEntry) -> Alias)? = nil) -> [Match] {
        let q = normalized(query)
        guard !q.isEmpty else { return [] }
        return entries.enumerated()
            .filter { shown?.contains($0.element.id) ?? true }
            .compactMap { offset, entry in rank(entry, q, alias: alias?(entry)).map { (rank: $0.rank, offset: offset, match: Match(entry: entry, why: $0.why)) } }
            .sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }
            .prefix(limit)
            .map(\.match)
    }

    static func search(_ query: String, limit: Int = 20, among shown: Set<String>? = nil, alias: ((ArisSettingsEntry) -> Alias)? = nil) -> [ArisSettingsEntry] {
        matches(query, limit: limit, among: shown, alias: alias).map(\.entry)
    }

    /// The pages that still carry 새 in the sidebar: the ones added lately that haven't been opened once (item 20).
    static func showsNew(_ page: ArisSettingsPage, seen: Set<String>) -> Bool { page.isNew && !seen.contains(page.rawValue) }
}
