import XCTest
@testable import ArisCore

/// jv-apps: the app layer's pure core. The recorded system files (sdef, Info.plist, App Intents) are exercised by the
/// harness (tests/apps-tests.swift); these use small inline data so `swift test` needs nothing from the Mac.
final class ArisAppsFindTests: XCTestCase {
    private let apps: [ArisApps.AppRecord] = [
        .init(bundle: "com.kakao.KakaoTalkMac", names: ["KakaoTalk", "카카오톡"]),
        .init(bundle: "com.google.Chrome", names: ["Google Chrome"]),
        .init(bundle: "com.apple.Notes", names: ["Notes", "메모"]),
        .init(bundle: "com.apple.TextEdit", names: ["TextEdit", "텍스트 편집기"]),
        .init(bundle: "com.microsoft.teams2", names: ["Microsoft Teams"]),
        .init(bundle: "com.microsoft.teams", names: ["Microsoft Teams classic"]),
        .init(bundle: "com.apple.dt.Xcode", names: ["Xcode"]),
    ]

    private func bundle(_ said: String, aliases: ArisApps.Aliases = .init()) -> String? {
        if case .app(let match) = ArisApps.Find.answer(ArisApps.Find.rank(said, apps: apps, aliases: aliases)) { return match.bundle }
        return nil
    }

    func testNicknamesAndNames() {
        XCTAssertEqual(bundle("카톡"), "com.kakao.KakaoTalkMac")
        XCTAssertEqual(bundle("까톡"), "com.kakao.KakaoTalkMac")
        XCTAssertEqual(bundle("카톡에서"), "com.kakao.KakaoTalkMac")
        XCTAssertEqual(bundle("크롬"), "com.google.Chrome")
        XCTAssertEqual(bundle("chorme"), "com.google.Chrome")
        XCTAssertEqual(bundle("메모 앱"), "com.apple.Notes")
        XCTAssertEqual(bundle("텍스트편집기"), "com.apple.TextEdit")
    }

    func testAmbiguityIsOneQuestion() {
        guard case .ask(let both) = ArisApps.Find.answer(ArisApps.Find.rank("팀즈", apps: apps)) else { return XCTFail("팀즈 should ask") }
        XCTAssertEqual(Set(both.compactMap(\.bundle)), ["com.microsoft.teams2", "com.microsoft.teams"])
        XCTAssertTrue(ArisApps.Find.question("팀즈", both).ko.hasSuffix("중 어느 앱인가요?"))
    }

    func testWebAndMissing() {
        guard case .web(let youtube) = ArisApps.Find.answer(ArisApps.Find.rank("유튜브", apps: apps)) else { return XCTFail("유튜브 is a web app") }
        XCTAssertEqual(youtube.web, "https://www.youtube.com")
        guard case .ask(let code) = ArisApps.Find.answer(ArisApps.Find.rank("코드", apps: apps)) else { return XCTFail("코드 without VS Code asks") }
        XCTAssertTrue(code.contains { $0.bundle == "com.apple.dt.Xcode" })
        XCTAssertEqual(ArisApps.Find.answer(ArisApps.Find.rank("없는앱이름", apps: apps)), .none)
    }

    func testLearnedAlias() {
        let taught = ArisApps.Aliases().learning("회사 메신저", bundle: "com.microsoft.teams")
        XCTAssertEqual(bundle("회사 메신저", aliases: taught), "com.microsoft.teams")
        XCTAssertNil(bundle("회사 메신저", aliases: taught.forgetting("회사 메신저")))
    }

    func testJamoAndSound() {
        XCTAssertGreaterThan(ArisApps.Text.similarity("슬랙", "스랙"), 0.9)
        XCTAssertLessThan(ArisApps.Text.similarity("메모", "메일"), 0.75)
        XCTAssertGreaterThanOrEqual(ArisApps.Text.soundsLike("피그마", "Figma"), 0.99)
    }
}

