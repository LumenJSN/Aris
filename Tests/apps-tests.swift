// Tests for jv-apps (Core 2's app layer): app.find's name resolution (Korean and English names, nicknames,
// jamo-level near misses, particles, learned aliases, web services, the one short question), the channels read from
// real files (scripting dictionaries recorded with `sdef` from /System/Applications, Info.plists, an App Intents
// metadata file) and from hand-written menu-bar trees, command search in both languages, the channel choice with
// macOS permission prompts counted as a cost (with and without the Automation grant, a background task, a denied
// grant recorded), and every capability end to end against a fake workspace, Accessibility and engine. Nothing here
// touches a real app: the live seams are only read for bundle files. Called from main.swift; uses its check().
import Foundation

private let appsFixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/apps")
private func appsFixture(_ name: String) -> Data { (try? Data(contentsOf: appsFixtures.appendingPathComponent(name))) ?? Data() }
private func appsMenu(_ name: String) -> ArisApps.MenuBar { (try? JSONDecoder().decode(ArisApps.MenuBar.self, from: appsFixture(name))) ?? ArisApps.MenuBar(menus: []) }

func runAppsTests() {
    appsTextTests()
    appsFindTests()
    appsFileChannelTests()
    appsCommandSearchTests()
    appsChannelChoiceTests()
    appsReadTests()
    appsRecipeTests()
    appsSpecTests()
    appsHandsTests()
    appsRiskTests()
    appsLiveReadOnlyTests()
}

// MARK: - Text

private func appsTextTests() {
    let T = ArisApps.Text.self
    check(T.jamo("카톡") == Array("ㅋㅏㅌㅗㄱ"), "apps text: 카톡 decomposes into its jamo")
    check(T.core("카톡 앱") == "카톡" && T.core("the Notes app") == "notes" && T.core("Google Chrome") == "googlechrome", "apps text: 'app' words and spacing never matter")
    check(T.forms("크롬에서").contains("크롬") && T.forms("카톡을").contains("카톡"), "apps text: a trailing particle is dropped")
    check(T.similarity("슬랙", "스랙") >= 0.9 && T.similarity("까톡", "카톡") >= 0.9 && T.similarity("엑셀", "액셀") >= 0.9, "apps text: loanword variants are near")
    check(T.similarity("메모", "메일") < 0.75 && T.similarity("노트", "노션") < 0.75, "apps text: different names are not near")
    check(T.soundsLike("피그마", "Figma") >= 0.99 && T.soundsLike("깃허브", "GitHub") >= 0.9 && T.soundsLike("레이캐스트", "Raycast") >= 0.99,
          "apps text: a Hangul spelling meets the English name by sound")
    check(T.soundsLike("피그마", "Notion") < 0.5, "apps text: unrelated names don't sound alike")
}

// MARK: - app.find

private let appsInstalled: [ArisApps.AppRecord] = [
    .init(bundle: "com.kakao.KakaoTalkMac", names: ["KakaoTalk", "카카오톡"], path: "/Applications/KakaoTalk.app"),
    .init(bundle: "com.google.Chrome", names: ["Google Chrome"], path: "/Applications/Google Chrome.app"),
    .init(bundle: "com.hnc.Discord", names: ["Discord"], path: "/Applications/Discord.app"),
    .init(bundle: "com.hnc.DiscordPTB", names: ["Discord PTB"], path: "/Applications/Discord PTB.app"),
    .init(bundle: "com.microsoft.Powerpoint", names: ["Microsoft PowerPoint"], path: "/Applications/Microsoft PowerPoint.app"),
    .init(bundle: "com.apple.Notes", names: ["Notes", "메모"], path: "/System/Applications/Notes.app"),
    .init(bundle: "com.apple.reminders", names: ["Reminders", "미리 알림"], path: "/System/Applications/Reminders.app"),
    .init(bundle: "com.apple.TextEdit", names: ["TextEdit", "텍스트 편집기"], path: "/System/Applications/TextEdit.app"),
    .init(bundle: "com.apple.Safari", names: ["Safari"], path: "/Applications/Safari.app"),
    .init(bundle: "com.apple.systempreferences", names: ["System Settings", "시스템 설정"], path: "/System/Applications/System Settings.app"),
    .init(bundle: "com.apple.MobileSMS", names: ["Messages", "메시지"], path: "/System/Applications/Messages.app"),
    .init(bundle: "com.apple.dt.Xcode", names: ["Xcode"], path: "/Applications/Xcode.app"),
    .init(bundle: "com.microsoft.teams2", names: ["Microsoft Teams"], path: "/Applications/Microsoft Teams.app"),
    .init(bundle: "com.microsoft.teams", names: ["Microsoft Teams classic"], path: "/Applications/Microsoft Teams classic.app"),
    .init(bundle: "com.raycast.macos", names: ["Raycast"], path: "/Applications/Raycast.app"),
    .init(bundle: "com.spotify.client", names: ["Spotify"], path: "/Applications/Spotify.app"),
    .init(bundle: "com.apple.finder", names: ["Finder"], path: "/System/Library/CoreServices/Finder.app"),
]

private func appsAnswer(_ said: String, apps: [ArisApps.AppRecord] = appsInstalled, aliases: ArisApps.Aliases = .init()) -> ArisApps.Find.Answer {
    ArisApps.Find.answer(ArisApps.Find.rank(said, apps: apps, aliases: aliases))
}

private func appsBundle(_ answer: ArisApps.Find.Answer) -> String? {
    if case .app(let match) = answer { return match.bundle }
    return nil
}

private func appsFindTests() {
    let expected: [(String, String)] = [
        ("카톡", "com.kakao.KakaoTalkMac"), ("카카오톡", "com.kakao.KakaoTalkMac"), ("까톡", "com.kakao.KakaoTalkMac"), ("카톡을", "com.kakao.KakaoTalkMac"),
        ("KakaoTalk", "com.kakao.KakaoTalkMac"), ("크롬", "com.google.Chrome"), ("크롬에서", "com.google.Chrome"), ("chrome", "com.google.Chrome"),
        ("chorme", "com.google.Chrome"), ("디코", "com.hnc.Discord"), ("디스코드", "com.hnc.Discord"), ("Discord", "com.hnc.Discord"),
        ("파포", "com.microsoft.Powerpoint"), ("피피티", "com.microsoft.Powerpoint"), ("메모", "com.apple.Notes"), ("메모 앱", "com.apple.Notes"),
        ("미리알림", "com.apple.reminders"), ("미리 알림", "com.apple.reminders"), ("텍스트 편집기", "com.apple.TextEdit"), ("텍스트편집기", "com.apple.TextEdit"),
        ("사파리", "com.apple.Safari"), ("설정", "com.apple.systempreferences"), ("시스템 설정", "com.apple.systempreferences"), ("문자", "com.apple.MobileSMS"),
        ("엑스코드", "com.apple.dt.Xcode"), ("스포티파이", "com.spotify.client"), ("스포티화이", "com.spotify.client"), ("파인더", "com.apple.finder"),
        ("com.apple.TextEdit", "com.apple.TextEdit"),
    ]
    for (said, bundle) in expected {
        check(appsBundle(appsAnswer(said)) == bundle, "apps find: ‘\(said)’ is \(bundle)")
    }
    // Two installed apps with the same nickname: one short question, never a guess.
    if case .ask(let both) = appsAnswer("팀즈") {
        check(Set(both.compactMap(\.bundle)) == ["com.microsoft.teams2", "com.microsoft.teams"], "apps find: 팀즈 with both Teams installed asks between them")
        let question = ArisApps.Find.question("팀즈", both)
        check(question.ko.contains("Microsoft Teams classic") && question.ko.hasSuffix("중 어느 앱인가요?") && question.en.hasPrefix("Which app"),
              "apps find: the question names both, Korean first")
    } else { check(false, "apps find: 팀즈 with both Teams installed asks between them") }
    // A web service people say by name, with no app for it: the browser and its address.
    if case .web(let match) = appsAnswer("유튜브") { check(match.web == "https://www.youtube.com", "apps find: 유튜브 is YouTube on the web") }
    else { check(false, "apps find: 유튜브 is YouTube on the web") }
    if case .web(let match) = appsAnswer("노션") { check(match.web?.contains("notion.so") == true, "apps find: 노션 with no Notion app opens its web app") }
    else { check(false, "apps find: 노션 with no Notion app opens its web app") }
    if case .notInstalled(let match) = appsAnswer("한컴") { check(match.name == "Hancom Office HWP", "apps find: 한컴 not installed says so") }
    else { check(false, "apps find: 한컴 not installed says so") }
    // The best is not installed but an installed app also fits: asked, not opened on the web or guessed.
    if case .ask(let options) = appsAnswer("코드") {
        check(options.map(\.name).contains("Visual Studio Code") && options.contains { $0.bundle == "com.apple.dt.Xcode" }, "apps find: 코드 without VS Code asks VS Code or Xcode")
    } else { check(false, "apps find: 코드 without VS Code asks VS Code or Xcode") }
    // Only a sound-alike: asked as a guess.
    if case .ask(let guess) = appsAnswer("레이캐스트") {
        check(guess.count == 1 && guess[0].bundle == "com.raycast.macos" && ArisApps.Find.question("레이캐스트", guess).ko.contains("Raycast 말씀이세요"),
              "apps find: 레이캐스트 is a guess at Raycast, asked once")
    } else { check(false, "apps find: 레이캐스트 is a guess at Raycast, asked once") }
    check(appsAnswer("완전히없는앱") == .none && appsAnswer("") == .none, "apps find: nothing by that name")
    // The owner's correction, learned and forgotten.
    let taught = ArisApps.Aliases().learning("내 메신저", bundle: "com.kakao.KakaoTalkMac")
    check(appsBundle(appsAnswer("내 메신저", aliases: taught)) == "com.kakao.KakaoTalkMac" && appsBundle(appsAnswer("내 메신저를", aliases: taught)) == "com.kakao.KakaoTalkMac",
          "apps find: a learned alias resolves (with a particle too)")
    check(appsBundle(appsAnswer("내 메신저", aliases: taught.forgetting("내 메신저"))) == nil, "apps find: a forgotten alias no longer resolves")
    let override = ArisApps.Aliases().learning("디코", bundle: "com.hnc.DiscordPTB")
    check(appsBundle(appsAnswer("디코", aliases: override)) == "com.hnc.DiscordPTB", "apps find: a learned alias beats the catalog")
    // A running app wins a tie.
    let twins: [ArisApps.AppRecord] = [.init(bundle: "a.one", names: ["Writer One"]), .init(bundle: "a.two", names: ["Writer Two"], running: true)]
    check(ArisApps.Find.rank("writer", apps: twins).first?.bundle == "a.two", "apps find: a running app ranks first in a tie")
    // The catalog's rows are well formed.
    let rows = ArisApps.Catalog.rows
    check(rows.allSatisfy { !$0.name.isEmpty && !$0.says.isEmpty && ($0.bundles.isEmpty == ($0.web != nil) || !$0.bundles.isEmpty) },
          "apps find: every catalog row has a name, nicknames and a bundle or a web address")
    let nicknames = rows.flatMap { row in row.says.map { (ArisApps.Text.core($0), row.name) } }
    let clashes = Dictionary(grouping: nicknames, by: \.0).filter { Set($0.value.map(\.1)).count > 1 }.keys.sorted()
    check(clashes.isEmpty, "apps find: no nickname belongs to two catalog rows \(clashes)")
}

// MARK: - Channels from real files

