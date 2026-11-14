//
//  ArisSettingsBuilder.swift
//  Aris
//
//  Each page's sections, from a snapshot. 14 pages (the owner's pick 6-B): 할 일 and 캘린더 are one page, and the 모양 page's
//  rows are in 일반 (the window's look) and 노치 (the notch's icon and tabs); 기본으로 답하는 AI lives in AI 서비스, and
//  대화 keeps a row that goes there. The 팀원 and 스킬 pages draw themselves. Foundation only (tested).
//

import Foundation

enum ArisSettingsBuilder {
    /// The accent colours offered: the eight presets the window has always had, so a saved one still shows its ring.
    static let accents = ["#007AFF", "#AF52DE", "#FF2D55", "#FF453A", "#FF9500", "#FFCC00", "#66D22D", "#8E8E93"]

    /// Every row and section the pages draw for `s`, and the 팀원 page's own tags: what a search may land on now.
    static func searchable(_ s: ArisSettingsSnapshot) -> Set<String> {
        ArisSettingsPage.allCases.reduce(into: Set(ArisSettingsIndex.teamAnchors + ArisSettingsIndex.skillsAnchors)) { $0.formUnion(ArisSettingsLayout.tags(sections($1, s))) }
    }

    static func sections(_ page: ArisSettingsPage, _ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        switch page {
        case .aris: conversation(s)
        case .memory: withSavedStepsFeature(ArisMemorySettingsRows.sections(s)) + [ArisDropLearnedSetting.section(s.dropHabits)]
        case .team, .skills: []
        case .voice: voice(s)
        case .dictation: dictation(s)
        case .todo: todo(s) + calendar(s)
        case .ai: services(s)
        case .control: control(s)
        case .notch: notch(s)
        case .features: features(s)
        case .general: general(s)
        case .keys: keys(s)
        case .about: about(s)
        }
    }

    /// 기억 with 저장된 단계's detail sheet a link away, at the end of its section's title.
    private static func withSavedStepsFeature(_ sections: [ArisSettingSection]) -> [ArisSettingSection] {
        sections.map { section in
            var out = section
            if section.id == ArisFeature.savedSteps.sectionID { out.feature = .savedSteps }
            return out
        }
    }

    private static func options(_ pairs: [(String, String)]) -> [ArisSettingOption] { pairs.map { .init(id: $0.0, title: $0.1) } }
    private static func button(_ title: String, _ action: ArisSettingsAction, _ kind: ArisSettingButtonKind = .ghost, enabled: Bool = true) -> ArisSettingControl {
        .buttons([ArisSettingButton(title: title, action: action, kind: kind, enabled: enabled)])
    }

    // MARK: ARIS

    private static func conversation(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [
            ArisSettingSection(id: "aris.call", heading: "부르기", note: callNote(s), rows: [
                ArisSettingItem(id: "aris.wake", icon: .symbol("waveform"), title: "“아리스”라고 부르기",
                               desc: "이름을 부르면 들어요.",
                               control: .toggle(.wakeWord, s.wakeWord)),
                ArisSettingItem(id: "aris.train", icon: .symbol("person.wave.2"), title: "내 목소리 익히기",
                               desc: s.hasVoiceModel ? "내 목소리로 익혀 뒀어요." : "아직 안 익혔어요.",
                               control: button(s.hasVoiceModel ? "다시 익히기" : "익히기", .trainVoice, enabled: !s.busy)),
                ArisSettingItem(id: "aris.talkKey", icon: .symbol("aris-star"), title: "말하기 단축키",
                               desc: "누르고 바로 말해요.", control: .shortcut(name: "talkToAris", caps: s.talkCaps)),
                ArisSettingItem(id: "aris.minutes", icon: .symbol("arrow.clockwise"), title: "대화 이어가기",
                               desc: "이 시간 안에 물으면 같은 대화로 이어져요.",
                               control: .choice(.minutes, options([("2", "2분"), ("5", "5분"), ("15", "15분")]), selected: String(s.minutes))),
            ]),
            ArisSettingSection(id: "aris.talk", heading: "대화 모드", note: "“됐어”, “그만”, Esc로 끝나고, 말이 없으면 고른 시간 뒤에 끝나요. 다른 앱 소리를 확인하는 동안 메뉴 막대에 보라색 표시가 뜨지만, 크기만 재고 녹음하지 않아요.", rows: [
                ArisSettingItem(id: "aris.silence", icon: .symbol("hand"), title: "계속 듣기",
                               desc: "답한 뒤에도 바로 다시 들어요.",
                               control: .choice(.silence, options([("0", "끄기"), ("15", "15초"), ("30", "30초"), ("60", "1분")]), selected: String(s.silence))),
                ArisSettingItem(id: "aris.bargeIn", icon: .symbol("hand.raised"), title: "스피커로 들을 때도 끼어들기",
                               desc: "스피커로 들을 때도 Aris보다 크게 말하면 멈추고 들어요.",
                               control: .toggle(.bargeInSpeakers, s.bargeInSpeakers)),
                ArisSettingItem(id: "aris.systemAudio", icon: .symbol("speaker.wave.2.circle"),
                               title: s.systemAudioMissing ? "시스템 오디오 권한 필요" : "다른 앱 소리 확인",
                               desc: "다른 앱에서 소리가 나면 듣기를 잠깐 멈춰요.",
                               control: .status(ok: !s.systemAudioMissing,
                                                s.systemAudioMissing ? ArisSettingButton(title: "열기", action: .permission("systemAudio")) : nil)),
            ]),
            ArisSettingSection(id: "aris.answer", heading: "답하는 AI", note: "“GPT한테 물어봐”처럼 이름을 먼저 말하면 그 한 번만 다른 AI가 답해요.", rows: [
                ArisSettingItem(id: "aris.brainLink", icon: .symbol("brain"), title: "기본으로 답하는 AI",
                               desc: "AI 서비스에서 바꿔요.",
                               control: .link(.go(.ai, anchor: "ai.brain"), value: s.brainTitle), indexed: false),
            ]),
            ArisSettingSection(id: "aris.alerts", heading: "알림", rows: [
                ArisSettingItem(id: "aris.sounds", icon: .symbol("volume-2"), title: "알림 효과음",
                               desc: "Claude가 일을 마치거나 승인이 필요할 때 짧은 소리를 내요.", control: .toggle(.sounds, s.sounds)),
                ArisDayEndSetting.row(s.dayEndOffer),
                ArisQuietSettingsRows.mute(s.muted),
            ] + ArisQuietSettingsRows.hourRows(s.quietHours), feature: .notify),
            claudeCode(s),
        ]
    }