final class ArisAppsCommandTests: XCTestCase {
    private let bar = ArisApps.MenuBar(menus: [
        ArisApps.MenuItem(title: "파일", items: [ArisApps.MenuItem(title: "새로운 윈도우", key: "N", modifiers: 0), ArisApps.MenuItem(title: "새로운 폴더", key: "N", modifiers: 1)]),
        ArisApps.MenuItem(title: "편집", items: [ArisApps.MenuItem(title: "실행 취소", key: "Z", modifiers: 0), ArisApps.MenuItem(title: "다시 실행", enabled: false)]),
        ArisApps.MenuItem(title: "View", items: [ArisApps.MenuItem(title: "Enter Full Screen", key: "F", modifiers: 4), ArisApps.MenuItem(title: "Zoom In")]),
        ArisApps.MenuItem(title: "Finder", items: [ArisApps.MenuItem(title: "휴지통 비우기…")]),
    ])

    private func top(_ query: String) -> String? { ArisApps.Commands.search(query, in: ArisApps.Commands.fromMenu(bar)).first?.command.title }

    func testBilingualSearch() {
        XCTAssertEqual(top("새 창"), "새로운 윈도우")
        XCTAssertEqual(top("new window"), "새로운 윈도우")
        XCTAssertEqual(top("새 폴더 만들어"), "새로운 폴더")
        XCTAssertEqual(top("undo"), "실행 취소")
        XCTAssertEqual(top("전체 화면"), "Enter Full Screen")
        XCTAssertEqual(top("확대"), "Zoom In")
        XCTAssertTrue(ArisApps.Commands.search("관계없는 말", in: ArisApps.Commands.fromMenu(bar)).isEmpty)
    }

    func testIdsKeysAndEffects() {
        let commands = ArisApps.Commands.fromMenu(bar)
        XCTAssertEqual(commands.first?.id, "menu:파일>새로운윈도우")
        XCTAssertEqual(commands.first { $0.title == "새로운 폴더" }?.keys, "⇧⌘N")
        XCTAssertEqual(commands.first { $0.title == "Enter Full Screen" }?.keys, "⌃⌘F")
        XCTAssertEqual(commands.first { $0.title == "휴지통 비우기…" }?.effect, .changePermanent)
        XCTAssertEqual(ArisApps.Commands.effect("send message", channel: .sdef), .outward)
        XCTAssertEqual(ArisApps.Commands.effect("get name", channel: .sdef), .observe)
    }

    func testSdefInline() throws {
        let xml = """
        <dictionary><suite name="Notes Suite" code="note">
        <command name="make" code="corecrel"><parameter name="new" code="kocl" type="type"/><parameter name="with properties" code="prdt" type="record" optional="yes"/></command>
        <command name="delete" code="coredelo" description="Delete an object."><direct-parameter type="specifier"/></command>
        <class name="application" code="capp"><element type="note"/></class>
        <class name="note" code="note" plural="notes"><property name="name" code="pnam" type="text"/><property name="body" code="body" type="text"/>
        <property name="id" code="ID  " type="text" access="r"/></class></suite></dictionary>
        """
        let dictionary = try XCTUnwrap(ArisApps.Sdef.parse(Data(xml.utf8)))
        XCTAssertEqual(dictionary.topElements, ["note"])
        let commands = ArisApps.Commands.fromSdef(dictionary)
        XCTAssertEqual(commands.first { $0.id == "sdef:delete" }?.effect, .changePermanent)
        XCTAssertEqual(commands.first { $0.id == "sdef:make:note" }?.parameters, ["name", "body"])
        XCTAssertEqual(try ArisApps.Script.make("note", bundle: "com.apple.Notes", dictionary: dictionary, properties: ["name": .string("a\"b")]),
                       "tell application id \"com.apple.Notes\" to make new note with properties {name:\"a\\\"b\"}")
        XCTAssertThrowsError(try ArisApps.Script.make("note", bundle: "x", dictionary: dictionary, properties: ["id": .string("1")]))
    }
}