private func appsFileChannelTests() {
    let standard: (String) -> Data? = { $0.hasSuffix("CocoaStandard.sdef") ? appsFixture("CocoaStandard.sdef") : nil }
    let rawNotes = ArisApps.Sdef.parse(appsFixture("sdef-Notes.xml"))
    check(rawNotes?.includes.first?.path == "/System/Library/ScriptingDefinitions/CocoaStandard.sdef" && rawNotes?.commands.contains { $0.name == "make" } == false,
          "apps sdef: an include left in the file is listed")
    let mailInclude = ArisApps.Sdef.parse(appsFixture("sdef-Mail.xml"))?.includes.first
    check(mailInclude?.excluded == ["delete", "duplicate", "move"], "apps sdef: the commands an include leaves out")
    guard let textEdit = ArisApps.Sdef.parse(appsFixture("sdef-TextEdit.xml")), let notes = rawNotes?.resolved(standard),
          let finder = ArisApps.Sdef.parse(appsFixture("sdef-Finder.xml")), let messages = ArisApps.Sdef.parse(appsFixture("sdef-Messages.xml"))?.resolved(standard),
          let reminders = ArisApps.Sdef.parse(appsFixture("sdef-Reminders.xml"))?.resolved(standard), let music = ArisApps.Sdef.parse(appsFixture("sdef-Music.xml")),
          let mail = ArisApps.Sdef.parse(appsFixture("sdef-Mail.xml"))?.resolved(standard) else {
        check(false, "apps sdef: the recorded dictionaries parse")
        return
    }
    check(Set(["close", "save", "make", "quit", "print"]).isSubset(of: Set(textEdit.commands.map(\.name))), "apps sdef: TextEdit's standard commands")
    check(textEdit.classNamed("document")?.properties.contains { $0.name == "text" } == true, "apps sdef: TextEdit's document gains `text` from its class-extension")
    check(Set(["note", "folder", "account"]).isSubset(of: Set(notes.topElements)), "apps sdef: Notes holds notes, folders and accounts")
    check(notes.classNamed("note")?.properties.contains { $0.name == "body" && $0.writable } == true, "apps sdef: a note's body can be set")
    check(reminders.topElements.contains("reminder") || reminders.topElements.contains("list"), "apps sdef: Reminders holds reminders or lists")
    check(music.commands.contains { $0.name == "play" } && music.commands.contains { $0.name == "next track" }, "apps sdef: Music plays and skips")
    check(!finder.commands.contains { $0.name.isEmpty } && finder.commands.contains { $0.name == "empty" }, "apps sdef: Finder's empty (the trash)")
    let finderCommands = ArisApps.Commands.fromSdef(finder)
    check(finderCommands.first { $0.id == "sdef:empty" }?.effect == .changePermanent, "apps sdef: emptying Finder's trash is permanent")
    check(ArisApps.Commands.fromSdef(messages).first { $0.id == "sdef:send" }?.effect == .outward, "apps sdef: Messages' send is outward")
    check(ArisApps.Commands.fromSdef(mail).first { $0.id == "sdef:send" }?.effect == .outward && ArisApps.Commands.fromSdef(mail).first { $0.id == "sdef:reply" }?.effect == .changeReversible,
          "apps sdef: Mail's send is outward, its reply only makes a draft")
    let noteCommands = ArisApps.Commands.fromSdef(notes)
    check(noteCommands.contains { $0.id == "sdef:make:note" && $0.parameters.contains("body") } && noteCommands.first { $0.id == "sdef:list:note" }?.effect == .observe,
          "apps sdef: make new note and list notes")
    check(ArisApps.Sdef.parse(Data("not xml".utf8)) == nil, "apps sdef: garbage is no dictionary")
    let hidden = """
    <dictionary><suite name="S" code="aaaa"><command name="shown" code="aaaabbbb"/><command name="secret" code="aaaacccc" hidden="yes"/></suite>\
    <suite name="H" code="bbbb" hidden="yes"><command name="also" code="bbbbcccc"/></suite></dictionary>
    """
    check(ArisApps.Sdef.parse(Data(hidden.utf8))?.commands.map(\.name) == ["shown"], "apps sdef: hidden terms are left out")

    // Scripts: only dictionary terms, every value quoted.
    let made = try? ArisApps.Script.make("note", bundle: "com.apple.Notes", dictionary: notes, properties: ["name": .string("장보기"), "body": .string("우유 \"2\" \\ 끝")])
    check(made == "tell application id \"com.apple.Notes\" to make new note with properties {body:\"우유 \\\"2\\\" \\\\ 끝\", name:\"장보기\"}",
          "apps script: make new note, its values quoted")
    let injected = try? ArisApps.Script.make("note", bundle: "com.apple.Notes", dictionary: notes, properties: ["name": .string("x\" & (do shell script \"rm -rf ~\") & \"")])
    check(injected?.contains("\\\" & (do shell script \\\"rm") == true && injected?.hasSuffix("& \\\"\"}") == true, "apps script: a value can't become code")
    check((try? ArisApps.Script.make("note", bundle: "com.apple.Notes", dictionary: notes, properties: ["do shell script": .string("x")])) == nil,
          "apps script: a property the class doesn't have is refused")
    check((try? ArisApps.Script.make("note\"x", bundle: "com.apple.Notes", dictionary: notes, properties: [:])) == nil, "apps script: a class that isn't a term is refused")
    let sent = try? ArisApps.Script.command("send", bundle: "com.apple.MobileSMS", dictionary: messages, direct: .string("곧 도착"),
                                             parameters: ["to": .object(["class": .string("participant"), "name": .string("엄마")])])
    check(sent == "tell application id \"com.apple.MobileSMS\" to send \"곧 도착\" to participant \"엄마\"", "apps script: Messages' send to a participant by name")
    check((try? ArisApps.Script.list("note", bundle: "com.apple.Notes", dictionary: notes)) == "tell application id \"com.apple.Notes\" to get name of every note",
          "apps script: list every note's name")
    check((try? ArisApps.Script.command("frobnicate", bundle: "x", dictionary: notes, direct: nil, parameters: [:])) == nil, "apps script: an unknown command is refused")

    // App Intents (Notes' metadata, trimmed to six actions).
    let intents = ArisApps.Intents.parse(appsFixture("intents-Notes.json"))
    check(intents.count == 6 && intents.first { $0.id == "CreateNoteLinkAction" }?.title == "Create Note", "apps intents: Notes' actions with their titles")
    check(intents.first { $0.id == "OpenNoteLinkAction" }?.opensApp == true && intents.first { $0.id == "CreateNoteLinkAction" }?.parameters.contains("contents") == true,
          "apps intents: whether it opens the app, and its parameters")
    let intentCommands = ArisApps.Commands.fromIntents(intents, shortcuts: ["Create Note"])
    check(intentCommands.first { $0.id == "intent:CreateNoteLinkAction" }?.channel == .shortcut && intentCommands.first { $0.id == "intent:PinNotesLinkAction" }?.runnable == false,
          "apps intents: an intent an owner's Shortcut is named for runs through it; the rest are shown, not run")
    check(intentCommands.first { $0.id == "intent:DeleteNotesLinkAction" }?.effect == .changePermanent, "apps intents: deleting notes is permanent")

    // Info.plist: names, schemes, documents, Services.
    let info = ArisApps.BundleInfo.parse(infoPlist: appsFixture("info-TextEdit.plist"), loctable: appsFixture("loctable-TextEdit.plist"))
    check(info?.bundle == "com.apple.TextEdit" && info?.localizedNames["ko"] == "텍스트 편집기" && info?.names.contains("텍스트 편집기") == true,
          "apps bundle: TextEdit's Korean name from its loctable")
    check(info?.scriptable == true && info?.documents.isEmpty == false && info?.services.isEmpty == false, "apps bundle: TextEdit is scriptable and has documents and Services")
    check(info?.versionKey.hasPrefix("com.apple.TextEdit@") == true, "apps bundle: the cache key carries the version")
    let notesInfo = ArisApps.BundleInfo.parse(infoPlist: appsFixture("info-Notes.plist"))
    check(notesInfo?.schemes.contains("notes") == true && notesInfo?.schemes.contains("applenotes") == true, "apps bundle: Notes' URL schemes")
    check(ArisApps.Commands.fromBundle(notesInfo!).contains { $0.id == "url:applenotes" && $0.channel == .url }, "apps bundle: a URL scheme is a command")
    let strings = Data("\"CFBundleDisplayName\" = \"카카오톡\";".utf8)
    check(ArisApps.BundleInfo.parse(infoPlist: try! PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "k", "CFBundleName": "KakaoTalk"], format: .xml, options: 0),
                                    strings: ["ko": strings])?.localizedNames["ko"] == "카카오톡", "apps bundle: a Korean name from ko.lproj/InfoPlist.strings")

    // Menu bars (hand-written trees in Accessibility's shape).
    let textMenu = appsMenu("menu-TextEdit.json")
    check(textMenu.item(at: ["Edit", "Find", "Find and Replace…"])?.shortcut == "⌥⌘F" && textMenu.item(at: ["File", "Duplicate"])?.shortcut == "⇧⌘S",
          "apps menu: key equivalents with their modifiers")
    check(textMenu.item(at: ["edit", "find", "find and replace..."]) != nil, "apps menu: paths compare without case and with ... as …")
    check(textMenu.item(at: ["Edit", "Spelling and Grammar", "Check Spelling While Typing"])?.checked == true && textMenu.item(at: ["Edit", "Redo"])?.enabled == false,
          "apps menu: checkmarks and greyed-out items")
    check(ArisApps.MenuBar.path("File › Export as PDF…") == ["File", "Export as PDF…"] && ArisApps.MenuBar.path("파일 > 새로운 폴더") == ["파일", "새로운 폴더"], "apps menu: a written path")
    let leaves = ArisApps.Commands.fromMenu(textMenu)
    check(leaves.contains { $0.id == "menu:file>exportaspdf…" || $0.id == "menu:file>exportaspdf" } && leaves.allSatisfy { $0.channel == .menu },
          "apps menu: every item is a command with a path id")
    check(leaves.first { $0.title == "Undo Typing" }?.keys == "⌘Z", "apps menu: a command keeps its keys")
}

// MARK: - Search

private func appsTop(_ query: String, _ menu: String) -> ArisApps.Command? {
    ArisApps.Commands.search(query, in: ArisApps.Commands.fromMenu(appsMenu(menu))).first?.command
}

private func appsCommandSearchTests() {
    let cases: [(String, String, String)] = [
        ("새 창", "menu-Finder-ko.json", "새로운 Finder 윈도우"), ("새 창 열어", "menu-Finder-ko.json", "새로운 Finder 윈도우"),
        ("new window", "menu-Finder-ko.json", "새로운 Finder 윈도우"), ("새 폴더 만들어", "menu-Finder-ko.json", "새로운 폴더"),
        ("새 탭", "menu-Finder-ko.json", "새로운 탭"), ("undo", "menu-Finder-ko.json", "실행 취소"), ("실행취소", "menu-Finder-ko.json", "실행 취소"),
        ("휴지통 비워", "menu-Finder-ko.json", "휴지통 비우기…"), ("다운로드 폴더로 가", "menu-Finder-ko.json", "다운로드"),
        ("사이드바 보여줘", "menu-Finder-ko.json", "사이드바 보기"), ("굵게", "menu-TextEdit.json", "Bold"), ("bold", "menu-TextEdit.json", "Bold"),
        ("전체 화면", "menu-TextEdit.json", "Enter Full Screen"), ("full screen", "menu-TextEdit.json", "Enter Full Screen"),
        ("확대", "menu-TextEdit.json", "Zoom In"), ("PDF로 내보내기", "menu-TextEdit.json", "Export as PDF…"), ("찾아서 바꾸기", "menu-TextEdit.json", "Find and Replace…"),
        ("인쇄", "menu-TextEdit.json", "Print…"), ("새 채팅", "menu-KakaoTalk-ko.json", "새로운 채팅"), ("new chat", "menu-KakaoTalk-ko.json", "새로운 채팅"),
        ("친구 추가", "menu-KakaoTalk-ko.json", "친구 추가"), ("새 메모", "menu-Notes.json", "New Note"), ("메모 고정", "menu-Notes.json", "Pin Note"),
    ]
    for (query, menu, title) in cases {
        let found = appsTop(query, menu)
        check(found?.title == title, "apps search: ‘\(query)’ finds \(title)" + (found.map { $0.title == title ? "" : " (got \($0.title))" } ?? " (got nothing)"))
    }
    let finder = ArisApps.Commands.fromMenu(appsMenu("menu-Finder-ko.json"))
    check(finder.first { $0.title == "휴지통 비우기…" }?.effect == .changePermanent && finder.first { $0.title == "휴지통으로 이동" }?.effect == .changeReversible,
          "apps search: emptying the trash is permanent, moving to it is not")
    check(ArisApps.Commands.search("완전히 관계없는 말", in: finder).isEmpty, "apps search: unrelated words find nothing")
    check(ArisApps.Commands.search(nil, in: finder, limit: 5).count == 5, "apps search: no query lists the commands in menu order")
    // A greyed-out item scores below the same item enabled.
    let lock = ArisApps.Commands.fromMenu(appsMenu("menu-Notes.json")).first { $0.title == "Lock Note" }!
    var unlocked = lock
    unlocked.enabled = true
    check(ArisApps.Commands.score("lock note", lock) < ArisApps.Commands.score("lock note", unlocked), "apps search: a greyed-out item scores lower")
}

// MARK: - Channel choice: permission prompts are a cost