    /// 부르기's small line: where the name is listened for, and while no voice is learned, that any voice wakes it.
    private static func callNote(_ s: ArisSettingsSnapshot) -> String {
        s.hasVoiceModel ? ArisWakeHonesty.note
            : ArisWakeHonesty.noteUntrained
    }

    /// Claude Code's usage in the closed notch's ear (mockup claude-usage.html): what the ring shows on a plan
    /// (ClaudeRingMode's raw values; anything else reads as 5시간, the ring as it always was), and the daily budget it
    /// fills against on an API key (that row draws itself: ClaudeBudgetRow).
    private static func claudeCode(_ s: ArisSettingsSnapshot) -> ArisSettingSection {
        let lines = ["fiveHour": "닫힌 노치 귀의 고리가 5시간 한도를 보여 줘요", "sevenDay": "닫힌 노치 귀의 고리가 주간 한도를 보여 줘요",
                     "auto": "5시간과 주간 중 더 많이 쓴 쪽을 보여 줘요"]
        let mode = lines[s.claudeRing] == nil ? "fiveHour" : s.claudeRing
        return ArisSettingSection(id: "aris.claude", heading: "Claude Code", grouped: true, rows: [
            ArisSettingItem(id: "aris.claudeRing", icon: .symbol("gauge.with.needle"), title: "귀에 보일 사용량", desc: lines[mode],
                           control: .choice(.claudeRing, options([("fiveHour", "5시간"), ("sevenDay", "주간"), ("auto", "자동")]), selected: mode)),
            ArisSettingItem(id: "aris.claudeBudget", icon: .symbol("dollarsign"), title: "API 키로 쓸 때 하루 예산", control: .custom("claudeBudget")),
        ])
    }

    /// What the closed language select says (the measured one: "English + 2 more"): the first language, then how many
    /// more ("한국어 외 1개"; the settings catalog has the English).
    static func languagesSummary(_ names: [String]) -> String {
        guard let first = names.first else { return "언어 추가" }
        return names.count == 1 ? first : "\(first) 외 \(names.count - 1)개"
    }

    private static func voice(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        let voiceRow = s.hasVoiceKey
            ? ArisSettingItem(id: "voice.voice", icon: .symbol("person.wave.2"), title: "목소리",
                             desc: "ElevenLabs 계정에 있는 목소리 중에서 골라요.",
                             control: .trailing("voicePicker"))
            : ArisSettingItem(id: "voice.voice", icon: .symbol("person.wave.2"), title: "목소리",
                             desc: "언어마다 이 Mac의 가장 좋은 목소리를 써요.", control: .none)
        let speedID = s.speed < 0.95 ? "0.9" : s.speed > 1.05 ? "1.15" : "1"
        // Scribe can't listen without its key, so its switch never reads as on then (VM run 2026-11-11: it showed on
        // on a new Mac with no key). The stored choice is left as it is, for when a key is added.
        let scribeRow = s.hasVoiceKey
            ? ArisSettingItem(id: "voice.scribe", icon: .symbol("cloud"), title: "ElevenLabs Scribe로 듣기",
                             desc: "말하는 동안 바로 받아 적어요.",
                             control: .toggle(.cloud, s.cloud))
            : ArisSettingItem(id: "voice.scribe", icon: .symbol("cloud"), title: "ElevenLabs Scribe로 듣기",
                             desc: "AI 서비스의 듣기에 ElevenLabs 키를 넣으면 켤 수 있어요.",
                             control: .toggle(.cloud, false, enabled: false))
        return [
            ArisSettingSection(id: "voice.language", heading: "언어", note: s.hasVoiceKey ? "여기 없는 언어로 말하면 소리 나는 대로 적혀요. Scribe를 켜면 말한 소리가 ElevenLabs로 가고 쓴 만큼 요금이 나와요." : "여기 없는 언어로 말하면 소리 나는 대로 적혀요.", rows: [
                ArisSettingItem(id: "voice.languages", icon: .symbol("globe"), title: "쓰는 언어",
                               desc: "말할 때 이 언어들 중에서 알아서 찾아요.",
                               control: .buttons([ArisSettingButton(title: languagesSummary(s.languages.map(\.title)), action: .addLanguage, kind: .select)])),
                scribeRow,
            ] + engineRow(s)),
            ArisSettingSection(id: "voice.voices", heading: "목소리", note: s.hasVoiceKey ? "들어 보기만 해서는 요금이 들지 않아요." : nil, rows: [
                voiceRow,
                ArisSettingItem(id: "voice.speed", icon: .symbol("gauge.with.needle"), title: "말하기 속도", desc: "답을 읽는 속도예요.",
                               control: .choice(.speed, options([("0.9", "느리게"), ("1", "보통"), ("1.15", "빠르게")]), selected: speedID,
                                                lead: ArisSettingButton(title: "들어 보기", action: .listen))),
            ]),
        ]
    }

