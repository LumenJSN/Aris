// Tests for the whole settings window in English on an English Mac (fresh install F5, after the first five pages):
// 기억, 스킬, 목소리 · 언어, 받아쓰기, 할 일, 캘린더, 컴퓨터 제어, 모양, 노치 기능, 단축키, and 팀원's leftover lines. Each
// page is held to the rule of the first five: no string it draws without its English, and no Korean literal in its
// view and model files that reaches the screen untranslated. Everything here reads the builder, the catalog file and
// the sources; nothing of the user's is touched. Called from main.swift; uses its check().
import Foundation

func runEnSettingsTests() {
    enSettingsEngineTests()
    enSettingsPageTests()
    enSettingsUserWordsTests()
    enSettingsPreviewTests()
    enSettingsSaidTests()
    enSettingsSourceTests()
    enSettingsHelperTests()
    enSettingsTeamTests()
    ArisSettingsCopy.install([:])
}

// MARK: - Reading the catalog and the sources

private func enSettingsRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

private func enSettingsSource(_ path: String) -> String {
    (try? String(contentsOf: enSettingsRoot().appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The settings catalog's pairs (Korean → English), read from the file the app compiles.
private func enSettingsPairs() -> [String: String] {
    let file = enSettingsRoot().appendingPathComponent("Aris/components/Settings/Settings.xcstrings")
    return ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: file)) ?? Data())
}

private func enHasHangul(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
}

/// Every string literal in a Swift source that has Korean in it, comments left out. A value written into the string
/// (`\(name)`) reads "7", which stands for a name or a number alike when the catalog is asked. A raw string and a
/// text of several lines are each one string.
private func enKoreanLiterals(_ source: String) -> [String] {
    var found: [String] = []
    let text = Array(source)
    var i = 0
    func literal() -> String {
        // `i` is just past the opening quote.
        var out = ""
        while i < text.count, text[i] != "\"" {
            if text[i] == "\\", i + 1 < text.count {
                if text[i + 1] == "(" {
                    i += 2
                    var depth = 1
                    while i < text.count, depth > 0 {
                        if text[i] == "\"" { i += 1; let inner = literal(); if enHasHangul(inner) { found.append(inner) } }
                        else { if text[i] == "(" { depth += 1 } else if text[i] == ")" { depth -= 1 }; i += 1 }
                    }
                    out += "7"
                    continue
                }
                out.append(text[i + 1] == "n" ? "\n" : text[i + 1])
                i += 2
                continue
            }
            out.append(text[i])
            i += 1
        }
        i += 1
        return out
    }
    /// Everything up to `end` (a raw string's or a several-line text's closing mark), taken as it is written.
    func through(_ end: [Character]) -> String {
        var out = ""
        while i + end.count <= text.count, Array(text[i..<(i + end.count)]) != end { out.append(text[i]); i += 1 }
        i += end.count
        return out
    }
    while i < text.count {
        if text[i] == "/", i + 1 < text.count, text[i + 1] == "/" {
            while i < text.count, text[i] != "\n" { i += 1 }
        } else if text[i] == "#", i + 1 < text.count, text[i + 1] == "\"" {
            // A raw string (#"…"#, a pattern): it may hold quotation marks of its own.
            i += 2
            let one = through(["\"", "#"])
            if enHasHangul(one) { found.append(one) }
        } else if text[i] == "\"", i + 2 < text.count, text[i + 1] == "\"", text[i + 2] == "\"" {
            // A text of several lines (a prompt): one string.
            i += 3
            let one = through(["\"", "\"", "\""])
            if enHasHangul(one) { found.append(one) }
        } else if text[i] == "\"" {
            i += 1
            let one = literal()
            if enHasHangul(one) { found.append(one) }
        } else {
            i += 1
        }
    }
    return found
}

/// The lines of a view's source that hand SwiftUI a Korean string directly, past the page's wording.
private func enRawLines(_ source: String) -> [String] {
    source.components(separatedBy: "\n").filter { line in
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//") else { return false }
        return ["Text(\"", ".help(\"", ".accessibilityLabel(\"", ".accessibilityValue(\"", "TextField(\"", "SecureField(\"", "Label(\""].contains { start in
            code.components(separatedBy: start).dropFirst().contains { enHasHangul(String($0.prefix { $0 != "\"" })) }
        }
    }
}

// MARK: - The pages

/// The app's own permission rows (ArisLiveSettings.base), with the helper's folders.
private func enPermissions(granted: Bool) -> [ArisSettingsSnapshot.Permission] {
    [.init(id: "ax", title: "손쉬운 사용", desc: "버튼·입력칸을 찾아 누르고 글자를 입력해요.", granted: granted),
     .init(id: "screen", title: "화면 기록", desc: "화면을 가리켜 말할 때 그 화면을 같이 봐요.", granted: granted),
     .init(id: "mic", title: "마이크", desc: "말을 들어요.", granted: granted),
     .init(id: "fda", title: "전체 디스크 접근", desc: "메시지·메일·메모를 읽기만 해요.", granted: granted)]
        + ArisSettingsSnapshot.folderPermissions(granted: granted ? ["Desktop": true, "Documents": true, "Downloads": true] : [:])
}

