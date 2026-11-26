//
//  ArisSettingsBuilder.swift
//  Aris
//
//  Each page's parts and their sections, from a snapshot (settings-ia option A: four pages, ArisSettingsParts). A
//  part's title is drawn above it, so its first section carries no title of its own. AI · 모델, 듣기 and 목소리 are drawn
//  by the AI views from their own state; their rows are listed here so the search finds them. 팀원 and 스킬 are rows
//  that open their sheets. Foundation only (tested).
//

import Foundation

enum ArisSettingsBuilder {
    /// The accent colours offered: the eight presets the window has always had, so a saved one still shows its ring.
    static let accents = ["#007AFF", "#AF52DE", "#FF2D55", "#FF453A", "#FF9500", "#FFCC00", "#66D22D", "#8E8E93"]

    /// Every row and section the pages draw for `s`, the parts, and the 팀원 sheet's own tags: what a search may land on now.
    static func searchable(_ s: ArisSettingsSnapshot) -> Set<String> {
        ArisSettingsPage.allCases.reduce(into: Set(ArisSettingsIndex.teamAnchors + ArisSettingsIndex.skillsAnchors + ArisSettingsIndex.loadedLater + ArisSettingsParts.all.map(\.id))) {
            $0.formUnion(ArisSettingsLayout.tags(sections($1, s)))
        }
    }

    /// A page's sections, every part's one after the other.
    static func sections(_ page: ArisSettingsPage, _ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        parts(page, s).flatMap(\.sections)
    }

    /// A page's parts, each with its sections.
    static func parts(_ page: ArisSettingsPage, _ s: ArisSettingsSnapshot) -> [ArisPartSections] {
        page.parts.map { part in ArisPartSections(part: part, sections: untitledFirst(sections(part: part.id, s))) }
    }

    /// The part's title stands above its sections: the first one's own title goes (a fold keeps its line).
    private static func untitledFirst(_ sections: [ArisSettingSection]) -> [ArisSettingSection] {
        guard var first = sections.first, first.fold == nil else { return sections }
        first.heading = nil
        return [first] + sections.dropFirst()
    }