private func appsChannelChoiceTests() {
    let menu = ArisApps.Command(id: "menu:file>newnote", title: "New Note", detail: "File", channel: .menu, path: ["File", "New Note"], enabled: true, effect: .changeReversible)
    let sdef = ArisApps.Command(id: "sdef:make:note", title: "make new note", channel: .sdef, parameters: ["body"], effect: .changeReversible)
    let onlySdef = ArisApps.Command(id: "sdef:list:note", title: "list notes", channel: .sdef, effect: .observe)
    var record = ArisApps.AppChannels()
    record.automation = .granted
    let granted = ArisApps.Choice.plan(target: menu, alternatives: [sdef], record: record, background: false)
    check(granted.steps.first?.command.channel == .sdef && granted.steps.allSatisfy { !$0.prompts }, "apps channels: with the Automation grant the scripting dictionary goes first")
    record.automation = .notAsked
    let notAsked = ArisApps.Choice.plan(target: sdef, alternatives: [menu], record: record, background: false)
    check(notAsked.steps.map(\.command.channel) == [.menu, .sdef] && notAsked.steps.last?.prompts == true,
          "apps channels: without it the menu bar goes first even when the scripting command was asked for; the prompt is the last resort")
    record.automation = .unknown
    check(ArisApps.Choice.plan(target: sdef, alternatives: [menu], record: record, background: false).steps.first?.command.channel == .menu,
          "apps channels: an app that can't be asked yet is treated as not asked")
    record.automation = .denied
    let denied = ArisApps.Choice.plan(target: sdef, alternatives: [menu], record: record, background: false)
    check(denied.steps.map(\.command.channel) == [.menu], "apps channels: a denied grant is never tried (it fails silently)")
    check(ArisApps.Choice.plan(target: onlySdef, alternatives: [], record: record, background: false).blocked?.contains("turned off") == true,
          "apps channels: scripting-only with the grant denied says why")
    record.automation = .notAsked
    let background = ArisApps.Choice.plan(target: onlySdef, alternatives: [], record: record, background: true)
    check(background.steps.isEmpty && background.blocked?.contains("background task never brings up a prompt") == true,
          "apps channels: a background task never causes a prompt")
    record.automation = .granted
    check(ArisApps.Choice.plan(target: onlySdef, alternatives: [], record: record, background: true).steps.count == 1,
          "apps channels: a background task uses a grant that is already there")
    record.automation = .notAsked
    record.failed["menu"] = "the item didn't take the press"
    check(ArisApps.Choice.plan(target: menu, alternatives: [sdef], record: record, background: false).steps.map(\.command.channel) == [.sdef],
          "apps channels: a channel that failed for this app isn't tried again")
    var disabled = menu
    disabled.enabled = false
    check(ArisApps.Choice.plan(target: disabled, alternatives: [], record: ArisApps.AppChannels(), background: false).blocked?.contains("greyed out") == true,
          "apps channels: a greyed-out item isn't pressed")

    // The one sentence before a prompt: once per app, and the step waits for it.
    let plan = ArisApps.Choice.plan(target: onlySdef, alternatives: [], record: ArisApps.AppChannels(automation: .notAsked), background: false)
    if case .sayFirst(let notice, let english, _) = ArisApps.Choice.next(plan, at: 0, record: ArisApps.AppChannels(automation: .notAsked), appName: "Notes", goAhead: false) {
        check(notice.hasPrefix("Notes에 직접 명령하려면") && notice.count < 80 && english.contains("once"), "apps channels: one short sentence before the prompt, Korean first")
    } else { check(false, "apps channels: one short sentence before the prompt, Korean first") }
    check(ArisApps.Choice.next(plan, at: 0, record: ArisApps.AppChannels(automation: .notAsked), appName: "Notes", goAhead: true) == .run(plan.steps[0]),
          "apps channels: with the go-ahead the step runs")
    check(ArisApps.Choice.next(plan, at: 0, record: ArisApps.AppChannels(automation: .notAsked, noticeSaid: true), appName: "Notes", goAhead: false) == .run(plan.steps[0]),
          "apps channels: the sentence is said once per app, never again")
    check(ArisApps.Choice.next(plan, at: 1, record: ArisApps.AppChannels(), appName: "Notes", goAhead: false) == .done, "apps channels: past the last step")
    check(ArisApps.Choice.readOrder(grant: .notAsked) == ["ax", "vision"] && ArisApps.Choice.readOrder(grant: .granted).first == "ax",
          "apps channels: reading uses the Accessibility tree first, scripting only with the grant")

    // The book: what each app's channels did.
    var book = ArisApps.ChannelBook().noting("com.apple.Notes", grant: .granted)
    book = book.noting("com.apple.Notes", grant: .unknown)
    check(book.record("com.apple.notes").automation == .granted, "apps channels: a known grant isn't forgotten when the app quits")
    book = book.noting("com.apple.Notes", channel: .menu, worked: false, why: "x").seeing("com.apple.Notes", versionKey: "v1")
    check(book.record("com.apple.Notes").failed.isEmpty && book.record("com.apple.Notes").automation == .granted, "apps channels: a new version tries failed channels again")
    let saved = try? JSONDecoder().decode(ArisApps.ChannelBook.self, from: JSONEncoder().encode(book.notingNoticeSaid("com.apple.Notes")))
    check(saved?.record("com.apple.Notes").noticeSaid == true, "apps channels: the book survives a restart")
}

// MARK: - Reading

private func appsElements() -> [ArisApps.JSON] {
    func element(_ id: Int, _ role: String, _ label: String, value: String? = nil, x: Double, y: Double, w: Double = 100, h: Double = 20, acts: Bool = false) -> ArisApps.JSON {
        var object: [String: ArisApps.JSON] = ["id": .string("elem_\(id)"), "role": .string(role), "label": .string(label), "is_actionable": .bool(acts),
                                               "bounds": .object(["x": .number(x), "y": .number(y), "width": .number(w), "height": .number(h)])]
        if let value { object["value"] = .string(value) }
        return .object(object)
    }
    return [
        element(1, "row", "엄마", x: 10, y: 100, w: 200, acts: true), element(2, "row", "팀 채팅", x: 10, y: 130, w: 200, acts: true),
        element(3, "staticText", "", value: "저녁 먹었어?", x: 300, y: 120), element(4, "staticText", "", value: "응 먹었어", x: 500, y: 160),
        element(5, "textArea", "메시지 입력", value: "", x: 300, y: 600, w: 500, h: 40), element(6, "button", "보내기", x: 820, y: 600, acts: true),
        element(7, "searchField", "검색", x: 10, y: 50, w: 200), element(8, "secureTextField", "암호", value: "hunter2", x: 10, y: 700),
    ]
}

private func appsReadTests() {
    let elements = appsElements().compactMap(ArisApps.ReadElement.init)
    check(elements.count == 8 && elements[0].shortId == "e1", "apps read: the engine's elements with short ids")
    let all = ArisApps.Read.page(ArisApps.Read.pick(.all, from: elements))
    check(all.text.contains("[e6] button “보내기”") && all.text.contains("[e5] textArea “메시지 입력”") && !all.text.contains("hunter2"),
          "apps read: roles and labels kept; a secure field never shows its value")
    let lines = all.text.split(separator: "\n")
    check(lines.first?.contains("검색") == true, "apps read: reading order is top to bottom")
    let conversation = ArisApps.Read.pick(.conversation, from: elements).map(\.shortId)
    check(conversation == ["e3", "e4", "e5"], "apps read: a chat's visible conversation is right of the sidebar, above the field (\(conversation))")
    check(ArisApps.Read.pick(.list, from: elements).map(\.shortId) == ["e1", "e2"], "apps read: a list's rows")
    check(ArisApps.Read.pick(.controls, from: elements).contains { $0.shortId == "e6" }, "apps read: the controls")
    let small = ArisApps.Read.page(elements, offset: 0, limit: 60)
    check(small.next != nil && small.shown >= 1 && ArisApps.Read.page(elements, offset: small.next!, limit: 10_000).next == nil, "apps read: bounded, with where to continue")
    check(ArisApps.Read.locate("e6", in: elements) == .one(elements[5]), "apps read: an element by its id")
    check(ArisApps.Read.locate("보내기 버튼", in: elements) == .one(elements[5]), "apps read: an element by a Korean description")
    check(ArisApps.Read.locate("send button", in: elements) == .one(elements[5]), "apps read: an element by an English description of a Korean label")
    check(ArisApps.Read.locate("message field 메시지 입력", in: elements) == .one(elements[4]), "apps read: the message field")
    check(ArisApps.Read.locate("엄마", in: elements) == .one(elements[0]), "apps read: a conversation by the person's name")
    check(ArisApps.Read.locate("없는 것", in: elements) == .none, "apps read: nothing by that description")
    let twins = [ArisApps.ReadElement(id: "elem_1", role: "button", label: "삭제"), ArisApps.ReadElement(id: "elem_2", role: "button", label: "삭제")]
    if case .several(let both) = ArisApps.Read.locate("삭제", in: twins) { check(both.count == 2, "apps read: two of the same are asked about") }
    else { check(false, "apps read: two of the same are asked about") }
}

// MARK: - Recipes

private func appsRecipeTests() {
    check(ArisApps.Recipes.fill("mailto:{to}?subject={subject|url}", inputs: ["to": "a@b.c", "subject": "회의 & 점심"], last: nil) == "mailto:a@b.c?subject=%ED%9A%8C%EC%9D%98%20%26%20%EC%A0%90%EC%8B%AC",
          "apps recipes: inputs filled in, URL-encoded where asked")
    check(ArisApps.Recipes.fill("{last.path}", inputs: [:], last: .object(["data": .object(["items": .array([.object(["path": .string("/x/a.pdf")])])])])) == "/x/a.pdf",
          "apps recipes: the step before's result")
    check(ArisApps.Recipes.fill("{to}", inputs: [:], last: nil) == nil, "apps recipes: a missing input stops the template")
    check(ArisApps.Recipes.pane("블루투스") == "com.apple.BluetoothSettings" && ArisApps.Recipes.pane("다크 모드 설정") == "com.apple.Appearance-Settings.extension",
          "apps recipes: settings panes by name")
    check(ArisApps.Recipes.mailto(["to": "a@b.c"]) == "mailto:a@b.c" && ArisApps.Recipes.mailto(["to": "a@b.c", "body": "hi"]) == "mailto:a@b.c?body=hi",
          "apps recipes: a mailto with only what was given")
    check(ArisApps.Recipes.recipe("message.send")?.effect == .outward && ArisApps.Recipes.recipe("mail.send")?.effect == .outward
          && ArisApps.Recipes.recipe("mail.compose")?.effect == .changeReversible, "apps recipes: sending is declared outward, composing is not")
    let sendStep = ArisApps.Recipes.recipe("message.send")!.parts.first { $0.name == "send" }!.ways[0][0]
    check(sendStep.effect == .outward, "apps recipes: the step that sends is outward")
    check(ArisApps.Recipes.find("엄마한테 카톡 보내줘").first?.id == "message.send" && ArisApps.Recipes.find("노래 틀어줘").first?.id == "music.play",
          "apps recipes: found by the request's words")
    let known = Set(ArisApps.Specs.all.map(\.name)).union(["event", "files.find"])
    check(ArisApps.Recipes.all.allSatisfy { recipe in recipe.parts.allSatisfy { $0.ways.allSatisfy { $0.allSatisfy { known.contains($0.call) } } } },
          "apps recipes: every step names a capability")
    // The runner: alternatives in turn, a required part with nothing left stops it.
    var calls: [String] = []
    let outcome = ArisApps.Recipes.run(ArisApps.Recipes.recipe("message.send")!, inputs: ["app": "카톡", "to": "엄마", "text": "곧 도착"]) { name, arguments in
        calls.append(name + (arguments["target"]?.string.map { ":" + $0 } ?? ""))
        let fails = name == "app.click"
        return ArisApps.Outcome(ok: !fails, did: name, now: "", effect: .changeReversible)
    }
    check(outcome.ok && calls.prefix(3) == ["app.open", "app.click:엄마", "app.do"], "apps recipes: the conversation found another way when the list has no row (\(calls))")
    check(calls.contains("app.press") && outcome.effect == .outward, "apps recipes: the message is sent, outward")
    let stuck = ArisApps.Recipes.run(ArisApps.Recipes.recipe("note.create")!, inputs: ["text": "우유"]) { _, _ in .failure("no", effect: .changeReversible) }
    check(!stuck.ok && stuck.did.contains("stopped"), "apps recipes: every way failing stops it and says where")
    check(!ArisApps.Recipes.run(ArisApps.Recipes.recipe("message.send")!, inputs: ["app": "카톡"]) { _, _ in .failure("", effect: .observe) }.ok,
          "apps recipes: a missing required input")
}