/// A memory of each kind and source, one said in each month, one not yet confirmed. What the user said is in English
/// here: his own words are never translated (enSettingsUserWordsTests).
private func enMemories() -> [ArisMemoryItem] {
    let kinds = ["preference", "fact", "project", "person", "routine", "other"], sources = ["said", "learned", "tool", "imported", "elsewhere"]
    return (0..<12).map { month in
        // The 15th at noon: the same month in every time zone.
        let said = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"), year: 2026, month: month + 1, day: 15, hour: 12).date!
        return ArisMemoryItem(id: "m\(month)", kind: kinds[month % kinds.count], subject: month % 2 == 0 ? "coffee" : "", text: "iced americano \(month)",
                              source: sources[month % sources.count], said: said.timeIntervalSince1970, used: nil, confidence: month == 3 ? 0.4 : nil)
    }
}

/// Snapshots that between them reach every line each of the later pages can draw.
private func enSettingsVariants(_ page: ArisSettingsPage) -> [ArisSettingsSnapshot] {
    let base = ArisSettingsSnapshot()
    func with(_ change: (inout ArisSettingsSnapshot) -> Void) -> ArisSettingsSnapshot {
        var copy = base
        change(&copy)
        return copy
    }
    switch page {
    case .memory:
        return [base, with { $0.memoriesLoaded = true }, with { $0.memoriesLoaded = true; $0.memories = [] },
                with { $0.memoriesLoaded = true; $0.memories = enMemories(); $0.autoMemory = false },
                with { $0.memoriesLoaded = true; $0.memories = enMemories(); $0.memoryQuery = "zzz"; $0.confirmingMemoryClear = true }]
    case .voice:
        return [base, with { $0.hasVoiceKey = true; $0.voiceName = "Rachel"; $0.speed = 0.9; $0.cloud = false; $0.languages = [.init(id: "en", title: "English")] },
                with { $0.speed = 1.15 }]
    case .dictation:
        return [base, with { $0.words = 12; $0.brainPolish = true; $0.pasteLastCaps = []; $0.styles = ["chat": "formal", "code": "standard"]
                             $0.learned = [.init(text: "Aris", heard: "Harris", proposed: true), .init(text: "Sol", heard: "", proposed: false),
                                           .init(text: "Lumen", heard: "Human", proposed: false)] }]
    case .todo:
        // 할 일 and 캘린더 are one page now: each half's states.
        let lists: [ArisSettingsSnapshot.ColoredItem] = [.init(id: "a", name: "Home", source: "iCloud", colorHex: "#FF9500", included: true),
                                                         .init(id: "b", name: "Work", source: "", colorHex: "#007AFF", included: false)]
        let calendars: [ArisSettingsSnapshot.ColoredItem] = [.init(id: "a", name: "Home", source: "iCloud", colorHex: "#34C759", included: true)]
        return [base, with { $0.reminders = .blocked }, with { $0.reminders = .granted },
                with { $0.reminders = .granted; $0.reminderLists = lists; $0.defaultList = "a"; $0.newListFailed = true; $0.newListName = "" },
                with { $0.reminders = .granted; $0.reminderLists = [lists[1]] },
                with { $0.calendarAccess = .blocked }, with { $0.calendarAccess = .granted },
                with { $0.calendarAccess = .granted; $0.calendars = calendars; $0.googleCalendars = 2; $0.allDay = false; $0.joinMeeting = false; $0.openIn = "google" }]
    case .control:
        let standing: [ArisSettingsSnapshot.Standing] = [.init(id: "p1", title: "메시지 보내기", desc: "대상: Mum · Messages", symbol: "message"),
                                                         .init(id: "p2", title: "Notion 일정 만들기 (+notify)", desc: "대상: Team calendar", symbol: "calendar")]
        return [with { $0.permissions = enPermissions(granted: false) },
                with { $0.permissions = enPermissions(granted: true); $0.standingLoaded = true; $0.seesScreen = false; $0.circle = false
                       $0.circleHint = ArisCircleHint.text(shortcut: nil) },
                with { $0.standingLoaded = true; $0.standing = []; $0.circleHint = ArisCircleHint.text(shortcut: "⌥Return") },
                with { $0.standingLoaded = true; $0.standing = standing; $0.circleHint = ArisCircleHint.text(shortcut: "⌥⇧") }]
    case .general:
        return [base, with { $0.theme = "dark"; $0.customAccent = true; $0.accentHex = "#FF2D55"; $0.reduceMotion = true }]
    case .notch:
        return [base, with { $0.settingsIcon = false; $0.alwaysTabs = false }]
    case .features:
        return [base, with { $0.more.nowPlayingWorks = false; $0.more.musicSource = "spotify"; $0.more.peek = true; $0.more.peekStyle = "inline"; $0.more.idleWait = 0
                             $0.more.fullScreen = "never"; $0.more.quickShareOptions = [.init(id: "AirDrop", title: "AirDrop"), .init(id: "menu", title: "공유 메뉴")] },
                with { $0.more.idleWait = 10; $0.more.fullScreen = "always"; $0.more.shelf = false }]
    case .keys:
        return [base, with { $0.talkCaps = []; $0.pasteLastCaps = []; $0.answerCaps = []; $0.clipCaps = []; $0.notchCaps = []; $0.peekCaps = [] }]
    default:
        return [base]
    }
}

