//
//  ArisSettingsParts.swift
//  Aris
//
//  The window's four pages as the owner picked them (settings-ia option A, "네 개의 방"): each a long page of parts, and the
//  sidebar lists the open page's parts under the four names. A part is data: its id, its title, its small line and
//  the search entries it holds, in order. The 14 pages the window had before are kept as names only
//  (ArisSettingsFormerPage): a stored or spoken page name, a link from another part of the app and a search for an
//  old page's name still land where those rows are now. Foundation only (tested).
//

import Foundation

/// One part of a page: a title in the sidebar and on the page, and the settings it holds, in the order drawn.
struct ArisSettingsPart: Identifiable, Equatable {
    let id: String
    let page: ArisSettingsPage
    let title: String
    /// The small line beside the title (only where the mockup has one).
    var subtitle: String?
    /// The search entries this part holds, in the page's order (ArisSettingsIndex ids).
    let rows: [String]
}

extension ArisSettingsPage {
    /// The page's parts, top to bottom: what its sidebar entry lists when it is open.
    var parts: [ArisSettingsPart] { ArisSettingsParts.all.filter { $0.page == self } }
}

enum ArisSettingsParts {
    private static func p(_ id: String, _ page: ArisSettingsPage, _ title: String, _ subtitle: String? = nil, _ rows: [String]) -> ArisSettingsPart {
        ArisSettingsPart(id: id, page: page, title: title, subtitle: subtitle, rows: rows)
    }

    /// Every part, page by page, as option A maps each row (settings-ia/OPTIONS.md).
    static let all: [ArisSettingsPart] = [
        // Aris와 말하기: the AI and its model first, so the window opens on them.
        p("talk.ai", .talk, "AI · 모델", "누가 답하고, 어떤 모델이 얼마나 깊이 생각할지",
          ["ai.brain", "ai.models", "ai.fallback", "ai.jev", "ai.services", "aris.claudeBudget", "aris.claudeConnect"]),
        p("talk.call", .talk, "부르기", nil,
          ["aris.wake", "aris.wakeName", "aris.voiceID", "aris.voiceEnrol", "aris.voiceForget", "aris.recordCalls", "aris.collect",
           "aris.recordClear"]),
        p("talk.hear", .talk, "듣기", nil, ["ai.hear", "hear.mic", "voice.languages", "hear.repair", "hear.words"]),
        p("talk.speak", .talk, "목소리", nil, ["ai.speak", "voice.speed"]),
        p("talk.chat", .talk, "대화", nil, ["aris.minutes", "aris.silence", "aris.duplex", "aris.bargeIn"]),
        p("talk.quiet", .talk, "조용히 · 알림", nil, ["aris.sounds", "aris.dayEnd", "aris.recap", "aris.mute", "aris.quietHours"]),
        // 할 수 있는 일
        p("able.control", .able, "컴퓨터 제어", nil, ["control.sees", "control.circle", "ai.computerEngine", "control.trust", "control.core2", "control.teach", "control.standing"]),
        p("able.dictation", .able, "받아쓰기", nil,
          ["dictation.on", "dictation.pill", "dictation.pillIdle", "dictation.brainPolish", "dictation.style.chat", "dictation.style.mail",
           "dictation.style.code", "dictation.style.other", "dictation.words"]),
        p("able.todo", .able, "할 일", nil, ["todo.lists", "todo.default", "todo.newList"]),
        p("able.calendar", .able, "캘린더", nil, ["calendar.google", "calendar.include", "calendar.allDay", "calendar.join", "calendar.openIn"]),
        p("able.memory", .able, "기억", nil,
          ["memory.auto", "memory.consolidate", "memory.import", "memory.search", "memory.clear", "memory.work", "memory.work.clear", "memory.saved", "memory.dropHabits"]),
        p("able.team", .able, "팀원", nil, ["team.add", "team.detail", "team.look", "team.make", "team.knowhow", "team.terminal"]),
        p("able.skills", .able, "스킬", nil, ["skills.feature", "skills.add", "skills.list"]),
        p("able.connect", .able, "연결", nil, ["ai.mcp.composio", "ai.mcp.add"]),
        // 모양
        p("look.notch", .look, "노치", nil,
          ["notch.hover", "notch.haptics", "notch.gestures", "notch.height", "notch.customHeight", "look.settingsIcon", "look.alwaysTabs", "aris.claudeRing",
           "features.fullScreen", "notch.advanced", "notch.hoverDelay", "notch.rememberTab", "notch.animation", "notch.animationSpeed",
           "notch.gestureDetail", "notch.closeGesture", "notch.mediaSwipe", "notch.fixedDirection", "notch.sensitivity", "notch.window",
           "notch.flatHeight", "notch.flatCustomHeight", "notch.cornerScaling", "notch.chin", "notch.lockScreen", "notch.hideFromMissionControl"]),
        p("look.side", .look, "사이드 노치", nil,
          ["notch.unhide", "notch.tab.history", "notch.tab.activity", "notch.tab.clipboard", "notch.tab.usage", "notch.tab.todo", "notch.tab.calendar"]),
        p("look.music", .look, "음악", nil,
          ["features.music", "features.musicSource", "features.musicActivity", "features.peek", "features.peekStyle", "features.idleWait",
           "features.coloredBars", "features.tinting"]),
        p("look.shelf", .look, "선반", nil,
          ["features.shelf", "features.shelfOn", "features.shelfOnHome", "features.wideDrop", "features.copyOnDrag", "features.removeAfterDrag",
           "features.reverseOrder", "features.quickShare"]),
        p("look.window", .look, "창 · 테마", nil,
          ["notch.theme", "notch.textBacking", "notch.restStar", "look.theme", "look.accent", "look.reduceMotion"]),
        // 앱
        p("app.permissions", .app, "권한", nil,
          ["control.ax", "control.screen", "control.mic", "control.speech", "control.input", "aris.systemAudio", "todo.access", "calendar.access",
           "general.onboarding"]),
        p("app.keys", .app, "단축키", nil,
          ["keys.talk", "keys.dictation", "keys.pasteLast", "keys.answer", "keys.clipboard", "keys.right", "keys.notch", "keys.peek"]),
        p("app.general", .app, "시작 · 언어 · 화면", nil,
          ["general.login", "general.name", "general.language", "general.display", "general.screen"]),
        p("app.update", .app, "업데이트", nil, ["about.version", "about.autoUpdate", "about.checkUpdate", "general.restart", "general.quit"]),
        p("app.data", .app, "데이터 · 개인정보", nil,
          ["about.folder", "notch.hideFromRecording", "about.export", "about.diagnostics", "about.wipe", "about.uninstall", "ai.savedKeys"]),
    ]

