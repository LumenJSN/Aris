//
//  ArisSettingsCatalog.swift
//  Aris
//
//  The settings window's pages and a search index of every setting in them: its id (the row the page draws with
//  that id, so a result can scroll to it), its page, its title and the Korean words people might type for it.
//  Foundation only, so the tests compile it.
//

import Foundation

/// The window's four pages (settings-ia option A, the owner's pick): what the user is doing. Each is one long page of
/// parts (ArisSettingsParts); the open page's parts are listed under its name in the sidebar.
enum ArisSettingsPage: String, CaseIterable, Identifiable {
    case talk, able, look, app

    var id: Self { self }

    /// The page a stored or spoken name means: a page's own name, or the page that took a former page's rows (the
    /// 14 pages before option A, and "calendar" and "look" before those).
    static func named(_ raw: String) -> ArisSettingsPage? {
        ArisSettingsPage(rawValue: raw) ?? ArisSettingsFormerPage.named(raw)?.page
    }

    /// No page is new: the 새 mark stays for a page added later.
    var isNew: Bool { false }

    var title: String {
        switch self {
        case .talk: "Aris와 말하기"
        case .able: "할 수 있는 일"
        case .look: "모양"
        case .app: "앱"
        }
    }

    /// What the page is for, in one line (its title's help).
    var subtitle: String {
        switch self {
        case .talk: "누가 답하고, 어떻게 듣고 말하고, 언제 조용한지 정해요."
        case .able: "Aris가 해 주는 일과 그 일에 쓰는 것들이에요."
        case .look: "노치, 사이드 노치, 음악, 선반과 창의 모양이에요."
        case .app: "권한, 단축키, 시작, 업데이트와 내 데이터예요."
        }
    }

    /// The page's line icon in the sidebar (ArisLineIconData).
    var lineIcon: String {
        switch self {
        case .talk: "aris-star"
        case .able: "wand-sparkles"
        case .look: "palette"
        case .app: "settings"
        }
    }

    /// An SF Symbol close to the page's line icon.
    var symbol: String {
        switch self {
        case .talk: "bubble.left"
        case .able: "wand.and.stars"
        case .look: "paintpalette"
        case .app: "gearshape"
        }
    }
}

/// The former pages' names, each the page that took its rows: code written for the 14 pages (and the branches still
/// being merged) keeps working, and lands on the right page. A row's own id says where on it.
extension ArisSettingsPage {
    static var aris: ArisSettingsPage { ArisSettingsFormerPage.aris.page }
    static var ai: ArisSettingsPage { ArisSettingsFormerPage.ai.page }
    static var voice: ArisSettingsPage { ArisSettingsFormerPage.voice.page }
    static var memory: ArisSettingsPage { ArisSettingsFormerPage.memory.page }
    static var team: ArisSettingsPage { ArisSettingsFormerPage.team.page }
    static var skills: ArisSettingsPage { ArisSettingsFormerPage.skills.page }
    static var dictation: ArisSettingsPage { ArisSettingsFormerPage.dictation.page }
    static var todo: ArisSettingsPage { ArisSettingsFormerPage.todo.page }
    static var control: ArisSettingsPage { ArisSettingsFormerPage.control.page }
    static var notch: ArisSettingsPage { ArisSettingsFormerPage.notch.page }
    static var features: ArisSettingsPage { ArisSettingsFormerPage.features.page }
    static var general: ArisSettingsPage { ArisSettingsFormerPage.general.page }
    static var keys: ArisSettingsPage { ArisSettingsFormerPage.keys.page }
    static var about: ArisSettingsPage { ArisSettingsFormerPage.about.page }
}