/// The pages this file finishes; the first five are held by fix-leftovers-tests.
private let enSettingsBuiltPages: [ArisSettingsPage] = [.memory, .voice, .dictation, .todo, .control, .features, .keys]

private func enSettingsEngineTests() {
    var table = ArisSettingsCopyTable([
        "취향": "Preference", "내가 말함": "You said it", "확인 전": "Not confirmed", "11월 %d일": "Nov %d", "마이크": "Microphone",
        "%@를 누른 채 그려요": "Hold %@ and draw", "%@. 권한이 필요해요.": "%@. Needs a permission.", "%@ 아직 허용 안 됨.": "%@ Not allowed yet.",
        "말을 들어요.": "Hears you.", "대상: %@": "For %@", "사람": "People", "‘%@’ 넣을까요?": "Add “%@”?", "%@ 탭이 꺼져 있어요": "The %@ tab is off",
        "받아 적은 ‘%@’를 ‘%@’로 고치셨어요.": "You changed “%@” to “%@”.", "이제 “%@ 스킬로 해줘”라고 하면 써요.": "Say “use the %@ skill”.",
    ])
    check(table.english("취향 · 11월 3일 · 내가 말함 · 확인 전") == "Preference · Nov 3 · You said it · Not confirmed",
          "copy: a line of parts joined by · is said part by part, a part with a number in it too")
    check(table.english("GitHub · hana-k") == nil && table.english("취향 · hana-k") == "Preference · hana-k",
          "copy: a part with no English stays as it is, and a line with none of its parts in the catalog has no English")
    check(table.english("⌥⇧를 누른 채 그려요. 권한이 필요해요.") == "Hold ⌥⇧ and draw. Needs a permission.",
          "copy: a value that is itself a sentence of the catalog is said in English inside the longer one")
    check(table.english("말을 들어요. 아직 허용 안 됨.") == "Hears you. Not allowed yet." && table.english("대상: Mum · Messages") == "For Mum · Messages",
          "copy: a whole sentence that fits is used before the line is taken apart")
    check(table.english("‘사람’ 넣을까요?") == "Add “사람”?" && table.english("받아 적은 ‘취향’를 ‘사람’로 고치셨어요.") == "You changed “취향” to “사람”."
          && table.english("이제 “사람 스킬로 해줘”라고 하면 써요.") == "Say “use the 사람 skill”." && table.english("사람 탭이 꺼져 있어요") == "The People tab is off",
          "copy: a value the Korean writes in quotation marks is a name or the user's own word, and stays as it is")
    check(ArisSettingsCopyTable.quoted("받아 적은 ‘%@’를 ‘%@’로 고치셨어요. 지금 %d개, %@") == [true, true, false, false], "copy: which of a line's values are in quotation marks")
}