// MARK: - Specs

private func appsSpecTests() {
    let specs = ArisApps.Specs.all
    let names = Set(specs.map(\.name))
    let wanted: Set<String> = ["app.find", "app.open", "app.quit", "app.hide", "app.focus", "app.running", "app.frontmost", "window.list", "window.move", "window.resize",
                               "window.tile", "window.space", "window.minimize", "window.close", "app.commands", "app.do", "app.read", "app.type", "app.click",
                               "app.press", "app.select", "app.scroll", "app.recipe", "app.alias"]
    check(wanted == names, "apps specs: every capability is an entry")
    check(specs.allSatisfy { $0.parameters["type"]?.string == "object" && $0.parameters["properties"]?.object != nil }, "apps specs: JSON Schema objects")
    check(specs.allSatisfy { $0.wireName.range(of: "^[a-zA-Z0-9_-]{1,64}$", options: .regularExpression) != nil }, "apps specs: wire names any provider takes")
    check(specs.allSatisfy { $0.summary.count >= 20 && $0.summary.count <= 320 }, "apps specs: one or two sentences each")
    let context = ArisApps.EffectContext(surface: { app, _ in app == "카톡" ? .chat : .plain }, label: { _, target in target == "e6" ? "보내기" : nil },
                                         command: { _, _, _ in nil }, pathKind: { $0.hasSuffix(".command") ? .runnable : .document })
    func effect(_ name: String, _ arguments: [String: ArisApps.JSON]) -> ArisApps.Effect { ArisApps.Spec.named(name)!.effect(.object(arguments), context) }
    check(effect("app.find", [:]) == .observe && effect("app.read", [:]) == .observe && effect("app.scroll", [:]) == .observe, "apps specs: looking is observe")
    check(effect("app.press", ["app": .string("카톡"), "keys": .string("return")]) == .outward && effect("app.press", ["app": .string("TextEdit"), "keys": .string("return")]) == .changeReversible,
          "apps specs: Return in a chat app is outward, elsewhere it isn't")
    check(effect("app.click", ["app": .string("카톡"), "target": .string("e6")]) == .outward, "apps specs: pressing a Send button is outward")
    check(effect("app.click", ["app": .string("x"), "target": .string("휴지통 비우기")]) == .changePermanent, "apps specs: pressing Empty Trash is permanent")
    check(effect("app.do", ["app": .string("Mail"), "command": .string("Message › Send")]) == .outward && effect("app.do", ["app": .string("x"), "command": .string("새 창")]) == .changeReversible,
          "apps specs: app.do's effect is its command's")
    check(effect("app.recipe", ["recipe": .string("message.send")]) == .outward && effect("app.recipe", ["recipe": .string("browser.search")]) == .changeReversible,
          "apps specs: a recipe's effect is declared")
    check(ArisApps.Spec.named("app_find")?.name == "app.find", "apps specs: found by wire name")
    check(ArisAppsFace.tools.count == specs.count && ArisAppsFace.tools.allSatisfy { $0.inputSchema["type"] as? String == "object" }, "apps face: every capability is a tool")
}

// MARK: - The capabilities, end to end, against fakes

private class AppsFakeSystem: ArisAppsSystem {
    var installed = appsInstalled
    var running: [ArisAppsRunning] = []
    var front: ArisAppsRunning?
    var opened: [ArisAppsOpenRequest] = []
    var grants: [String: ArisApps.Grant] = [:]
    var scripts: [String] = []
    var scriptAnswer: (ok: Bool, output: String, code: Int?) = (true, "장보기, 회의", nil)
    var promptAnswers: ArisApps.Grant?
    var infos: [String: ArisApps.BundleInfo] = [:]
    var sdefs: [String: Data] = [:]
    var intents: [String: Data] = [:]
    var quits: [Int32] = []
    var startsOnOpen: [String: ArisAppsRunning] = [:]

    func installedApps() -> [ArisApps.AppRecord] { installed }
    func runningApps() -> [ArisAppsRunning] { running }
    func frontmost() -> ArisAppsRunning? { front }
    func defaultBrowser() -> String? { "com.apple.Safari" }
    func open(_ request: ArisAppsOpenRequest) -> (ok: Bool, message: String) {
        opened.append(request)
        if let bundle = request.bundle, let app = startsOnOpen[bundle], !running.contains(app) { running.append(app) }
        return (true, "opened")
    }
    func quit(pid: Int32) -> Bool { quits.append(pid); running.removeAll { $0.pid == pid }; return true }
    func hide(pid: Int32) -> Bool { true }
    func activate(pid: Int32) -> Bool { front = running.first { $0.pid == pid }; return true }
    func bundleInfo(path: String) -> ArisApps.BundleInfo? { infos[path] }
    func scriptingDictionary(path: String) -> Data? { sdefs[path] }
    func intentsMetadata(path: String) -> Data? { intents[path] }
    func includedDictionary(path: String) -> Data? { path.hasSuffix("CocoaStandard.sdef") ? appsFixture("CocoaStandard.sdef") : nil }
    func shortcuts() -> [String] { [] }
    func runShortcut(_ name: String, input: String?) -> (ok: Bool, output: String) { (true, "") }
    func automation(bundle: String) -> ArisApps.Grant { grants[bundle] ?? .notAsked }
    func runScript(_ source: String, timeout: TimeInterval) -> (ok: Bool, output: String, code: Int?) {
        scripts.append(source)
        let bundle = source.split(separator: "\"").dropFirst().first.map(String.init) ?? ""
        if scriptAnswer.code == -1743 { grants[bundle] = .denied }
        // The prompt the script brought up was answered.
        if let answer = promptAnswers { grants[bundle] = answer }
        return scriptAnswer
    }
    var kinds: [String: ArisApps.PathKind] = [:]
    func pathKind(_ path: String) -> ArisApps.PathKind { kinds[path] ?? .document }
    func displays() -> [ArisApps.Rect] { [ArisApps.Rect(x: 0, y: 25, width: 1440, height: 875), ArisApps.Rect(x: 1440, y: 0, width: 1920, height: 1080)] }
}

private final class AppsFakeAX: ArisAppsAccessibility {
    var bars: [Int32: ArisApps.MenuBar] = [:]
    var pressed: [[String]] = []
    var onPress: (([String]) -> Void)?
    func menuBar(pid: Int32) -> ArisApps.MenuBar? { bars[pid] }
    func pressMenu(pid: Int32, path: [String]) -> (ok: Bool, message: String) {
        guard let item = bars[pid]?.item(at: path) else { return (false, "no menu item “\(path.last ?? "")”") }
        guard item.enabled else { return (false, "greyed out") }
        pressed.append(path)
        onPress?(path)
        return (true, "pressed")
    }
    func setFullScreen(pid: Int32, window: Int, on: Bool) -> Bool { true }
    var focused: [Int32: String] = [:]
    func focusedRole(pid: Int32) -> String? { focused[pid] ?? "textArea" }
}

private final class AppsFakeEngine: ArisAppsEngine {
    var windows: [String: [ArisApps.JSON]] = [:]
    var calls: [[String]] = []
    var elements: [ArisApps.JSON] = appsElements()
    var refuse: Set<String> = []
    /// Called with each run's arguments before it answers (exp11: a "type" changes what the field holds).
    var onRun: (([String]) -> Void)?

    static func window(_ id: Int, _ title: String, x: Double = 100, y: Double = 100, front: Bool = true) -> ArisApps.JSON {
        .object(["window_id": .number(Double(id)), "window_title": .string(title), "is_frontmost": .bool(front),
                 "bounds": .object(["x": .number(x), "y": .number(y), "width": .number(800), "height": .number(600)])])
    }

    func run(_ arguments: [String], background: Bool) -> ArisApps.JSON {
        calls.append(arguments + (background ? ["(background)"] : []))
        onRun?(arguments)
        if refuse.contains(arguments.first ?? "") { return .object(["success": .bool(false), "error": .object(["message": .string("refused")])]) }
        switch (arguments.first ?? "", arguments.dropFirst().first ?? "") {
        case ("window", "list"):
            let bundle = arguments.last ?? ""
            return .object(["success": .bool(true), "data": .object(["windows": .array(windows[bundle] ?? [])])])
        case ("window", "move"):
            let id = Int(arguments[3])!, x = Double(arguments[5])!, y = Double(arguments[7])!
            for (bundle, list) in windows {
                windows[bundle] = list.map { window in
                    guard window["window_id"]?.int == id, case .object(var object) = window, case .object(var bounds)? = object["bounds"] else { return window }
                    bounds["x"] = .number(x)
                    bounds["y"] = .number(y)
                    object["bounds"] = .object(bounds)
                    return .object(object)
                }
            }
            return .object(["success": .bool(true), "data": .object([:])])
        case ("see", _):
            return .object(["success": .bool(true), "data": .object(["snapshot_id": .string("ps1_test"), "window_title": .string("채팅"), "ui_elements": .array(elements)])])
        default:
            return .object(["success": .bool(true), "data": .object(["delivery": .string("ax-press")])])
        }
    }
}

private func appsHands() -> (ArisAppsHands, AppsFakeSystem, AppsFakeAX, AppsFakeEngine) {
    let system = AppsFakeSystem(), ax = AppsFakeAX(), engine = AppsFakeEngine()
    let hands = ArisAppsHands(system: system, ax: ax, engine: engine, store: ArisAppsMemoryStore())
    hands.pollSeconds = 0
    let notesPath = "/System/Applications/Notes.app"
    system.infos[notesPath] = ArisApps.BundleInfo.parse(infoPlist: appsFixture("info-Notes.plist"))
    system.sdefs[notesPath] = appsFixture("sdef-Notes.xml")
    system.intents[notesPath] = appsFixture("intents-Notes.json")
    let notes = ArisAppsRunning(bundle: "com.apple.Notes", name: "Notes", pid: 501)
    let kakao = ArisAppsRunning(bundle: "com.kakao.KakaoTalkMac", name: "KakaoTalk", pid: 502, active: true)
    system.running = [notes, kakao]
    system.front = kakao
    ax.bars[501] = appsMenu("menu-Notes.json")
    ax.bars[502] = appsMenu("menu-KakaoTalk-ko.json")
    engine.windows["com.apple.Notes"] = [AppsFakeEngine.window(11, "Notes")]
    engine.windows["com.kakao.KakaoTalkMac"] = [AppsFakeEngine.window(21, "채팅", x: 200)]
    return (hands, system, ax, engine)
}