    /// 듣기 엔진: which of Apple's speech engines hears on this Mac (shown, nothing to change). None in a still picture.
    private static func engineRow(_ s: ArisSettingsSnapshot) -> [ArisSettingItem] {
        guard !s.listenEngine.isEmpty else { return [] }
        return [ArisSettingItem(id: "voice.engine", icon: .symbol("waveform"), title: ArisListenEngineWords.rowTitle, desc: s.listenEngine, control: .none)]
    }

    private static func dictation(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [
            ArisSettingSection(id: "dictation.keys", heading: "단축키", note: "두 번 빠르게 누르면 손을 떼고 말할 수 있고, 한 번 더 누르면 넣어요. Esc로 취소하고, 한 번에 20분까지예요.", rows: [
                ArisSettingItem(id: "dictation.key", icon: .symbol("mic"), title: "누르고 있는 동안 받아쓰기",
                               desc: "누른 채로 말하고, 떼면 붙여 넣어요.",
                               control: .shortcut(name: ArisDictationKey.Choice.recorderName, caps: s.dictationCaps)),
                ArisSettingItem(id: "dictation.pasteLast", icon: .symbol("clipboard-paste"), title: "마지막 받아쓰기 다시 넣기",
                               desc: "방금 받아 적은 말을 커서 자리에 한 번 더 넣어요.", control: .shortcut(name: "pasteLastDictation", caps: s.pasteLastCaps)),
            ]),
            ArisSettingSection(id: "dictation.screen", heading: "화면", note: "켜 두면 받아쓰는 동안 노치는 조용하고, 화면 아래 알약에 듣는 소리와 진행이 보여요. 알약을 눌러도 받아쓰기를 시작해요.", rows: [
                ArisSettingItem(id: "dictation.pill", icon: .symbol("audio-lines"), title: "받아쓰기 알약 보이기",
                               desc: "끄면 받아쓰기가 예전처럼 노치에 보여요.",
                               control: .toggle(.dictationPill, s.dictationPill)),
                ArisSettingItem(id: "dictation.pillIdle", icon: .symbol("moon"), title: "쉴 때도 보이기",
                               desc: "끄면 받아 쓸 때만 나타나요.",
                               control: .toggle(.dictationPillIdle, s.dictationPillIdle, enabled: s.dictationPill)),
            ]),
            ArisSettingSection(id: "dictation.polish", heading: "다듬기", note: "그때는 받아 적은 말과 커서 주변 글이 Anthropic으로 가요. 꺼 두면 말이 Mac 밖으로 나가지 않아요.", rows: [
                ArisSettingItem(id: "dictation.brainPolish", icon: .symbol("text.badge.checkmark"), title: "Mac에서 못 다듬을 때 AI로 다듬기",
                               desc: "이 Mac이 못 다듬을 때만 Claude가 다듬어요.",
                               control: .toggle(.dictationBrainPolish, s.brainPolish)),
            ]),
            ArisSettingSection(id: "dictation.styles", heading: "앱별 문체", grouped: true, rows: ArisAppKind.allCases.map { kind in
                ArisSettingItem(id: "dictation.style.\(kind.rawValue)", icon: .none, title: kind.title, desc: kind.detail,
                               control: .choice(.dictationStyle(kind.rawValue), options(ArisWritingStyle.allCases.map { ($0.rawValue, $0.title) }),
                                                selected: ArisWritingStyles.style(for: kind, choices: s.styles).rawValue))
            }),
            ArisSettingSection(id: "dictation.vocabulary", heading: "내 단어", rows: [
                ArisSettingItem(id: "dictation.words", icon: .symbol("book"), title: "단어장",
                               desc: "자꾸 틀리는 말을 넣어 두면 그대로 적어요 · \(s.words)개", control: button("편집", .editWords)),
            ] + learnedRows(s.learned)),
        ]
    }

    /// Proposals first (넣기 / 무시), then the learned words (지우기).
    private static func learnedRows(_ words: [ArisSettingsSnapshot.LearnedWord]) -> [ArisSettingItem] {
        let proposed = words.filter(\.proposed).map { word in
            ArisSettingItem(id: "dictation.proposed.\(word.text)", icon: .symbol("questionmark.bubble"), title: "‘\(word.text)’ 넣을까요?",
                           desc: "받아 적은 ‘\(word.heard)’를 ‘\(word.text)’로 고치셨어요.",
                           control: .buttons([ArisSettingButton(title: "넣기", action: .learnWord(word.text), kind: .primary),
                                              ArisSettingButton(title: "무시", action: .dismissWord(word.text))]), indexed: false)
        }
        let learned = words.filter { !$0.proposed }.map { word in
            ArisSettingItem(id: "dictation.learned.\(word.text)", icon: .symbol("checkmark.bubble"), title: word.text,
                           desc: word.heard.isEmpty ? "고친 걸 보고 배웠어요." : "‘\(word.heard)’로 들리던 말이에요.",
                           control: .buttons([ArisSettingButton(title: "지우기", action: .forgetWord(word.text), kind: .danger)]), indexed: false)
        }
        return proposed + learned
    }

    private static func access(_ access: ArisAccess, granted: String, ask: String, refresh: ArisSettingButton? = nil,
                               request: ArisSettingsAction) -> (desc: String, control: ArisSettingControl) {
        switch access {
        case .granted: (granted, .status(ok: true, refresh))
        case .undecided: (ask, button("허용", request, .primary))
        case .blocked: (ask, button("시스템 설정 열기", request, .primary))
        }
    }