    static func sections(part: String, _ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        switch part {
        case "talk.ai": services(s)
        case "talk.call": call(s)
        case "talk.hear": hearing(s)
        case "talk.speak": speaking(s)
        case "talk.chat": chat(s)
        case "talk.quiet": quiet(s)
        case "able.control": control(s)
        case "able.dictation": dictation(s)
        case "able.todo": todo(s)
        case "able.calendar": calendar(s)
        case "able.memory": withSavedStepsFeature(ArisMemorySettingsRows.sections(s)) + [ArisDropLearnedSetting.section(s.dropHabits)]
        case "able.team": team(s)
        case "able.skills": skills(s)
        case "able.connect": connect(s)
        case "look.notch": notch(s)
        case "look.side": side(s)
        case "look.music": [music(s)]
        case "look.shelf": [ArisMoreRows.shelf(s.more)]
        case "look.window": [look(s)]
        case "app.permissions": permissions(s)
        case "app.keys": keys(s)
        case "app.general": general(s)
        case "app.update": about(s)
        case "app.data": data(s)
        default: []
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

    // MARK: Aris와 말하기

    /// 부르기: the wake word (and its name and status, once jv-wake's rows are in: ArisSettingsSlots), the voice it
    /// learns, then 호출어 녹음 folded.
    private static func call(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        var record = ArisWakeRecordRows.section(s.wakeRecord, busy: s.busy)
        record.heading = nil
        record.fold = ArisSettingFold(title: "호출어 녹음", desc: "내 호출 녹음하기 · 하루 소리 모으기 · 녹음 다 지우기", symbol: "mic")
        return [
            ArisSettingSection(id: "aris.call", heading: "부르기", note: callNote(s), rows: [
                ArisSettingItem(id: "aris.wake", icon: .symbol("waveform"), title: "“아리스”라고 부르기",
                               desc: s.wakeWord && !s.wakeStatus.isEmpty ? s.wakeStatus : "이름을 부르면 들어요.",
                               control: .toggle(.wakeWord, s.wakeWord)),
            ] + ArisSettingsSlots.wakeRows(s) + ArisVoiceIDRows.rows(s.voiceID, busy: s.busy, wakeTrained: s.hasVoiceModel)),
            record,
        ]
    }

    /// 대화: how long a conversation lasts and listens on, and the echo-cancelled engine (experimental, off by
    /// default) that brings back interrupting Aris while it speaks through the speakers.
    private static func chat(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        var rows = [
            ArisSettingItem(id: "aris.minutes", icon: .symbol("arrow.clockwise"), title: "대화 이어가기",
                           desc: "이 시간 안에 물으면 같은 대화로 이어져요.",
                           control: .choice(.minutes, options([("2", "2분"), ("5", "5분"), ("15", "15분")]), selected: String(s.minutes))),
            ArisSettingItem(id: "aris.silence", icon: .symbol("hand"), title: "계속 듣기",
                           desc: "답한 뒤에도 바로 다시 들어요.",
                           control: .choice(.silence, options([("0", "끄기"), ("15", "15초"), ("30", "30초"), ("60", "1분")]), selected: String(s.silence))),
            ArisSettingItem(id: "aris.duplex", icon: .symbol("audio-lines"), title: "에코 제거 오디오 (새 엔진)",
                           desc: "실험 중인 엔진으로, 스피커로 나오는 Aris 목소리를 빼고 들어요.",
                           control: .toggle(.duplexAudio, s.duplexAudio)),
        ]
        // Only with the echo canceller: without it Aris's own voice through the speakers stopped it and came back as a
        // turn (2026-11-16, ArisBargeIn.echoCancellerOn). Headphones and "아리스" stop it either way.
        if s.duplexAudio {
            rows.append(ArisSettingItem(id: "aris.bargeIn", icon: .symbol("speaker.wave.2"), title: "스피커로 들을 때도 끼어들기",
                                       desc: "Aris가 말하는 동안 말을 걸면 멈추고 들어요.",
                                       control: .toggle(.bargeInSpeakers, s.bargeInSpeakers)))
        }
        return [ArisSettingSection(id: "aris.talk", heading: "대화 모드", note: "“됐어”, “그만”, Esc로 끝나고, 말이 없으면 고른 시간 뒤에 끝나요. 다른 앱 소리를 확인하는 동안 메뉴 막대에 보라색 표시가 뜨지만, 크기만 재고 녹음하지 않아요.", rows: rows)]
    }

    /// 조용히 · 알림.
    private static func quiet(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [ArisSettingSection(id: "aris.alerts", heading: "알림", rows: [
            ArisSettingItem(id: "aris.sounds", icon: .symbol("volume-2"), title: "알림 효과음",
                           desc: "Claude가 일을 마치거나 승인이 필요할 때 짧은 소리를 내요.", control: .toggle(.sounds, s.sounds)),
            ArisDayEndSetting.row(s.dayEndOffer),
            ArisRecapSetting.row(s.recap),
            ArisQuietSettingsRows.mute(s.muted),
        ] + ArisQuietSettingsRows.hourRows(s.quietHours), feature: .notify)]
    }

    /// 부르기's small line: where the name is listened for, while no voice is learned that any voice wakes it, and while
    /// 하루 소리 모으기 is on what it keeps (ArisWakeHonesty).
    private static func callNote(_ s: ArisSettingsSnapshot) -> String {
        ArisWakeHonesty.note(trained: s.hasVoiceModel, collecting: s.wakeRecord.collecting)
    }

    /// Claude Code's usage in the closed notch's ear (mockup claude-usage.html): what the ring shows on a plan
    /// (ClaudeRingMode's raw values; anything else reads as 5시간, the ring as it always was). It is a notch display, so
    /// it sits in 모양 › 노치.
    private static func claudeRing(_ s: ArisSettingsSnapshot) -> ArisSettingItem {
        let lines = ["fiveHour": "닫힌 노치 귀의 고리가 5시간 한도를 보여 줘요", "sevenDay": "닫힌 노치 귀의 고리가 주간 한도를 보여 줘요",
                     "auto": "5시간과 주간 중 더 많이 쓴 쪽을 보여 줘요"]
        let mode = lines[s.claudeRing] == nil ? "fiveHour" : s.claudeRing
        return ArisSettingItem(id: "aris.claudeRing", icon: .symbol("gauge.with.needle"), title: "귀에 보일 사용량", desc: lines[mode],
                               control: .choice(.claudeRing, options([("fiveHour", "5시간"), ("sevenDay", "주간"), ("auto", "자동")]), selected: mode))
    }

    /// The daily budget Claude Code fills against on an API key (the row draws itself: ClaudeBudgetRow), in the
    /// 연결된 서비스 fold beside Claude Code's login.
    private static let claudeBudget = ArisSettingItem(id: "aris.claudeBudget", icon: .symbol("dollarsign"), title: "API 키로 쓸 때 하루 예산", control: .custom("claudeBudget"))

    /// Claude Code 연결: Aris's hooks in Claude Code's settings, put there or taken out from here.
    private static func claudeConnect(_ s: ArisSettingsSnapshot) -> ArisSettingItem {
        ArisSettingItem(id: "aris.claudeConnect", icon: .symbol("link"), title: "Claude Code 연결",
                        desc: s.claudeConnected ? "세션과 승인 요청이 노치에 와요." : "세션과 승인 요청을 노치로 받아요.",
                        control: .status(ok: s.claudeConnected, s.claudeConnected ? ArisSettingButton(title: "연결 끊기", action: .claudeDisconnect)
                                                                           : ArisSettingButton(title: "연결", action: .claudeConnect)))
    }

    /// What the closed language select says (the measured one: "English + 2 more"): the first language, then how many
    /// more ("한국어 외 1개"; the settings catalog has the English).
    static func languagesSummary(_ names: [String]) -> String {
        guard let first = names.first else { return "언어 추가" }
        return names.count == 1 ? first : "\(first) 외 \(names.count - 1)개"
    }

    /// 듣기: the hearing card (drawn by the AI view from its own state: `ai.hear`), then 쓰는 언어 in the same card. One
    /// key chooses Scribe (`arisHearEngine`); the second switch that wrote `arisCloudListening` is gone (D6).
    private static func hearing(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [ArisSettingSection(id: "talk.hear.rows", heading: "듣기", note: "여기 없는 언어로 말하면 소리 나는 대로 적혀요.", grouped: true, rows: [
            ArisSettingItem(id: "ai.hear", icon: .symbol("mic"), title: "듣기", control: .custom("ai.hear")),
            microphone(s),
            ArisSettingItem(id: "voice.languages", icon: .symbol("globe"), title: "쓰는 언어",
                           desc: "말할 때 이 언어들 중에서 알아서 찾아요.",
                           control: .buttons([ArisSettingButton(title: languagesSummary(s.languages.map(\.title)), action: .addLanguage, kind: .select)])),
            ArisSettingItem(id: "hear.repair", icon: .symbol("wand.and.stars"), title: "들은 말 다듬기",
                           desc: "잘못 들은 단어, 띄어쓰기, 한글로 적힌 영어 단어를 빠른 AI가 바로잡아요. 1초쯤 안에 안 되면 들은 그대로 써요. 자동일 때는 처음부터 켜져 있어요.",
                           control: .toggle(.hearRepair, s.hearRepair)),
            ArisSettingItem(id: "hear.words", icon: .symbol("book"), title: "Aris가 알아야 할 단어",
                           desc: "이름, 앱, 용어를 한 줄에 하나씩 적어요. ‘들린 말 -> 맞는 말’처럼 적으면 그렇게 고쳐 들어요 · \(s.words)개",
                           control: button("편집", .editWords)),
        ])]
    }

    /// 마이크 (ArisMicSetting): this Mac's own (the default), the system's input, or one input device by its name; a
    /// chosen device that is gone stays in the menu by its kept name, and the line under it says what Aris hears with.
    static func microphone(_ s: ArisSettingsSnapshot) -> ArisSettingItem {
        let setting = ArisMicSetting(stored: s.microphone)
        let devices = s.microphones ?? []
        let listed = devices.filter { $0.hasInput && $0.transport != .builtIn && $0.uid != nil }
        var choices = options([(ArisMicSetting.thisMac.stored, "이 Mac (내장)"), (ArisMicSetting.system.stored, "시스템 설정과 같게")])
        choices += listed.map { ArisSettingOption(id: ArisMicSetting.device(uid: $0.uid ?? "").stored, title: $0.name ?? $0.uid ?? "") }
        if case .device = setting, !choices.contains(where: { $0.id == setting.stored }) {
            choices.append(ArisSettingOption(id: setting.stored, title: s.microphoneName ?? "고른 마이크"))
        }
        return ArisSettingItem(id: "hear.mic", icon: .symbol("waveform"), title: "마이크", desc: microphoneLine(setting, devices: s.microphones),
                               control: .menu(.microphone, choices, selected: setting.stored))
    }

    private static func microphoneLine(_ setting: ArisMicSetting, devices: [ArisAudioDevice]?) -> String {
        let pick = devices.map(setting.pick)
        switch setting {
        case .system: return "시스템 설정의 입력 기기를 따라가요. 다른 마이크가 있으면 헤드폰 마이크는 쓰지 않아요."
        case .thisMac:
            return pick?.fallback == .noBuiltIn ? "이 Mac에 내장 마이크가 없어 시스템 설정의 입력 기기로 들어요."
                : "에어팟을 연결해도 이 Mac의 마이크로 들어서 음악 음질이 그대로예요."
        case .device:
            guard pick?.fallback == .chosenGone else { return "고른 마이크로 들어요." }
            return pick?.device == nil ? "고른 마이크가 연결되어 있지 않아 시스템 설정의 입력 기기로 들어요."
                : "고른 마이크가 연결되어 있지 않아 이 Mac의 마이크로 들어요."
        }
    }

    /// 목소리: the speaking card (`ai.speak`: the engine, its model and the one voice picker, D5), then 말하기 속도.
    private static func speaking(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        let speedID = s.speed < 0.95 ? "0.9" : s.speed > 1.05 ? "1.15" : "1"
        return [ArisSettingSection(id: "talk.speak.rows", heading: "목소리", note: "들어 보기만 해서는 요금이 들지 않아요.", grouped: true, rows: [
            ArisSettingItem(id: "ai.speak", icon: .symbol("speaker.wave.2"), title: "말하기", control: .custom("ai.speak")),
            ArisSettingItem(id: "voice.speed", icon: .symbol("gauge.with.needle"), title: "말하기 속도", desc: "답을 읽는 속도예요.",
                           control: .choice(.speed, options([("0.9", "느리게"), ("1", "보통"), ("1.15", "빠르게")]), selected: speedID,
                                            lead: ArisSettingButton(title: "들어 보기", action: .listen))),
        ])]
    }

    /// 듣기 엔진 (#38): which of Apple's speech engines hears on this Mac. Nothing to change, so it is a status line
    /// under the 듣기 card, not a row among the settings. None in a still picture.
    static func engineLine(_ s: ArisSettingsSnapshot) -> String? {
        s.listenEngine.isEmpty ? nil : ArisListenEngineWords.rowTitle + " · " + s.listenEngine
    }

    private static func dictation(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        // 받아쓰기 쓰기 off: the key, ⌃⌘V, the pill and polish are dimmed (as 쉴 때도 보이기 is with the pill off).
        let on = s.dictationOn
        return [
            ArisSettingSection(id: "dictation.use", rows: [
                ArisSettingItem(id: "dictation.on", icon: .symbol("power"), title: "받아쓰기 쓰기",
                               desc: "끄면 단축키와 알약이 꺼지고, 다른 받아쓰기 앱과 겹치지 않아요.",
                               control: .toggle(.dictationOn, on)),
            ]),
            ArisSettingSection(id: "dictation.screen", heading: "화면", note: "켜 두면 받아쓰는 동안 노치는 조용하고, 화면 아래 알약에 듣는 소리와 진행이 보여요. 알약을 눌러도 받아쓰기를 시작해요.", rows: [
                ArisSettingItem(id: "dictation.pill", icon: .symbol("audio-lines"), title: "받아쓰기 알약 보이기",
                               desc: "끄면 받아쓰기가 예전처럼 노치에 보여요.",
                               control: .toggle(.dictationPill, s.dictationPill, enabled: on)),
                ArisSettingItem(id: "dictation.pillIdle", icon: .symbol("moon"), title: "쉴 때도 보이기",
                               desc: "끄면 받아 쓸 때만 나타나요.",
                               control: .toggle(.dictationPillIdle, s.dictationPillIdle, enabled: on && s.dictationPill)),
            ]),
            ArisSettingSection(id: "dictation.polish", heading: "다듬기", note: "그때는 받아 적은 말과 커서 주변 글이 Anthropic으로 가요. 꺼 두면 말이 Mac 밖으로 나가지 않아요.", rows: [
                ArisSettingItem(id: "dictation.brainPolish", icon: .symbol("text.badge.checkmark"), title: "Mac에서 못 다듬을 때 AI로 다듬기",
                               desc: "이 Mac이 못 다듬을 때만 Claude가 다듬어요.",
                               control: .toggle(.dictationBrainPolish, s.brainPolish, enabled: on)),
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
        // 허용하기, as every other permission's button in 앱 › 권한 (fourth VM run: Calendar's alone said 허용).
        case .undecided: (ask, button("허용하기", request, .primary))
        case .blocked: (ask, button("시스템 설정 열기", request, .primary))
        }
    }

    /// 미리 알림 접근: in 앱 › 권한 with the other permissions; `id` another for its echo in 할 일 while it is missing.
    static func remindersAccessRow(_ s: ArisSettingsSnapshot, id: String = "todo.access") -> ArisSettingItem {
        let state = access(s.reminders, granted: "허용됐어요.", ask: "허용하면 할 일을 보고 넣을 수 있어요.", request: .remindersAccess)
        return ArisSettingItem(id: id, icon: .symbol("checklist"), title: "미리 알림 접근", desc: state.desc, control: state.control, indexed: id == "todo.access")
    }

    /// 캘린더 접근, as 미리 알림 접근.
    static func calendarAccessRow(_ s: ArisSettingsSnapshot, id: String = "calendar.access") -> ArisSettingItem {
        let state = access(s.calendarAccess, granted: "Apple 캘린더가 바뀌면 저절로 따라가요.", ask: "일정을 읽으려면 캘린더 전체 접근이 필요해요.",
                           refresh: ArisSettingButton(title: "새로 고침", action: .calendarRefresh), request: .calendarAccess)
        return ArisSettingItem(id: id, icon: .symbol("calendar.badge.checkmark"), title: "캘린더 접근", desc: state.desc, control: state.control, indexed: id == "calendar.access")
    }

    /// 할 일: the lists once Reminders may be read; until then the permission's row, echoed from 앱 › 권한.
    private static func todo(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        let intro = ArisSettingSection(id: "todo.intro", heading: "할 일", note: "여기서 고른 목록이 할 일 탭에 나오고, 새로 넣은 건 미리 알림 앱에도 생겨요.",
                                       rows: s.reminders == .granted ? [] : [remindersAccessRow(s, id: "todo.accessHere")])
        var sections = [intro]
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

    /// 캘린더: Google and the calendars once Calendar may be read; until then the permission's row, echoed.
    private static func calendar(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        var intro = s.calendarAccess == .granted ? [] : [calendarAccessRow(s, id: "calendar.accessHere")]
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

    /// AI · 모델 (option A's first part, the window opens on it). 답하는 AI, its login and 짧은 명령 are drawn by the AI
    /// view from its own state (ArisAIServicesModel); the model per role is jv-models' view
    /// (ArisLiveSlots), 다른 AI로 넘기기 a plain switch row (ArisSettingsSlots.fallback). 연결된 서비스 is folded: the AIs' logins and usage, and Claude Code's daily budget.
    private static func services(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        let serviceRows = s.services.isEmpty
            ? [ArisSettingItem(id: "ai.service.loading", icon: .none, title: "서비스를 확인하는 중", control: .loading, indexed: false)]
            : s.services.map { ArisSettingItem(id: "ai.service.\($0.id)", icon: .logo($0.id), title: $0.title, desc: $0.detail, control: .chip($0.status, tone: $0.tone), indexed: false) }
        return [
            ArisSettingSection(id: "ai.think", heading: "생각", rows: [
                ArisSettingItem(id: "ai.brain", icon: .symbol("brain"), title: "답하는 AI", control: .custom("ai.think")),
                ArisSettingItem(id: "ai.jev", icon: .none, title: "짧은 명령 빨리 알아듣기", control: .custom("ai.jev")),
                // jv-models' view, drawn in its slot by the AI view (ArisLiveSlots.models): listed for the search.
                ArisSettingItem(id: "ai.models", icon: .none, title: "모델 고르기", control: .custom("ai.models")),
            ]),
            ArisSettingsSlots.fallback(s),
            ArisSettingSection(id: "ai.services", note: "로그인 정보는 각 앱의 것을 읽기만 하고 Aris가 따로 저장하지 않아요. 키와 토큰은 키체인에만 저장돼요.",
                               grouped: true, rows: serviceRows + [claudeBudget, claudeConnect(s)],
                               fold: ArisSettingFold(title: "연결된 서비스", desc: "Claude Code · Codex · Antigravity · 하루 예산", symbol: "powerplug")),
        ]
    }

    /// The external services (Composio and the user's MCP servers): drawn by ArisServicesSection's rows.
    private static let mcpRows = [
        ArisSettingItem(id: "ai.mcp.composio", icon: .symbol("square.stack.3d.up"), title: "Composio", control: .custom("mcp.composio")),
        ArisSettingItem(id: "ai.mcp.servers", icon: .symbol("server.rack"), title: "MCP 서버", control: .custom("mcp.servers"), indexed: false),
        ArisSettingItem(id: "ai.mcp.add", icon: .symbol("plus"), title: "MCP 서버 추가", control: .custom("mcp.add")),
    ]

    /// 할 수 있는 일 › 연결: the outside services every AI uses alike.
    private static func connect(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [ArisSettingSection(id: "able.connect.rows", heading: "연결", note: "어느 AI로 답하든 똑같이 써요. 읽기는 바로 하고, 보내거나 바꾸는 일은 매번 카드로 물어봐요.",
                            grouped: true, rows: mcpRows)]
    }

    /// 팀원: the team draws itself in a sheet (ArisTeamPage); here are the ways into it and the terminal its Claude
    /// Code teammates open in.
    private static func team(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [ArisSettingSection(id: "able.team.rows", heading: "팀원", rows: [
            ArisSettingItem(id: "team.add", icon: .symbol("person.2"), title: "팀원 추가", desc: "이름을 부르면 그 팀원이 일을 맡아요.",
                           control: button("추가", .openSheet("team", anchor: "team.add"))),
            ArisSettingItem(id: "team.detail", icon: .symbol("user-round"), title: "팀원 이름 · 언제 부를까요", desc: "이름, 역할, 두뇌, 쓸 수 있는 것, 기억",
                           control: .link(.openSheet("team", anchor: "team.detail"), value: s.teamCount > 0 ? "\(s.teamCount)명" : nil)),
            ArisSettingItem(id: "team.make", icon: .symbol("wand.and.stars"), title: "말로 팀원 만들기", desc: "문서 담당, 리서처, 일정 비서",
                           control: button("만들기", .openSheet("team", anchor: "team.make"))),
            ArisTerminalSetting.row(pinned: s.teammateTerminal, installed: s.terminals),
        ])]
    }

    /// 스킬: its switch here, the skills themselves in a sheet (ArisSkillsPage).
    private static func skills(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [ArisSettingSection(id: "able.skills.rows", heading: "스킬", rows: [
            ArisSettingItem(id: "skills.feature", icon: .symbol("wand.and.stars"), title: "스킬 기능", desc: "Aris에게 말로 가르치는 일하는 방법이에요.",
                           control: .trailing("skills.switch")),
            ArisSettingItem(id: "skills.add", icon: .symbol("sparkles"), title: "스킬 추가 · 말로 만들기", desc: "GitHub 링크를 붙여 넣거나 말로 설명해요.",
                           control: button("추가", .openSheet("skills", anchor: "skills.add"))),
            ArisSettingItem(id: "skills.list", icon: .symbol("list"), title: "내 스킬", desc: s.skillCount > 0 ? "\(s.skillCount)개" : "아직 없어요",
                           control: .link(.openSheet("skills", anchor: "skills.list"), value: "보기")),
        ], feature: .skills)]
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
            ArisSettingSection(id: "control.seeing", heading: "화면 보기", note: "다른 질문에는 화면을 찍지 않고, Aris 창은 언제나 빼요. 동그라미는 화면 기록 권한이 있어야 돼요.", rows: [
                ArisSettingItem(id: "control.sees", icon: .symbol("sparkles"), title: "질문할 때 화면 같이 보기",
                               desc: "화면을 가리켜 물을 때만 화면을 찍어 보내요.",
                               control: .toggle(.seesScreen, s.seesScreen)),
                ArisSettingItem(id: "control.circle", icon: .symbol("lasso"), title: "동그라미로 가리키기",
                               desc: "\(s.circleHint).", control: .toggle(.circle, s.circle)),
            ], feature: .control),
            ArisSettingSection(id: "control.engine", heading: "앱 다루기", rows: [
                ArisSettingItem(id: "ai.computerEngine", icon: .symbol("macwindow"), title: "다른 앱을 다루는 방식",
                               desc: "Aris는 앱을 뒤에서 다뤄서 지금 보던 창과 포인터가 그대로예요. 어느 AI로 답하든 돼요. Peekaboo는 따로 내려받고, GPT는 Codex가 있어야 하고 없으면 Aris로 해요.",
                               control: .menu(.computerEngine, s.computerEngines, selected: s.computerEngine)),
            ]),
        ] + ArisSettingsSlots.trust(s) + [
            // 실험 기능 (ArisLabsSetting): Core 2 and show it once, above the list that grows (묻지 않고 하는 일 stays last).
            ArisLabsSetting.section(core2: s.core2, teach: s.teach),
            ArisSettingSection(id: "control.standing", heading: "묻지 않고 하는 일",
                               note: "같은 일을 세 번 연달아 허락하면 앞으로 그냥 할지 물어보고, 여기서 취소하면 다시 물어봐요. 앱 조작, 명령 실행, 파일 수정, 메일 보내기, 영구 삭제는 늘 물어보고, 결제는 할 때마다 카드로 물어봐요.",
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

    /// 다른 앱 소리 확인 (#9) as a permission: allowed is said in words like the others, missing has its button. macOS
    /// answers nothing about it until it is used, so it is "allowed" only once a tap has really heard sound; before
    /// that it says so and keeps the button (it used to say 허용됨 on a Mac that had never allowed it: VM run, D6).
    static func systemAudioRow(_ s: ArisSettingsSnapshot) -> ArisSettingItem {
        let desc = "다른 앱에서 소리가 나면 듣기를 잠깐 멈춰요."
        if s.systemAudioProven && !s.systemAudioMissing {
            return ArisSettingItem(id: "aris.systemAudio", icon: .symbol("checkmark"), title: "시스템 오디오", desc: desc, control: .said("허용됨"))
        }
        return ArisSettingItem(id: "aris.systemAudio", icon: .status(false), title: "시스템 오디오",
                               desc: s.systemAudioMissing ? desc : "허용됐는지는 처음 쓸 때 알 수 있고, 다른 앱에서 소리가 나면 듣기를 잠깐 멈춰요.",
                               control: button("허용하기", .permission("systemAudio"), .primary))
    }

    /// 앱 › 권한: every permission in one list (the ones 컴퓨터 제어, 대화 and 할 일 · 캘린더 each held), then the guide
    /// that asks for them again.
    private static func permissions(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        // What 허용하기 does for the rows still missing: macOS's dialog, System Settings, or both (ArisPermissionsNote).
        [
            ArisSettingSection(id: "control.permissions", heading: "권한", note: ArisPermissionsNote.note(s),
                               grouped: true, rows: ArisSettingsSlots.permissions(s)),
            ArisSettingSection(id: "general.guide", rows: [
                ArisSettingItem(id: "general.onboarding", icon: .symbol("hand.wave"), title: "처음 안내 다시 보기", desc: ArisFix.Pane.osMajor >= 27 ? "마이크, 기기 제어 및 데이터 접근 같은 권한을 하나씩 다시 안내해요." : "마이크, 손쉬운 사용 같은 권한을 하나씩 다시 안내해요.", control: button("열기", .onboarding)),
            ]),
        ]
    }

    // MARK: 모양

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
        // 노치에 설정 아이콘 (#89): the notch draws the icon this switch promises, so the row is here (ArisSettingsSlots).
        top += ArisSettingsSlots.settingsIconRow(s) + [
            ArisSettingItem(id: "look.alwaysTabs", icon: .symbol("square.grid.2x2"), title: "탭 항상 보이기", desc: "열린 노치의 탭 줄을 늘 보여요.", control: .toggle(.alwaysTabs, s.alwaysTabs)),
            claudeRing(s),
        ] + ArisMoreRows.music(s.more).rows.filter { $0.id == fullScreenID }
        // 화면 기록에서 숨기기 is a privacy setting: it is in 앱 › 데이터 · 개인정보.
        let more = ArisMoreRows.notch(s.more, gestures: s.gestures).map { section in
            var out = section
            out.rows = section.rows.filter { $0.id != hideFromRecordingID }
            if section.id == "notch.window" { out.fold = section.fold.map { ArisSettingFold(title: $0.title, desc: "노치 없는 화면 · 모서리 · 잠금 화면", symbol: $0.symbol) } }
            if section.id == "notch.advanced" { out.heading = nil }
            return out
        }
        return [ArisSettingSection(id: "notch.top", heading: "위 노치", rows: top)] + more
    }

    /// 전체 화면일 때 hides the whole notch, not the music: it is in 모양 › 노치 (#120).
    private static let fullScreenID = "features.fullScreen"
    private static let hideFromRecordingID = "notch.hideFromRecording"

    /// 음악 without the full-screen rule.
    private static func music(_ s: ArisSettingsSnapshot) -> ArisSettingSection {
        var section = ArisMoreRows.music(s.more)
        section.rows = section.rows.filter { $0.id != fullScreenID }
        return section
    }

    /// 사이드 노치: the hidden ones back, and which tabs each side shows. The two keys are in 앱 › 단축키.
    private static func side(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [
            ArisSettingSection(id: "notch.side", heading: "사이드 노치", rows: [
                ArisSettingItem(id: "notch.unhide", icon: .symbol("aris-side-notch"), title: "숨긴 사이드 노치",
                               desc: "숨긴 사이드 노치를 다시 보이게 해요.", control: button("다시 보이기", .unhideSides, enabled: s.hiddenSides)),
            ]),
            ArisSettingSection(id: "notch.sideLeft", heading: "왼쪽 사이드 노치에 보일 탭", rows: sideTabRows(.left, s)),
            ArisSettingSection(id: "notch.sideRight", heading: "오른쪽 사이드 노치에 보일 탭",
                               note: "한쪽 탭을 모두 끄면 그쪽 사이드 노치도 나오지 않아요. 클립보드 탭을 끄면 복사한 것을 더 기록하지 않아요.", rows: sideTabRows(.right, s)),
        ]
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

    /// 창 · 테마: how Aris looks, the notch's look and the window's in one place (D10).
    private static func look(_ s: ArisSettingsSnapshot) -> ArisSettingSection {
        ArisSettingSection(id: "look.all", heading: "모양", note: "macOS의 ‘동작 줄이기’를 켜도 캐릭터는 가만히 있어요.", rows: ArisNotchLookSetting.rows(theme: s.notchTheme, backing: s.textBacking, restStar: s.restStar) + [
            ArisSettingItem(id: "look.theme", icon: .symbol("circle.lefthalf.filled"), title: "설정 창 모양", desc: "설정 창만 바뀌고, 노치는 늘 어두워요.",
                           control: .choice(.theme, options([("light", "라이트"), ("dark", "다크"), ("auto", "자동")]), selected: s.theme)),
            ArisSettingItem(id: "look.accent", icon: .symbol("paintpalette"), title: "강조 색", desc: "선택 표시와 초점 테두리에 쓰는 색이에요.",
                           control: .choice(.accentCustom, options([("system", "시스템"), ("custom", "직접")]), selected: s.customAccent ? "custom" : "system"),
                           extra: s.customAccent ? .swatches(accents, selected: s.accentHex) : .none),
            ArisSettingItem(id: "look.reduceMotion", icon: .symbol("figure.walk.motion"), title: "모션 줄이기",
                           desc: "캐릭터가 돌거나 뛰지 않고 가만히 있어요.", control: .toggle(.reduceMotion, s.reduceMotion)),
        ])
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
            ArisSettingSection(id: "general.screens", heading: "화면", rows: screen),
        ]
    }

    /// 다시 시작 and 종료, after 업데이트 as the mockup has them.
    private static func appRows() -> ArisSettingSection {
        ArisSettingSection(id: "general.app", heading: "앱", rows: [
                ArisSettingItem(id: "general.restart", icon: .symbol("arrow.triangle.2.circlepath"), title: "Aris 다시 시작", desc: "앱을 껐다가 다시 켜요.", control: button("다시 시작", .restart)),
                ArisSettingItem(id: "general.quit", icon: .symbol("xmark.circle"), title: "Aris 종료", desc: "앱을 완전히 꺼요.", control: button("종료", .quit)),
        ])
    }

    private static func keys(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [ArisSettingSection(id: "keys.all", note: "받아쓰기 키를 두 번 빠르게 누르면 손을 떼고 말할 수 있고, 한 번 더 누르면 넣어요. Esc로 취소하고, 한 번에 20분까지예요.", grouped: true, rows: [
            ArisSettingItem(id: "keys.talk", icon: .symbol("aris-star"), title: "Aris에게 말하기", desc: "누르고 바로 말해요.", control: .shortcut(name: "talkToAris", caps: s.talkCaps)),
            // 받아쓰기 쓰기 off: its two keys are dimmed, as they were on 받아쓰기.
            ArisSettingItem(id: "keys.dictation", icon: .symbol("mic"), title: "받아쓰기", desc: "누르고 있는 동안 받아 적어요.",
                           control: .shortcut(name: ArisDictationKey.Choice.recorderName, caps: s.dictationCaps, enabled: s.dictationOn)),
            ArisSettingItem(id: "keys.pasteLast", icon: .symbol("clipboard-paste"), title: "마지막 받아쓰기 다시 넣기", desc: "방금 받아 적은 말을 한 번 더 넣어요.",
                           control: .shortcut(name: "pasteLastDictation", caps: s.pasteLastCaps, enabled: s.dictationOn)),
            ArisSettingItem(id: "keys.answer", icon: .symbol("bubble.left.and.text.bubble.right"), title: "Claude에게 답하기", desc: "승인 · 질문 카드가 떠 있을 때 말로 답해요.",
                           control: .shortcut(name: "answerClaude", caps: s.answerCaps)),
            ArisSettingItem(id: "keys.clipboard", icon: .symbol("clipboard-list"), title: "클립보드 열기 (왼쪽 사이드 노치)",
                           desc: s.hiddenSideTabs.contains(ArisSideTab.clipboard.rawValue) ? "클립보드 탭이 꺼져 있어서 지금은 열리지 않아요." : "포인터 없이 키로 클립보드 탭을 열어요.",
                           control: .shortcut(name: "openClipboard", caps: s.clipCaps)),
            ArisSettingItem(id: "keys.right", icon: .symbol("aris-side-notch"), title: "오른쪽 사이드 노치 열기",
                           desc: ArisSideTabWork.takesRightKey(hidden: s.hiddenSideTabs) ? "포인터 없이 키로 할 일과 캘린더를 열고 닫아요."
                               : "오른쪽 탭이 모두 꺼져 있어서 지금은 열리지 않아요.",
                           control: .shortcut(name: "openRightPanel", caps: s.rightPanelCaps)),
            ArisSettingItem(id: "keys.notch", icon: .symbol("aris-notch"), title: "노치 열고 닫기", desc: "노치를 키로 열고 닫아요.",
                           control: .shortcut(name: "toggleNotchOpen", caps: s.notchCaps)),
            ArisSettingItem(id: "keys.peek", icon: .symbol("music.note"), title: "음악 미리 보기", desc: "재생 중인 곡을 노치 아래에 잠깐 띄워요.",
                           control: .shortcut(name: "toggleSneakPeek", caps: s.peekCaps)),
        ])]
    }

    /// 업데이트: only in a build that updates itself (the public one).
    private static func updates(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        guard s.updates else { return [] }
        return [
            ArisSettingSection(id: "about.update", heading: "업데이트", rows: [
                ArisSettingItem(id: "about.autoUpdate", icon: .symbol("arrow.triangle.2.circlepath"), title: "자동으로 업데이트",
                               desc: "새 버전을 받아 두었다가 Aris가 쉴 때 설치하고 다시 열어요.", control: .toggle(.autoUpdate, s.autoUpdate)),
                ArisSettingItem(id: "about.checkUpdate", icon: .symbol("arrow.down.circle"), title: "업데이트 확인",
                               desc: "지금 버전 \(s.appVersion)", control: button("확인하기", .checkUpdate)),
            ]),
        ]
    }

    /// 업데이트: the version, updating (only in a build that updates itself), then 다시 시작 and 종료.
    private static func about(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        [
            ArisSettingSection(id: "about.app", rows: [
                ArisSettingItem(id: "about.version", icon: .none, title: "Aris", desc: s.versionLine, control: .custom("about")),
            ]),
        ] + updates(s) + [appRows()]
    }

    /// 데이터 · 개인정보: where Aris keeps its data, the privacy switch from the notch's window fold, exporting and
    /// erasing. The saved API keys follow (the AI view draws them: `ai.savedKeys`).
    private static func data(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        let recording = ArisMoreRows.notch(s.more, gestures: s.gestures).flatMap(\.rows).filter { $0.id == hideFromRecordingID }
        return [
            ArisSettingSection(id: "about.data", heading: "데이터", rows: [
                ArisSettingItem(id: "about.folder", icon: .symbol("folder"), title: "데이터가 있는 곳", desc: "대화 기록, 기억과 로그는 이 Mac의 ~/.config/aris에만 있어요.", control: button("Finder에서 보기", .openFolder)),
            ] + recording + [
                ArisSettingItem(id: "about.export", icon: .symbol("square.and.arrow.up"), title: "데이터 내보내기", desc: "대화 기록, 기억, 팀원을 파일로 받아요.", control: .link(.export, value: nil)),
                ArisSettingItem(id: "about.diagnostics", icon: .symbol("stethoscope"), title: "진단 내보내기", desc: "문제가 생겼을 때 보낼 기록 파일이에요.", control: .link(.diagnostics, value: nil)),
                ArisSettingItem(id: "about.wipe", icon: .symbol("trash"), title: "데이터 지우기", desc: "골라서 지우고, 되돌릴 수 없어요.", control: button("지우기…", .wipe, .danger), danger: true),
                ArisSettingItem(id: "about.uninstall", icon: .symbol("shippingbox"), title: "Aris 제거", desc: "앱과 Aris가 만든 것을 모두 지워요.", control: button("제거…", .uninstall, .danger), danger: true),
            ]),
        ] + (s.savedKeys > 0 ? [ArisSettingSection(id: "ai.savedKeys", heading: "저장된 키", rows: [])] : [])
    }
}