private func enSettingsPageTests() {
    let pairs = enSettingsPairs()
    ArisSettingsCopy.install(pairs)
    check(pairs.count > 700, "settings catalog: it holds the later pages' strings too (\(pairs.count))")
    check(pairs.allSatisfy { !enHasHangul($0.value) || $0.value == "한국어" } && pairs.allSatisfy { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty },
          "settings catalog: every entry's English is English")
    func placeholders(_ text: String) -> Int { text.components(separatedBy: "%@").count + text.components(separatedBy: "%d").count - 2 }
    func positional(_ text: String) -> Int { (1...9).filter { text.contains("%\($0)$@") || text.contains("%\($0)$d") }.count }
    let uneven = pairs.filter { placeholders($0.key) != placeholders($0.value) + positional($0.value) }.map(\.key)
    check(uneven.isEmpty, "settings catalog: an entry's English takes as many values as its Korean gives" + (uneven.isEmpty ? "" : " (\(uneven.prefix(3)))"))

    check(ArisSettingsCopy.translatedPages == Set(ArisSettingsPage.allCases), "settings in English: every page is English now, none is left wholly Korean")
    for page in enSettingsBuiltPages {
        let wording = ArisSettingsWording.make(page: page, english: true)
        check(wording.pageEnglish, "settings in English: \(page.rawValue) is drawn in English")
        let left = enSettingsVariants(page).flatMap { ArisSettingsWording.shown(wording.sections(ArisSettingsBuilder.sections(page, $0))) }
            .filter { enHasHangul($0) && $0 != "한국어" }
        check(left.isEmpty, "settings in English: \(page.rawValue) has no Korean left" + (left.isEmpty ? "" : " (\(Array(Set(left)).sorted().prefix(4)))"))
        for snapshot in enSettingsVariants(page) {
            let sections = ArisSettingsBuilder.sections(page, snapshot)
            check(wording.sections(sections).map(\.id) == sections.map(\.id) && wording.sections(sections).flatMap(\.rows).map(\.id) == sections.flatMap(\.rows).map(\.id)
                  && ArisSettingsWording.korean.sections(sections) == sections,
                  "settings in English: \(page.rawValue) keeps every row and id, and in Korean nothing changes")
        }
    }
    // Every page's settings can be found by an English name, the pages that draw themselves too.
    let unnamed = ArisSettingsIndex.entries.filter { ArisSettingsCopy.english($0.title) == nil && enHasHangul($0.title) }
    check(unnamed.isEmpty, "settings in English: every setting can be found by an English name" + (unnamed.isEmpty ? "" : " (\(unnamed.map(\.title).prefix(4)))"))
    let english = ArisSettingsWording.make(page: .voice, english: true)
    let alias: (ArisSettingsEntry) -> ArisSettingsIndex.Alias = { .init(title: english.of($0.page, $0.title), page: english.frame($0.page.title)) }
    check(ArisSettingsIndex.search("speaking speed", alias: alias).first?.id == "voice.speed" && ArisSettingsIndex.search("word list", alias: alias).first?.id == "dictation.words"
          && ArisSettingsIndex.search("my skills", alias: alias).first?.id == "skills.list",
          "search: a setting of the later pages is found by its English name")

    // Lines whose values keep their places.
    let memory = ArisSettingsWording.make(page: .memory, english: true), control = ArisSettingsWording.make(page: .control, english: true)
    check(memory("12가지를 기억하고 있어요.") == "Aris remembers 12 things." && memory("취향 · 11월 3일 · 내가 말함 · 확인 전") == "Preference · Nov 3 · you said it · not confirmed",
          "기억 in English: how many it remembers, and a memory's kind, day and source")
    check(control(ArisCircleHint.text(shortcut: "⌥⇧")) == "Hold ⌥⇧ and draw a circle on the screen, and Aris looks at that part too"
          && control(ArisCircleHint.text(shortcut: "⌥Return")).hasPrefix("Hold ⌥ Return and draw") && control(ArisCircleHint.text(shortcut: nil)).hasPrefix("Hold the talk shortcut and draw"),
          "컴퓨터 제어 in English: the circle's line names the key, whichever particle the Korean took")
    check(english("자꾸 틀리는 말을 넣어 두면 그대로 적어요 · 12개").hasSuffix("· 12")
          && english("파일 폴더 3곳") == "3 file folders" && english("처음 한 번 준비가 필요해요 · 약 75MB · 1~2분").contains("75"),
          "settings in English: numbers keep their places")
    check(english("앱 언어") == "App language" && !enHasHangul(english("설정과 메뉴 글자의 언어예요.")),
          "일반 › 앱 언어: its line has its English")
}

/// What the user named or typed is never translated, even when it happens to be a word the catalog has.
private func enSettingsUserWordsTests() {
    var s = ArisSettingsSnapshot()
    s.reminders = .granted
    s.reminderLists = [.init(id: "a", name: "캘린더", source: "기록", colorHex: "#FF9500", included: true)]
    s.defaultList = "a"
    s.calendarAccess = .granted
    s.calendars = [.init(id: "c", name: "할 일", source: "기록", colorHex: "#34C759", included: true)]
    s.memoriesLoaded = true
    s.memories = [ArisMemoryItem(id: "m", kind: "fact", subject: "", text: "캘린더", source: "said", said: 1_762_300_000, used: nil)]
    s.learned = [.init(text: "기록", heard: "", proposed: false)]
    s.userName = "기록"
    func rows(_ page: ArisSettingsPage) -> [ArisSettingItem] {
        ArisSettingsWording.make(page: page, english: true).sections(ArisSettingsBuilder.sections(page, s)).flatMap(\.rows)
    }
    let list = rows(.todo).first { $0.id == "todo.list.a" }, calendar = rows(.todo).first { $0.id == "calendar.cal.c" }
    check(list?.title == "캘린더" && list?.desc == "기록" && calendar?.title == "할 일" && calendar?.desc == "기록",
          "user's words: a Reminders list and a calendar keep the names the user gave them")
    let english = ArisSettingsWording.make(page: .todo, english: true)
    if case .menu(let key, let options, _)? = rows(.todo).first(where: { $0.id == "todo.default" })?.control {
        check(options.map(\.title) == ["캘린더"] && ArisSettingsWording.namesUserWords(key) && !ArisSettingsWording.namesUserWords(.displayMode)
              && english.verbatim("캘린더") == "캘린더" && english("캘린더") == "Calendar" && english.verbatim.frame("일반") == "General",
              "user's words: the list picker names the lists as they are, on its button and in its menu")
    } else {
        check(false, "user's words: the list picker names the lists as they are, on its button and in its menu")
    }
    let dropdown = enSettingsSource("Aris/components/Settings/ArisSettingsDropdown.swift")
    check(dropdown.components(separatedBy: "ArisSettingsWording.namesUserWords(").count == 3 && dropdown.contains(".environment(\\.arisWords, choice)"),
          "user's words: the dropdown draws such a menu's button and its list as written")
    let item = rows(.memory).first { $0.id == "memory.item.m" }, learned = rows(.dictation).first { $0.id == "dictation.learned.기록" }
    check(item?.title == "캘린더" && item?.desc?.hasPrefix("About you · ") == true, "user's words: a memory is shown as the user said it, under an English line")
    check(learned?.title == "기록" && learned?.desc == "Learned from your correction.", "user's words: a learned word is shown as it is written")
    if case .field(_, let text, _, _)? = rows(.general).first(where: { $0.id == "general.name" })?.control {
        check(text == "기록", "user's words: what a field holds is left alone")
    } else {
        check(false, "user's words: what a field holds is left alone")
    }
}