    private static func todo(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        let state = access(s.reminders, granted: "허용됐어요.", ask: "허용하면 할 일을 보고 넣을 수 있어요.", request: .remindersAccess)
        var sections = [ArisSettingSection(id: "todo.intro", heading: "할 일", note: "여기서 고른 목록이 할 일 탭에 나오고, 새로 넣은 건 미리 알림 앱에도 생겨요.", rows: [
            ArisSettingItem(id: "todo.access", icon: .symbol("checklist"), title: "미리 알림 접근", desc: state.desc, control: state.control),
        ])]
        guard s.reminders == .granted else { return sections }
        let included = s.reminderLists.filter(\.included)
        sections.append(ArisSettingSection(id: "todo.lists", heading: "할 일 목록", grouped: true, rows: s.reminderLists.map { list in
            ArisSettingItem(id: "todo.list.\(list.id)", icon: .dot(list.colorHex), title: list.name, desc: list.source.isEmpty ? nil : list.source,
                           control: .toggle(.todoList(list.id), list.included), indexed: false)
        }))
        sections.append(ArisSettingSection(id: "todo.more", rows: [
            included.isEmpty
                ? ArisSettingItem(id: "todo.default", icon: .symbol("tray.and.arrow.down"), title: "새 항목 넣을 목록", desc: "목록을 먼저 포함해 주세요.", control: .none)
                : ArisSettingItem(id: "todo.default", icon: .symbol("tray.and.arrow.down"), title: "새 항목 넣을 목록", desc: "할 일 탭이나 말로 새로 넣은 항목이 가는 곳이에요.",
                                 control: .menu(.todoDefault, included.map { .init(id: $0.id, title: $0.name) }, selected: s.defaultList)),
            ArisSettingItem(id: "todo.newList", icon: .symbol("plus.rectangle.on.folder"), title: "새 목록 만들기",
                           desc: s.newListFailed ? "목록을 만들지 못했어요." : "미리 알림에 새 목록을 만들고 바로 포함해요.",
                           control: .field(.newListName, text: s.newListName, placeholder: "이름",
                                           ArisSettingButton(title: "만들기", action: .createList, enabled: !s.newListName.trimmingCharacters(in: .whitespaces).isEmpty))),
        ]))
        return sections
    }

    private static func calendar(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        let state = access(s.calendarAccess, granted: "Apple 캘린더가 바뀌면 저절로 따라가요.", ask: "일정을 읽으려면 캘린더 전체 접근이 필요해요.",
                           refresh: ArisSettingButton(title: "새로 고침", action: .calendarRefresh), request: .calendarAccess)
        var intro = [ArisSettingItem(id: "calendar.access", icon: .symbol("calendar.badge.checkmark"), title: "캘린더 접근", desc: state.desc, control: state.control)]
        var sections: [ArisSettingSection] = []
        let google = s.googleCalendars
        if s.calendarAccess == .granted {
            intro.append(ArisSettingItem(id: "calendar.google", icon: .symbol("g.circle"), title: "Google 캘린더",
                                        desc: google > 0 ? "연결됐어요 · 캘린더 \(google)개"
                                                         : "Mac의 인터넷 계정에 Google을 추가하고 캘린더를 켜면 나와요.",
                                        control: google > 0 ? .status(ok: true, ArisSettingButton(title: "계정 관리", action: .internetAccounts))
                                                            : button("연결", .internetAccounts)))
        }
        sections.append(ArisSettingSection(id: "calendar.intro", heading: "캘린더", note: "포함한 캘린더의 앞으로 일주일 일정이 사이드 노치에 나오고, Aris가 일정을 찾을 때도 그 캘린더만 봐요.", rows: intro))
        if s.calendarAccess == .granted {
            sections.append(s.calendars.isEmpty
                ? ArisSettingSection(id: "calendar.include", heading: "포함할 캘린더", rows: [
                    ArisSettingItem(id: "calendar.none", icon: .none, title: "캘린더가 없어요", desc: "Apple 캘린더에서 계정을 연결하거나 새로 만들어 주세요", control: .empty, indexed: false)])
                : ArisSettingSection(id: "calendar.include", heading: "포함할 캘린더", grouped: true, rows: s.calendars.map { entry in
                    ArisSettingItem(id: "calendar.cal.\(entry.id)", icon: .dot(entry.colorHex), title: entry.name, desc: entry.source,
                                   control: .toggle(.calendar(entry.id), entry.included), indexed: false)
                }))
        }
        sections.append(ArisSettingSection(id: "calendar.show", heading: "일정 표시", note: "Google 캘린더로 열면 그날 보기가 웹에서 열려요.", rows: [
            ArisSettingItem(id: "calendar.allDay", icon: .symbol("sun.max"), title: "종일 일정 표시", desc: "종일 일정을 날짜 아래 작은 칩으로 보여 줘요.", control: .toggle(.allDay, s.allDay)),
            ArisSettingItem(id: "calendar.join", icon: .symbol("video"), title: "일정을 누르면 회의 참가",
                           desc: "진행 중이거나 10분 안에 시작하는 회의는 참가 링크를 열어요.", control: .toggle(.joinMeeting, s.joinMeeting)),
            ArisSettingItem(id: "calendar.openIn", icon: .symbol("arrow.up.forward.app"), title: "일정 열기", desc: "일정을 누르면 열 앱이에요.",
                           control: .choice(.openIn, options([("apple", "Apple 캘린더"), ("google", "Google 캘린더")]), selected: s.openIn)),
        ]))
        return sections
    }