final class ArisAppsChannelTests: XCTestCase {
    private let menu = ArisApps.Command(id: "menu:file>newnote", title: "New Note", channel: .menu, path: ["File", "New Note"], enabled: true, effect: .changeReversible)
    private let sdef = ArisApps.Command(id: "sdef:make:note", title: "make new note", channel: .sdef, effect: .changeReversible)

    private func plan(_ grant: ArisApps.Grant, background: Bool = false, alternatives: [ArisApps.Command]? = nil) -> ArisApps.Choice.Plan {
        ArisApps.Choice.plan(target: sdef, alternatives: alternatives ?? [menu], record: ArisApps.AppChannels(automation: grant), background: background)
    }

    func testPromptIsACost() {
        XCTAssertEqual(plan(.granted).steps.map(\.command.channel), [.sdef, .menu])
        XCTAssertEqual(plan(.notAsked).steps.map(\.command.channel), [.menu, .sdef])
        XCTAssertEqual(plan(.notAsked).steps.last?.prompts, true)
        XCTAssertEqual(plan(.denied).steps.map(\.command.channel), [.menu])
        XCTAssertTrue(plan(.notAsked, background: true, alternatives: []).steps.isEmpty)
        XCTAssertEqual(plan(.granted, background: true, alternatives: []).steps.count, 1)
    }

    func testTheGrantComesFromThePermissionLayersReading() {
        XCTAssertEqual(ArisApps.Grant(ArisPermissionState.granted), .granted)
        XCTAssertEqual(ArisApps.Grant(ArisPermissionState.denied), .denied)
        XCTAssertEqual(ArisApps.Grant(ArisPermissionState.notAsked), .notAsked)
        XCTAssertEqual(ArisApps.Grant(ArisPermissionState.unknown), .unknown)
        // Not granted yet (or can't tell): the Accessibility route goes first and the Apple Events step is the last
        // resort, said once before it; granted: the scripting dictionary is free.
        for state in [ArisPermissionState.notAsked, .unknown] {
            XCTAssertEqual(plan(ArisApps.Grant(state)).steps.first?.command.channel, .menu)
            XCTAssertEqual(plan(ArisApps.Grant(state)).steps.last?.prompts, true)
        }
        XCTAssertEqual(plan(ArisApps.Grant(.granted)).steps.first?.prompts, false)
    }

    func testNoticeOncePerApp() {
        let only = plan(.notAsked, alternatives: [])
        guard case .sayFirst = ArisApps.Choice.next(only, at: 0, record: ArisApps.AppChannels(automation: .notAsked), appName: "Notes", goAhead: false) else {
            return XCTFail("the sentence comes first")
        }
        XCTAssertEqual(ArisApps.Choice.next(only, at: 0, record: ArisApps.AppChannels(automation: .notAsked, noticeSaid: true), appName: "Notes", goAhead: false),
                       .run(only.steps[0]))
    }

    func testBook() {
        let book = ArisApps.ChannelBook().noting("a", grant: .granted).noting("a", grant: .unknown)
        XCTAssertEqual(book.record("A").automation, .granted)
        let failed = book.noting("a", channel: .menu, worked: false, why: "no").seeing("a", versionKey: "a@2")
        XCTAssertTrue(failed.record("a").failed.isEmpty)
    }
}

final class ArisAppsReadRecipeTests: XCTestCase {
    func testReadAndLocate() {
        let elements = [ArisApps.ReadElement(id: "elem_1", role: "row", label: "엄마", frame: (10, 100, 200, 20)),
                        ArisApps.ReadElement(id: "elem_2", role: "textArea", label: "메시지 입력", value: "", frame: (300, 600, 500, 40)),
                        ArisApps.ReadElement(id: "elem_3", role: "button", label: "보내기", actionable: true, frame: (820, 600, 80, 30))]
        XCTAssertEqual(ArisApps.Read.locate("send button", in: elements), .one(elements[2]))
        XCTAssertEqual(ArisApps.Read.locate("e1", in: elements), .one(elements[0]))
        let page = ArisApps.Read.page(elements, limit: 30)
        XCTAssertNotNil(page.next)
        XCTAssertTrue(page.text.hasPrefix("[e1] row “엄마”"))
    }