// MARK: - The notch preview

private func enSettingsPreviewTests() {
    func caption(_ page: ArisSettingsPage, _ change: (inout ArisNotchPreviewInput) -> Void = { _ in }) -> String {
        var input = ArisNotchPreviewInput()
        input.page = page
        change(&input)
        return ArisSettingsWording.make(page: page, english: true)(ArisNotchPreviewPlan.make(input).caption)
    }
    let captions = [caption(.voice), caption(.voice) { $0.speedTitle = "느리게"; $0.voiceName = "Rachel" }, caption(.voice) { $0.speedTitle = "빠르게" },
                    caption(.control), caption(.control) { $0.circleGesture = false }, caption(.control) { $0.circleGesture = false; $0.seesScreen = false },
                    caption(.team), caption(.team) { $0.teammateNames = ["Cody", "Tam"] },
                    caption(.skills), caption(.skills) { $0.skillsOn = true }, caption(.skills) { $0.skillsOn = true; $0.skillTitles = ["Meeting notes"] }]
        + [ArisSettingsPage.memory, .dictation, .todo, .features, .keys].map { caption($0) }
    let left = captions.filter(enHasHangul)
    check(left.isEmpty, "preview in English: every page's line under the notch is English" + (left.isEmpty ? "" : " (\(left.prefix(3)))"))
    check(caption(.voice) { $0.speedTitle = "느리게"; $0.voiceName = "Rachel" } == "Speaking speed · Slow · voice Rachel" && caption(.voice) == "Speaking speed · Normal · the Mac's voice",
          "preview in English: the voice page's line names the speed and the voice")
    check(caption(.team) { $0.teammateNames = ["Cody", "Tam"] } == "2 teammates · Cody, Tam" && caption(.team) == "0 teammates",
          "preview in English: the team's line counts the teammates and names them")
    let voice = ArisSettingsWording.make(page: .voice, english: true), skills = ArisSettingsWording.make(page: .skills, english: true)
    check(voice(ArisNotchPreviewPlan.line) == "Hello, I'm Aris. This is how fast I'll speak." && !enHasHangul(skills(ArisNotchPreviewPlan.skillLine)),
          "preview in English: the sample line Aris reads out, and the sample answer under a skill's tag")
    var input = ArisNotchPreviewInput()
    input.page = .skills
    input.skillsOn = true
    input.skillTitles = ["Meeting notes"]
    if case .skillAnswer(let tag, _) = ArisNotchPreviewPlan.make(input).content {
        check(skills(tag) == "Using the Meeting notes skill", "preview in English: the tag over an answer that followed a skill")
    } else {
        check(false, "preview in English: the tag over an answer that followed a skill")
    }
    check(voice(ArisSettingsCaption.changed("Speaking speed", on: nil)) == "Changed Speaking speed" && voice("목소리를 Rachel로 바꿨어요") == "Changed the voice to Rachel"
          && voice("목소리를 Adam으로 바꿨어요") == "Changed the voice to Adam",
          "preview in English: the line after a change")
}

// MARK: - Toasts and lines the pages build while they work