private func appsHandsTests() {
    // app.do: the menu bar when the Automation grant isn't there, the effect checked.
    do {
        let (hands, system, ax, engine) = appsHands()
        ax.onPress = { path in if path.last == "New Note" { engine.windows["com.apple.Notes"]!.append(AppsFakeEngine.window(12, "New Note")) } }
        let done = hands.call("app.do", .object(["app": .string("메모"), "command": .string("새 메모")]))
        check(done.ok && done.channel == "menu" && ax.pressed == [["File", "New Note"]] && system.scripts.isEmpty,
              "apps do: ‘새 메모’ presses File › New Note; no script, so no prompt")
        check(done.verified && done.now.contains("New Note"), "apps do: what is true now: the new window")
        let asked = hands.call("app.do", .object(["app": .string("메모"), "command": .string("sdef:make:note"), "arguments": .object(["body": .string("우유")])]))
        check(asked.ok && asked.channel == "menu" && system.scripts.isEmpty, "apps do: a scripting command asked for runs as its menu twin while the grant isn't there")
    }
    // With the grant: the scripting dictionary first, in the background, with its answer.
    do {
        let (hands, system, ax, _) = appsHands()
        system.grants["com.apple.Notes"] = .granted
        let made = hands.call("app.do", .object(["app": .string("Notes"), "command": .string("sdef:make:note"), "arguments": .object(["body": .string("우유")])]))
        check(made.ok && made.channel == "sdef" && ax.pressed.isEmpty && system.scripts == ["tell application id \"com.apple.Notes\" to make new note with properties {body:\"우유\"}"],
              "apps do: with the grant, make new note runs by the scripting dictionary")
    }
    // Scripting only, no grant yet: one sentence first, then the prompt, then never again.
    do {
        let (hands, system, _, _) = appsHands()
        system.promptAnswers = .granted
        let first = hands.call("app.do", .object(["app": .string("Notes"), "command": .string("sdef:list:note")]))
        check(!first.ok && first.notice?.contains("허락") == true && system.scripts.isEmpty && first.data["needs"]?.string == "automation",
              "apps do: scripting-only and not granted: the sentence first, nothing run")
        let second = hands.call("app.do", .object(["app": .string("Notes"), "command": .string("sdef:list:note"), "permission_ok": .bool(true)]))
        check(second.ok && second.channel == "sdef" && system.scripts.count == 1 && second.now.contains("장보기"), "apps do: with the go-ahead it runs, with its answer")
        check(hands.record("com.apple.Notes").automation == .granted && hands.record("com.apple.Notes").noticeSaid, "apps do: the grant and the sentence are recorded")
        let third = hands.call("app.do", .object(["app": .string("Notes"), "command": .string("sdef:list:note")]))
        check(third.ok && third.notice == nil && system.scripts.count == 2, "apps do: the next time it just runs")
    }
    do {
        let (hands, system, _, _) = appsHands()
        let background = hands.call("app.do", .object(["app": .string("Notes"), "command": .string("sdef:list:note")]), context: .init(background: true))
        check(!background.ok && background.notice == nil && system.scripts.isEmpty && background.did.contains("background"),
              "apps do: a background task never causes a prompt, and says why")
    }
    do {
        let (hands, system, _, _) = appsHands()
        system.scriptAnswer = (false, "execution error: Not authorized to send Apple events to Notes. (-1743)", -1743)
        _ = hands.call("app.do", .object(["app": .string("Notes"), "command": .string("sdef:list:note"), "permission_ok": .bool(true)]))
        check(hands.record("com.apple.Notes").automation == .denied, "apps do: a refusal (-1743) is recorded as denied")
        let again = hands.call("app.do", .object(["app": .string("Notes"), "command": .string("sdef:list:note"), "permission_ok": .bool(true)]))
        check(!again.ok && system.scripts.count == 1 && again.did.contains("turned off"), "apps do: a denied app is never sent Apple Events again")
    }
    do {
        let (hands, _, ax, _) = appsHands()
        let unknown = hands.call("app.do", .object(["app": .string("Notes"), "command": .string("완전히 관계없는 일")]))
        check(!unknown.ok && unknown.did.contains("app.read") && ax.pressed.isEmpty, "apps do: no such command points at app.read, and presses nothing")
        let disabled = hands.call("app.do", .object(["app": .string("Notes"), "command": .string("File › Lock Note")]))
        check(!disabled.ok && ax.pressed.isEmpty, "apps do: a greyed-out item is not pressed")
        let ambiguous = hands.call("app.do", .object(["app": .string("팀즈"), "command": .string("새 창")]))
        check(ambiguous.question?.contains("중 어느 앱인가요") == true, "apps do: an ambiguous app name is one question")
    }
    // A command app not running: opened in the background first.
    do {
        let (hands, system, ax, _) = appsHands()
        system.running.removeAll { $0.bundle == "com.apple.Notes" }
        system.startsOnOpen["com.apple.Notes"] = ArisAppsRunning(bundle: "com.apple.Notes", name: "Notes", pid: 501)
        let done = hands.call("app.do", .object(["app": .string("메모"), "command": .string("새 메모")]))
        check(done.ok && system.opened.first?.front == false && ax.pressed.count == 1, "apps do: an app not running is opened in the background, then pressed")
    }
    // app.commands: every channel, searchable, cached per version.
    do {
        let (hands, _, _, _) = appsHands()
        let listed = hands.call("app.commands", .object(["app": .string("Notes"), "query": .string("새 메모")]))
        let first = listed.data["commands"]?.array?.first
        check(listed.ok && first?["title"]?.string.map { ["New Note", "make new note"].contains($0) } == true, "apps commands: ‘새 메모’ first (\(first?["title"]?.string ?? "-"))")
        let channels = listed.data["channels"]?.object ?? [:]
        check(channels["menu"] != nil && channels["sdef"] != nil && channels["intent"] != nil && channels["url"] != nil,
              "apps commands: the menu bar, the scripting dictionary, App Intents and URL schemes")
        check(listed.now.contains("would need macOS's permission once"), "apps commands: says which channels need a prompt")
        let some = hands.call("app.commands", .object(["app": .string("Notes"), "limit": .number(10)]))
        check((some.data["commands"]?.array?.count ?? 0) == 10 && some.did.contains("commands, 10 shown"), "apps commands: bounded, with how many there are")
        check(hands.store.cachedCommands(ArisApps.BundleInfo.parse(infoPlist: appsFixture("info-Notes.plist"))!.versionKey)?.contains { $0.id == "sdef:make:note" } == true,
              "apps commands: cached per app version")
    }
    // Reading and acting on what was read.
    do {
        let (hands, _, _, engine) = appsHands()
        let read = hands.call("app.read", .object(["app": .string("카톡"), "part": .string("conversation")]))
        check(read.ok && read.data["text"]?.string?.contains("[e3] staticText “저녁 먹었어?”") == true && read.channel == "ax", "apps read: the chat's conversation with ids")
        check(engine.calls.contains { $0.first == "see" && $0.contains("21") }, "apps read: the app's front window, read by the engine")
        let clicked = hands.call("app.click", .object(["app": .string("카톡"), "target": .string("e1")]))
        check(clicked.ok && engine.calls.contains { $0.starts(with: ["click", "--snapshot", "ps1_test", "--on", "elem_1"]) }, "apps click: by the id app.read gave")
        check(hands.effect("app.click", .object(["app": .string("카톡"), "target": .string("보내기")])) == .outward, "apps click: the Send button is outward before it runs")
        check(hands.effect("app.press", .object(["app": .string("카톡"), "keys": .string("return")])) == .outward
              && hands.effect("app.press", .object(["app": .string("메모"), "keys": .string("return")])) == .changeReversible, "apps press: Return sends only in a chat app")
        let typed = hands.call("app.type", .object(["app": .string("카톡"), "text": .string("곧 도착"), "target": .string("메시지 입력")]))
        check(typed.ok && engine.calls.contains { $0.starts(with: ["click", "--snapshot", "ps1_test", "--on", "elem_5"]) }
              && engine.calls.contains { $0.starts(with: ["type", "--text", "곧 도착", "--window-id", "21"]) }, "apps type: the field focused, then the text typed")
        _ = hands.call("app.type", .object(["app": .string("카톡"), "text": .string("새 글"), "target": .string("e5"), "replace": .bool(true)]))
        check(engine.calls.contains { $0.starts(with: ["set-value", "--snapshot", "ps1_test", "--on", "elem_5", "--value", "새 글"]) }, "apps type: replace sets the value")
        let pressed = hands.call("app.press", .object(["app": .string("카톡"), "keys": .string("cmd+k return")]))
        check(pressed.ok && engine.calls.contains { $0.starts(with: ["press", "cmd+k", "return", "--window-id", "21"]) }, "apps press: keys to the app's window")
        let scrolled = hands.call("app.scroll", .object(["app": .string("카톡"), "target": .string("e3"), "direction": .string("up")]))
        check(scrolled.ok && engine.calls.contains { $0.starts(with: ["scroll", "--snapshot", "ps1_test", "--on", "elem_3", "--direction", "up"]) }, "apps scroll: by id")
        let many = hands.call("app.click", .object(["app": .string("카톡"), "target": .string("없는 버튼")]))
        check(!many.ok, "apps click: nothing by that description")
        // Tenth VM run, item 8: a long window read for one word is only the lines that hold it.
        let narrowed = hands.call("app.read", .object(["app": .string("카톡"), "find": .string("저녁")]))
        let whole = hands.call("app.read", .object(["app": .string("카톡")]))
        check(narrowed.ok && narrowed.data["text"]?.string?.contains("저녁 먹었어?") == true && (narrowed.data["total"]?.int ?? 0) >= 1
              && (narrowed.data["total"]?.int ?? 99) < (whole.data["total"]?.int ?? 0)
              && narrowed.data["text"]?.string?.split(separator: "\n").allSatisfy { $0.contains("저녁") } == true, "apps read: find narrows the read to the lines holding the word")
        _ = hands.call("app.read", .object(["app": .string("카톡")]), context: .init(background: true))
        check(engine.calls.last?.last == "(background)", "apps read: a background task's calls go to the engine as a job (never forward)")
    }
    do {
        let (hands, _, _, engine) = appsHands()
        engine.elements = []
        let empty = hands.call("app.read", .object(["app": .string("카톡")]))
        check(empty.channel == "vision" && engine.calls.contains { $0.first == "see" && $0.contains("--path") }, "apps read: an empty tree falls to a picture of the window")
    }
    // Apps and windows.
    do {
        let (hands, system, _, engine) = appsHands()
        let youtube = hands.call("app.open", .object(["app": .string("유튜브")]))
        check(youtube.ok && system.opened.last?.url == "https://www.youtube.com" && system.opened.last?.front == false, "apps open: 유튜브 opens in the browser, in the background")
        _ = hands.call("app.open", .object(["app": .string("메모"), "front": .bool(true)]), context: .init(background: true))
        check(system.opened.last?.front == false, "apps open: a background task never brings anything forward")
        _ = hands.call("app.open", .object(["url": .string("spotify:search:아이유")]))
        check(system.opened.last?.url == "spotify:search:아이유", "apps open: an app's own link")
        check(!hands.call("app.open", .object(["url": .string("그냥 글자")])).ok, "apps open: words that aren't a URL")
        let quit = hands.call("app.quit", .object(["app": .string("메모")]))
        check(quit.ok && quit.verified && system.quits == [501], "apps quit: asked, and seen to quit")
        check(!hands.call("app.focus", .object(["app": .string("카톡")]), context: .init(background: true)).ok, "apps focus: never from a background task")
        let focus = hands.call("app.focus", .object(["app": .string("카톡")]))
        check(focus.ok && focus.verified, "apps focus: brought forward when asked")
        let running = hands.call("app.running", .object([:]))
        check(running.data["apps"]?.array?.count == 1, "apps running: the running list")
        let left = hands.call("window.move", .object(["app": .string("카톡"), "to": .string("left")]))
        check(left.ok && engine.calls.contains { $0.starts(with: ["window", "move", "--window-id", "21", "--x", "0", "--y", "25"]) }
              && engine.calls.contains { $0.starts(with: ["window", "resize", "--window-id", "21", "--width", "720", "--height", "875"]) }, "apps window: the left half of its display")
        check(left.verified, "apps window: the move is read back")
        let next = hands.call("window.move", .object(["app": .string("카톡"), "to": .string("next-display")]))
        check(next.ok && engine.calls.last { $0.starts(with: ["window", "move"]) }.map { Int($0[5])! >= 1440 } == true, "apps window: onto the next display")
        check(!hands.call("window.move", .object(["app": .string("카톡"), "to": .string("somewhere")])).ok, "apps window: a place it doesn't know")
        let list = hands.call("window.list", .object(["app": .string("카톡")]))
        check(list.data["windows"]?.array?.first?["id"]?.int == 21, "apps window: the app's windows with ids")
        let space = hands.call("window.space", .object(["app": .string("카톡"), "to": .string("desktop 3")]))
        check(!space.ok && space.did.contains("no public way"), "apps window: a numbered desktop is said plainly to be impossible")
        engine.windows["com.apple.Notes"] = [AppsFakeEngine.window(11, "Notes")]
        system.running.append(ArisAppsRunning(bundle: "com.apple.Notes", name: "Notes", pid: 501))
        let tiled = hands.call("window.tile", .object(["apps": .array([.string("카톡"), .string("메모")])]))
        check(tiled.ok && tiled.did == "tiled 2 of 2 windows", "apps window: two apps side by side")
    }
    // Recipes through the capabilities.
    do {
        let (hands, system, _, engine) = appsHands()
        let sent = hands.call("app.recipe", .object(["recipe": .string("message.send"), "inputs": .object(["app": .string("카톡"), "to": .string("엄마"), "text": .string("곧 도착")])]))
        check(sent.ok && sent.effect == .outward, "apps recipe: a KakaoTalk message, declared outward")
        check(engine.calls.contains { $0.starts(with: ["click", "--snapshot", "ps1_test", "--on", "elem_1"]) }
              && engine.calls.contains { $0.starts(with: ["type", "--text", "곧 도착"]) } && engine.calls.contains { $0.starts(with: ["press", "return"]) },
              "apps recipe: the conversation opened, the text put, Return pressed")
        let mail = hands.call("app.recipe", .object(["recipe": .string("mail.compose"), "inputs": .object(["to": .string("a@b.c"), "subject": .string("회의")])]))
        check(mail.ok && system.opened.last?.url == "mailto:a@b.c?subject=%ED%9A%8C%EC%9D%98", "apps recipe: a mail composed by mailto (no permission needed)")
        let pane = hands.call("app.recipe", .object(["recipe": .string("settings.change"), "inputs": .object(["pane": .string("블루투스")])]))
        check(pane.ok && system.opened.last?.url == "x-apple.systempreferences:com.apple.BluetoothSettings", "apps recipe: a settings pane by its link")
        let search = hands.call("app.recipe", .object(["recipe": .string("browser.search"), "inputs": .object(["query": .string("서울 날씨")])]))
        check(search.ok && system.opened.last?.url?.hasPrefix("https://www.google.com/search?q=%EC%84%9C%EC%9A%B8") == true, "apps recipe: a web search")
        hands.external = { name, arguments in
            name == "files.find" ? ArisApps.Outcome(ok: true, did: "found", now: "", data: .object(["items": .array([.object(["path": .string("/Users/x/계약서.pdf")])])]), effect: .observe) : nil
        }
        let file = hands.call("app.recipe", .object(["recipe": .string("file.open"), "inputs": .object(["words": .string("계약서")])]))
        check(file.ok && system.opened.last?.path == "/Users/x/계약서.pdf", "apps recipe: a file found by Aris's search, opened")
    }
    // Aliases are kept.
    do {
        let (hands, _, _, _) = appsHands()
        _ = hands.call("app.alias", .object(["name": .string("업무 메신저"), "app": .string("Microsoft Teams classic")]))
        let found = hands.call("app.find", .object(["query": .string("업무 메신저")]))
        check(found.ok && found.data["app"]?["bundle"]?.string == "com.microsoft.teams" && hands.store.loadAliases().byKey["업무메신저"] == "com.microsoft.teams",
              "apps alias: the owner's name for an app is learned and saved")
        let web = hands.call("app.find", .object(["query": .string("유튜브 뮤직")]))
        check(web.ok && web.data["browser"]?.string == "com.apple.Safari", "apps find: a web app names the default browser")
    }
    // The file store round-trips.
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-apps-\(UUID().uuidString.prefix(8))")
        let store = ArisAppsFileStore(folder: folder)
        store.saveAliases(ArisApps.Aliases().learning("카톡", bundle: "k"))
        store.cacheCommands([ArisApps.Command(id: "menu:a", title: "A", channel: .menu, effect: .observe)], for: "com.x@1(2)")
        check(ArisAppsFileStore(folder: folder).loadAliases().byKey["카톡"] == "k" && ArisAppsFileStore(folder: folder).cachedCommands("com.x@1(2)")?.first?.id == "menu:a",
              "apps store: aliases and the command cache survive a restart")
        try? FileManager.default.removeItem(at: folder)
    }
}