    /// The external services (Composio and the user's MCP servers): drawn by ArisServicesSection's rows.
    private static let mcpRows = [
        ArisSettingItem(id: "ai.mcp.composio", icon: .symbol("square.stack.3d.up"), title: "Composio", control: .custom("mcp.composio")),
        ArisSettingItem(id: "ai.mcp.servers", icon: .symbol("server.rack"), title: "MCP 서버", control: .custom("mcp.servers"), indexed: false),
        ArisSettingItem(id: "ai.mcp.add", icon: .symbol("plus"), title: "MCP 서버 추가", control: .custom("mcp.add")),
    ]

    /// AI 서비스 (the owner's pick, mockup ai-services-D). 생각, 듣기 and 말하기 are drawn by ArisAIServicesPage from its own
    /// state (ArisAIServicesModel); their rows are listed here so the search finds them and can scroll to them. 연결된
    /// 서비스 folds under the mockup's one row, and the two rows after it are this page's earlier settings.
    private static func services(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        let serviceRows = s.services.isEmpty
            ? [ArisSettingItem(id: "ai.service.loading", icon: .none, title: "서비스를 확인하는 중", control: .loading, indexed: false)]
            : s.services.map { ArisSettingItem(id: "ai.service.\($0.id)", icon: .logo($0.id), title: $0.title, desc: $0.detail, control: .chip($0.status, tone: $0.tone), indexed: false) }
        return [
            ArisSettingSection(id: "ai.think", heading: "생각", rows: [
                ArisSettingItem(id: "ai.brain", icon: .symbol("brain"), title: "생각", control: .custom("ai.think")),
                ArisSettingItem(id: "ai.jev", icon: .none, title: "짧은 명령 빨리 알아듣기", control: .custom("ai.jev")),
            ]),
            ArisSettingSection(id: "ai.voice", heading: "음성", rows: [
                ArisSettingItem(id: "ai.hear", icon: .symbol("mic"), title: "듣기", control: .custom("ai.hear")),
                ArisSettingItem(id: "ai.speak", icon: .symbol("speaker.wave.2"), title: "말하기", control: .custom("ai.speak")),
            ]),
            ArisSettingSection(id: "ai.services", heading: "연결된 서비스",
                               note: "위는 사이드 노치 사용량 탭에 나오는 AI예요. 로그인 정보는 각 앱의 것을 읽기만 하고 Aris가 따로 저장하지 않아요. 아래는 어느 AI로 답하든 똑같이 쓰는 외부 서비스예요: 읽기는 바로 하고, 보내거나 바꾸는 일은 매번 카드로 물어봐요. 키와 토큰은 키체인에만 저장돼요.",
                               grouped: true, rows: serviceRows + mcpRows),
            ArisSettingSection(id: "ai.more", rows: [
                ArisSettingItem(id: "ai.computerEngine", icon: .symbol("macwindow"), title: "다른 앱을 다루는 방식",
                               desc: "Peekaboo는 무료이고 어느 AI로 답하든 돼요. GPT는 Codex가 있어야 하고, 없으면 Peekaboo로 해요.",
                               control: .menu(.computerEngine, s.computerEngines, selected: s.computerEngine)),
                ArisSettingItem(id: "ai.teamBrain", icon: .symbol("person.2"), title: "팀원의 두뇌", desc: "팀원마다 따로 정해요. 어느 AI든 고를 수 있어요.",
                               control: .link(.go(.team, anchor: "team.detail"), value: "팀원")),
            ]),
        ]
    }

    // MARK: 생각 › Claude, ChatGPT and Gemini (ArisAIServicesBuilder words its rows with these)

    /// What a brain's own login runs in a terminal (the agent's fixed command); the API brain has none.
    static func brainCommand(_ brain: ArisBrain) -> String? {
        switch brain {
        case .claude: "claude"
        case .codex: "codex login"
        case .antigravity: "agy"
        case .api: nil
        }
    }

    /// How an AI that isn't on this Mac is made ready (the row under 생각 when its tool isn't installed).
    static func brainHow(_ brain: ArisBrain) -> String {
        switch brain {
        case .claude: "Claude Code를 설치한 뒤 터미널에서 claude를 한 번 실행해 로그인해 주세요. 그다음 다시 확인을 눌러요."
        case .codex: "Codex를 설치한 뒤 터미널에서 codex login으로 ChatGPT에 로그인해 주세요. 그다음 다시 확인을 눌러요."
        case .antigravity: "Antigravity를 설치한 뒤 터미널에서 agy를 한 번 실행해 로그인해 주세요. 그다음 다시 확인을 눌러요."
        case .api: "API 키가 아직 없어요. 아래 API 브레인에서 서비스를 고르고 키를 넣어 주세요."
        }
    }

    /// What 로그인 says once pressed: the terminal opened, or it couldn't because the AI's tool isn't installed.
    static func loginToast(opened: Bool, brain: ArisBrain) -> String {
        opened ? "터미널을 열었어요. 거기서 로그인해 주세요" : "\(ArisParticle.attach(brain.shortTitle, .iGa)) 이 Mac에 설치돼 있지 않아요. 먼저 설치해 주세요"
    }