/// The window and its sidebar, as measured (SETTINGS-REA.md §2–3): a 1080 × 710 window rounded 20 with its traffic
/// lights at 18, 18; a 220 sidebar `px-4` whose header is `pt-10`; nav items 44 tall, r12, 4 apart, a 20-pt icon 12
/// from a 14 / 500 label, 15.5 in from the left and 16 from the right. Option A: the four pages with no group names, and
/// under the open one its parts, 30-pt links r10 at 13 / 500 whose words start where the pages' names do. The list fits
/// the window at its smallest; it still scrolls and fades at its end if the window is ever shorter.
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

    /// The open page's part links: 30 tall, r10, 2 apart, 2 under the page's row and 6 over the next one; their words
    /// (13 / 500) start where the pages' names do (15.5 + 20 + 12).
    static let partRow = 30.0
    static let partGap = 2.0
    static let partsTop = 2.0
    static let partsBottom = 6.0
    static let partRadius = 10.0
    static let partLeading = rowLeading + iconSize + iconGap
    static let partTrailing = 10.0
    static let partLabelSize = 13.0
    /// How far a part's name may shrink before it is cut: "Startup · Language · Displays" fits the 220-pt sidebar at
    /// this (it was cut to "Startup · Language · D…" at .85: eleventh VM run).
    static let partLabelScale = 0.78

    /// The height the sidebar needs with `open`'s parts listed.
    static func height(open: ArisSettingsPage) -> Double {
        top + greeting + greetingGap + searchHeight + searchGap + pagesHeight(open: open) + bottom
    }

    /// The tallest the sidebar gets: with the page of the most parts open.
    static var tallest: Double { ArisSettingsPage.allCases.map { height(open: $0) }.max() ?? 0 }

    /// The open page's part links alone, the gap before them included.
    static func partsHeight(_ page: ArisSettingsPage) -> Double {
        let n = Double(page.parts.count)
        guard n > 0 else { return 0 }
        return rowGap + partsTop + n * partRow + (n - 1) * partGap + partsBottom
    }

    /// The list: the four pages' rows, and the open page's parts under its row.
    static func pagesHeight(open: ArisSettingsPage) -> Double {
        let pages = Double(ArisSettingsPage.allCases.count)
        return pages * row + (pages - 1) * rowGap + partsHeight(open)
    }

    /// Where `page`'s row lies in the list, from the list's own top, with `open`'s parts listed under its row.
    static func rowSpan(_ page: ArisSettingsPage, open: ArisSettingsPage) -> (top: Double, bottom: Double)? {
        var y = 0.0
        for (place, shown) in ArisSettingsPage.allCases.enumerated() {
            if place > 0 { y += rowGap }
            if shown == page { return (y, y + row) }
            y += row
            if shown == open { y += partsHeight(open) }
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
    /// The page it was on before option A: its name still finds it, and a row no part lists yet (one a branch added
    /// with its old page) lands in the part that took that page's rows.
    let former: ArisSettingsFormerPage
    let title: String
    let keywords: [String]
    /// What the row was called before (its title on a page it was merged from): found like its own name.
    var formerly: [String] = []

    init(id: String, page former: ArisSettingsFormerPage, title: String, keywords: [String], formerly: [String] = []) {
        self.id = id
        self.former = former
        self.title = title
        self.keywords = keywords
        self.formerly = formerly
    }

    /// The part that holds it now.
    var part: ArisSettingsPart {
        ArisSettingsParts.holding(id) ?? ArisSettingsParts.part(former.part) ?? ArisSettingsParts.all[0]
    }

    var page: ArisSettingsPage { part.page }
}

enum ArisSettingsIndex {
    private static func e(_ id: String, _ page: ArisSettingsFormerPage, _ title: String, _ keywords: String = "", formerly: [String] = []) -> ArisSettingsEntry {
        ArisSettingsEntry(id: id, page: page, title: title, keywords: keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, formerly: formerly)
    }

    /// Every setting, page by page.
    static let entries: [ArisSettingsEntry] = [
        e("aris.wake", .aris, "“아리스”라고 부르기", "호출어, 웨이크 워드, wake word, 깨우기, 부르기, 음성 호출, 아리스"),
        e("aris.wakeName", .aris, "부를 이름", "호출어 이름, 이름 바꾸기, 웨이크 워드, wake name, 자비스, 깨우는 말"),
        e("aris.voiceID", .aris, "내 목소리만 듣기", "내 목소리, 화자 인식, 목소리 확인, 다른 사람, 영상 소리, 보안, voice id, speaker"),
        e("aris.voiceEnrol", .aris, "내 목소리 익히기", "목소리 등록, 화자 등록, 내 목소리, 문장 읽기, enroll, 목소리 학습, 호출어 익히기, 다시 익히기, train",
          formerly: ["내 목소리 등록하기"]),
        e("aris.voiceForget", .aris, "목소리 정보 지우기", "목소리 지우기, 삭제, 화자 정보, 키체인"),
        e("aris.recordCalls", .aris, "내 호출 녹음하기", "호출어 녹음, 웨이크 워드, 녹음, 아리스, 학습 데이터"),
        e("aris.collect", .aris, "하루 소리 모으기", "소리 모으기, 녹음, 주변 소리, 오탐, 호출어"),
        e("aris.recordClear", .aris, "녹음 다 지우기", "녹음 지우기, 삭제, 호출어 녹음"),
        e("aris.minutes", .aris, "대화 이어가기", "대화 시간, 이어서 묻기, 후속 질문, 새 대화"),
        e("aris.silence", .aris, "계속 듣기", "대화 모드, 계속 듣기, 핸즈프리, 다시 듣기, 끝내기, 침묵"),
        e("aris.duplex", .aris, "에코 제거 오디오 (새 엔진)", "에코, 에코 제거, 스피커, 끼어들기, 새 엔진, 실험, 오디오 엔진, echo, duplex"),
        e("aris.bargeIn", .aris, "스피커로 들을 때도 끼어들기", "끼어들기, 말 끊기, 스피커, 헤드폰, 에코 제거, barge in"),
        e("aris.systemAudio", .aris, "시스템 오디오", "시스템 오디오, 권한, 보라색 표시, 녹음 표시, 다른 앱 소리", formerly: ["다른 앱 소리 확인"]),
        e("aris.sounds", .aris, "알림 효과음", "소리, 효과음, 알림음, 사운드"),
        ArisDayEndSetting.entry,
        ArisRecapSetting.entry,
        ArisLabsSetting.core2Entry,
        ArisLabsSetting.teachEntry,
        e("aris.mute", .aris, "음소거", "음소거, 조용히, 무음, 말하지 않기, 글로만, mute, 소리 끄기"),
        e("aris.quietHours", .aris, "밤에는 조용히", "조용한 시간, 밤, 야간, 방해 금지, 집중 모드, 화면 잠금, quiet, 알림 읽지 않기"),
        e("aris.claudeRing", .aris, "귀에 보일 사용량", "Claude Code, 클로드 코드, 사용량, 한도, 5시간, 주간, 자동, 고리, 링, 귀"),
        e("aris.claudeBudget", .aris, "API 키로 쓸 때 하루 예산", "Claude Code, 클로드 코드, API 키, 예산, 달러, 비용, 쓴 돈, 요금"),
        e("aris.claudeConnect", .aris, "Claude Code 연결", "Claude Code, 클로드 코드, 훅, hook, 연결, 승인, 세션, 상태 줄"),
        e("memory.auto", .memory, "자동으로 기억하기", "기억, 메모리, 학습, 자동, 배우기"),
        e("memory.search", .memory, "기억 찾기", "기억, 메모리, 검색, 찾기, 지우기, 잊기"),
        e("memory.clear", .memory, "기억 모두 지우기", "기억, 메모리, 전부 지우기, 초기화, 잊기"),
        e("memory.consolidate", .memory, ArisMemoryReviewRows.tidyTitle, "정리, 요약, 매주, 사람, 프로젝트, 기억 정리, 되돌리기, 메모리"),
        e("memory.import", .memory, ArisMemoryImportCopy.rowTitle, "가져오기, 다른 AI, 옮기기, 이전, 내보내기, import, 기억 가져오기, 메모리"),
        e("memory.work", .memory, ArisWorkSettingsRows.toggleTitle, "한 일, 작업 기억, 배운 것, 방법, 학습, 사용량, 토큰, 일하면서 배운 것"),
        e("memory.work.clear", .memory, ArisWorkSettingsRows.clearTitle, "한 일, 작업 기억, 배운 것, 전부 지우기, 초기화, 잊기"),
        // The saved steps and the lessons taught by showing them (fifth VM run, D8: "saved", "steps", "lesson" found nothing).
        e("memory.saved", .memory, ArisSavedStepsSettingsRows.heading,
          "저장, 저장된 단계, 단계, 수업, 배운 것, 가르친 것, 보여 주고 가르치기, 다시 하기, 이름 바꾸기, saved, steps, saved steps, lesson, lessons, taught, teach, replay"),
        e("team.add", .team, "팀원 추가", "팀, 새 팀원, 팀원 빼기"),
        e("team.detail", .team, "팀원 이름 · 언제 부를까요", "이름, 역할, 하는 일, 언제 부를까요, 어떻게 일할까요, 지시, 두뇌, 쓸 수 있는 것, 권한, 기억, 팀원 편집, 코디", formerly: ["팀원의 두뇌"]),
        e("team.look", .team, "팀원 캐릭터", "캐릭터, 종류, 색, 질감, 패브릭, 모양"),
        e("team.make", .team, "말로 팀원 만들기", "만들기, 새 팀원, 말로, 템플릿, 문서 담당, 리서처, 일정 비서"),
        e("team.knowhow", .team, "앱 노하우", "앱, 노하우, 배운 것, 카카오톡, 단축키, 팁"),
        ArisTerminalSetting.entry,
        ArisDropLearnedSetting.entry,
        e("skills.feature", .skills, "스킬 기능", "스킬, skill, 스킬 켜기, SkillSpector, 파이썬, 보안 검사"),
        e("skills.add", .skills, "스킬 추가 · 말로 만들기", "스킬, 링크, GitHub, 깃허브, skill-creator, 만들기, 폴더, 가르치기"),
        e("skills.list", .skills, "내 스킬", "스킬 목록, 끄기, 삭제, 모든 AI로 시험, 테스트, SKILL.md"),
        e("voice.languages", .voice, "쓰는 언어", "언어, 언어 추가, 한국어, 영어, 다국어"),
        e("hear.repair", .voice, "들은 말 다듬기", "잘못 들음, 오인식, 교정, 고치기, 영어 섞어 말하기, 다듬기, repair"),
        e("hear.words", .voice, "Aris가 알아야 할 단어", "단어장, 내 단어, 사전, 고유명사, 어휘, 들린 말, 맞는 말"),
        e("voice.speed", .voice, "말하기 속도", "속도, 빠르게, 느리게, 들어 보기"),
        e("dictation.on", .dictation, "받아쓰기 쓰기", "받아쓰기 끄기, 받아쓰기 켜기, 다른 받아쓰기 앱, 끄기, 켜기, 딕테이션, 단축키 끄기, 알약 숨기기, dictation, off"),
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
        e("ai.brain", .ai, "답하는 AI", "두뇌, 답하는 AI, Claude, Codex, ChatGPT, Gemini, GPT, 모델, 클로드, API 키, API key, OpenAI, Anthropic, OpenRouter, Groq, xAI, Mistral, DeepSeek, Ollama, LM Studio, 로컬 모델, 다른 AI 연결, 내 연결", formerly: ["생각", "기본으로 답하는 AI"]),
        e("ai.jev", .ai, "짧은 명령 빨리 알아듣기", "TypeSafe, Jev, 타입세이프, API 키, API key, 키체인, 짧은 명령, 알아듣는 모델, 라우터, router, Haiku, 하이쿠, GPT-6 Luna, 루나, nano, 나노, Gemini Flash-Lite, 판단, 판단 모델, decision model, OpenRouter, Cloudflare, Clef, Perplexity, Decider, Mercury Decide, Solar Decide, Upstage, Liquid, Microsoft Decision, Kev, OpenJev, systemone, 키워드 규칙"),
        e("ai.fallback", .ai, "다른 AI로 넘기기", "다른 AI, 대신 답하기, 넘기기, 한도, 폴백, fallback, 백업 AI, 안 될 때, Codex로, GPT로, 자동 전환"),
        e("ai.models", .ai, "모델 고르기", "모델 바꾸기, 추론 수준, 생각 수준, effort, reasoning, Opus, Sonnet, Haiku, Fable, 오퍼스, 소넷, 하이쿠, Luna, Sol, 직접 입력, 깊은 일, 작업, 작은 도우미, 새 모델, 최신 모델"),
        e("ai.hear", .ai, "듣기", "받아 적기, 음성 인식, 자동, Whisper, 위스퍼, Apple 받아쓰기, ElevenLabs Scribe, 일레븐랩스, Soniox, 소닉스, OpenAI, 큰 모델, 작은 모델, 모델 받기, 클라우드, 듣기 엔진", formerly: ["ElevenLabs Scribe로 듣기", "듣기 엔진"]),
        e("ai.speak", .ai, "말하기 · 목소리", "목소리, 음성, 보이스, ElevenLabs, 일레븐랩스, macOS 목소리, 라이브러리, 링크로 추가, 미리 듣기, API 키, API key, 목소리 바꾸기", formerly: ["목소리"]),
        e("ai.computerEngine", .ai, "다른 앱을 다루는 방식", "컴퓨터 사용, 앱 조작, 백그라운드, Aris, Peekaboo, GPT, Codex"),
        e("ai.services", .ai, "연결된 서비스", "사용량, 로그인, 계정, Claude, Codex, Antigravity"),
        e("ai.mcp.composio", .ai, "Composio", "Composio, 컴포지오, Gmail, Slack, Notion, 구글 캘린더, 외부 서비스, 연결, API 키, API key, 키체인"),
        e("ai.mcp.add", .ai, "MCP 서버 추가", "MCP, 서버, 도구, 외부 서비스, 토큰, 연결"),
        e("control.ax", .control, ArisFix.Pane.accessibility.title(english: false), "권한, 접근성, 손쉬운 사용, 기기 제어, 누르기, 입력"),
        e("control.screen", .control, ArisFix.Pane.screen.title(english: false), "권한, 스크린, 화면 기록, 화면 녹화"),
        e("control.mic", .control, "마이크", "권한, 마이크로폰, 듣기"),
        e("control.speech", .control, "음성 인식", "권한, 음성 인식, 받아쓰기, 말 알아듣기, speech recognition"),
        e("control.input", .control, "입력 모니터링", "권한, 입력 모니터링, 키보드, 받아쓰기 키, 동그라미 키, 단축키, input monitoring"),
        e("control.sees", .control, "질문할 때 화면 같이 보기", "화면, 스크린샷, 같이 보기, 이거, 화면 봐 줘, 가리킬 때만"),
        e("control.circle", .control, "동그라미로 가리키기", "제스처, 그리기, 가리키기, 동그라미, 원"),
        e("control.standing", .control, "묻지 않고 하는 일", "허락, 승인, 자동, 취소, 상시 허용"),
        e("notch.hover", .notch, "포인터를 올리면 열기", "호버, 마우스, 포인터"),
        e("notch.haptics", .notch, "진동", "햅틱, 트랙패드"),
        e("notch.gestures", .notch, "제스처", "스와이프, 두 손가락, 쓸기"),
        e("notch.height", .notch, "노치 크기", "높이, 메뉴 막대, 실제 노치"),
        e("notch.customHeight", .notch, "직접 정한 높이", "높이, 슬라이더"),
        e("notch.unhide", .notch, "숨긴 사이드 노치", "다시 보이기, 숨기기"),
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
        e("look.settingsIcon", .notch, "노치에 설정 아이콘", "아이콘, 톱니바퀴, 설정"),
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
        e("keys.talk", .keys, "Aris에게 말하기", "단축키, 핫키, 키, 말하기, 옵션 스페이스", formerly: ["말하기 단축키"]),
        e("keys.dictation", .keys, "받아쓰기", "단축키, 오른쪽 옵션, 딕테이션, 받아 적기", formerly: ["누르고 있는 동안 받아쓰기"]),
        e("keys.pasteLast", .keys, "마지막 받아쓰기 다시 넣기", "단축키, 다시 넣기, 받아쓰기, 붙여 넣기, 컨트롤 커맨드 V"),
        e("keys.answer", .keys, "Claude에게 답하기", "단축키, 승인, 질문 카드"),
        e("keys.clipboard", .keys, "클립보드 열기 (왼쪽 사이드 노치)", "단축키, 클립보드, 사이드 노치, 왼쪽", formerly: ["클립보드 기록", "왼쪽 사이드 노치 열기"]),
        e("keys.right", .keys, "오른쪽 사이드 노치 열기", "단축키, 사이드 노치, 오른쪽, 할 일, 캘린더"),
        e("keys.notch", .keys, "노치 열고 닫기", "단축키, 노치"),
        e("keys.peek", .keys, "음악 미리 보기", "단축키, 음악"),
        e("about.version", .about, "버전 정보", "버전, 정보, Aris"),
        e("about.autoUpdate", .about, "자동으로 업데이트", "업데이트, 자동, 새 버전, 버전"),
        e("about.checkUpdate", .about, "업데이트 확인", "업데이트, 새 버전, 확인, 버전"),
        e("about.folder", .about, "데이터가 있는 곳", "Finder, 로그, 폴더, 기록, .config, 저장 위치, 어디에 저장", formerly: ["기록 폴더 열기"]),
        e("about.export", .about, "데이터 내보내기", "JSON, 백업, 내보내기"),
        e("about.diagnostics", .about, "진단 내보내기", "문제, 로그, 버그, 진단"),
        e("about.wipe", .about, "데이터 지우기", "삭제, 초기화, 기록 지우기"),
        e("about.uninstall", .about, "Aris 제거", "삭제, 언인스톨, 제거"),
        e("ai.savedKeys", .ai, "저장된 키", "API 키, API key, 키체인, 키 지우기, ElevenLabs"),
    ]

    static func entry(_ id: String) -> ArisSettingsEntry? { entries.first { $0.id == id } }

    /// The tags the 팀원 sheet draws itself (its roster, the picked one's fields, the character picker): a search that
    /// lands on one opens the sheet.
    static let teamAnchors = ["team.add", "team.detail", "team.look", "team.make", "team.knowhow"]

    /// The tags the 스킬 page draws itself (its switch, its chat, its list).
    static let skillsAnchors = ["skills.feature", "skills.add", "skills.list"]

    /// Rows drawn only once the helper has answered (저장된 단계): searchable before that, whatever page was shown first
    /// and in either language (sixth VM run, item 3: in a Korean UI they were found only after 할 수 있는 일 › 기억 had
    /// been shown once, the page that asks the helper for them).
    static let loadedLater = ["memory.saved"]

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
        /// Its former names and its former page's name, in that language.
        var formerly: [String] = []
    }

    /// `entry`'s names in the English window: its name, its page and part, its former names and its former page's.
    static func english(_ entry: ArisSettingsEntry, _ w: ArisSettingsWording) -> Alias {
        Alias(title: w.of(entry.page, entry.title), page: [entry.page.title, entry.part.title, entry.former.title].map(w.frame).joined(separator: " "),
              formerly: entry.formerly.map { w.of(entry.page, $0) })
    }

    /// How well `entry` matches the normalized query (lower is better) and, when it was one of its keywords that
    /// matched and not its name, that keyword; or nil.
    private static func rank(_ entry: ArisSettingsEntry, _ q: String, alias: Alias?) -> (rank: Int, why: String?)? {
        let titles = ([entry.title, alias?.title].compactMap { $0 } + entry.formerly + (alias?.formerly ?? [])).map(normalized)
        if titles.contains(where: { $0.hasPrefix(q) }) { return (0, nil) }
        if titles.contains(where: { $0.contains(q) }) { return (1, nil) }
        if isInitials(q), initials(entry.title).contains(q) { return (2, nil) }
        if let word = entry.keywords.first(where: { normalized($0).hasPrefix(q) }) { return (3, word) }
        if let word = entry.keywords.first(where: { normalized($0).contains(q) }) { return (4, word) }
        // The page it is on, its part, and the page it was on before (a search for "AI 서비스" still finds its rows).
        if ([entry.page.title, entry.part.title, entry.former.title] + (alias.map { [$0.page] } ?? [])).contains(where: { normalized($0).contains(q) }) { return (5, nil) }
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
