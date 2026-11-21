// Tests for jv-vmfix9, the sixth VM run (aris-vmcheck notes6/*, cap6/*): the parts of its defects that live in the
// helper and the app (the pure ones are in Tests/ArisCoreTests/ArisTeachVM6Tests). Each fake does what the VM did, as
// its records and screenshots show it.
// 1  typing after File › New is read back and gets its undo (the read after it used a look's element id);
// 2  an exact menu name that is gone once its app is in front is said as missing, never "greyed out", nothing pressed;
// 3  Settings search finds 저장된 단계 before 할 수 있는 일 › 기억 was shown;
// 4  the app that was in front goes back once, when the call or the replay ends; never Aris; "0 windows" never from a
//    list that couldn't be read;
// 5  a shortened card line ends at a word with "…";
// 6  a failed replay's tag isn't ticked; 정말 지우기 ignores the double-click's second press; the receipt chip's life;
// 7  the observer reads submenus' submenus;
// 8  a System Settings that was already running, sent to by the setup, is hidden at the end.
// Called from main.swift; uses its check().
import Foundation

private let vmfix9Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func vmfix9Source(_ path: String) -> String { (try? String(contentsOf: vmfix9Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runVmfix9Tests() {
    vmfix9TypeAfterNewTests()
    vmfix9MenuMissTests()
    vmfix9FrontBackTests()
    vmfix9WindowCountTests()
    vmfix9SearchTests()
    vmfix9CardLineTests()
    vmfix9MinorTests()
    vmfix9RecorderTests()
    vmfix9SetupTests()
}

// MARK: - Fakes: TextEdit behind Finder, Aris's card may have the keyboard

private final class V9System: ArisAppsSystem {
    let editor = ArisAppsRunning(bundle: "com.apple.TextEdit", name: "TextEdit", pid: 701)
    let finder = ArisAppsRunning(bundle: "com.apple.finder", name: "Finder", pid: 501)
    let safari = ArisAppsRunning(bundle: "com.apple.Safari", name: "Safari", pid: 601)
    let aris = ArisAppsRunning(bundle: "com.lumenjsn.aris", name: "Aris", pid: 900)
    /// The app with the keyboard.
    var front: Int32 = 501
    /// The last app other than Aris that came to the front (ArisAppsOwnerFront's note).
    var lastOwner: Int32? = 501
    var activated: [Int32] = []
    var all: [ArisAppsRunning] { [editor, finder, safari, aris] }
    func installedApps() -> [ArisApps.AppRecord] { [.init(bundle: "com.apple.TextEdit", names: ["TextEdit"], path: "/System/Applications/TextEdit.app")] }
    func runningApps() -> [ArisAppsRunning] { all }
    func frontmost() -> ArisAppsRunning? { all.first { $0.pid == front } }
    func ownerFront() -> ArisAppsRunning? {
        if let now = frontmost(), now.pid != aris.pid { return now }
        return lastOwner.flatMap { pid in all.first { $0.pid == pid } }
    }
    /// He clicks something in an app himself.
    func switchTo(_ pid: Int32) {
        front = pid
        if pid != aris.pid { lastOwner = pid }
    }
    func defaultBrowser() -> String? { "com.apple.Safari" }
    func open(_ request: ArisAppsOpenRequest) -> (ok: Bool, message: String) { (true, "opened") }
    func quit(pid: Int32) -> Bool { true }
    func hide(pid: Int32) -> Bool { true }
    func activate(pid: Int32) -> Bool { activated.append(pid); switchTo(pid); return true }
    func bundleInfo(path: String) -> ArisApps.BundleInfo? { nil }
    func scriptingDictionary(path: String) -> Data? { nil }
    func includedDictionary(path: String) -> Data? { nil }
    func intentsMetadata(path: String) -> Data? { nil }
    func shortcuts() -> [String] { [] }
    func runShortcut(_ name: String, input: String?) -> (ok: Bool, output: String) { (true, "") }
    func automation(bundle: String) -> ArisApps.Grant { .notAsked }
    func runScript(_ source: String, timeout: TimeInterval) -> (ok: Bool, output: String, code: Int?) { (false, "", nil) }
    func pathKind(_ path: String) -> ArisApps.PathKind { .document }
    func displays() -> [ArisApps.Rect] { [ArisApps.Rect(x: 0, y: 25, width: 1440, height: 875)] }
}

/// TextEdit's menus as Cocoa keeps them: an item is checked (its title and whether it is enabled) only while TextEdit
/// is active. In the background the Format menu still reads the title it had at its last check ("Wrap to Page", from
/// the lesson, before the document was wrapped to the page) and is greyed out for want of a key window; in front it
/// reads "Wrap to Window". Select All needs the key window too.
private final class V9AX: ArisAppsAccessibility {
    let system: V9System
    var pressed: [[String]] = []
    var onNew: () -> Void = {}
    /// Something the app does as an item is pressed.
    var onPress: () -> Void = {}
    /// The title the Format menu's wrap item had at its last check (in front it is checked again).
    var staleWrap = "Wrap to Page"
    init(system: V9System) { self.system = system }
    private var active: Bool { system.front == system.editor.pid }
    func menuBar(pid: Int32) -> ArisApps.MenuBar? {
        ArisApps.MenuBar(menus: [
            ArisApps.MenuItem(title: "File", items: [ArisApps.MenuItem(title: "New", key: "N", modifiers: 0)]),
            ArisApps.MenuItem(title: "Edit", items: [ArisApps.MenuItem(title: "Select All", enabled: active, key: "A", modifiers: 0)]),
            ArisApps.MenuItem(title: "Format", items: [ArisApps.MenuItem(title: active ? "Wrap to Window" : staleWrap, enabled: active, key: "W", modifiers: 1),
                                                       ArisApps.MenuItem(title: "Make Plain Text", enabled: active, key: "T", modifiers: 1)]),
        ])
    }
    func pressMenu(pid: Int32, path: [String]) -> (ok: Bool, message: String) {
        guard let item = menuBar(pid: pid)?.item(at: path) else { return (false, "no menu item “\(path.last ?? "")” under “\(path.first ?? "")”") }
        guard item.enabled else { return (false, "“\(item.title)” is greyed out right now") }
        pressed.append(path)
        onPress()
        if path == ["File", "New"] { onNew() }
        return (true, "pressed")
    }
    func setFullScreen(pid: Int32, window: Int, on: Bool) -> Bool { true }
    func focusedRole(pid: Int32) -> String? { "textArea" }
    func caretToEnd(pid: Int32, at point: (x: Double, y: Double)?) -> ArisApps.CaretEnd { .moved }
}

/// TextEdit's windows as the engine (ArisNativeRunner) shows them. Each look numbers its elements in walk order
/// ("elem_1", …). A document that has been changed shows "Edited" in its title bar, walked before its text area; a new
/// document's first change adds it, so the text area's number moves (and the old number is the "Edited" text). The text
/// area has no label, only its identifier "First Text View" (notes6: "typed 9 characters in TextEdit (textArea)").
/// `busyLooks`: looks that come back with nothing right after a new document's first change.
private final class V9Engine: ArisAppsEngine {
    var texts: [Int: String] = [60: "Base doc"]
    var edited: Set<Int> = [60]
    var newAt: Date?
    var typedInto: [Int] = []
    var busyAfterFirstChange = 0
    private var busy = 0
    /// Window lists that fail (TextEdit busy just after it came forward), then the real one.
    var failingLists = 0
    var listed: [Int] { newAt == nil ? [60] : [60, 61] }
    var focused: Int { newAt == nil ? 60 : 61 }
    func run(_ arguments: [String], background: Bool) -> ArisApps.JSON {
        switch (arguments.first ?? "", arguments.dropFirst().first ?? "") {
        case ("window", "list"):
            if failingLists > 0 {
                failingLists -= 1
                return .object(["success": .bool(false), "error": .object(["message": .string("the app isn't answering")])])
            }
            let windows = listed.map { id -> ArisApps.JSON in
                .object(["window_id": .number(Double(id)), "window_title": .string(id == 60 ? "Untitled" : "Untitled 2"), "is_frontmost": .bool(id == focused),
                         "bounds": .object(["x": .number(100), "y": .number(100), "width": .number(800), "height": .number(600)])])
            }
            return .object(["success": .bool(true), "data": .object(["windows": .array(windows)])])
        case ("see", _):
            if busy > 0 {
                busy -= 1
                return .object(["success": .bool(false), "error": .object(["message": .string("TextEdit isn't responding")])])
            }
            let id = Int(arguments[2]) ?? 60
            var elements: [ArisApps.JSON] = [.object(["id": .string("elem_1"), "role": .string("button"), "label": .string("close button")])]
            if edited.contains(id) { elements.append(.object(["id": .string("elem_\(elements.count + 1)"), "role": .string("staticText"), "label": .string("Edited")])) }
            elements.append(.object(["id": .string("elem_\(elements.count + 1)"), "role": .string("textArea"), "label": .string(""), "identifier": .string("First Text View"),
                                     "value": .string(texts[id] ?? ""),
                                     "bounds": .object(["x": .number(100), "y": .number(150), "width": .number(800), "height": .number(400)])]))
            return .object(["success": .bool(true), "data": .object(["snapshot_id": .string("ps_\(id)_\(UUID().uuidString.prefix(4))"), "window_title": .string("Untitled"),
                                                                     "ui_elements": .array(elements)])])
        case ("type", _):
            typedInto.append(focused)
            texts[focused] = (texts[focused] ?? "") + arguments[2]
            if !edited.contains(focused) {
                edited.insert(focused)
                busy = busyAfterFirstChange
            }
            return .object(["success": .bool(true), "data": .object(["delivery": .string("typed")])])
        default:
            return .object(["success": .bool(true), "data": .object([:])])
        }
    }
}

private func v9Hands() -> (ArisAppsHands, V9System, V9AX, V9Engine) {
    let system = V9System()
    let ax = V9AX(system: system), engine = V9Engine()
    ax.onNew = { engine.newAt = Date() }
    let hands = ArisAppsHands(system: system, ax: ax, engine: engine, store: ArisAppsMemoryStore())
    hands.pollSeconds = 0.4
    hands.settleSeconds = 0.3
    hands.readBackSeconds = 0.8
    return (hands, system, ax, engine)
}

/// The replay's own call for "메모 쓰기" step 3 (notes6/R2en-taught.json: target "First Text View 칸", place end).
private let memoLine: ArisApps.JSON = .object(["app": .string("TextEdit"), "text": .string("Memo line"), "target": .string("First Text View 칸"), "at": .string("end")])

// MARK: - 1: typing after File › New

private func vmfix9TypeAfterNewTests() {
    for busy in [0, 1] {
        let (hands, system, _, engine) = v9Hands()
        system.front = system.editor.pid
        engine.busyAfterFirstChange = busy
        let new = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=File › New [cmd+n]")]))
        check(new.ok && new.now.contains("a new window “Untitled 2” opened"), "vmfix9 1: File › New sees its window, as in the VM (\(new.now))")
        let typed = hands.call("app.type", memoLine)
        var inserted: String?
        if case .textInserted(_, let element, _)? = typed.undo { inserted = ArisApps.TextUndo.mark(element)?.inserted }
        let why = busy == 0 ? "the new document's first change renumbered the look" : "and the first look after it came back empty"
        check(typed.ok && typed.verified && inserted == "Memo line" && engine.typedInto == [61] && typed.did == "typed 9 characters in TextEdit (textArea)",
              "vmfix9 1: typing into the brand-new document is verified and undoable (\(why)): \(typed.now), \(String(describing: inserted))")
        check(engine.texts[60] == "Base doc", "vmfix9 1: the old document is untouched")
    }
    // A field that can't be read back at all: the text is in, and the outcome says it can't be undone.
    do {
        let (hands, system, _, engine) = v9Hands()
        system.front = system.editor.pid
        _ = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=File › New [cmd+n]")]))
        engine.busyAfterFirstChange = 100
        let typed = hands.call("app.type", memoLine)
        check(typed.ok && !typed.verified && typed.undo == nil && typed.now == ArisAppsHands.unreadAfterTyping,
              "vmfix9 1: typing that can't be read back says it can't be undone (\(typed.now))")
    }
    // The field found again by what it is, never by a look's element number.
    let before = ArisApps.ReadElement(id: "elem_2", role: "textArea", label: "")
    var area = before
    area.identifier = "First Text View"
    var fresh = [ArisApps.ReadElement(id: "elem_1", role: "button", label: "close button"), ArisApps.ReadElement(id: "elem_2", role: "staticText", label: "Edited"),
                 ArisApps.ReadElement(id: "elem_3", role: "textArea", label: "", value: "Memo line")]
    fresh[2].identifier = "First Text View"
    check(ArisAppsHands.sameField(area, in: fresh)?.id == "elem_3" && ArisAppsHands.sameField(before, in: fresh)?.id == "elem_3",
          "vmfix9 1: the same field in the next look is the text area, not what now has its old number")
    check(ArisAppsHands.sameField(ArisApps.ReadElement(id: "elem_3", role: "button", label: "Send"), in: fresh) == nil,
          "vmfix9 1: never an element of another role")
    // The replay says what stays when a typing has no undo (ArisTeachRunEnd).
    let turn = vmfix9Source("ArisAgent/Teach/ArisTeachTurn.swift")
    check(turn.contains("unchecked.note(call: item.call.name, result: result)") && turn.contains("ArisTeachRunEnd.withUnchecked(account, apps: unchecked.apps, english: english)"),
          "vmfix9 1: the replay's account names typing it couldn't check")
}

// MARK: - 2: an exact name gone once the app is in front

private func vmfix9MenuMissTests() {
    // notes6/D7-failures.txt 17:54:17 and 18:03:34: "“Wrap to Page” is greyed out right now".
    do {
        let (hands, system, ax, _) = v9Hands()
        let done = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Format › Wrap to Page")]))
        check(!done.ok && done.did == "that menu item isn't there now (TextEdit shows ‘Wrap to Window’ instead)" && ax.pressed.isEmpty,
              "vmfix9 2: a stale background title is said as the miss it is, nothing pressed (\(done.did))")
        check(!done.did.contains("greyed out"), "vmfix9 2: an exact-name miss is never “greyed out”")
        check(system.front == system.finder.pid, "vmfix9 2: the app that was in front is back (\(system.activated))")
        check(ArisTeachCopy.reason(done.did, english: false) == "그 메뉴 항목이 지금은 없어요 (앱에는 ‘Wrap to Window’ 항목이 있어요)",
              "vmfix9 2: and in a Korean UI")
    }
    // A miss in the background read itself: nothing is brought forward for it.
    do {
        let (hands, system, ax, _) = v9Hands()
        ax.staleWrap = "Wrap to Window"
        let done = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Format › Wrap to Page")]))
        check(!done.ok && done.did.hasPrefix("that menu item isn't there now") && system.activated.isEmpty && ax.pressed.isEmpty,
              "vmfix9 2: an item not there in the background brings nothing forward and presses nothing (\(done.did))")
    }
    // The same for the app layer's own press, not only through the book's exact lookup.
    do {
        let (hands, system, ax, _) = v9Hands()
        let pressed = hands.pressMenuItem(pid: system.editor.pid, path: ["Format", "Wrap to Page"], app: "TextEdit")
        check(!pressed.ok && pressed.message.hasPrefix("that menu item isn't there now") && ax.pressed.isEmpty, "vmfix9 2: pressMenuItem says the miss (\(pressed.message))")
    }
    // D1 still works: Select All, greyed out only for want of the key window, is pressed with TextEdit in front.
    do {
        let (hands, system, ax, _) = v9Hands()
        let done = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Edit › Select All [cmd+a]")]))
        check(done.ok && ax.pressed == [["Edit", "Select All"]] && system.front == system.finder.pid, "vmfix9 2: an item enabled only in front is still pressed there")
    }
    // Security: the name pressed is the name judged; a near one is never pressed, in front or not.
    do {
        let (hands, _, ax, _) = v9Hands()
        _ = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Format › Wrap to Page")]))
        check(!ax.pressed.contains(["Format", "Wrap to Window"]), "vmfix9 2 security: “Wrap to Window” is never pressed for “Wrap to Page”")
    }
}

// MARK: - 4: the app that was in front goes back once

private func vmfix9FrontBackTests() {
    // notes6/D1-front-poll.txt: Finder in front, his click on the card gave Aris the keyboard, the replay brought TextEdit
    // forward for Edit › Select All, and TextEdit was still in front 5 s after the run.
    do {
        let (hands, system, ax, _) = v9Hands()
        system.switchTo(system.aris.pid)
        hands.beginFrontHold()
        let selected = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Edit › Select All [cmd+a]")]))
        check(selected.ok && ax.pressed == [["Edit", "Select All"]] && system.front == system.editor.pid,
              "vmfix9 4: within a replay TextEdit stays in front for the steps after the press (\(system.activated))")
        _ = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Format › Make Plain Text")]))
        check(system.activated == [system.editor.pid], "vmfix9 4: no flicker: nothing goes back and comes forward between steps (\(system.activated))")
        system.switchTo(system.aris.pid)   // their yes on the next card
        hands.endFrontHold()
        check(system.front == system.finder.pid && system.activated == [system.editor.pid, system.finder.pid],
              "vmfix9 4: the run over, Finder (his app, not Aris) is back in front (\(system.activated))")
        check(!system.activated.contains(system.aris.pid), "vmfix9 4: Aris is never put in front")
    }
    // One call outside a replay: back at its end.
    do {
        let (hands, system, _, _) = v9Hands()
        system.switchTo(system.aris.pid)
        _ = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Edit › Select All [cmd+a]")]))
        check(system.front == system.finder.pid, "vmfix9 4: a single call puts his app back when it ends (\(system.activated))")
    }
    // A run that ends in a failure (the miss) or a declined card still puts it back: the hold ends however the run does.
    do {
        let (hands, system, _, _) = v9Hands()
        hands.beginFrontHold()
        _ = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Format › Wrap to Page")]))
        hands.endFrontHold()
        check(system.front == system.finder.pid, "vmfix9 4: after a failed step, his app is back")
        let turn = vmfix9Source("ArisAgent/Teach/ArisTeachTurn.swift")
        let begin = turn.range(of: "hands.beginFrontHold()")?.lowerBound, run = turn.range(of: "let ended = runner.run(")?.lowerBound,
            end = turn.range(of: "hands.endFrontHold()")?.lowerBound
        check(begin != nil && run != nil && end != nil && begin! < run! && run! < end!, "vmfix9 4: the replay holds the front for its whole run, and lets go once it returns (done, failed, stopped or declined)")
    }
    // He switched apps himself meanwhile: his choice stands.
    do {
        let (hands, system, _, _) = v9Hands()
        hands.beginFrontHold()
        _ = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Edit › Select All [cmd+a]")]))
        system.switchTo(system.safari.pid)
        hands.endFrontHold()
        check(system.front == system.safari.pid && system.activated == [system.editor.pid], "vmfix9 4: an app he went to himself is left in front")
    }
    // Nothing of his to go back to (only Aris was ever in front): nothing is activated.
    do {
        let (hands, system, _, _) = v9Hands()
        system.front = system.aris.pid
        system.lastOwner = nil
        _ = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Edit › Select All [cmd+a]")]))
        check(system.activated == [system.editor.pid], "vmfix9 4: with no app of his known, nothing is put back (and never Aris)")
    }
    let live = vmfix9Source("ArisAgent/Apps/ArisAppsLive.swift")
    check(live.contains("ArisAppsOwnerFront.shared.start()"), "vmfix9 4: the live helper notes the apps that come to the front")
}

// MARK: - 4: "TextEdit now has 0 windows"

private func vmfix9WindowCountTests() {
    // notes6/D1-selectall-record.txt: {"now":"TextEdit now has 0 windows"} after Edit › Select All, with one window
    // open. TextEdit, just brought forward for the press, doesn't answer the window list the first time after it.
    let (hands, system, ax, engine) = v9Hands()
    system.switchTo(system.aris.pid)
    ax.onPress = { engine.failingLists = 1 }
    let done = hands.call("app.do", .object(["app": .string("TextEdit"), "command": .string("=Edit › Select All [cmd+a]")]))
    check(done.ok && !done.now.contains("0 windows"), "vmfix9 4: a window list that couldn't be read is never “0 windows” (\(done.now))")
    engine.failingLists = 1
    check(hands.listedWindows(of: "com.apple.TextEdit") == nil, "vmfix9 4: a list that failed is nil, never empty")
    check(hands.listedWindows(of: "com.apple.TextEdit")?.count == 1, "vmfix9 4: read again, the window is there")
}

// MARK: - 3: Settings search before the page was shown

private func vmfix9SearchTests() {
    // cap6/D8-ko-montage.jpg: 저장, 단계, 수업, saved, steps, lesson all said "찾는 설정이 없어요" in a Korean UI until
    // 할 수 있는 일 › 기억 had been shown once (that page asks the helper for the saved steps; until then they are nil).
    let before = ArisSettingsSnapshot()
    check(before.savedSteps == nil, "vmfix9 3: the snapshot before the helper answered")
    let shown = ArisSettingsBuilder.searchable(before)
    for word in ["저장", "단계", "수업", "saved", "steps", "lesson"] {
        let found = ArisSettingsIndex.search(word, among: shown).map(\.id)
        check(found.contains("memory.saved"), "vmfix9 3: “\(word)” finds 저장된 단계 in a Korean UI before its page was shown (\(found.prefix(4)))")
    }
    let catalog = ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: vmfix9Root.appendingPathComponent("Aris/components/Settings/Settings.xcstrings"))) ?? Data())
    ArisSettingsCopy.install(catalog)
    defer { ArisSettingsCopy.install([:]) }
    let english = ArisSettingsWording.make(page: .able, english: true)
    let alias: (ArisSettingsEntry) -> ArisSettingsIndex.Alias = { .init(title: english.of($0.page, $0.title), page: english.frame($0.page.title)) }
    for word in ["saved", "steps", "lesson", "저장"] {
        check(ArisSettingsIndex.search(word, among: shown, alias: alias).map(\.id).contains("memory.saved"), "vmfix9 3: and in an English UI (“\(word)”)")
    }
    let live = vmfix9Source("Aris/components/Settings/ArisLiveSettings.swift")
    check(live.contains("Task { await memory.loadSavedSteps() }"), "vmfix9 3: the settings window asks for the saved steps as it opens, so the jump finds their rows")
}