    static func part(_ id: String) -> ArisSettingsPart? { all.first { $0.id == id } }

    /// Rows another branch is building, placed here ahead of them: each is drawn in its part's slot
    /// (ArisSettingsSlots) and becomes a search entry when its owner adds it to the index.
    static let slots: Set<String> = ["control.trust"]

    /// The part a search entry is listed in (nil: none lists it, and it goes to its former page's part).
    static func holding(_ entry: String) -> ArisSettingsPart? { all.first { $0.rows.contains(entry) } }

    /// Rows that were merged into another or removed (option A's duplicates and dead rows): a link or a search that
    /// still names one lands on the row that does its job now.
    static let moved: [String: String] = [
        "aris.talkKey": "keys.talk",
        "dictation.key": "keys.dictation",
        "dictation.pasteLast": "keys.pasteLast",
        "notch.clipKey": "keys.clipboard",
        "notch.rightKey": "keys.right",
        "voice.voice": "ai.speak",
        "voice.scribe": "ai.hear",
        "voice.engine": "ai.hear",
        "aris.brainLink": "ai.brain",
        "ai.teamBrain": "team.detail",
        "features.calendar": "calendar.google",
        "ai.voice": "talk.hear",
        "team.claude": "team.terminal",
    ]

    /// The rows only the 팀원 sheet draws (the team's own view): a search or a link to one opens the sheet on it.
    static let sheetAnchors: [String: String] = ["team.look": "team", "team.knowhow": "team"]

    /// Where a link to `anchor` lands now: a moved row's new row, else the anchor itself.
    static func landing(_ anchor: String) -> String { moved[anchor] ?? anchor }
}

/// The 14 pages the window had before option A. Only their names are left: what a stored value, a link elsewhere in
/// the app, the agent or a reply may still say, and the place that took each one's rows.
enum ArisSettingsFormerPage: String, CaseIterable {
    case aris, ai, voice, memory, team, skills, dictation, todo, control, notch, features, general, keys, about

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

    /// The part that holds most of what the page held (where its name alone lands).
    var part: String {
        switch self {
        case .aris: "talk.call"
        case .ai: "talk.ai"
        case .voice: "talk.hear"
        case .memory: "able.memory"
        case .team: "able.team"
        case .skills: "able.skills"
        case .dictation: "able.dictation"
        case .todo: "able.todo"
        case .control: "able.control"
        case .notch: "look.notch"
        case .features: "look.music"
        case .general: "app.general"
        case .keys: "app.keys"
        case .about: "app.data"
        }
    }

    var page: ArisSettingsPage { ArisSettingsParts.part(part)?.page ?? .talk }

    /// A stored or spoken old name: a page of the 14, or one of the names before those ("calendar", "look").
    static func named(_ raw: String) -> ArisSettingsFormerPage? {
        switch raw {
        case "calendar": .todo
        default: ArisSettingsFormerPage(rawValue: raw)
        }
    }
}

/// Which part is in view while a long page scrolls (the sidebar marks it): the last part whose top has passed `line`
/// from the top of the scroll box, or the first part before any has. Scrolled to the very end, the last part is in
/// view even when its top can't reach the line.
enum ArisSettingsSpy {
    /// Where a part counts as reached: a little under the top fade.
    static let line = 120.0

    static func current(order: [String], tops: [String: Double], atEnd: Bool = false, line: Double = line) -> String? {
        guard let first = order.first else { return nil }
        if atEnd, let last = order.last(where: { tops[$0] != nil }) { return last }
        return order.last { (tops[$0] ?? .infinity) <= line } ?? first
    }
}

/// Where the window opens: on Aris와 말하기's first part (AI · 모델), unless a link chose a page or a row just before
/// the window was asked to open (the notch's "설정에서 … 열어", a fix card, the to-do tab's link).
enum ArisSettingsOpening {
    /// How long a link's choice holds for the window opening after it.
    static let linkHolds: TimeInterval = 2

    static func keepsLink(linkedAt: Date?, now: Date) -> Bool {
        guard let linkedAt else { return false }
        return now.timeIntervalSince(linkedAt) < linkHolds && now >= linkedAt
    }
}