private func enSettingsSaidTests() {
    let w = ArisSettingsWording.make(page: .dictation, english: true)
    let said: [String: String] = [
        "‘Errands’ 목록을 만들고 포함했어요": "Made the list “Errands” and included it",
        "‘Aris’ 단어장에 넣었어요": "Added “Aris” to the word list", "‘Aris’ 다시 묻지 않을게요": "Won't ask about “Aris” again", "‘Aris’ 지웠어요": "Cleared “Aris”",
        "‘메모’ 단어장에 넣었어요": "Added “메모” to the word list", "‘할 일’ 목록을 만들고 포함했어요": "Made the list “할 일” and included it",
        "바꾸지 못했어요. Aris 도우미가 켜져 있는지 확인해 주세요.": "Couldn't change it. Check that Aris's helper is running.",
        "잊었어요": "Forgotten", "확인했어요": "Confirmed", "기억을 모두 지웠어요": "Cleared every memory",
        "메시지 보내기는 다시 물어볼게요": "Sending messages: Aris will ask again", "미리 알림은 다시 물어볼게요": "Reminders: Aris will ask again",
        "Notion 일정 만들기 (+notify)는 다시 물어볼게요": "Creating Notion events (+notify): Aris will ask again",
        "Cody를 팀에서 뺐어요": "Removed Cody from the team", "Tam을 팀에서 뺐어요": "Removed Tam from the team", "Cody 빼기": "Remove Cody",
    ]
    let wrong = said.filter { w($0.key) != $0.value }.map { "\($0.key) → \(w($0.key))" }
    check(wrong.isEmpty, "settings in English: what the later pages say when something is done is English, names as they are" + (wrong.isEmpty ? "" : " (\(wrong.sorted().prefix(3)))"))
    // 스킬: the lines its chat, list and cards build.
    let skills = ArisSettingsWording.make(page: .skills, english: true)
    let built = ["내 스킬 3개", "처음 한 번 작은 준비가 필요해요. 보안 검사 도구(SkillSpector)와 파이썬을 Aris 폴더에 설치해요 · 약 75MB · 1~2분.",
                 "보안 검사 도구(SkillSpector)와 파이썬을 Aris 폴더에 설치해요 · 약 75MB · 1~2분",
                 "추가했어요. 연결한 AI로 시험도 하는 중이에요. 이제 “Meeting notes 스킬로 해줘”라고 하면 써요.", "‘Meeting notes’ 스킬에서 무엇을 바꿀까요?",
                 "연결한 AI 3개 모두에서 시험했어요.",
                 "연결한 AI 3개 중 1개에서 시험했어요. 스킬은 모든 AI에서 돌아가야 해서, 나머지도 시험해 보는 걸 권해요. AI는 AI 서비스에서 더 연결할 수 있어요.",
                 "확인할 게 2개 있어요", "파일 4개 · 스크립트가 하는 일", "폴더 · meeting-notes", "AI 3개 모두", "AI 2개 · 1개 아직", "AI 1개 · 2개 아직", "시험 전", "아직 · API 모델",
                 "GitHub · hana-k · 요약", "skill-creator로 만듦 · summary", "Aris 기본 · summary", "내 폴더 · summary",
                 "지시문 · 1.2KB", "스크립트 · 340B", "참고 자료", "자료 · 2.0MB", "인터넷 씀", "내 Mac 안에서만",
                 "GitHub · studyhub · 버전 1.3.0 · ★ 214 · 2주 전 업데이트 · MIT", "오늘 업데이트", "3일 전 업데이트", "2달 전 업데이트", "1년 전 업데이트", "GitHub · studyhub · 파일 4개"]
    let builtLeft = built.filter { $0 != "GitHub · hana-k · 요약" && enHasHangul(skills($0)) }
    check(builtLeft.isEmpty, "스킬 in English: the lines its chat, list and cards build are English" + (builtLeft.isEmpty ? "" : " (\(builtLeft.prefix(3)))"))
    check(skills("내 스킬 3개") == "My skills · 3" && skills("AI 2개 · 1개 아직") == "2 AIs · 1 to go" && skills("AI 1개 · 2개 아직") == "1 AI · 2 to go"
          && skills("GitHub · hana-k · 요약") == "GitHub · hana-k · 요약"
          && skills("GitHub · studyhub · 버전 1.3.0 · ★ 214 · 2주 전 업데이트 · MIT") == "GitHub · studyhub · version 1.3.0 · ★ 214 · updated 2 weeks ago · MIT",
          "스킬 in English: counts and names keep their places, and a skill's own summary is left as it was written")
}

// MARK: - The sources: every Korean string of the later pages has its English, and none is drawn past the wording

/// The view and model files of the later pages (the builder, catalog, snapshot and live settings are read too: what
/// they hold reaches the screen through the wording).
private let enSettingsFiles: [String] = [
    // 기억
    "Aris/private/Aris/ArisMemorySettings.swift",
    // 스킬
    "Aris/components/Settings/ArisSkillsPage.swift", "Aris/components/Settings/ArisSkillsCards.swift", "Aris/private/Aris/Skills/ArisSkillsModel.swift",
    "Aris/private/Aris/Skills/ArisSkillsStatus.swift",
    // 목소리 · 언어, 받아쓰기
    "Aris/components/Settings/ArisVoicePicker.swift", "Aris/private/Aris/Dictation/ArisWritingStyle.swift",
    // 컴퓨터 제어
    "Aris/components/Settings/ArisStandingPermissionsSection.swift", "Aris/private/Aris/Gesture/ArisCircleHint.swift", "Aris/components/Settings/ArisSettingsSnapshot.swift",
    // 노치 기능
    "Aris/components/Settings/ArisMoreSettings.swift", "Aris/components/Settings/ArisMoreSettingsModel.swift",
    // 팀원's leftovers
    "Aris/private/Aris/Team/ArisTeamEditing.swift", "Aris/private/Aris/Team/ArisTeamModel.swift", "Aris/private/Aris/Team/ArisTeamSaveRule.swift",
    "Aris/components/Settings/ArisTeamPage.swift", "Aris/components/Settings/ArisTeamSections.swift", "Aris/components/Settings/ArisTeammateInspector.swift",
    // Every page
    "Aris/components/Settings/ArisSettingsBuilder.swift", "Aris/components/Settings/ArisSettingsCatalog.swift", "Aris/components/Settings/ArisLiveSettings.swift",
    "Aris/components/Settings/ArisNotchPreviewPlan.swift", "Aris/components/Settings/ArisNotchPreview.swift", "Aris/components/Settings/ArisSettingsWords.swift",
    "Aris/components/Settings/ArisSettingsWindow.swift",
]