// MARK: - 5: card lines

private func vmfix9CardLineTests() {
    let long = String(repeating: "word ", count: 40)
    let cleaned = ArisCardWords.clean(long, limit: 30)
    check(cleaned.hasSuffix("…") && !cleaned.dropLast().hasSuffix(" ") && cleaned.count <= 31 && long.hasPrefix(String(cleaned.dropLast())),
          "vmfix9 5: a brain's word on a card is cut at a word, with “…” (\(cleaned))")
    check(ArisTeachCopy.quoted(String(repeating: "Memo line ", count: 10)).hasSuffix("…’"), "vmfix9 5: a quoted value too")
}

// MARK: - 6: minor

private func vmfix9MinorTests() {
    // 6a: cap6/D7en-card2.jpg "Doing “랩 메모” ✓" above "Step 2 didn't work".
    let session = ArisSession().listening().hearing("do 랩 메모").thinking().working("Doing “랩 메모” 2/3").stepFailed(nil)
    check(session.tags.first?.failed == true && session.tags.first?.done == true, "vmfix9 6a: the run's tag shows it didn't finish, never a tick")
    let turn = vmfix9Source("ArisAgent/Teach/ArisTeachTurn.swift")
    let failed = turn.range(of: "if ArisTeachRunEnd.marksTagFailed(ended.outcome) { stream(.stepFailed(nil), on: connection) }")?.lowerBound,
        answered = turn.range(of: "stream(.answer(ArisTeachRunEnd.withUnchecked(")?.lowerBound
    check(failed != nil && answered != nil && failed! < answered!, "vmfix9 6a: the tag is marked before the answer settles the turn")
    // The failed face is the tag's own still mark (no blinking or pulsing dot: the standing design rule).
    let tag = vmfix9Source("Aris/private/Aris/Home/ArisActivityTag.swift")
    check(tag.contains("if failed {"), "vmfix9 6a: a failed tag has its own still face")

    // 6b: 정말 지우기 comes up where 지우기 was.
    typealias R = ArisSavedStepsSettingsRows
    let shownAt = Date(timeIntervalSince1970: 1_800_000_000)
    check(!R.confirmCounts(since: shownAt, now: shownAt.addingTimeInterval(0.25)), "vmfix9 6b: a double-click's second press on 정말 지우기 does nothing")
    check(R.confirmCounts(since: shownAt, now: shownAt.addingTimeInterval(R.confirmGrace)), "vmfix9 6b: a press after a moment is his second decision")
    check(!R.confirmCounts(since: nil, now: shownAt), "vmfix9 6b: never before it was shown")
    let model = vmfix9Source("Aris/private/Aris/ArisMemorySettingsModel.swift")
    check(model.contains("if confirmingForget == key, !ArisSavedStepsSettingsRows.confirmCounts(since: confirmingSince, now: Date()) { return false }"),
          "vmfix9 6b: the model ignores the press that came too soon")
    var s = ArisSettingsSnapshot()
    s.savedSteps = [ArisSavedStepsItem(key: "plain", request: "정리", steps: ["a"], stepsEn: ["a"], apps: "Finder", saved: "")]
    s.savedStepsConfirming = "plain"
    check(R.sections(s, english: false).first?.rows.first?.control == .buttons([ArisSettingButton(title: R.cancel, action: .keepSavedSteps),
                                                                                 ArisSettingButton(title: R.really, action: .forgetSavedSteps("plain"), kind: .danger)]),
          "vmfix9 6b: the row looks as the other destructive rows do (취소, 정말 지우기)")

    // 6c: the receipt chip lives about five seconds by its contract; it is not kept for a reopened notch.
    check(ArisReceiptClock.stay == 5, "vmfix9 6c: the receipt line stays about five seconds (ArisReceipt), by design")
}