    private static func control(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        let standingRows: [ArisSettingItem]
        if let standing = s.standing, !standing.isEmpty {
            standingRows = standing.map {
                ArisSettingItem(id: "control.standing.\($0.id)", icon: .symbol($0.symbol), title: $0.title, desc: $0.desc,
                               control: button("취소", .revokeStanding($0.id)), indexed: false)
            }
        } else {
            let text = !s.standingLoaded ? "불러오는 중" : s.standing == nil ? "Aris 에이전트가 답하지 않아요" : "아직 없어요"
            standingRows = [ArisSettingItem(id: "control.standing.none", icon: .none, title: text,
                                           desc: s.standing?.isEmpty == true ? "세 번 연달아 허락한 일이 생기면 여기에 나와요" : nil,
                                           control: s.standingLoaded ? .empty : .loading, indexed: false)]
        }
        return [
            ArisSettingSection(id: "control.permissions", heading: "권한", note: s.permissions.allSatisfy(\.granted) ? nil : "허용하기를 누르면 시스템 설정이 열리고, Aris 아이콘을 목록으로 끌어다 놓으면 돼요.",
                               grouped: true, rows: permissionRows(s.permissions)),
            ArisSettingSection(id: "control.seeing", heading: "화면 보기", note: "다른 질문에는 화면을 찍지 않고, 암호 앱과 Aris 창은 언제나 빼요. 동그라미는 화면 기록 권한이 있어야 돼요.", rows: [
                ArisSettingItem(id: "control.sees", icon: .symbol("sparkles"), title: "질문할 때 화면 같이 보기",
                               desc: "화면을 가리켜 물을 때만 화면을 찍어 보내요.",
                               control: .toggle(.seesScreen, s.seesScreen)),
                ArisSettingItem(id: "control.circle", icon: .symbol("lasso"), title: "동그라미로 가리키기",
                               desc: "\(s.circleHint).", control: .toggle(.circle, s.circle)),
            ], feature: .control),
            ArisSettingSection(id: "control.standing", heading: "묻지 않고 하는 일",
                               note: "같은 일을 세 번 연달아 허락하면 앞으로 그냥 할지 물어보고, 여기서 취소하면 다시 물어봐요. 앱 조작, 명령 실행, 파일 수정, 메일 보내기, 영구 삭제는 늘 물어보고, 돈이 드는 일은 하지 않아요.",
                               grouped: true, rows: standingRows),
        ]
    }

    /// 권한's rows (item 11): what still needs allowing comes first with its button; what is allowed is quiet, a check
    /// and 허용됨 with nothing to press. The three folders macOS guards are one row.
    static func permissionRows(_ permissions: [ArisSettingsSnapshot.Permission]) -> [ArisSettingItem] {
        let folders = permissions.filter { $0.id.hasPrefix("folder.") }
        var rows = permissions.filter { !$0.id.hasPrefix("folder.") }
        if !folders.isEmpty {
            rows.append(.init(id: "folders", title: "파일 폴더 \(folders.count)곳", desc: "데스크탑, 문서, 다운로드의 파일을 옮기고 되돌려요.", granted: folders.allSatisfy(\.granted)))
        }
        return (rows.filter { !$0.granted } + rows.filter(\.granted)).map { p in
            p.granted
                ? ArisSettingItem(id: "control.\(p.id)", icon: .symbol("checkmark"), title: p.title, desc: p.desc, control: .said("허용됨"))
                : ArisSettingItem(id: "control.\(p.id)", icon: .status(false), title: p.title, desc: p.desc, control: button("허용하기", .permission(p.id), .primary))
        }
    }

    // MARK: 화면

    private static func notch(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        var top = [
            ArisSettingItem(id: "notch.hover", icon: .symbol("cursorarrow.motionlines"), title: "포인터를 올리면 열기", desc: "노치 위에 잠깐 머물면 열려요.", control: .toggle(.hover, s.hover)),
            ArisSettingItem(id: "notch.haptics", icon: .symbol("hand.tap"), title: "진동", desc: "노치가 열리거나 사이드 노치가 나올 때 트랙패드가 톡 울려요.", control: .toggle(.haptics, s.haptics)),
            ArisSettingItem(id: "notch.gestures", icon: .symbol("hand.draw"), title: "제스처",
                           desc: s.hover ? "노치 위에서 두 손가락으로 쓸어 열고 닫아요." : "포인터로 열지 않을 땐 늘 켜져 있어요.",
                           control: .toggle(.gestures, s.gestures, enabled: s.hover)),
            ArisSettingItem(id: "notch.height", icon: .symbol("arrow.up.and.down"), title: "노치 크기", desc: "노치가 있는 화면에서 닫힌 노치 높이예요.",
                           control: .choice(.heightMode, options([("real", "실제 노치"), ("menubar", "메뉴 막대"), ("custom", "직접")]), selected: s.heightMode)),
        ]
        if s.heightMode == "custom" {
            top.append(ArisSettingItem(id: "notch.customHeight", icon: .symbol("slider.horizontal.3"), title: "직접 정한 높이", desc: "닫힌 노치의 높이예요.",
                                      control: .slider(.notchHeight, value: s.notchHeight, min: 15, max: 45, unit: "pt")))
        }
        // The two rows that were 모양's and are about the open notch.
        top += [
            ArisSettingItem(id: "look.settingsIcon", icon: .symbol("gearshape"), title: "노치에 설정 아이콘", desc: "열린 노치 위에 설정으로 가는 작은 아이콘을 보여요.", control: .toggle(.settingsIcon, s.settingsIcon)),
            ArisSettingItem(id: "look.alwaysTabs", icon: .symbol("square.grid.2x2"), title: "탭 항상 보이기", desc: "열린 노치의 탭 줄을 늘 보여요.", control: .toggle(.alwaysTabs, s.alwaysTabs)),
        ]
        top += ArisNotchLookSetting.rows(theme: s.notchTheme, backing: s.textBacking, restStar: s.restStar)
        return [
            ArisSettingSection(id: "notch.top", heading: "위 노치", rows: top),
            ArisSettingSection(id: "notch.side", heading: "사이드 노치", rows: [
                ArisSettingItem(id: "notch.unhide", icon: .symbol("aris-side-notch"), title: "숨긴 사이드 노치",
                               desc: "숨긴 사이드 노치를 다시 보이게 해요.", control: button("다시 보이기", .unhideSides, enabled: s.hiddenSides)),
                ArisSettingItem(id: "notch.clipKey", icon: .symbol("clipboard-list"), title: "왼쪽 사이드 노치 열기",
                               desc: s.hiddenSideTabs.contains(ArisSideTab.clipboard.rawValue) ? "클립보드 탭이 꺼져 있어서 지금은 열리지 않아요." : "포인터 없이 키로 클립보드 탭을 열어요.",
                               control: .shortcut(name: "openClipboard", caps: s.clipCaps)),
                ArisSettingItem(id: "notch.rightKey", icon: .symbol("aris-side-notch"), title: "오른쪽 사이드 노치 열기",
                               desc: ArisSideTabWork.takesRightKey(hidden: s.hiddenSideTabs) ? "포인터 없이 키로 할 일과 캘린더를 열고 닫아요."
                                   : "오른쪽 탭이 모두 꺼져 있어서 지금은 열리지 않아요.",
                               control: .shortcut(name: "openRightPanel", caps: s.rightPanelCaps)),
            ]),
            ArisSettingSection(id: "notch.sideLeft", heading: "왼쪽 사이드 노치에 보일 탭", rows: sideTabRows(.left, s)),
            ArisSettingSection(id: "notch.sideRight", heading: "오른쪽 사이드 노치에 보일 탭",
                               note: "한쪽 탭을 모두 끄면 그쪽 사이드 노치도 나오지 않아요. 클립보드 탭을 끄면 복사한 것을 더 기록하지 않아요.", rows: sideTabRows(.right, s)),
        ] + ArisMoreRows.notch(s.more, gestures: s.gestures)
    }