    func testRecipes() {
        XCTAssertEqual(ArisApps.Recipes.recipe("message.send")?.effect, .outward)
        XCTAssertEqual(ArisApps.Recipes.fill("q={query|url}", inputs: ["query": "a b&c"], last: nil), "q=a%20b%26c")
        XCTAssertEqual(ArisApps.Recipes.pane("와이파이"), "com.apple.wifi-settings-extension")
        var calls: [String] = []
        let outcome = ArisApps.Recipes.run(ArisApps.Recipes.recipe("browser.search")!, inputs: ["query": "날씨"]) { name, arguments in
            calls.append(arguments["url"]?.string ?? name)
            return ArisApps.Outcome(ok: arguments["app"] == nil, did: name, now: "", effect: .changeReversible)
        }
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(calls.last, "https://www.google.com/search?q=%EB%82%A0%EC%94%A8")
    }

    func testLayout() {
        let displays = [ArisApps.Rect(x: 0, y: 25, width: 1440, height: 875)]
        let window = ArisApps.Rect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertEqual(ArisApps.Layout.frame("left", window: window, displays: displays), ArisApps.Rect(x: 0, y: 25, width: 720, height: 875))
        XCTAssertEqual(ArisApps.Layout.frame("bottom-right", window: window, displays: displays), ArisApps.Rect(x: 720, y: 462, width: 720, height: 437))
        XCTAssertNil(ArisApps.Layout.frame("next-display", window: window, displays: displays))
        XCTAssertEqual(ArisApps.Layout.tile(count: 4, grid: nil, in: displays[0]).count, 4)
        XCTAssertEqual(ArisApps.Layout.tile(count: 2, grid: nil, in: displays[0])[1].x, 720)
    }

    func testSpecs() {
        XCTAssertEqual(ArisApps.Specs.all.count, 24)
        XCTAssertTrue(ArisApps.Specs.all.allSatisfy { !$0.wireName.contains(".") })
        let context = ArisApps.EffectContext(surface: { app, _ in app == "카톡" ? .chat : .plain })
        XCTAssertEqual(ArisApps.Spec.named("app.press")?.effect(.object(["app": .string("카톡"), "keys": .string("return")]), context), .outward)
        XCTAssertEqual(ArisApps.Spec.named("app_read")?.effect(.object([:]), context), .observe)
    }
}

/// The security review's five items: calls that can run code, send or act for good are classified as that.
final class ArisAppsRiskTests: XCTestCase {
    private let context = ArisApps.EffectContext(surface: { app, _ in app == "Terminal" ? .terminal : app == "카톡" ? .chat : .plain },
                                                 label: { _, target in target == "e1" ? "Delete Account" : nil },
                                                 command: { _, _, _ in nil }, pathKind: { $0.hasSuffix(".command") ? .runnable : .document })

    private func effect(_ name: String, _ arguments: [String: ArisApps.JSON]) -> ArisApps.Effect? {
        ArisApps.Spec.named(name)?.effect(.object(arguments), context)
    }

    func testCodeInScriptingCommands() {
        let doScript = ArisApps.Sdef.Command(name: "do script", code: "coredosc", suite: "Terminal", description: "Runs a UNIX shell script or command.",
                                             direct: ArisApps.Sdef.Parameter(name: "", code: "", type: "text", optional: true, description: "The command to execute."),
                                             parameters: [], result: nil)
        XCTAssertTrue(ArisApps.Risk.runsCode(doScript, bundle: "com.apple.Terminal").runs)
        let close = ArisApps.Sdef.Command(name: "close", code: "coreclos", suite: "Standard", description: "Close an object.",
                                          direct: ArisApps.Sdef.Parameter(name: "", code: "", type: "specifier", optional: false, description: "the object for the command"),
                                          parameters: [], result: nil)
        XCTAssertFalse(ArisApps.Risk.runsCode(close, bundle: "com.apple.TextEdit").runs)
        XCTAssertEqual(effect("app.do", ["app": .string("Terminal"), "command": .string("do shell script")]), .changePermanent)
        XCTAssertEqual(effect("app.do", ["app": .string("Notes"), "command": .string("새 메모")]), .changeReversible)
    }