// MARK: - The live seams, read-only (bundle files only: no app is launched, scripted or touched)

private func appsLiveReadOnlyTests() {
    let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    guard FileManager.default.fileExists(atPath: textEdit.path) else { return }
    let record = ArisAppsLiveSystem.record(textEdit)
    check(record?.bundle == "com.apple.TextEdit" && record?.names.contains("TextEdit") == true && record?.names.contains("텍스트 편집기") == true,
          "apps live: TextEdit's names from its bundle, Korean too")
    check(ArisAppsLiveSystem.grant(0) == .granted && ArisAppsLiveSystem.grant(-1743) == .denied && ArisAppsLiveSystem.grant(-1744) == .notAsked
          && ArisAppsLiveSystem.grant(-600) == .unknown, "apps live: Automation answers read without a prompt")
    check(ArisAppsLiveSystem.errorCode("execution error: Not authorized to send Apple events to Notes. (-1743)") == -1743, "apps live: osascript's error number")
    check(ArisAppsFileStore.fileName("com.apple.TextEdit@1.21(420)") == "com.apple.TextEdit_1.21_420_.json", "apps live: a cache file name")
}

// MARK: - The calls that run code, send, or act for good (security review of jv-apps, items 1-5)

private func appsRiskTests() {
    let standard: (String) -> Data? = { $0.hasSuffix("CocoaStandard.sdef") ? appsFixture("CocoaStandard.sdef") : nil }
    func commands(_ file: String, _ bundle: String) -> [ArisApps.Command] {
        ArisApps.Sdef.parse(appsFixture(file)).map { ArisApps.Commands.fromSdef($0.resolved(standard), bundle: bundle) } ?? []
    }
    // 1. Another app's interpreter, from the real dictionaries.
    let terminal = commands("sdef-Terminal.xml", "com.apple.Terminal")
    let doScript = terminal.first { $0.id == "sdef:doscript" }
    check(doScript?.runsCode == true && doScript?.effect == .changePermanent && doScript?.interpreter == "shell", "apps risk: Terminal's do script runs shell code, permanent")
    let safari = commands("sdef-Safari.xml", "com.apple.Safari")
    check(safari.first { $0.id == "sdef:dojavascript" }.map { $0.runsCode && $0.effect == .changePermanent && $0.interpreter == "javascript" } == true,
          "apps risk: Safari's do JavaScript runs code")
    check(safari.first { $0.id == "sdef:searchtheweb" }?.runsCode == false && safari.first { $0.id == "sdef:showbookmarks" }?.effect == .changeReversible,
          "apps risk: Safari's other commands stay mild")
    let chrome = commands("sdef-Chrome.xml", "com.google.Chrome")
    check(chrome.first { $0.id == "sdef:execute" }.map { $0.runsCode && $0.codeParameter == "javascript" } == true, "apps risk: Chrome's execute carries its javascript")
    check(chrome.first { $0.id == "sdef:reload" }?.runsCode == false, "apps risk: Chrome's reload doesn't")
    let shortcuts = ArisApps.Sdef.parse(appsFixture("sdef-Shortcuts.xml"))?.resolved(standard)
    check(shortcuts?.commands.first { $0.name == "run" }.map { ArisApps.Risk.runsCode($0, bundle: "com.apple.shortcuts").runs } == true, "apps risk: Shortcuts' run runs code")
    let events = commands("sdef-SystemEvents.xml", "com.apple.systemevents")
    check(events.first { $0.id == "sdef:keystroke" }?.runsCode == true && events.first { $0.id == "sdef:keycode" }?.runsCode == true,
          "apps risk: System Events' keystrokes drive other apps")
    let editor = commands("sdef-ScriptEditor.xml", "com.apple.ScriptEditor2")
    check(editor.filter { $0.id.hasPrefix("sdef:make:") }.allSatisfy(\.runsCode) && editor.first { $0.id == "sdef:compile" }?.effect == .changePermanent,
          "apps risk: everything Script Editor makes or compiles counts as code")
    check(commands("sdef-Automator.xml", "com.apple.Automator").first { $0.id == "sdef:execute" }?.runsCode == true, "apps risk: Automator's execute")
    check(commands("sdef-TextEdit.xml", "com.apple.TextEdit").allSatisfy { !$0.runsCode } && commands("sdef-Notes.xml", "com.apple.Notes").allSatisfy { !$0.runsCode },
          "apps risk: TextEdit and Notes run no code")
    let assessed = ArisApps.Risk.command(doScript!, bundle: "com.apple.Terminal", arguments: .object(["direct": .string("rm -rf ~/x")]))
    check(assessed.effect == .changePermanent && assessed.code == "rm -rf ~/x" && assessed.askAlways && assessed.interpreter == "shell",
          "apps risk: the code text goes to the trust policy, asked every time")
    let unnamed = ArisApps.Sdef.Command(name: "frobnicate", code: "xxxxyyyy", suite: "s", description: "", direct: ArisApps.Sdef.Parameter(name: "", code: "", type: "text",
                                         optional: false, description: "The AppleScript source to evaluate."), parameters: [], result: nil)
    check(ArisApps.Risk.runsCode(unnamed, bundle: "com.unknown.app").runs, "apps risk: a direct parameter described as source code runs code in any app")
    check(ArisApps.Risk.unknownCommand("do shell script").effect == .changePermanent && ArisApps.Risk.unknownCommand("새 창").effect == .changeReversible,
          "apps risk: words that say code are permanent; ordinary words stay mild")
    let menu = ArisApps.Commands.fromMenu(ArisApps.MenuBar(menus: [ArisApps.MenuItem(title: "Script", items: [ArisApps.MenuItem(title: "Run")]),
                                                                    ArisApps.MenuItem(title: "편집", items: [ArisApps.MenuItem(title: "실행 취소"), ArisApps.MenuItem(title: "다시 실행")])]))
    check(menu.first { $0.title == "Run" }?.effect == .changePermanent && menu.first { $0.title == "실행 취소" }?.effect == .changeReversible
          && menu.first { $0.title == "다시 실행" }?.effect == .changeReversible, "apps risk: Script › Run is permanent; undo and redo stay mild")
    do {
        let (hands, system, _, _) = appsHands()
        let terminalPath = "/System/Applications/Utilities/Terminal.app"
        system.installed.append(.init(bundle: "com.apple.Terminal", names: ["Terminal", "터미널"], path: terminalPath))
        system.sdefs[terminalPath] = appsFixture("sdef-Terminal.xml")
        let call = ArisApps.JSON.object(["app": .string("터미널"), "command": .string("sdef:doscript"), "arguments": .object(["direct": .string("ls")])])
        let found = hands.assess("app.do", call)
        check(found.effect == .changePermanent && found.code == "ls" && found.askAlways, "apps risk: app.do of Terminal's do script is permanent, with its code, before it runs")
        check(hands.assess("app.do", .object(["app": .string("메모"), "command": .string("새 메모")])).effect == .changeReversible, "apps risk: an ordinary app.do stays mild")
        check(hands.assess("app.do", .object(["app": .string("메모"), "command": .string("run shell script")])).effect == .changePermanent,
              "apps risk: a command not found but worded as code is permanent")
    }

    // 2. app.open by what it opens.
    let kinds: (String) -> ArisApps.PathKind = { ["/x/a.pdf": .document, "/x/run.command": .runnable, "/Users/x/Downloads/Tool.app": .otherApp,
                                                 "/Applications/Notes.app": .installedApp, "/x": .folder][$0] ?? .runnable }
    func opening(_ url: String?, _ path: String? = nil) -> ArisApps.Assessment { ArisApps.Risk.opening(url: url, path: path, kind: kinds) }
    check(opening("https://example.com").effect == .changeReversible && opening("x-apple.systempreferences:com.apple.BluetoothSettings").effect == .changeReversible
          && opening("mailto:a@b.c?subject=hi").effect == .changeReversible && opening(nil, "/x/a.pdf").effect == .changeReversible
          && opening(nil, "/x").effect == .changeReversible && opening(nil, "/Applications/Notes.app").effect == .changeReversible,
          "apps risk: a web page, a settings pane, an empty mail, a document, a folder, an installed app: mild")
    check(opening("shortcuts://run-shortcut?name=x").effect == .changePermanent && opening("shortcuts://run-shortcut?name=x").code == "x"
          && opening("shortcuts://run-shortcut?name=x").interpreter == "shortcut", "apps risk: shortcuts://run-shortcut runs the Shortcut it names")
    check(opening("tel:01012345678").effect == .outward && opening("facetime:a@b.c").effect == .outward, "apps risk: tel: and facetime: call someone")
    check(opening("mailto:a@b.c?body=secret").effect == .changePermanent, "apps risk: a mailto with its body filled in makes the app act")
    check(opening("myapp://do/thing").effect == .changePermanent, "apps risk: a custom scheme makes an app act")
    check(opening(nil, "/x/run.command").effect == .changePermanent && opening("file:///x/run.command").effect == .changePermanent
          && opening(nil, "/Users/x/Downloads/Tool.app").effect == .changePermanent, "apps risk: a script, a file: link to it, an app from a download: they run")
    let R = ArisApps.Risk.self
    check(R.kind(resolved: "/Applications/Notes.app", isFolder: true, executable: false, exists: true, home: "/Users/x") == .installedApp
          && R.kind(resolved: "/Users/x/Applications/A.app", isFolder: true, executable: false, exists: true, home: "/Users/x") == .installedApp
          && R.kind(resolved: "/Volumes/Disk/A.app", isFolder: true, executable: false, exists: true, home: "/Users/x") == .otherApp
          && R.kind(resolved: "/Users/x/a.sh", isFolder: false, executable: false, exists: true, home: "/Users/x") == .runnable
          && R.kind(resolved: "/Users/x/tool", isFolder: false, executable: true, exists: true, home: "/Users/x") == .runnable
          && R.kind(resolved: "/Users/x/notes.txt", isFolder: false, executable: false, exists: true, home: "/Users/x") == .document
          && R.kind(resolved: "/Users/x/My.workflow", isFolder: true, executable: false, exists: true, home: "/Users/x") == .runnable,
          "apps risk: what a path is: apps by where they live, scripts and executables, documents, bundles that run")
    // A link to a script is the script (aliases and links resolved before classifying).
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-apps-risk-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let script = folder.appendingPathComponent("go.command"), link = folder.appendingPathComponent("harmless.pdf"), note = folder.appendingPathComponent("note.txt")
    try? Data("echo hi\n".utf8).write(to: script)
    try? Data("hi".utf8).write(to: note)
    try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: script)
    let live = ArisAppsLiveSystem()
    check(live.pathKind(link.path) == .runnable && live.pathKind(note.path) == .document && live.pathKind(folder.path) == .folder,
          "apps risk: a link named .pdf that points at a script is classified as the script")
    try? FileManager.default.removeItem(at: folder)
    do {
        let (hands, system, _, _) = appsHands()
        system.kinds["/Users/x/Downloads/setup.command"] = .runnable
        check(hands.assess("app.open", .object(["path": .string("/Users/x/Downloads/setup.command")])).effect == .changePermanent
              && hands.assess("app.open", .object(["path": .string("/Users/x/a.pdf")])).effect == .changeReversible
              && hands.assess("app.open", .object(["app": .string("유튜브")])).effect == .changeReversible, "apps risk: app.open's effect comes from its arguments")
    }

    // 2b. app.do on the url and document channels opens what the call names: judged as app.open judges it.
    do {
        let (hands, system, _, _) = appsHands()
        let previewPath = "/System/Applications/Preview.app"
        system.installed.append(.init(bundle: "com.apple.Preview", names: ["Preview", "미리보기"], path: previewPath))
        system.running.append(ArisAppsRunning(bundle: "com.apple.Preview", name: "Preview", pid: 503))
        var preview = ArisApps.BundleInfo()
        preview.bundle = "com.apple.Preview"
        preview.name = "Preview"
        preview.version = "11"
        preview.documents = [.init(name: "PDF document", role: "Viewer", types: ["com.adobe.pdf"], extensions: ["pdf"])]
        preview.schemes = ["previewapp"]
        system.infos[previewPath] = preview
        system.kinds["/Users/x/Downloads/setup.command"] = .runnable
        system.kinds["/Users/x/report.pdf"] = .document
        let script = ArisApps.JSON.object(["app": .string("미리보기"), "command": .string("open:pdfdocument"), "arguments": .object(["path": .string("/Users/x/Downloads/setup.command")])])
        check(hands.assess("app.do", script).effect == .changePermanent, "apps risk: app.do opening a script on a document channel is judged as running it, before it runs")
        let refused = hands.call("app.do", script, context: .init())
        check(!refused.ok && !system.opened.contains { $0.path == "/Users/x/Downloads/setup.command" }, "apps risk: a file not of the command's document type isn't opened as one")
        let link = hands.call("app.do", .object(["app": .string("미리보기"), "command": .string("open:pdfdocument"), "arguments": .object(["url": .string("myapp://act")])]))
        check(!link.ok && !system.opened.contains { $0.url == "myapp://act" }, "apps risk: a url on a document channel is refused")
        let scheme = ArisApps.JSON.object(["app": .string("미리보기"), "command": .string("url:previewapp"), "arguments": .object(["url": .string("previewapp://do/thing")])])
        check(hands.assess("app.do", scheme).effect == .changePermanent, "apps risk: app.do on a url channel with an app's own scheme is judged as that scheme")
        let pdf = ArisApps.JSON.object(["app": .string("미리보기"), "command": .string("open:pdfdocument"), "arguments": .object(["path": .string("/Users/x/report.pdf")])])
        check(hands.assess("app.do", pdf).effect == .changeReversible, "apps risk: opening a PDF as a PDF document stays mild")
        let opened = hands.call("app.do", pdf)
        check(opened.ok && system.opened.last?.path == "/Users/x/report.pdf" && system.opened.last?.bundle == "com.apple.Preview", "apps risk: and it opens in that app")
    }

    // 2c. Every Shortcut run is running code (a Shortcut can run shell scripts, send and delete), whatever its title;
    // whether to ask is the policy's: an owner-named Shortcut runs (said first), on both paths alike.
    let mild = ArisApps.Commands.fromShortcuts(["Notes 정리", "Morning"], app: "Notes")
    check(mild.count == 1 && mild[0].runsCode && mild[0].effect == .changePermanent && mild[0].interpreter == "shortcut",
          "apps risk: a Shortcut titled like a mild change still runs code, permanent")
    let viaShortcut = ArisApps.Risk.command(mild[0], bundle: "com.apple.Notes", arguments: .object([:]))
    let viaLink = opening("shortcuts://run-shortcut?name=Notes%20%EC%A0%95%EB%A6%AC")
    check(viaShortcut.code == "Notes 정리" && !viaShortcut.askAlways && viaShortcut.effect == .changePermanent
          && viaLink.code == "Notes 정리" && !viaLink.askAlways && viaLink.effect == viaShortcut.effect,
          "apps risk: app.do's Shortcut and a shortcuts:// link agree: permanent, the name carried, no forced ask")
    let viaIntent = ArisApps.Commands.fromIntents(ArisApps.Intents.parse(appsFixture("intents-Notes.json")), shortcuts: ["Create Note"])
    check(viaIntent.first { $0.id == "intent:CreateNoteLinkAction" }.map { $0.runsCode && $0.effect == .changePermanent && $0.title == "Create Note" } == true,
          "apps risk: an App Intent run through a Shortcut is running that Shortcut")
    check(viaIntent.first { $0.id == "intent:PinNotesLinkAction" }.map { !$0.runsCode && !$0.runnable && $0.effect == .changeReversible } == true,
          "apps risk: an intent no Shortcut runs is only shown, and stays mild")
    check(ArisApps.Commands.fromMenu(appsMenu("menu-Notes.json")).first { $0.title == "New Note" }?.effect == .changeReversible, "apps risk: the menu's New Note stays mild")
    do {
        final class Shortcuts: AppsFakeSystem {
            var ran: [String] = []
            override func shortcuts() -> [String] { ["Notes 정리"] }
            override func runShortcut(_ name: String, input: String?) -> (ok: Bool, output: String) { ran.append(name); return (true, "done") }
        }
        let system = Shortcuts(), ax = AppsFakeAX(), engine = AppsFakeEngine()
        let hands = ArisAppsHands(system: system, ax: ax, engine: engine, store: ArisAppsMemoryStore())
        hands.pollSeconds = 0
        system.infos["/System/Applications/Notes.app"] = ArisApps.BundleInfo.parse(infoPlist: appsFixture("info-Notes.plist"))
        system.running = [ArisAppsRunning(bundle: "com.apple.Notes", name: "Notes", pid: 501)]
        ax.bars[501] = appsMenu("menu-Notes.json")
        let call = ArisApps.JSON.object(["app": .string("메모"), "command": .string("Notes 정리 실행해")])
        let assessed = hands.assess("app.do", call)
        check(assessed.effect == .changePermanent && assessed.code == "Notes 정리" && !assessed.askAlways, "apps risk: the owner's ‘Notes 정리 실행해’ is a permanent Shortcut run, left to the policy")
        let ran = hands.call("app.do", call)
        check(ran.ok && system.ran == ["Notes 정리"] && ran.channel == "shortcut", "apps risk: and once the policy lets it, the Shortcut runs")
    }

    // 3. app.select: the label of the target and of the option decide; buttons are refused.
    let context = ArisApps.EffectContext(surface: { _, _ in .plain }, label: { _, target in ["e1": "Delete Account", "e2": "글꼴"][target] },
                                         command: { _, _, _ in nil }, pathKind: { _ in .document })
    let select = ArisApps.Spec.named("app.select")!
    check(select.effect(.object(["app": .string("x"), "target": .string("e1")]), context) == .changePermanent
          && select.effect(.object(["app": .string("x"), "target": .string("e2"), "option": .string("휴지통 비우기")]), context) == .changePermanent,
          "apps risk: selecting Delete, or choosing Empty Trash in a pop-up, is permanent")
    check(select.effect(.object(["app": .string("x"), "target": .string("e2"), "option": .string("Helvetica")]), context) == .changeReversible, "apps risk: choosing a font stays mild")
    do {
        let (hands, _, _, engine) = appsHands()
        let refused = hands.call("app.select", .object(["app": .string("카톡"), "target": .string("e6")]))
        check(!refused.ok && refused.did.contains("app.click") && !engine.calls.contains { $0.first == "click" }, "apps risk: app.select refuses a button (보내기)")
        let row = hands.call("app.select", .object(["app": .string("카톡"), "target": .string("e1")]))
        check(row.ok && engine.calls.contains { $0.starts(with: ["click", "--snapshot", "ps1_test", "--on", "elem_1"]) }, "apps risk: app.select takes a list row")
    }

    // 4. Return and newlines, in every spelling, where they send or run.
    check(R.normalized("Cmd+Return") == (["cmd"], "return") && R.normalized("⌘↩").key == "return" && R.normalized("command+enter") == (["cmd"], "return")
          && R.normalized("kp_enter").key == "return" && R.normalized("numpadenter").key == "return" && R.normalized("shift+return").modifiers == ["shift"],
          "apps risk: Return's spellings are one key, modifiers kept")
    check(R.press("cmd+return", surface: .chat).effect == .outward && R.press("⌘↩", surface: .chat).effect == .outward && R.press("kp_enter", surface: .chat).effect == .outward,
          "apps risk: ⌘Return or the keypad's Enter in a chat sends")
    check(R.press("return", surface: .form).effect == .outward && R.press("return", surface: .unknown).effect == .outward && R.press("cmd+shift+d", surface: .mail).effect == .outward,
          "apps risk: Return in a form field or an unread focus, and ⌘⇧D in mail, send")
    check(R.press("return", surface: .terminal).effect == .changePermanent, "apps risk: Return in a terminal runs the line")
    check(R.press("return", surface: .plain).effect == .changeReversible && R.press("cmd+n", surface: .chat).effect == .changeReversible, "apps risk: Return in a document and ⌘N stay mild")
    check(R.type("ls -la\n", surface: .terminal).effect == .changePermanent && R.type("ls -la\n", surface: .terminal).code == "ls -la\n", "apps risk: a typed line in a terminal is code")
    check(R.type("곧 도착\r", surface: .chat).effect == .outward && R.type("곧 도착", surface: .chat).effect == .changeReversible
          && R.type("한 줄\n두 줄", surface: .plain).effect == .changeReversible, "apps risk: a typed newline sends in a chat, not in a document")
    check(R.surface(bundle: "com.apple.mail", focusedRole: nil) == .mail && R.surface(bundle: "com.googlecode.iterm2", focusedRole: "textArea") == .terminal
          && R.surface(bundle: "com.apple.Safari", focusedRole: "textField") == .form && R.surface(bundle: "com.apple.TextEdit", focusedRole: "textArea") == .plain
          && R.surface(bundle: "com.apple.TextEdit", focusedRole: nil) == .unknown, "apps risk: where keys land, by app kind and focused role")
    do {
        let (hands, system, ax, _) = appsHands()
        check(hands.effect("app.press", .object(["app": .string("카톡"), "keys": .string("cmd+enter")])) == .outward, "apps risk: app.press ⌘Enter in KakaoTalk is outward")
        system.installed.append(.init(bundle: "com.apple.Terminal", names: ["Terminal"], path: "/System/Applications/Utilities/Terminal.app"))
        check(hands.assess("app.type", .object(["app": .string("Terminal"), "text": .string("rm -rf /tmp/x\n")])).effect == .changePermanent, "apps risk: app.type of a line into Terminal runs it")
        ax.focused[501] = "textField"
        check(hands.effect("app.press", .object(["app": .string("메모"), "keys": .string("return")])) == .outward, "apps risk: Return in a focused text field submits")
        ax.focused[501] = "textArea"
        check(hands.effect("app.press", .object(["app": .string("메모"), "keys": .string("return")])) == .changeReversible, "apps risk: Return in a note's text stays mild")
        system.running.removeAll { $0.bundle == "com.apple.Notes" }
        check(hands.effect("app.press", .object(["app": .string("메모"), "keys": .string("return")])) == .outward, "apps risk: Return where the focus can't be read is taken as sending")
    }

    // 5. Recipes: assessed as a whole up front, every step checked again when it runs.
    do {
        let (hands, system, _, _) = appsHands()
        check(hands.effect("app.recipe", .object(["recipe": .string("browser.open"), "inputs": .object(["url": .string("shortcuts://run-shortcut?name=x")])])) == .changePermanent,
              "apps risk: a recipe that opens a shortcuts:// link is assessed as running code")
        check(hands.effect("app.recipe", .object(["recipe": .string("browser.search"), "inputs": .object(["query": .string("날씨")])])) == .changeReversible,
              "apps risk: a web search stays mild")
        hands.external = { name, _ in
            name == "files.find" ? ArisApps.Outcome(ok: true, did: "found", now: "", data: .object(["items": .array([.object(["path": .string("/Users/x/Downloads/setup.command")])])]), effect: .observe) : nil
        }
        system.kinds["/Users/x/Downloads/setup.command"] = .runnable
        let opened = system.opened.count
        let ran = hands.call("app.recipe", .object(["recipe": .string("file.open"), "inputs": .object(["words": .string("setup")])]))
        check(!ran.ok && system.opened.count == opened && ran.data["steps"]?.array?.contains { $0.string?.contains("go-ahead") == true } == true,
              "apps risk: a recipe whose found file is a script doesn't open it: the step is checked again and stopped")
        final class Refuse: ArisAppsGate {
            var seen: [String] = []
            func refusal(_ request: ArisAppsGateRequest) -> String? {
                seen.append(request.call + ":" + request.assessment.effect.rawValue)
                return request.assessment.effect == .outward ? "the owner said no" : nil
            }
        }
        let gate = Refuse()
        hands.gate = gate
        let sent = hands.call("app.recipe", .object(["recipe": .string("message.send"), "inputs": .object(["app": .string("카톡"), "to": .string("엄마"), "text": .string("곧 도착")])]))
        check(!sent.ok && gate.seen.contains("app.open:change-reversible") && gate.seen.contains("app.press:outward"),
              "apps risk: every recipe step goes to the trust gate with its own effect, and a refusal stops the send")
    }
}