    /// A switch for each of a side's tabs.
    private static func sideTabRows(_ edge: ArisSideEdge, _ s: ArisSettingsSnapshot) -> [ArisSettingItem] {
        ArisSideTabChoice.all(edge).map { tab in
            ArisSettingItem(id: "notch.tab.\(tab.rawValue)", icon: .symbol(tab.symbol), title: tab.title, desc: sideTabDesc(tab),
                           control: .toggle(.sideTab(tab.rawValue), !s.hiddenSideTabs.contains(tab.rawValue)))
        }
    }

    private static func sideTabDesc(_ tab: ArisSideTab) -> String {
        switch tab {
        case .history: "지금 돌아가는 AI 세션과 지난 대화예요."
        case .activity: "Aris와 팀원이 오늘 한 일이에요."
        case .clipboard: "복사한 것들이에요."
        case .usage: "AI 요금제 한도와 쓴 비용이에요."
        case .todo: "할 일과 마감이에요."
        case .calendar: "날짜별 일정이에요."
        }
    }

    /// What the 모양 page held that is about the window and the characters; it is a section of 일반 now (pick 6-B).
    private static func look(_ s: ArisSettingsSnapshot) -> ArisSettingSection {
        ArisSettingSection(id: "look.all", heading: "모양", note: "macOS의 ‘동작 줄이기’를 켜도 캐릭터는 가만히 있어요.", rows: [
            ArisSettingItem(id: "look.theme", icon: .symbol("circle.lefthalf.filled"), title: "설정 창 모양", desc: "설정 창만 바뀌고, 노치는 늘 어두워요.",
                           control: .choice(.theme, options([("light", "라이트"), ("dark", "다크"), ("auto", "자동")]), selected: s.theme)),
            ArisSettingItem(id: "look.accent", icon: .symbol("paintpalette"), title: "강조 색", desc: "선택 표시와 초점 테두리에 쓰는 색이에요.",
                           control: .choice(.accentCustom, options([("system", "시스템"), ("custom", "직접")]), selected: s.customAccent ? "custom" : "system"),
                           extra: s.customAccent ? .swatches(accents, selected: s.accentHex) : .none),
            ArisSettingItem(id: "look.reduceMotion", icon: .symbol("figure.walk.motion"), title: "모션 줄이기",
                           desc: "캐릭터가 돌거나 뛰지 않고 가만히 있어요.", control: .toggle(.reduceMotion, s.reduceMotion)),
        ])
    }

    private static func features(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [
            ArisMoreRows.music(s.more),
            ArisMoreRows.shelf(s.more),
            ArisSettingSection(id: "features.more", rows: [
                ArisSettingItem(id: "features.calendar", icon: .symbol("calendar"), title: "캘린더 설정", desc: "보여 줄 캘린더와 일정 표시 방식을 골라요.",
                               control: .link(.go(.todo, anchor: "calendar.intro"), value: nil), indexed: false),
            ]),
        ]
    }

    // MARK: 일반