    func testOpening() {
        XCTAssertEqual(effect("app.open", ["url": .string("https://example.com")]), .changeReversible)
        XCTAssertEqual(effect("app.open", ["url": .string("shortcuts://run-shortcut?name=x")]), .changePermanent)
        XCTAssertEqual(effect("app.open", ["url": .string("tel:123")]), .outward)
        XCTAssertEqual(effect("app.open", ["path": .string("/x/go.command")]), .changePermanent)
        XCTAssertEqual(effect("app.open", ["path": .string("/x/a.pdf")]), .changeReversible)
    }

    func testSelectPressType() {
        XCTAssertEqual(effect("app.select", ["app": .string("x"), "target": .string("e1")]), .changePermanent)
        XCTAssertEqual(effect("app.select", ["app": .string("x"), "target": .string("글꼴"), "option": .string("Helvetica")]), .changeReversible)
        XCTAssertEqual(effect("app.press", ["app": .string("카톡"), "keys": .string("⌘↩")]), .outward)
        XCTAssertEqual(effect("app.press", ["app": .string("TextEdit"), "keys": .string("return")]), .changeReversible)
        XCTAssertEqual(effect("app.type", ["app": .string("Terminal"), "text": .string("ls\n")]), .changePermanent)
        XCTAssertEqual(effect("app.type", ["app": .string("카톡"), "text": .string("hi")]), .changeReversible)
    }

    func testShortcutsRunCodeAndLeaveAskingToThePolicy() {
        let shortcut = ArisApps.Commands.fromShortcuts(["Notes cleanup"], app: "Notes")[0]
        XCTAssertEqual(shortcut.effect, .changePermanent)
        let assessed = ArisApps.Risk.command(shortcut, bundle: "com.apple.Notes", arguments: .object([:]))
        XCTAssertEqual(assessed.code, "Notes cleanup")
        XCTAssertFalse(assessed.askAlways)
        let link = ArisApps.Risk.opening(url: "shortcuts://run-shortcut?name=Notes%20cleanup", path: nil, kind: { _ in .document })
        XCTAssertEqual(link.effect, assessed.effect)
        XCTAssertEqual(link.code, "Notes cleanup")
        XCTAssertFalse(link.askAlways)
        let document = ArisApps.Command(id: "open:pdf", title: "open PDF", channel: .document, effect: .changeReversible)
        XCTAssertEqual(ArisApps.Risk.command(document, bundle: "x", arguments: .object(["path": .string("/x/go.command")]),
                                             kind: { $0.hasSuffix(".command") ? .runnable : .document }).effect, .changePermanent)
        XCTAssertEqual(ArisApps.Risk.command(document, bundle: "x", arguments: .object(["path": .string("/x/a.pdf")]), kind: { _ in .document }).effect,
                       .changeReversible)
    }

    func testRecipeWhole() {
        XCTAssertEqual(effect("app.recipe", ["recipe": .string("browser.open"), "inputs": .object(["url": .string("myapp://x")])]), .changePermanent)
        XCTAssertEqual(effect("app.recipe", ["recipe": .string("browser.open"), "inputs": .object(["url": .string("https://example.com")])]), .changeReversible)
        let approved = ArisApps.Assessment.plain(.changeReversible)
        XCTAssertNotNil(ArisApps.Recipes.stepRefusal(.plain(.changePermanent, "a script"), approved: approved))
        XCTAssertNil(ArisApps.Recipes.stepRefusal(.plain(.changeReversible), approved: approved))
    }
}