/// Korean in the sources that is never drawn in the window as it is written there.
private let enSettingsNotDrawn: Set<String> = [
    // written both ways where it is (ArisUIWords)
    "Aris 설정",
    // words heard or matched, never shown: a skill's icon by its subject, a finding read for "uses the internet", what
    // an "add this skill" request says, the apps a writing style goes by, Aris's own name
    "회의", "회의록", "과제", "공부", "시험", "숙제", "수업", "강의 노트", "유튜브", "영상", "강의", "캡션", "인스타", "사진", "영수증", "가계부", "예산",
    "일정", "달력", "체크", "이메일", "번역", "코드", "개발",
    "인터넷", "접속", "받아요", "보내요", "보내지 않", "Mac 안", "설치", "넣어", "깔아", "받아", " 스킬 추가", "카카오톡", "메시지", "터미널", "아리스",
    // the Korean particles themselves
    "을", "를", "이", "가", "은", "는", "으로", "로",
]

/// A literal that is only a piece of a line (the code joins it to a name, a number or a particle: 을/를 by the name's
/// last sound), and the catalog's entries for the whole line. The sentences as they are said are checked in
/// enSettingsSaidTests, enSettingsPreviewTests and enSettingsPageTests; here only that each entry exists.
private let enSettingsPieces: [String: [String]] = [
    "목소리를 7 바꿨어요": ["목소리를 %@로 바꿨어요", "목소리를 %@으로 바꿨어요"],
    "7 다시 물어볼게요": ["%@는 다시 물어볼게요", "%@은 다시 물어볼게요"],
    "7 팀에서 뺐어요": ["%@를 팀에서 뺐어요", "%@을 팀에서 뺐어요"],
    "7 이 Mac에 아직 없어요. 아래에서 준비하거나 다른 AI를 골라 주세요.": ["%@는 이 Mac에 아직 없어요. 아래에서 준비하거나 다른 AI를 골라 주세요.", "%@은 이 Mac에 아직 없어요. 아래에서 준비하거나 다른 AI를 골라 주세요."],
    "7 이 Mac에 설치돼 있지 않아요. 먼저 설치해 주세요": ["%@가 이 Mac에 설치돼 있지 않아요. 먼저 설치해 주세요", "%@이 이 Mac에 설치돼 있지 않아요. 먼저 설치해 주세요"],
    "7 바꿨어요": ["%@를 바꿨어요", "%@을 바꿨어요"], "켰어요": ["%@를 켰어요", "%@을 켰어요"], "껐어요": ["%@를 껐어요", "%@을 껐어요"],
    "7 누르면 들어요": ["%@를 누르면 들어요", "%@을 누르면 들어요"],
    "권한 ": ["권한 %d개가 더 필요해요"], "더 필요해요": ["권한 %d개가 더 필요해요"],
    "누른 채 화면에 동그라미를 그리면 그 부분을 같이 봐요": ["%@를 누른 채 화면에 동그라미를 그리면 그 부분을 같이 봐요", "%@을 누른 채 화면에 동그라미를 그리면 그 부분을 같이 봐요"],
    "7를 7": ["말하기 단축키를 누른 채 화면에 동그라미를 그리면 그 부분을 같이 봐요"],
    " 아직 허용 안 됨.": ["%@ 아직 허용 안 됨."],
    " 포인터로 열지 않을 땐 늘 켜져 있어요.": ["노치 위에서 두 손가락으로 쓸어 열고 닫아요. 포인터로 열지 않을 땐 늘 켜져 있어요."],
    "7초": ["포인터가 %d초 머물면 열려요.", "일시 정지하고 %d초가 지나면 닫힌 노치에서 음악이 사라져요."],
    "%.1f초": ["포인터가 %d초 머물면 열려요.", "일시 정지하고 %d초가 지나면 닫힌 노치에서 음악이 사라져요."],
    "포인터가 7 머물면 열려요.": ["포인터가 %d초 머물면 열려요."], "보통의 %.1f배": ["보통의 %d배"],
    "일시 정지하고 7가 지나면 닫힌 노치에서 음악이 사라져요.": ["일시 정지하고 %d초가 지나면 닫힌 노치에서 음악이 사라져요."],
    "버전 ": ["버전 %@"], "초안이 형식에 맞지 않아요: ": ["초안이 형식에 맞지 않아요: %@"],
]

/// Whether a Korean literal of the sources has its English: by itself, or as a piece of lines that do.
private func enSettingsHasEnglish(_ literal: String, _ pairs: [String: String]) -> Bool {
    if enSettingsNotDrawn.contains(literal) { return true }
    if let lines = enSettingsPieces[literal] { return lines.allSatisfy { pairs[$0] != nil } }
    return ArisSettingsCopy.english(literal) != nil
}