    private static func general(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        var screen = [
            ArisSettingItem(id: "general.display", icon: .symbol("display"), title: "표시 방식", desc: "노치를 어느 화면에 띄울지 정해요.", control: .menu(.displayMode, s.displayModes, selected: s.displayMode)),
        ]
        if s.displayMode == "preferred" || s.displayMode == "fallback" {
            screen.append(ArisSettingItem(id: "general.screen", icon: .symbol("display.2"), title: "선호하는 화면", desc: "노치를 먼저 띄울 화면이에요.", control: .menu(.screen, s.screens, selected: s.screen)))
        }
        return [
            ArisSettingSection(id: "general.all", rows: [
                ArisSettingItem(id: "general.login", icon: .symbol("log-in"), title: "로그인할 때 열기", desc: "Mac을 켜면 Aris가 자동으로 켜져요.", control: .toggle(.login, s.login)),
                ArisSettingItem(id: "general.name", icon: .symbol("user-round"), title: "부르는 이름", desc: "가끔 이 이름으로 불러요.",
                               control: .field(.userName, text: s.userName, placeholder: "이름",
                                               ArisSettingButton(title: "지우기", action: .clearName, enabled: !s.userName.trimmingCharacters(in: .whitespaces).isEmpty))),
                ArisSettingItem(id: "general.language", icon: .symbol("globe"), title: "앱 언어", desc: "설정과 메뉴 글자의 언어예요.", control: .menu(.appLanguage, s.appLanguages, selected: s.appLanguage)),
            ]),
            look(s),
            ArisSettingSection(id: "general.screens", heading: "화면", rows: screen),
            ArisSettingSection(id: "general.app", heading: "앱", rows: [
                ArisSettingItem(id: "general.onboarding", icon: .symbol("hand.wave"), title: "처음 안내 다시 보기", desc: ArisFix.Pane.osMajor >= 27 ? "마이크, 기기 제어 및 데이터 접근 같은 권한을 하나씩 다시 안내해요." : "마이크, 손쉬운 사용 같은 권한을 하나씩 다시 안내해요.", control: button("열기", .onboarding)),
                ArisSettingItem(id: "general.restart", icon: .symbol("arrow.triangle.2.circlepath"), title: "Aris 다시 시작", desc: "앱을 껐다가 다시 켜요.", control: button("다시 시작", .restart)),
                ArisSettingItem(id: "general.quit", icon: .symbol("xmark.circle"), title: "Aris 종료", desc: "앱을 완전히 꺼요.", control: button("종료", .quit)),
            ]),
        ]
    }

    private static func keys(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [ArisSettingSection(id: "keys.all", rows: [
            ArisSettingItem(id: "keys.talk", icon: .symbol("aris-star"), title: "Aris에게 말하기", desc: "누르고 바로 말해요.", control: .shortcut(name: "talkToAris", caps: s.talkCaps)),
            ArisSettingItem(id: "keys.dictation", icon: .symbol("mic"), title: "받아쓰기", desc: "누르고 있는 동안 받아 적어요.", control: .shortcut(name: ArisDictationKey.Choice.recorderName, caps: s.dictationCaps)),
            ArisSettingItem(id: "keys.pasteLast", icon: .symbol("clipboard-paste"), title: "마지막 받아쓰기 다시 넣기", desc: "방금 받아 적은 말을 한 번 더 넣어요.",
                           control: .shortcut(name: "pasteLastDictation", caps: s.pasteLastCaps)),
            ArisSettingItem(id: "keys.answer", icon: .symbol("bubble.left.and.text.bubble.right"), title: "Claude에게 답하기", desc: "승인 · 질문 카드가 떠 있을 때 말로 답해요.",
                           control: .shortcut(name: "answerClaude", caps: s.answerCaps)),
            ArisSettingItem(id: "keys.clipboard", icon: .symbol("clipboard-list"), title: "클립보드 기록", desc: "왼쪽 사이드 노치의 클립보드 탭을 열어요.",
                           control: .shortcut(name: "openClipboard", caps: s.clipCaps)),
            ArisSettingItem(id: "keys.notch", icon: .symbol("aris-notch"), title: "노치 열고 닫기", desc: "노치를 키로 열고 닫아요.",
                           control: .shortcut(name: "toggleNotchOpen", caps: s.notchCaps)),
            ArisSettingItem(id: "keys.peek", icon: .symbol("music.note"), title: "음악 미리 보기", desc: "재생 중인 곡을 노치 아래에 잠깐 띄워요.",
                           control: .shortcut(name: "toggleSneakPeek", caps: s.peekCaps)),
        ])]
    }

    private static func about(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [
            ArisSettingSection(id: "about.app", rows: [
                ArisSettingItem(id: "about.version", icon: .none, title: "Aris", desc: s.versionLine, control: .custom("about")),
            ]),
            ArisSettingSection(id: "about.help", heading: "문제 해결", rows: [
                ArisSettingItem(id: "about.folder", icon: .symbol("folder"), title: "기록 폴더 열기", desc: "대화 기록과 로그가 있는 폴더예요.", control: button("Finder에서 보기", .openFolder)),
            ]),
            ArisSettingSection(id: "about.data", heading: "데이터", rows: [
                ArisSettingItem(id: "about.export", icon: .symbol("square.and.arrow.up"), title: "데이터 내보내기", desc: "대화 기록, 기억, 팀원을 파일로 받아요.", control: .link(.export, value: nil)),
                ArisSettingItem(id: "about.diagnostics", icon: .symbol("stethoscope"), title: "진단 내보내기", desc: "문제가 생겼을 때 보낼 기록 파일이에요.", control: .link(.diagnostics, value: nil)),
                ArisSettingItem(id: "about.wipe", icon: .symbol("trash"), title: "데이터 지우기", desc: "골라서 지우고, 되돌릴 수 없어요.", control: button("지우기…", .wipe, .danger), danger: true),
                ArisSettingItem(id: "about.uninstall", icon: .symbol("shippingbox"), title: "Aris 제거", desc: "앱과 Aris가 만든 것을 모두 지워요.", control: button("제거…", .uninstall, .danger), danger: true),
            ]),
        ]
    }
}