// MARK: - 7: the observer's menus

private func vmfix9RecorderTests() {
    let live = vmfix9Source("ArisAgent/Teach/ArisTeachLiveObserver.swift")
    check(live.contains("guard depth < 3, items.count < 600 else { return }"), "vmfix9 7b: a menu's submenus and theirs are read for key equivalents")
}

// MARK: - 8: a System Settings that was running before the setup sent the user there

private func vmfix9SetupTests() {
    // notes6/setup-walk.txt: System Settings running from login (pid 397); page 1's Accessibility Allow sent the user
    // there; the password sheet; Aris back; … Start: System Settings frontmost and visible.
    var leave = ArisSetupLeave(frontApp: "com.apple.finder")
    leave.sending(runningPid: 397)
    leave.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 397, sinceForward: nil)
    leave.cameForward(.agent, bundleID: "com.apple.SecurityAgent", settingsPid: 397, sinceForward: nil)
    leave.cameForward(.aris, bundleID: "com.lumenjsn.aris", settingsPid: 397, sinceForward: 0.1)
    let granted = leave.planOnGranted(runningPid: 397)
    check(granted.hidesSettings, "vmfix9 8: Accessibility on, the System Settings the setup sent the user to is put away, though it was running before")
    leave.putAway()
    // macOS hands the screen back to it after Start, as in the VM.
    leave.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 397, sinceForward: 0.2)
    check(leave.plan(runningPid: 397, quitting: false) == ArisSetupLeave.Plan(hidesSettings: true, activates: "com.apple.finder"),
          "vmfix9 8: at the end it is hidden (never quit) and Finder comes forward")
    // He went back to it himself: it is his.
    var his = ArisSetupLeave(frontApp: "com.apple.finder")
    his.sending(runningPid: 397)
    his.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 397, sinceForward: nil)
    his.cameForward(.aris, bundleID: "com.lumenjsn.aris", settingsPid: 397, sinceForward: 0.1)
    his.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 397, sinceForward: 40)
    check(his.plan(runningPid: 397, quitting: false) == ArisSetupLeave.Plan(), "vmfix9 8: one he went back to by himself is left alone")
    let guide = vmfix9Source("Aris/private/Aris/Onboarding/ArisOnboardingGuide+Leave.swift")
    check(guide.contains("settings?.hide()") && !guide.contains("terminate()"), "vmfix9 8: hidden, never quit")
}