// MARK: - jv-safe10 (tenth VM run, item 4): app.type with no field named, as the model called it

/// 03:38:32 app.type {app: TextEdit, text: 새 내용입니다, replace: true} with no target: nothing was read before it, the
/// card said the erased text couldn't be read, no copy was kept and nothing could undo it.
func runSafe10AppsTests() {
    let (hands, _, _, engine) = appsHands()
    hands.readBackSeconds = 0
    var kept: [String] = []
    hands.keepText = { text in
        kept.append(text)
        return "copy-1"
    }
    // The window's one text area holds what he wrote.
    engine.elements = engine.elements.map { element in
        guard element["id"]?.string == "elem_5", case .object(var object) = element else { return element }
        object["value"] = .string("원래 있던 글")
        return .object(object)
    }
    check(hands.peekField(app: "카톡", target: nil) == "원래 있던 글", "safe10 4: with no field named, the card's read finds the window's one text area (what would be erased)")
    let replaced = hands.call("app.type", .object(["app": .string("카톡"), "text": .string("새 내용입니다"), "replace": .bool(true)]))
    check(replaced.ok && engine.calls.contains { $0.starts(with: ["set-value", "--snapshot", "ps1_test", "--on", "elem_5", "--value", "새 내용입니다"]) },
          "safe10 4: the model's replace sets that field's value, as a replay's does (\(replaced.did))")
    check(kept == ["원래 있던 글"], "safe10 4: what it erases is kept first")
    if case .textInserted(_, let element, _)? = replaced.undo {
        check(ArisApps.TextUndo.mark(element)?.erased == "copy-1", "safe10 4: and its undo puts that text back")
    } else {
        check(false, "safe10 4: the model's replace has an undo (\(String(describing: replaced.undo)))")
    }
    // Bound to what its card showed (ArisApps.TypeOver): the field holds something else by then, and nothing is set.
    let (bound, _, _, held) = appsHands()
    bound.readBackSeconds = 0
    held.elements = held.elements.map { element in
        guard element["id"]?.string == "elem_5", case .object(var object) = element else { return element }
        object["value"] = .string("그 사이 고친 글")
        return .object(object)
    }
    let seen = ArisApps.TypeOver.mark(erases: ArisErasedText(text: "원래 있던 글", keepable: true))
    let stopped = bound.call("app.type", .object(["app": .string("카톡"), "text": .string("새 내용입니다"), "replace": .bool(true), ArisApps.TypeOver.argument: .string(seen)]))
    check(!stopped.ok && stopped.did == ArisApps.TypeOver.replaceRefusal && !held.calls.contains { $0.first == "set-value" },
          "safe10 4: the model's replace sets nothing when the field no longer holds what its card showed (\(stopped.did))")
    let now = ArisApps.TypeOver.mark(erases: ArisErasedText(text: "그 사이 고친 글", keepable: true))
    let went = bound.call("app.type", .object(["app": .string("카톡"), "text": .string("새 내용입니다"), "replace": .bool(true), ArisApps.TypeOver.argument: .string(now)]))
    check(went.ok && held.calls.contains { $0.first == "set-value" }, "safe10 4: and sets it when it does, with no field named")
    // Plain typing with no field named: read before and after, nothing clicked, the caret left where it is.
    let (plain, _, _, typing) = appsHands()
    plain.readBackSeconds = 0
    let typed = plain.call("app.type", .object(["app": .string("카톡"), "text": .string("안녕")]))
    check(typed.ok && typing.calls.contains { $0.starts(with: ["type", "--text", "안녕"]) } && !typing.calls.contains { $0.first == "click" },
          "safe10 4: plain typing with no field named clicks nothing and types where the focus is")
    // Two fields and no focus: none is guessed.
    let elements = appsElements().compactMap(ArisApps.ReadElement.init)
    check(ArisApps.Read.defaultTextField(in: elements)?.shortId == "e5", "safe10 4: the window's one text area")
    check(ArisApps.Read.defaultTextField(in: elements + [ArisApps.ReadElement(id: "elem_9", role: "textArea", label: "둘째")]) == nil, "safe10 4: two text areas and no focus: none")
    check(ArisApps.Read.defaultTextField(in: elements.filter { $0.role == "secureTextField" }) == nil, "safe10 4: never a password field")
    check(ArisApps.Read.defaultTextField(in: elements, focusedFrame: (10, 50))?.shortId == "e7", "safe10 4: the focused field first")
}