private func enSettingsSourceTests() {
    let pairs = enSettingsPairs()
    for file in enSettingsFiles {
        let source = enSettingsSource(file)
        // The index's keywords are Korean words to type, matched and never shown: its titles are checked by name above.
        let literals = file.hasSuffix("ArisSettingsCatalog.swift")
            ? (ArisSettingsPage.allCases.flatMap { [$0.title, $0.subtitle] } + ArisSettingsGroup.allCases.map(\.rawValue) + ArisSettingsIndex.entries.map(\.title)).filter(enHasHangul)
            : enKoreanLiterals(source)
        let missing = literals.filter { !enSettingsHasEnglish($0, pairs) }
        check(!source.isEmpty && missing.isEmpty, "settings in English: every Korean string in \((file as NSString).lastPathComponent) has its English"
              + (missing.isEmpty ? "" : " (\(missing.count): \(missing.prefix(3)))"))
        let raw = enRawLines(source)
        check(raw.isEmpty, "settings in English: \((file as NSString).lastPathComponent) draws no Korean string past the wording" + (raw.isEmpty ? "" : " (\(raw.prefix(2)))"))
    }
    // The pages that draw themselves take the page's wording where they draw.
    for file in ["Aris/components/Settings/ArisSkillsPage.swift", "Aris/components/Settings/ArisSkillsCards.swift", "Aris/components/Settings/ArisVoicePicker.swift",
                 "Aris/components/Settings/ArisTeamPage.swift", "Aris/components/Settings/ArisTeammateInspector.swift"] {
        check(enSettingsSource(file).contains("@Environment(\\.arisWords) private var w"), "settings in English: \((file as NSString).lastPathComponent) words itself for the page")
    }
}

// MARK: - The helper's lines the 스킬 page shows (its sources are read here, never changed)

private func enSettingsHelperTests() {
    let pairs = enSettingsPairs()
    ArisSettingsCopy.install(pairs)
    // Left out: the prompts the helper gives a brain (they are never shown), and a line that is said to the brain.
    func shown(_ file: String, without drop: [String] = []) -> [String] {
        enKoreanLiterals(enSettingsSource(file)).filter { literal in !drop.contains { literal.contains($0) } }
    }
    let helper = shown("ArisAgent/ArisSkillArchive.swift") + shown("ArisAgent/ArisSkillFormat.swift") + shown("ArisAgent/ArisSkillInstaller.swift")
        + shown("ArisAgent/ArisSkillLink.swift") + shown("ArisAgent/ArisSkillProcess.swift") + shown("ArisAgent/ArisSkillRoutes.swift") + shown("ArisAgent/ArisSkillSetup.swift")
        // "해요체": the piece of each prompt that asks for Korean polite speech (the prompts ask for the app's language now).
        + shown("ArisAgent/ArisSkillTrials.swift", without: ["You write agent skills", "해요체"]) + shown("ArisAgent/ArisSkillFolder.swift") + shown("ArisAgent/ArisSkills+Add.swift")
        + shown("ArisAgent/ArisSkillCheck.swift", without: ["You review an agent skill", "해요체"])
        + shown("ArisAgent/ArisSkills.swift", without: ["Skills are switched off"])
    let left = helper.filter { !enSettingsHasEnglish($0, pairs) }
    check(helper.count > 90 && left.isEmpty, "스킬 in English: every line the helper can answer the page with has its English (\(helper.count))" + (left.isEmpty ? "" : " (\(left.count): \(left.prefix(3)))"))
    let w = ArisSettingsWording.make(page: .skills, english: true)
    check(w("너무 커요 (파일 400개 넘음).") == "It is too big (more than 400 files)." && w("초안이 형식에 맞지 않아요: SKILL.md에 description이 없어요.") == "The draft isn't in the right form: SKILL.md has no description."
          && w("다운로드가 12MB에서 끊겼어요. 인터넷 연결을 확인하고 다시 시도해 주세요.") == "The download stopped at 12MB. Check the internet connection and try again."
          && w("스킬 이름 ‘My Skill’은 쓸 수 없어요. 소문자, 숫자, 하이픈만 돼요.") == "The skill name “My Skill” can't be used. Only lowercase letters, digits and hyphens work.",
          "스킬 in English: the helper's reasons keep their names and numbers, one reason inside another too")
}

// MARK: - 팀원: the lines its own catalog doesn't hold

private func enSettingsTeamTests() {
    let w = ArisSettingsWording.make(page: .team, english: true)
    let mate = ArisTeammate(id: "mate-a", name: "Cody", routing: "", instructions: "", look: .standard, brain: "codex", scopes: [], memoryFile: "teammates/mate-a.md")
    let problems = ["\u{200B}Cody", " ", "a<b", String(repeating: "가", count: 40), "Aris", "cody"].compactMap { ArisTeamEditing.nameProblem($0, id: "other", in: [mate]) }
        + ["name", "duplicateName", "role", "instructions", "scopes", "look", "brain", "tooMany", "?"].map(ArisTeamEditing.problemText)
        + [ArisTeamSaveRule.failedNotice(putBack: true), ArisTeamSaveRule.failedNotice(putBack: false), ArisTeamEditing.mainRole]
    let left = problems.filter { enHasHangul(w($0)) }
    check(problems.count == 18 && left.isEmpty, "팀원 in English: a name's problem, a refused save and Aris's own row are English" + (left.isEmpty ? "" : " (\(left.prefix(3)))"))
    check(w(ArisTeamEditing.problemText("tooMany")) == "A team has up to \(ArisTeamEditing.maxTeammates) teammates."
          && w(ArisTeamEditing.problemText("name")) == "A name is up to 12 letters (6 in Korean).",
          "팀원 in English: the limits are said with their numbers")
    check(ArisSettingsWording.korean(ArisTeamEditing.problemText("role")) == ArisTeamEditing.problemText("role"), "팀원: in Korean its lines are as written")
}