// MARK: - jv-exp11 (eleventh VM run, item 1, and the security review of its Select All handling): the app layer

/// The text area of KakaoTalk's window (elem_5) set to `value`, with `selected` characters of it selected from 0.
private func exp11Field(_ engine: AppsFakeEngine, value: String, selected: Int?) {
    engine.elements = engine.elements.map { element in
        guard element["id"]?.string == "elem_5", case .object(var object) = element else { return element }
        object["value"] = .string(value)
        object["selected_text_range"] = selected.map { .object(["location": .number(0), "length": .number(Double($0))]) }
        return .object(object)
    }
}

func runExp11AppsTests() {
    let original = "원래 문장 하나\n원래 문장 둘"
    // Select All, then typing bound to the whole text (the batch's replace): it types over it, keeps it, and its undo puts it back.
    do {
        let (hands, _, _, engine) = appsHands()
        hands.readBackSeconds = 0
        var kept: [String] = []
        hands.keepText = { text in kept.append(text); return "copy-1" }
        exp11Field(engine, value: original, selected: original.utf16.count)
        engine.onRun = { arguments in if arguments.first == "type" { exp11Field(engine, value: "교체된 내용", selected: 0) } }
        let mark = ArisApps.TypeOver.mark(erases: ArisErasedText(text: original, keepable: true))
        let typed = hands.call("app.type", .object(["app": .string("카톡"), "text": .string("교체된 내용"), ArisApps.TypeOver.argument: .string(mark)]))
        check(typed.ok && engine.calls.contains { $0.starts(with: ["type", "--text", "교체된 내용"]) }, "exp11 1: typing over the Select All its card showed types (\(typed.did))")
        check(kept == [original], "exp11 1: what it types over is kept first (\(kept))")
        if case .textInserted(_, let element, _)? = typed.undo {
            check(ArisApps.TextUndo.mark(element)?.erased == "copy-1", "exp11 1: and its undo puts that text back")
        } else {
            check(false, "exp11 1: typing over a selection has an undo (\(String(describing: typed.undo)), \(typed.now))")
        }
    }
    // Bound to nothing selected (a model's plain typing): anything selected by then, or a selection that can't be read, stops it.
    do {
        let (hands, _, _, engine) = appsHands()
        hands.readBackSeconds = 0
        exp11Field(engine, value: original, selected: 4)
        let empty = ArisApps.TypeOver.mark(erases: nil)
        let stopped = hands.call("app.type", .object(["app": .string("카톡"), "text": .string("x"), ArisApps.TypeOver.argument: .string(empty)]))
        check(!stopped.ok && stopped.did == ArisApps.TypeOver.refusal && !engine.calls.contains { $0.first == "type" },
              "exp11 sec3: typing whose decision saw nothing selected types nothing when something is selected right before it types (\(stopped.did))")
        exp11Field(engine, value: original, selected: nil)
        let unread = hands.call("app.type", .object(["app": .string("카톡"), "text": .string("x"), ArisApps.TypeOver.argument: .string(empty)]))
        check(!unread.ok && !engine.calls.contains { $0.first == "type" }, "exp11 sec3: nor when the selection can't be read then")
        exp11Field(engine, value: original, selected: 0)
        let went = hands.call("app.type", .object(["app": .string("카톡"), "text": .string("x"), ArisApps.TypeOver.argument: .string(empty)]))
        check(went.ok && engine.calls.contains { $0.first == "type" }, "exp11 sec3: and types when nothing is selected, as the decision saw")
    }
    // C3: a replace whose field the model named in words no element carries ("문서"): the window's one document is set,
    // never text typed at the caret.
    do {
        let (hands, _, _, engine) = appsHands()
        hands.readBackSeconds = 0
        hands.keepText = { _ in "copy-2" }
        exp11Field(engine, value: original, selected: 0)
        check(hands.peekField(app: "카톡", target: "문서") == original, "exp11 1: the card's read finds the document the words meant")
        let replaced = hands.call("app.type", .object(["app": .string("카톡"), "target": .string("문서"), "text": .string("교체된 내용"), "replace": .bool(true)]))
        check(replaced.ok && engine.calls.contains { $0.starts(with: ["set-value", "--snapshot", "ps1_test", "--on", "elem_5", "--value", "교체된 내용"]) }
              && !engine.calls.contains { $0.first == "type" }, "exp11 1: the replace sets that field, never types at the caret (\(replaced.did))")
    }
    // C3b/C3c: a replace by the id of a read the model took; the field changed after the card: nothing is set.
    do {
        let (hands, _, _, engine) = appsHands()
        hands.readBackSeconds = 0
        hands.keepText = { _ in "copy-3" }
        exp11Field(engine, value: original, selected: 0)
        _ = hands.call("app.read", .object(["app": .string("카톡")]))
        exp11Field(engine, value: "카드 뒤에 바뀐 글", selected: 0)
        let mark = ArisApps.TypeOver.mark(erases: ArisErasedText(text: original, keepable: true))
        let stopped = hands.call("app.type", .object(["app": .string("카톡"), "target": .string("e5"), "text": .string("교체된 내용"), "replace": .bool(true),
                                                      ArisApps.TypeOver.argument: .string(mark)]))
        check(!stopped.ok && !engine.calls.contains { $0.first == "set-value" } && !engine.calls.contains { $0.first == "type" },
              "exp11 1: C3c: the document changed after the card: nothing is replaced or typed (\(stopped.did))")
        exp11Field(engine, value: original, selected: 0)
        let went = hands.call("app.type", .object(["app": .string("카톡"), "target": .string("e5"), "text": .string("교체된 내용"), "replace": .bool(true),
                                                   ArisApps.TypeOver.argument: .string(mark)]))
        check(went.ok && engine.calls.contains { $0.first == "set-value" }, "exp11 1: the text the card showed is replaced (\(went.did))")
        // Allowed on a card that couldn't read it, and the field now holds text he never saw: stopped.
        let any = hands.call("app.type", .object(["app": .string("카톡"), "target": .string("문서"), "text": .string("교체된 내용"), "replace": .bool(true),
                                                  ArisApps.TypeOver.argument: .string(ArisApps.TypeOver.any)]))
        check(!any.ok && any.did == ArisApps.TypeOver.unseenRefusal, "exp11 1: text the unread card never showed stops the replace (\(any.did))")
    }
}
