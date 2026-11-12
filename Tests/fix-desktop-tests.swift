//
//  fix-desktop-tests.swift
//  The 2026-11-10 audit's computer-use findings (desk-1 … desk-12, qa/audit-1110/desktop.json). Nothing here touches a
//  real app, key or screen: a fake Peekaboo (a shell script answering from a queue of envelopes made in the test), fake
//  window lists, a fake front app and clipboard, and the pure decision functions.
//

import CoreGraphics
import Foundation

// MARK: - The rig

/// The fake Peekaboo: logs its argv and answers each command from its queue in order, else from a standing reply.
private let fixPeekabooScript = """
    #!/bin/bash
    S="$(pwd)"
    printf '%s\\n' "$*" >> "$S/calls.log"
    key="$1"; case "$1" in menu|dialog|window|app|dock) key="$1-$2";; esac
    path=""; prev=""
    for a in "$@"; do [ "$prev" = "--path" ] && path="$a"; prev="$a"; done
    first=$(ls "$S/queue/$key" 2>/dev/null | sort | head -1)
    if [ -n "$first" ]; then out=$(cat "$S/queue/$key/$first"); rm -f "$S/queue/$key/$first"
    elif [ -f "$S/replies/$key.json" ]; then out=$(cat "$S/replies/$key.json")
    else echo '{"success":false,"error":{"code":"NO_FIXTURE","message":"no fixture"}}'; exit 1; fi
    if [ -n "$path" ]; then cp "$S/canvas.png" "$path"; ann="${path%.png}_annotated.png"; cp "$S/canvas.png" "$ann"; out="${out//__PATH__/$path}"; out="${out//__ANNOTATED__/$ann}"; fi
    printf '%s\\n' "$out"
    """

private final class FixDownload: ArisDesktopDownloading {
    var archive: URL?
    func fetch(_ url: URL, to file: URL) -> String? {
        guard let archive else { return "offline" }
        do { try FileManager.default.copyItem(at: archive, to: file) } catch { return "copy failed" }
        return nil
    }
}

private final class FixApps: ArisDesktopApps {
    var apps: [String: ArisDesktopTarget] = [:]
    var secureInput = false
    var front: Int32? = 4242
    var keyFrame: CGRect? = CGRect(x: 80, y: 329, width: 1040, height: 720)
    /// The clipboard's change count, one value a read (the last repeats): a copy moves it.
    var clipboard: [Int] = [1]
    /// Whether the window's document has unsaved changes, one value a read (the last repeats); empty: can't be told.
    var edited: [Bool] = []
    func resolve(_ name: String) -> ArisDesktopTarget? { apps[name.lowercased()] }
    func installed(_ name: String) -> ArisDesktopTarget? { apps[name.lowercased()] }
    func dock() -> ArisDesktopTarget? { nil }
    /// Whether the app is still running, one value a read (the last repeats).
    var running: [Bool] = [true]
    func isRunning(_ target: ArisDesktopTarget) -> Bool { running.count > 1 ? running.removeFirst() : running.first ?? true }
    func shownPath(_ target: ArisDesktopTarget, window: Int?) -> String? { nil }
    func frontmostPid() -> Int32? { front }
    func focusedWindowFrame(pid: Int32) -> CGRect? { pid == front ? keyFrame : nil }
    func secondsSinceKeyDown() -> Double { 999 }
    func focusedInWebArea(pid: Int32) -> Bool? { false }
    func identity(pid: Int32) -> ArisCardTarget? { pid > 0 ? ArisCardTarget(pid: pid, bundle: "fake.\(pid)", started: 1) : nil }
    var arisPid: Int32?
    func isAris(pid: Int32) -> Bool { pid == arisPid }
    func clipboardChanges() -> Int? { clipboard.count > 1 ? clipboard.removeFirst() : clipboard.first }
    func documentEdited(pid: Int32, frame: CGRect) -> Bool? { edited.count > 1 ? edited.removeFirst() : edited.first }
}

private final class FixWindows: ArisDesktopWindows {
    var byPid: [Int32: [ArisDesktopWindow]] = [:]
    func windows(of pid: Int32) -> [ArisDesktopWindow] { byPid[pid] ?? [] }
    func topWindow(at point: CGPoint) -> (pid: Int32, id: Int)? { nil }
    func promptOnScreen() -> String? { nil }
}

private final class FixAccess: ArisDesktopAccess {
    var trusted = true
    var screenRecording = true
    var guided = 0, guidedScreen = 0
    func guide() { guided += 1 }
    func guideScreen() { guidedScreen += 1 }
}

private final class FixPointer: ArisDesktopPointer {
    func save() -> ArisDesktopPointerState { ArisDesktopPointerState(location: CGPoint(x: 5, y: 6), frontmost: 1) }
    func restore(_ state: ArisDesktopPointerState) {}
}

private final class FixVision: ArisDesktopVision {
    var pick: ArisDesktopPick?
    /// The brains that can look at a picture on this (fake) Mac.
    var sees: Set<ArisBrain> = [.claude]
    var asked: [ArisBrain] = []
    func locate(png: Data, width: Int, height: Int, target: String, marks: [String]) -> ArisDesktopPick? { pick }
    func available(for brain: ArisBrain) -> Bool { !sees.isEmpty }
    func locate(png: Data, width: Int, height: Int, target: String, marks: [String], brain: ArisBrain) -> ArisDesktopPick? { asked.append(brain); return pick }
}

private final class FixReader: ArisDesktopTextReader {
    var texts: [String] = []
    func read(png: Data) -> [(text: String, box: CGRect)] { texts.map { ($0, CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)) } }
}

private final class FixTurn: ArisDesktopTurn {
    let brain: ArisBrain
    let ledger = ArisComputerUseLedger()
    var brainName: String { brain.title }
    var foreign = ArisTaint.none
    var appsRead: Set<String> = []
    var handsFree = false, isTask = false, screen = false, relayed = false
    var answer: ArisMCPAnswer = .yes([:])
    var cards: [ArisMCPCard] = []
    var audits: [[String: String]] = []
    var steps = 0
    var live = true
    var request = ""

    init(_ request: String = "", brain: ArisBrain = .claude) {
        self.request = request
        self.brain = brain
    }

    var taint: ArisTaint { appsRead.isEmpty ? foreign : .outsideText }
    func taint(forApp app: String) -> ArisTaint { appsRead.subtracting([app]).isEmpty ? foreign : .outsideText }
    func markAppRead(_ app: String) { appsRead.insert(app) }
    func takeOutsideText() { foreign = .outsideText }
    func ask(_ card: ArisMCPCard, answer done: @escaping (ArisMCPAnswer) -> Void) { cards.append(card); done(answer) }
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { done(.allow(note: "")) }
    func quiet(_ status: String) {}
    func audit(_ fields: [String: String]) { audits.append(fields) }
    func operating(_ target: ArisOperatingTarget) {}
    func desktopStep() -> Int { steps += 1; return steps }
}

private func fixTarget(_ name: String, bundle: String, pid: Int32 = 4242, sending: Bool = false) -> ArisDesktopTarget {
    ArisDesktopTarget(name: name, bundle: bundle, pid: pid, known: true, never: false, browser: false, sending: sending)
}

private let fixEditor = fixTarget("TextEdit", bundle: "com.apple.TextEdit")
private let fixChat = fixTarget("카카오톡", bundle: "com.kakao.KakaoTalkMac", sending: true)
private let fixFrame = CGRect(x: 80, y: 329, width: 1040, height: 720)
private let fixIdentity = ArisDesktopIdentity(userName: "testuser", fullName: "Alex Tester", home: "/Users/testuser")

/// One element of a made-up `see`: Peekaboo's own keys.
private func fixElement(_ id: Int, _ role: String, _ label: String, value: String? = nil, x: Double = 100, y: Double = 400, width: Double = 800, height: Double = 400,
                        selected: (Int, Int)? = nil, actionable: Bool = false) -> [String: Any] {
    var element: [String: Any] = ["id": "elem_\(id)", "role": role, "label": label, "is_actionable": actionable,
                                  "bounds": ["x": x, "y": y, "width": width, "height": height],
                                  "ax_role": role == "textArea" ? "AXTextArea" : role == "textField" ? "AXTextField" : role == "button" ? "AXButton" : "AXStaticText"]
    if let value { element["value"] = value }
    if let selected { element["selected_text_range"] = ["location": selected.0, "length": selected.1] }
    return element
}

private var fixSnapshots = 0

/// A `see` envelope of one window, made in the test (`focus`: the element that has the keyboard focus).
private func fixSee(window: Int = 9189, title: String, elements: [[String: Any]], focus: Int? = nil, dialog: Bool = false) -> Data {
    fixSnapshots += 1
    var data: [String: Any] = ["snapshot_id": "ps1_" + String(format: "%032x", fixSnapshots), "window_title": title, "ui_elements": elements, "is_dialog": dialog,
                               "application_name": "Fake", "screenshot_raw": "__PATH__", "screenshot_annotated": "__ANNOTATED__"]
    if let focus, let element = elements.first(where: { $0["id"] as? String == "elem_\(focus)" }), let bounds = element["bounds"] as? [String: Double] {
        data["focused_element"] = ["frame": [[bounds["x"] ?? 0, bounds["y"] ?? 0], [bounds["width"] ?? 0, bounds["height"] ?? 0]], "role": element["ax_role"] ?? "",
                                   "processIdentifier": 4242, "windowID": window]
    }
    let object: [String: Any] = ["success": true, "data": data, "target_receipt": ["pid": 4242, "window_id": window]]
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
}

/// Keys, a click or typing that Peekaboo sent on (nothing verified: the controller reads the window back).
private let fixSent = Data(#"{"success":true,"data":{},"outcome":{"dispatch_state":"dispatched","mutation_dispatched":true,"retry_safe":false,"state":"dispatched_unverified"},"target_receipt":{"pid":4242,"window_id":9189}}"#.utf8)

/// A document window's look: one text area holding `text` (`selected`: its caret or selection), focused.
private func fixDocument(window: Int = 9189, title: String, text: String, selected: (Int, Int)? = nil) -> Data {
    fixSee(window: window, title: title, elements: [fixElement(1, "textArea", "body", value: text, selected: selected)], focus: 1)
}

private final class FixRig {
    let root: URL
    let apps = FixApps()
    let windows = FixWindows()
    let access = FixAccess()
    let vision = FixVision()
    let reader = FixReader()
    let installer: ArisDesktopInstaller
    private let download = FixDownload()
    lazy var engine = ArisDesktopEngine(installer: installer, apps: apps, access: access, windows: windows, pointer: FixPointer(), vision: vision,
                                        reader: reader, identity: fixIdentity, tools: "/tools/aris-tools")

    init(_ target: ArisDesktopTarget = fixEditor, windows list: [ArisDesktopWindow] = [ArisDesktopWindow(id: 9189, frame: fixFrame, title: "무제")]) {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix-desktop-\(UUID().uuidString)")
        let files = root.appendingPathComponent("archive-files/peekaboo-macos-test")
        try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let contents = [ArisDesktopRelease.binaryName: fixPeekabooScript, ArisDesktopRelease.libraryName: "not a real library", ArisDesktopRelease.licenceName: "MIT License"]
        for (name, text) in contents {
            FileManager.default.createFile(atPath: files.appendingPathComponent(name).path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o755])
        }
        let archive = root.appendingPathComponent("fake.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path, "-C", root.appendingPathComponent("archive-files").path, "peekaboo-macos-test"]
        try? tar.run()
        tar.waitUntilExit()
        let hashes = Dictionary(uniqueKeysWithValues: contents.keys.map { ($0, ArisDesktopInstaller.sha256(of: files.appendingPathComponent($0)) ?? "") })
        let release = ArisDesktopRelease(version: "9.9.9-test", archives: [ArisDesktopRelease.machine: .init(
            url: URL(string: "https://github.com/openclaw/Peekaboo/releases/download/v9.9.9/fake.tar.gz")!,
            sha256: ArisDesktopInstaller.sha256(of: archive) ?? "", folder: "peekaboo-macos-test", files: hashes)])
        download.archive = archive
        installer = ArisDesktopInstaller(root: root.appendingPathComponent("runtime"), release: release, downloader: download, retryAfter: 60)
        _ = installer.ready()
        let canvas = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/peekaboo/canvas.png")
        try? FileManager.default.copyItem(at: canvas, to: installer.stateFolder.appendingPathComponent("canvas.png"))
        apps.apps[target.name.lowercased()] = target
        windows.byPid[target.pid] = list
    }

    private var queued = 0
    /// Answers in order: each `(command, envelope)` is answered once.
    func queue(_ items: [(String, Data)]) {
        for (key, data) in items {
            let folder = installer.stateFolder.appendingPathComponent("queue/\(key)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            queued += 1
            FileManager.default.createFile(atPath: folder.appendingPathComponent(String(format: "%05d.json", queued)).path, contents: data)
        }
    }

    /// What Peekaboo was asked, in order (its own clean-up aside).
    var calls: [String] {
        ((try? String(contentsOf: installer.stateFolder.appendingPathComponent("calls.log"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init).filter { !$0.hasPrefix("clean ") }
    }

    func run(_ words: [String], text: String? = nil, turn: FixTurn) -> ArisMCPOutcome {
        nonisolated(unsafe) var result: ArisMCPOutcome?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            self.engine.handle(words, text: text, turn: turn) { result = $0; done.signal() }
        }
        _ = done.wait(timeout: .now() + 60)
        return result ?? .failed("no answer")
    }

    /// The ref of the element with this label, as the brain would copy it from a look's output.
    func ref(_ label: String, in output: String) -> String {
        output.split(separator: "\n").first { $0.hasPrefix("@") && $0.contains("“\(label)”") }.flatMap { $0.split(separator: " ").first }.map(String.init) ?? "@none:e1"
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

private func fixSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

func runFixDesktopTests() {
    fixDeskNamedWindowTests()
    fixDeskReplaceGuardTests()
    fixDeskQuietKeyTests()
    fixDeskRelayTurnTests()
    fixDeskChildFeedTests()
    fixDeskAsideUnansweredTests()
    fixDeskVisionTests()
    fixDeskFrontDocumentTests()
    fixDeskBlindSendTests()
    fixDeskKeyLayoutTests()
    fixDeskBatchRenameTests()
    fixDeskCatalogTests()
    fixDeskCatalogWindowTests()
    fixDeskAppNameTests()
    fixDeskAsideCLITests()
    fixDeskQuitTests()
}

// MARK: - desk-1: a call with no ref goes to the window the user named, never the front one

private func fixDeskNamedWindowTests() {
    let front = ArisDesktopWindow(id: 9190, frame: CGRect(x: 200, y: 200, width: 900, height: 600), title: "무제 2")
    let named = ArisDesktopWindow(id: 9189, frame: fixFrame, title: "무제")
    let said = "TextEdit 무제 창 내용 다 지워 줘"

    // The words: press and click-at may name their window.
    let pressTitled = try? ArisDesktopWords.parse(["press", "cmd+a", "delete", "--app", "TextEdit", "--title", "무제"]).get()
    let pressById = try? ArisDesktopWords.parse(["press", "return", "--app", "TextEdit", "--window", "9189"]).get()
    let clickTitled = try? ArisDesktopWords.parse(["click-at", "--app", "TextEdit", "--target", "저장", "--title", "무제"]).get()
    check(pressTitled?.title == "무제" && pressTitled?.keys == ["cmd+a", "delete"] && pressById?.window == 9189 && clickTitled?.title == "무제",
          "desk-1: press and click-at take --window and --title")
    check((try? ArisDesktopWords.parse(["see", "--app", "TextEdit", "--window-id", "9189"]).get()) == nil
          && ArisWindowNaming.chooseLine(app: "TextEdit", windows: [front, named]).contains("--window <id>") && !ArisWindowNaming.chooseLine(app: "TextEdit", windows: [front, named]).contains("--window-id <id>"),
          "desk-1: the several-windows line names the flag the engine reads (--window), never Peekaboo's own --window-id")

    // The decision, pure.
    let press = ArisDesktopRequest(verb: .press, keys: ["cmd+a", "delete"])
    check(ArisDesktopAim.decide(press, named: named, windows: [front, named], app: "TextEdit") == .window(9189),
          "desk-1: keys with no window named in the call go to the window the user named, not the front one")
    check(ArisDesktopAim.decide(press, named: nil, windows: [front, named], app: "TextEdit") == .asIs, "desk-1: with no window named by anyone, a press is as it was")
    var elsewhere = press
    elsewhere.title = "무제 2"
    if case .refuse(let why, _) = ArisDesktopAim.decide(elsewhere, named: named, windows: [front, named], app: "TextEdit") {
        check(why.contains("named the window “무제”") && why.contains("--title \"무제\""), "desk-1: keys aimed at another window than the named one are refused, with the way to aim them")
    } else { check(false, "desk-1: keys aimed at another window than the named one are refused, with the way to aim them") }
    var same = press
    same.title = "무제"
    check(ArisDesktopAim.decide(same, named: named, windows: [front, named], app: "TextEdit") == .window(9189)
          && ArisDesktopAim.decide(same, named: nil, windows: [front, named], app: "TextEdit") == .window(9189), "desk-1: a title that picks one window pins the call to its id")
    var missing = press
    missing.title = "없는 창"
    if case .refuse(let why, _) = ArisDesktopAim.decide(missing, named: nil, windows: [front, named], app: "TextEdit") {
        check(why.contains("No window of TextEdit is titled"), "desk-1: a title that names no window stops before any card")
    } else { check(false, "desk-1: a title that names no window stops before any card") }
    let menu = ArisDesktopRequest(verb: .menuClick, path: "파일 > 저장")
    if case .refuse(let why, _) = ArisDesktopAim.decide(menu, named: named, windows: [front, named], app: "TextEdit") {
        check(why.contains("desktop window focus --app \"TextEdit\" --title \"무제\""), "desk-1: a menu call with another document in front is refused, with the way to bring the named one forward")
    } else { check(false, "desk-1: a menu call with another document in front is refused, with the way to bring the named one forward") }
    let sheet = ArisDesktopWindow(id: 9300, frame: CGRect(x: 300, y: 400, width: 500, height: 300), title: nil)
    let dialog = ArisDesktopRequest(verb: .dialogClick, button: "저장")
    check(ArisDesktopAim.decide(dialog, named: named, windows: [sheet, named, front], app: "TextEdit") == .asIs
          && ArisDesktopAim.decide(menu, named: named, windows: [named, front], app: "TextEdit") == .asIs
          && ArisDesktopAim.decide(dialog, named: named, windows: [front, named], app: "TextEdit", isDialog: { $0 == 9190 }) == .asIs,
          "desk-1: the named window in front, or only its own sheet or dialog over it, lets a menu or dialog call through")
    let close = ArisDesktopRequest(verb: .window, operation: "close")
    var closeOther = close
    closeOther.title = "무제 2"
    check(ArisDesktopAim.decide(close, named: named, windows: [front, named], app: "TextEdit") == .window(9189)
          && ArisDesktopAim.decide(closeOther, named: named, windows: [front, named], app: "TextEdit") == .asIs,
          "desk-1: a window operation that names no window is for the one the user named; one that names its own is left alone")
    var withRef = ArisDesktopRequest(verb: .click)
    withRef.ref = ArisDesktopRef(snapshot: "sabcd1", element: 1)
    check(ArisDesktopAim.decide(withRef, named: named, windows: [front, named], app: "TextEdit") == .asIs
          && ArisDesktopAim.decide(ArisDesktopRequest(verb: .see), named: named, windows: [front, named], app: "TextEdit") == .asIs,
          "desk-1: a ref carries its own window, and a look is never re-aimed here")

    // The engine: the user names 무제 with 무제 2 in front; the keys go to 무제, and their card names it.
    let rig = FixRig(windows: [front, named])
    let turn = FixTurn(said)
    rig.queue([("see", fixDocument(title: "무제", text: "회의록 초안")), ("press", fixSent), ("see", fixDocument(title: "무제", text: ""))])
    let emptied = rig.run(["press", "cmd+a", "delete", "--app", "TextEdit"], turn: turn)
    check(emptied.status == 0 && rig.calls.first?.hasPrefix("see --window-id 9189") == true && !rig.calls.contains { $0.contains("9190") },
          "desk-1: `press cmd+a delete` is looked at and pressed in the named window only: \(rig.calls) \(emptied.output.prefix(160))")
    check(turn.cards.count == 1 && turn.cards[0].detail.contains("창: “무제”") && !turn.cards[0].detail.contains("무제 2"),
          "desk-1: the card names the window the keys go to, even with no look at it before: \(turn.cards.first?.detail ?? "")")
    // With TextEdit's yes remembered there is no card: still the named window.
    let quick = FixRig(windows: [front, named])
    let again = FixTurn(said)
    again.ledger.remember(fixEditor.memoryKey ?? "", tainted: false)
    quick.queue([("see", fixDocument(title: "무제", text: "회의록 초안")), ("press", fixSent), ("see", fixDocument(title: "무제", text: ""))])
    let remembered = quick.run(["press", "cmd+a", "delete", "--app", "TextEdit"], turn: again)
    check(remembered.status == 0 && again.cards.isEmpty && quick.calls.first?.hasPrefix("see --window-id 9189") == true && !quick.calls.contains { $0.contains("9190") },
          "desk-1: with the app's yes remembered (no card) the keys still go to the named window: \(quick.calls)")
    // Aimed elsewhere by the brain: nothing is looked at or pressed, and no card goes up.
    let refused = FixRig(windows: [front, named])
    let third = FixTurn(said)
    let wrong = refused.run(["press", "cmd+a", "delete", "--app", "TextEdit", "--title", "무제 2"], turn: third)
    check(wrong.status != 0 && wrong.output.contains("named the window “무제”") && refused.calls.isEmpty && third.cards.isEmpty,
          "desk-1: a press the brain aimed at the other window is refused before any card or key")
    let menuRun = refused.run(["menu", "click", "--app", "TextEdit", "--path", "파일 › 저장"], turn: third)
    check(menuRun.status != 0 && menuRun.output.contains("desktop window focus") && refused.calls.isEmpty && third.cards.isEmpty,
          "desk-1: a menu click with the other document in front is refused before any card")
    // A window operation with no window named closes the one the user named.
    let closing = FixRig(windows: [front, named])
    let fourth = FixTurn("TextEdit 무제 창 닫아 줘")
    closing.queue([("window-close", fixSent)])
    _ = closing.run(["window", "close", "--app", "TextEdit"], turn: fourth)
    check(closing.calls == ["window close --window-id 9189 --json"], "desk-1: `window close` with no window named closes the one the user named: \(closing.calls)")
}

// MARK: - desk-3: the replace guard

private func fixDeskReplaceGuardTests() {
    let oneStep = [ArisDesktopStep(verb: .press, keys: ["cmd+a", "delete"])]
    check(ArisDesktopBatch.replacesAll(oneStep) && ArisDesktopBatch.replacesAll([ArisDesktopStep(verb: .press, keys: ["a+cmd", "backspace"])]),
          "desk-3: `press cmd+a delete` in one step is a replace")
    check(ArisDesktopBatch.replacesAll([ArisDesktopStep(verb: .press, keys: ["cmd+a"]), ArisDesktopStep(verb: .press, keys: ["delete", "cmd+a"])])
          && !ArisDesktopBatch.replacesAll([ArisDesktopStep(verb: .press, keys: ["delete", "cmd+a"])])
          && !ArisDesktopBatch.replacesAll([ArisDesktopStep(verb: .press, keys: ["cmd+a", "cmd+c"])]),
          "desk-3: a delete after a select-all counts wherever it is; a delete before one, or a copy, doesn't")
    check(ArisDesktopBatch.selectsThenDeletes(["cmd+a", "delete"]) && !ArisDesktopBatch.selectsThenDeletes(["delete", "cmd+a"]) && !ArisDesktopBatch.selectsThenDeletes(["cmd+a"]),
          "desk-3: one press selects and deletes only with the delete after the select-all")
    check(ArisDesktopBatch.leavesAllSelected(["cmd+a"]) == true && ArisDesktopBatch.leavesAllSelected(["cmd+a", "cmd+c"]) == true
          && ArisDesktopBatch.leavesAllSelected(["cmd+a", "delete"]) == false && ArisDesktopBatch.leavesAllSelected(["cmd+down"]) == false
          && ArisDesktopBatch.leavesAllSelected(["cmd+s"]) == nil, "desk-3: what a press leaves selected is its last word on the selection")
    check(ArisDesktopBatch.asksToReplace("무제 창 내용 전부 삭제해 줘") && ArisDesktopBatch.asksToReplace("이 문서 싹 비워 줘") && ArisDesktopBatch.asksToReplace("delete everything in it")
          && !ArisDesktopBatch.asksToReplace("지우에게 보낼 글을 써 줘") && !ArisDesktopBatch.asksToReplace("무제 창에 회의 끝 이라고 덧붙여 줘"),
          "desk-3: emptying a document is the user's to ask for (삭제, 비워, delete); a name like 지우 or “덧붙여” isn't asking")

    // "덧붙여 줘", and the brain runs the one-step form the prompt teaches: refused before any card, nothing pressed.
    let adding = "TextEdit 무제 창에 회의 끝 이라고 덧붙여 줘"
    let rig = FixRig()
    let turn = FixTurn(adding)
    turn.ledger.remember(fixEditor.memoryKey ?? "", tainted: false)
    let emptied = rig.run(["press", "cmd+a", "delete", "--app", "TextEdit"], turn: turn)
    check(emptied.output == ArisDesktopBatch.appendLine && rig.calls.isEmpty && turn.cards.isEmpty,
          "desk-3: `press cmd+a delete` when the user asked to add is refused, with the app's yes remembered too: nothing is pressed")
    // The same in a batch of one step.
    rig.queue([("see", fixDocument(title: "무제", text: "첫 줄"))])
    _ = rig.run(["see", "--app", "TextEdit"], turn: turn)
    let before = rig.calls.count
    let batched = rig.run(["batch", "--app", "TextEdit", "--stdin"], text: "press cmd+a delete", turn: turn)
    check(batched.output == ArisDesktopBatch.appendLine && rig.calls.count == before, "desk-3: a one-step batch `press cmd+a delete` is refused the same way")

    // A lone select-all whose keys went out, then a type: the type would replace the document, so it is refused; after
    // the caret is moved to the end, typing adds again.
    let lone = FixRig()
    let second = FixTurn(adding)
    second.ledger.remember(fixEditor.memoryKey ?? "", tainted: false)
    // The window can't show the selection here (no range in the look): the select-all still counts once its keys went out.
    lone.queue([("see", fixDocument(title: "무제", text: "첫 줄")), ("press", fixSent), ("see", fixDocument(title: "무제", text: "첫 줄"))])
    let selected = lone.run(["press", "cmd+a", "--app", "TextEdit"], turn: second)
    check(second.ledger.selectedAll(in: 9189), "desk-3: a select-all whose keys went out is noted even when the window can't show it: \(selected.output.prefix(80))")
    let body = lone.ref("body", in: selected.output)
    let pressed = lone.calls.count
    let typed = lone.run(["type", body, "--stdin"], text: "회의 끝", turn: second)
    check(typed.output.contains(ArisDesktopBatch.appendLine) && lone.calls.count == pressed, "desk-3: a type after a lone select-all is refused when the user asked to add: nothing is typed")
    lone.queue([("see", fixDocument(title: "무제", text: "첫 줄", selected: (0, 3))), ("press", fixSent), ("see", fixDocument(title: "무제", text: "첫 줄", selected: (3, 0)))])
    let moved = lone.run(["press", "cmd+down", "--app", "TextEdit"], turn: second)
    check(moved.status == 0 && !second.ledger.selectedAll(in: 9189), "desk-3: moving the caret to the end ends the selection, so the advice in the refusal can be followed: \(moved.output.prefix(80))")
    // Still selected after the caret key (the look says so): the mark stays.
    let stuck = FixRig()
    let third = FixTurn(adding)
    third.ledger.remember(fixEditor.memoryKey ?? "", tainted: false)
    third.ledger.noteSelectAll(window: 9189)
    stuck.queue([("see", fixDocument(title: "무제", text: "첫 줄", selected: (0, 3))), ("press", fixSent), ("see", fixDocument(title: "무제", text: "첫 줄", selected: (0, 3)))])
    _ = stuck.run(["press", "cmd+down", "--app", "TextEdit"], turn: third)
    check(third.ledger.selectedAll(in: 9189), "desk-3: a caret key that left everything selected doesn't end the mark")

    // The user asked to empty it: it goes through, and their card says first that everything is deleted.
    let asked = FixRig()
    let fourth = FixTurn("TextEdit 무제 창 내용 다 지워 줘")
    asked.queue([("see", fixDocument(title: "무제", text: "첫 줄")), ("press", fixSent), ("see", fixDocument(title: "무제", text: ""))])
    let done = asked.run(["press", "cmd+a", "delete", "--app", "TextEdit"], turn: fourth)
    check(done.status == 0 && fourth.cards.first?.detail.hasPrefix("⚠️ 이 창의 글을 모두 선택해서 지워요") == true && !fourth.ledger.selectedAll(in: 9189),
          "desk-3: when the user asked, the card says plainly that everything is deleted, and nothing stays marked as selected")
}

// MARK: - desk-2: keys that change nothing in the window's tree

private func fixDeskQuietKeyTests() {
    let body = { (range: (Int, Int)?) -> ArisDesktopElement in
        var element = ArisDesktopElement(id: "elem_1", role: "textArea", label: "body", value: "첫 줄", bounds: CGRect(x: 100, y: 400, width: 800, height: 400))
        element.selectedRange = range.map { ArisTextRange(location: $0.0, length: $0.1) }
        return element
    }
    let look = { (range: (Int, Int)?) in
        ArisDesktopObservation(snapshot: "sfix1", peekaboo: "ps1_x", target: fixEditor, window: 9189, title: "무제", elements: [body(range)],
                               focused: CGRect(x: 100, y: 400, width: 800, height: 400), isDialog: false, hidden: false)
    }
    let isDone = { (check: ArisDesktopCheck) -> Bool in if case .done = check { return true }; return false }
    let caret = look((3, 0)), all = look((0, 3)), unread = look(nil)
    check(isDone(ArisDesktopVerify.pressed(["cmd+a"], dispatched: true, before: caret, after: all)),
          "desk-2: a select-all is confirmed when the focused text's selection covers everything")
    check(!isDone(ArisDesktopVerify.pressed(["cmd+a"], dispatched: true, before: caret, after: caret))
          && !isDone(ArisDesktopVerify.pressed(["cmd+a"], dispatched: true, before: unread, after: unread))
          && !isDone(ArisDesktopVerify.pressed(["cmd+a"], dispatched: false, before: caret, after: all)),
          "desk-2: a select-all that selected nothing, can't be read, or was never sent stays not confirmed")
    let copied = ArisPressEvidence(clipboardChanged: true)
    check(isDone(ArisDesktopVerify.pressed(["cmd+c"], dispatched: true, before: all, after: all, evidence: copied))
          && isDone(ArisDesktopVerify.pressed(["cmd+a", "cmd+c"], dispatched: true, before: caret, after: all, evidence: copied))
          && !isDone(ArisDesktopVerify.pressed(["cmd+c"], dispatched: true, before: all, after: all)),
          "desk-2: a copy is confirmed by the clipboard having moved, and only by that")
    check(!isDone(ArisDesktopVerify.pressed(["cmd+c", "return"], dispatched: true, before: all, after: all, evidence: copied))
          && !isDone(ArisDesktopVerify.pressed(["return"], dispatched: true, before: unread, after: unread, evidence: copied))
          && !isDone(ArisDesktopVerify.pressed(["shift+end"], dispatched: true, before: unread, after: unread)),
          "desk-2: Return, or a selection key with no sign of it, is never confirmed this way (security review)")
    check(isDone(ArisDesktopVerify.pressed(["shift+end"], dispatched: true, before: look((0, 0)), after: all)), "desk-2: a Shift caret key is confirmed when the selection changed")
    let saved = ArisDesktopVerify.pressed(["cmd+s"], dispatched: true, before: unread, after: unread, evidence: ArisPressEvidence(editedBefore: true, editedAfter: false))
    let nothingToSave = ArisDesktopVerify.pressed(["cmd+s"], dispatched: true, before: unread, after: unread, evidence: ArisPressEvidence(editedBefore: false, editedAfter: false))
    check(isDone(saved) && saved.detail.contains("unsaved changes are saved") && isDone(nothingToSave) && nothingToSave.detail.contains("nothing left to save"),
          "desk-2: a save is confirmed by the document having no unsaved changes after it, said as what it was")
    check(!isDone(ArisDesktopVerify.pressed(["cmd+s"], dispatched: true, before: unread, after: unread))
          && !isDone(ArisDesktopVerify.pressed(["cmd+s"], dispatched: true, before: unread, after: unread, evidence: ArisPressEvidence(editedBefore: true, editedAfter: true))),
          "desk-2: a save whose document still has unsaved changes, or can't be told, stays not confirmed")

    // The engine: "이 문서 전체 복사해 줘" is `press cmd+a cmd+c`: done, by the clipboard.
    let rig = FixRig()
    let turn = FixTurn("TextEdit 문서 전체 복사해 줘")
    turn.ledger.remember(fixEditor.memoryKey ?? "", tainted: false)
    rig.apps.clipboard = [7, 8]
    rig.queue([("see", fixDocument(title: "무제", text: "첫 줄", selected: (3, 0))), ("press", fixSent), ("see", fixDocument(title: "무제", text: "첫 줄", selected: (0, 3)))])
    let copy = rig.run(["press", "cmd+a", "cmd+c", "--app", "TextEdit"], turn: turn)
    check(copy.status == 0 && copy.output.contains("the clipboard changed") && copy.output.contains("everything in “body” is selected"),
          "desk-2: `press cmd+a cmd+c` reads back as done when the clipboard moved: \(copy.output.prefix(200))")
    // The clipboard didn't move: not confirmed, as before.
    let still = FixRig()
    still.apps.clipboard = [7]
    still.queue([("see", fixDocument(title: "무제", text: "첫 줄", selected: (0, 3))), ("press", fixSent), ("see", fixDocument(title: "무제", text: "첫 줄", selected: (0, 3)))])
    let failed = still.run(["press", "cmd+c", "--app", "TextEdit"], turn: turn)
    check(failed.status == 1 && failed.output.contains("Not confirmed"), "desk-2: a copy with no change on the clipboard is still told as not confirmed")
    // A save of a document with unsaved changes: done once its mark clears.
    let saving = FixRig()
    saving.apps.edited = [true, false]
    saving.queue([("see", fixDocument(title: "report.txt", text: "첫 줄")), ("press", fixSent), ("see", fixDocument(title: "report.txt", text: "첫 줄"))])
    saving.windows.byPid[4242] = [ArisDesktopWindow(id: 9189, frame: fixFrame, title: "report.txt")]
    let save = saving.run(["press", "cmd+s", "--app", "TextEdit"], turn: turn)
    check(save.status == 0 && save.output.contains("unsaved changes are saved"), "desk-2: `press cmd+s` on an edited saved file reads back as saved: \(save.output.prefix(160))")
    // A batch no longer stops at its select-all step.
    let batch = FixRig()
    let fifth = FixTurn("TextEdit 무제 창 내용을 회의 끝 으로 바꿔 줘")
    fifth.ledger.remember(fixEditor.memoryKey ?? "", tainted: false)
    batch.queue([("see", fixDocument(title: "무제", text: "첫 줄", selected: (3, 0)))])
    let seen = batch.run(["see", "--app", "TextEdit"], turn: fifth)
    batch.queue([("see", fixDocument(title: "무제", text: "첫 줄", selected: (3, 0))), ("press", fixSent), ("see", fixDocument(title: "무제", text: "첫 줄", selected: (0, 3))),
                 ("see", fixDocument(title: "무제", text: "첫 줄", selected: (0, 3))), ("type", fixSent), ("see", fixDocument(title: "무제", text: "회의 끝", selected: (4, 0)))])
    let replaced = batch.run(["batch", "--app", "TextEdit", "--stdin"], text: "press cmd+a\ntype \(batch.ref("body", in: seen.output)) 회의 끝", turn: fifth)
    check(replaced.status == 0 && batch.calls.contains { $0.hasPrefix("type") }, "desk-2: a batch goes on past its `press cmd+a` step to the type: \(replaced.output.prefix(200))")
}

// MARK: - desk-5: agy's relay turn tells the engine the user's words, and each relayed turn starts its ledger over

private func fixDeskRelayTurnTests() {
    let relay = fixSource("ArisAgent/ArisMCPRoutes.swift")
    check(relay.contains("\n    let request: String\n") && !relay.contains("private let request"),
          "desk-5: the relay turn's request is visible to the desktop engine's conformance in another file")
    check(!fixSource("ArisAgent/ArisDesktopEngine.swift").contains("var request: String { \"\" }"),
          "desk-5: the user's words have no silent default: a turn that doesn't give them doesn't compile")
    check(fixSource("ArisAgent/ArisDesktopRoutes.swift").contains("static let relaySteps = ArisDesktopStepCount(onReset: { relayLedger.startTurn() })"),
          "desk-5: the relay's step count starts its ledger's turn over when it is reset")
    let ledger = ArisComputerUseLedger()
    let steps = ArisDesktopStepCount(onReset: { ledger.startTurn() })
    ledger.noteSelectAll(window: 9189)
    ledger.noteNotDone()
    ledger.remember("desktop:com.apple.TextEdit", tainted: false)
    _ = steps.next()
    steps.reset()
    check(!ledger.selectedAll(in: 9189) && ledger.actionsThisTurn.notDone == 0 && steps.next() == 1 && ledger.allows("desktop:com.apple.TextEdit", tainted: false),
          "desk-5: a new relayed turn forgets the last one's select-all and counts, and keeps the conversation's yes")
    // With their words seen, a relayed turn's file panel and replace are his to ask for, as on every other brain.
    let turn = FixTurn("TextEdit 문서를 report.txt로 저장해 줘")
    turn.relayed = true
    let save = try? ArisDesktopWords.parse(["dialog", "file", "--app", "TextEdit", "--path", "~/Desktop", "--name", "report.txt"]).get()
    let named = ArisDesktopGate.namesApp(turn.request, names: ["TextEdit", "com.apple.TextEdit"])
    if let save, case .ask = ArisDesktopGate.decide(save, target: fixEditor, context: ArisDesktopContext(relayed: true, request: turn.request, userNamedApp: named),
                                                    remembered: false, secureInput: false) {} else {
        check(false, "desk-5: with the user's words seen, a relayed file panel asks on his card instead of being refused")
    }
}

// MARK: - desk-7: a helper child that exits or stalls can't kill or hang the agent

private func fixDeskChildFeedTests() {
    let big = Data(repeating: UInt8(ascii: "a"), count: 3 * 1_024 * 1_024)
    let child = { (path: String, arguments: [String]) -> Process in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        return process
    }
    // A child that exits without reading: the write fails quietly (no SIGPIPE: this process is still here to say so).
    let started = Date()
    let gone = ArisChildFeed.exchange(child("/usr/bin/true", []), input: big, timeout: 10)
    check(gone != nil && gone?.isEmpty == true && Date().timeIntervalSince(started) < 8, "desk-7: a child that exits before reading 3 MB neither kills nor hangs its parent")
    // A child that never reads: ended at the time limit, the write freed with it.
    let waiting = Date()
    let stalled = ArisChildFeed.exchange(child("/bin/sleep", ["30"]), input: big, timeout: 1)
    check(stalled == nil && Date().timeIntervalSince(waiting) < 8, "desk-7: a child that never reads is ended at the time limit: \(Date().timeIntervalSince(waiting))")
    // A child that prints while it still reads (more than a pipe holds): read from the start, so neither side blocks.
    let echoed = ArisChildFeed.exchange(child("/bin/cat", []), input: big, timeout: 20)
    check(echoed == big, "desk-7: a child that answers while it reads gets all of its input and all of its answer comes back")
    check(ArisChildFeed.exchange(child("/nonexistent/aris-no-such-tool", []), input: big, timeout: 2) == nil, "desk-7: a child that can't start is no answer")
    let vision = fixSource("ArisAgent/ArisDesktopVision.swift")
    check(vision.contains("ArisChildFeed.exchange(process, input:") && !vision.contains("fileHandleForWriting.write"), "desk-7: the vision child gets its screenshot through the guarded hand-over")
}

// MARK: - desk-12: an Aside card nobody answered is not the user's no

/// A turn for the Aside tool whose one card gets `answer`.
private final class FixAsideTurn: ArisAsideTurn {
    let brainName = "Claude"
    var taint = ArisTaint.none
    let handsFree = false, isTask = false, screen = false, relayed = false
    let answer: ArisMCPAnswer
    var audits: [[String: String]] = []
    let asideTurnKey = "fix-" + UUID().uuidString
    let asideLive = true

    init(_ answer: ArisMCPAnswer) { self.answer = answer }

    func takeOutsideText() { taint = .outsideText }
    func ask(_ card: ArisMCPCard, answer done: @escaping (ArisMCPAnswer) -> Void) { done(answer) }
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { done(.blocked(.undecided)) }
    func quiet(_ status: String) {}
    func audit(_ fields: [String: String]) { audits.append(fields) }
    func asideRunning(_ brief: String) {}
    func asideWaiting(_ status: String) {}
    func asideEnded() {}
}

private func fixDeskAsideUnansweredTests() {
    let run = { (answer: ArisMCPAnswer) -> (ArisMCPOutcome, FixAsideTurn, Int) in
        nonisolated(unsafe) var runs = 0
        let deps = ArisAsideDeps(locate: { .ready("/x/aside") }, run: { _, _, _, _ in runs += 1; return ArisSkillProcessResult(status: 0, stdout: "ok", stderr: "", timedOut: false) },
                                 open: { _ in false }, environment: [:], verify: { _ in true })
        let turn = FixAsideTurn(answer)
        let outcome = ArisAsideTool.answer("Book the 7pm table at Jungsik", turn: turn, critical: false, deps: deps)
        return (outcome, turn, runs)
    }
    let (silent, silentTurn, silentRuns) = run(.unanswered)
    check(silent.status != 0 && silent.output == ArisAside.unanswered && !silent.output.contains("The user said no") && silentRuns == 0
          && silentTurn.audits.contains { $0["answer"] == "unanswered" } && !silentTurn.audits.contains { $0["answer"] == "no" },
          "desk-12: an Aside card that closed unanswered is told and logged as unanswered, never as the user's no")
    let (refused, refusedTurn, refusedRuns) = run(.no)
    check(refused.output == ArisAside.declined && refusedRuns == 0 && refusedTurn.audits.contains { $0["answer"] == "no" }, "desk-12: his own no is still his no")
    let (allowed, _, allowedRuns) = run(.yes([:]))
    check(allowed.status == 0 && allowedRuns == 1, "desk-12: their yes still runs it")
    check(ArisAside.unanswered.contains("didn't answer") && ArisAside.unanswered.contains("never “알겠어요”"), "desk-12: the unanswered line tells the brain not to word it as a no")
}

// MARK: - desk-9: click-at checks what it needs before the card, and looks with the brain the turn runs on

private func fixDeskVisionTests() {
    check(ArisDesktopLiveVision.seeing(chosen: .api, claudeInstalled: true, apiSees: true) == .api
          && ArisDesktopLiveVision.seeing(chosen: .claude, claudeInstalled: true, apiSees: true) == .claude
          && ArisDesktopLiveVision.seeing(chosen: .codex, claudeInstalled: false, apiSees: true) == .api
          && ArisDesktopLiveVision.seeing(chosen: .api, claudeInstalled: true, apiSees: false) == .claude
          && ArisDesktopLiveVision.seeing(chosen: .antigravity, claudeInstalled: false, apiSees: false) == nil,
          "desk-9: the picture is looked at by the turn's own brain when it can, else by another that can; none is none")
    let canvas = fixSee(title: "Canvas", elements: [fixElement(1, "button", "저장", x: 200, y: 500, width: 80, height: 30, actionable: true)])
    // No brain can look: said before any card, nothing looked at.
    let blind = FixRig()
    blind.vision.sees = []
    let turn = FixTurn("TextEdit에서 저장 눌러 줘", brain: .codex)
    let none = blind.run(["click-at", "--app", "TextEdit", "--target", "저장"], turn: turn)
    check(none.output == ArisDesktopEngine.noVisionLine(app: "TextEdit") && turn.cards.isEmpty && blind.calls.isEmpty,
          "desk-9: click-at with no brain that can look says so before the user's card")
    check(none.output.contains("Claude Code") && none.output.contains("--ocr") && none.output.contains("wasn't asked"), "desk-9: the line says what is missing and what works instead")
    // Screen Recording off: its line (System Settings opened at it), before any card.
    let dark = FixRig()
    dark.access.screenRecording = false
    let second = FixTurn("TextEdit에서 저장 눌러 줘")
    let recording = dark.run(["click-at", "--app", "TextEdit", "--target", "저장"], turn: second)
    check(recording.output == ArisDesktopEngine.screenLine && second.cards.isEmpty && dark.access.guidedScreen == 1 && dark.calls.isEmpty,
          "desk-9: click-at without Screen Recording says so before the user's card")
    // Accessibility off: any action that would ask says so first.
    let untrusted = FixRig()
    untrusted.access.trusted = false
    let third = FixTurn("TextEdit 무제 창에서 엔터 눌러 줘")
    let access = untrusted.run(["press", "return", "--app", "TextEdit"], turn: third)
    check(access.output == ArisDesktopEngine.accessLine && third.cards.isEmpty && untrusted.access.guided == 1, "desk-9: an action without Accessibility says so before the user's card")
    // The look is by the brain the turn runs on.
    let api = FixRig()
    api.vision.sees = [.api]
    api.vision.pick = .mark("elem_1")
    let fourth = FixTurn("TextEdit에서 저장 눌러 줘", brain: .api)
    api.queue([("see", canvas), ("click", fixSent), ("see", canvas)])
    _ = api.run(["click-at", "--app", "TextEdit", "--target", "저장"], turn: fourth)
    check(api.vision.asked == [.api] && fourth.cards.count == 1 && api.calls.contains { $0.hasPrefix("click --on elem_1") },
          "desk-9: click-at asks the turn's own brain to look, after one card: \(api.vision.asked) \(api.calls)")
    // A window with nothing for accessibility: the hint offers click-at only when a brain can look.
    let poor = fixSee(title: "Canvas", elements: [fixElement(1, "staticText", "그림판")])
    blind.queue([("see", poor)])
    let hint = blind.run(["see", "--app", "TextEdit"], turn: turn)
    api.queue([("see", poor)])
    let offered = api.run(["see", "--app", "TextEdit"], turn: fourth)
    check(hint.output.contains("--ocr") && !hint.output.contains("click-at") && offered.output.contains("click-at"),
          "desk-9: the poor-window hint leaves click-at out when no brain can look at a picture")
}

// MARK: - desk-8: "이 문서 저장해 줘" goes to the file panel's card

private func fixDeskFrontDocumentTests() {
    for said in ["이 문서 저장해 줘", "이거 바탕화면에 저장해 줘", "지금 열려 있는 파일 다른 이름으로 저장해 줘", "save this document to the desktop", "이걸 PDF로 저장해 줘"] {
        check(ArisDesktopGate.pointsAtDocument(said), "desk-8: “\(said)” points at the document in front")
    }
    for said in ["방금 답을 파일로 저장해 줘", "방금 올랜도 기온 답을 홈 폴더의 aris-qa-tmp 안에 orlando.txt 파일로 저장해 줘", "이 답변 저장해 줘", "save your answer as a file", "report.txt로 저장해 줘", "이거나 저거나"] {
        check(!ArisDesktopGate.pointsAtDocument(said), "desk-8: “\(said)” doesn't (the answer is Aris's own to write; nothing is pointed at)")
    }
    let save = try? ArisDesktopWords.parse(["dialog", "file", "--app", "TextEdit", "--path", "~/Desktop", "--name", "회의록.txt"]).get()
    var context = ArisDesktopContext(request: "이 문서 바탕화면에 저장해 줘")
    // (Audit gate-19: with neither named, it is no longer refused: the same card asks, with a warning line first.)
    check(save.map { ArisDesktopGate.decide($0, target: fixEditor, context: context, remembered: true, secureInput: false) } == .ask(remember: false) && !context.namesDocument,
          "desk-8: with neither the app named nor the front document pointed at, the file panel asks on the user's card too")
    context.pointsAtFrontDocument = true
    check(save.map { ArisDesktopGate.decide($0, target: fixEditor, context: context, remembered: true, secureInput: false) } == .ask(remember: false),
          "desk-8: pointed at, the file panel asks on the user's card, every time (never a remembered yes)")

    // The engine: TextEdit in front, "이 문서 … 저장해 줘": his card, naming the document.
    let rig = FixRig()
    let turn = FixTurn("이 문서 바탕화면에 회의록.txt로 저장해 줘")
    turn.answer = .no
    let asked = rig.run(["dialog", "file", "--app", "TextEdit", "--path", "~/Desktop", "--name", "회의록.txt"], turn: turn)
    check(turn.cards.count == 1 && turn.cards[0].detail.contains("창: “무제”") && turn.cards[0].detail.contains("이 문서를 저장하거나 열어요") && asked.output.hasPrefix(ArisDesktopEngine.noLine),
          "desk-8: “이 문서 저장해 줘” with the app in front shows the card that names the document: \(turn.cards.first?.detail ?? asked.output)")
    // Another app is in front: "이 문서" isn't this app's, so the card says their words named no document here (audit
    // gate-19: this was a refusal with no card).
    let behind = FixRig()
    behind.apps.front = 555
    let second = FixTurn("이 문서 바탕화면에 회의록.txt로 저장해 줘")
    second.answer = .no
    let refused = behind.run(["dialog", "file", "--app", "TextEdit", "--path", "~/Desktop", "--name", "회의록.txt"], turn: second)
    check(refused.output.hasPrefix(ArisDesktopEngine.noLine) && second.cards.count == 1 && second.cards[0].detail.hasPrefix(ArisDesktopCard.unnamedDocumentLine),
          "desk-8: with another app in front, “이 문서” isn't taken to be this app's document: the card warns first")
    // Aris itself in front (he typed into the notch): the card still goes up.
    let typedInNotch = FixRig()
    typedInNotch.apps.front = 777
    typedInNotch.apps.arisPid = 777
    let third = FixTurn("이거 바탕화면에 저장해 줘")
    third.answer = .no
    _ = typedInNotch.run(["dialog", "file", "--app", "TextEdit", "--path", "~/Desktop", "--name", "회의록.txt"], turn: third)
    check(third.cards.count == 1, "desk-8: with only Aris in front, the card still goes up")
    // The QA case (the last answer is not a TextEdit document) is no longer a flat refusal (audit gate-19): the file
    // panel never runs without the card, and the card says first that their words named no document.
    let answer = FixTurn("방금 답을 파일로 저장해 줘")
    answer.answer = .no
    let kept = rig.run(["dialog", "file", "--app", "TextEdit", "--path", "~/Desktop", "--name", "답.txt"], turn: answer)
    check(kept.output.hasPrefix(ArisDesktopEngine.noLine) && answer.cards.count == 1 && answer.cards[0].detail.hasPrefix(ArisDesktopCard.unnamedDocumentLine)
          && !rig.calls.contains { $0.hasPrefix("dialog") }, "desk-8: “방금 답을 파일로 저장해 줘” never drives an app's file panel without the card that warns")
}

// MARK: - desk-4: a message typed into a field that gives no value can be sent, on a card that says so

private func fixDeskBlindSendTests() {
    // A chat whose message field gives no value (KakaoTalk's): `shown` is what the window shows of the typed text.
    let chat = { (shown: String?, bubble: String?) -> Data in
        var elements = [fixElement(1, "staticText", "엄마: 언제 와?", x: 120, y: 420, width: 300, height: 20),
                        fixElement(2, "textArea", "메시지 입력", x: 120, y: 980, width: 800, height: 40)]
        if let shown { elements.append(fixElement(3, "staticText", shown, x: 124, y: 984, width: 200, height: 20)) }
        if let bubble { elements.append(fixElement(4, "staticText", bubble, x: 700, y: 460, width: 200, height: 20)) }
        return fixSee(title: "엄마", elements: elements, focus: 2)
    }
    let window = [ArisDesktopWindow(id: 9189, frame: fixFrame, title: "엄마")]
    let rig = FixRig(fixChat, windows: window)
    let turn = FixTurn("카톡으로 엄마한테 곧 갈게 라고 보내 줘")
    rig.queue([("see", chat(nil, nil))])
    let look = rig.run(["see", "--app", "카카오톡"], turn: turn)
    // The type: its exact-text card, confirmed from the window read back.
    rig.queue([("see", chat(nil, nil)), ("see", chat(nil, nil)), ("type", fixSent), ("see", chat("곧 갈게", nil))])
    let typed = rig.run(["type", rig.ref("메시지 입력", in: look.output), "--stdin"], text: "곧 갈게", turn: turn)
    check(typed.status == 0 && turn.ledger.blindTyped(window: 9189) == "곧 갈게", "desk-4: a message typed into a field that gives no value is kept for its send: \(typed.output.prefix(160))")
    // The send: a card that says what Aris typed and that the field can't be read; then Return goes out.
    rig.queue([("see", chat("곧 갈게", nil)), ("see", chat("곧 갈게", nil)), ("press", fixSent), ("see", chat(nil, "나: 곧 갈게"))])
    let sent = rig.run(["press", "return", "--app", "카카오톡"], turn: turn)
    let card = turn.cards.last
    check(sent.status == 0 && rig.calls.contains { $0.hasPrefix("press return") } && card?.title == "카카오톡에서 보내기"
          && card?.detail.contains("보낼 글 (Aris가 방금 입력한 글):\n곧 갈게") == true && card?.detail.contains("입력 칸을 읽을 수 없어요") == true && card?.detail.contains("(읽지 못함)") == false,
          "desk-4: the send is asked on a card with the text Aris typed, said as unreadable in the field, and then sent: \(card?.detail ?? sent.output)")
    // One try for one typed text: a second send has nothing to vouch for it.
    let cards = turn.cards.count
    rig.queue([("see", chat(nil, "곧 갈게"))])
    let again = rig.run(["press", "return", "--app", "카카오톡"], turn: turn)
    check(again.output == ArisDesktopEngine.unreadSendLine && turn.cards.count == cards && turn.ledger.blindTyped(window: 9189) == nil,
          "desk-4: after the send was tried, another Return isn't asked about blind")
    // Nothing typed by Aris this turn (the user's own draft, or an unconfirmed type): refused as before, no card.
    let other = FixRig(fixChat, windows: window)
    let second = FixTurn("카톡 보내 줘")
    other.queue([("see", chat("내가 쓴 글", nil))])
    let blind = other.run(["press", "return", "--app", "카카오톡"], turn: second)
    check(blind.output == ArisDesktopEngine.unreadSendLine && second.cards.isEmpty && !other.calls.contains { $0.hasPrefix("press") },
          "desk-4: with nothing Aris typed there to show, a send from an unreadable field is still refused")
    // The window no longer shows what Aris typed when the send is asked for: refused, no card.
    let changed = FixRig(fixChat, windows: window)
    changed.access.screenRecording = false
    let third = FixTurn("카톡으로 엄마한테 곧 갈게 라고 보내 줘")
    third.ledger.noteBlindTyped(window: 9189, text: "곧 갈게")
    changed.queue([("see", chat("다른 글", nil))])
    let gone = changed.run(["press", "return", "--app", "카카오톡"], turn: third)
    check(gone.output == ArisDesktopEngine.unreadSendLine && third.cards.isEmpty, "desk-4: when the window no longer shows the typed text, no send card goes up")
    // It changed while the card waited: nothing is sent.
    let late = FixRig(fixChat, windows: window)
    late.access.screenRecording = false
    let fourth = FixTurn("카톡으로 엄마한테 곧 갈게 라고 보내 줘")
    fourth.ledger.noteBlindTyped(window: 9189, text: "곧 갈게")
    late.queue([("see", chat("곧 갈게", nil)), ("see", chat("다른 글", nil))])
    let held = late.run(["press", "return", "--app", "카카오톡"], turn: fourth)
    check(held.output.contains(ArisDesktopSession.blindGoneLine) && fourth.cards.count == 1 && !late.calls.contains { $0.hasPrefix("press") },
          "desk-4: the typed text gone from the window after the user's yes: nothing is sent: \(held.output.prefix(160))")
    // The field's text only shows on the screen (not in the tree): read from the screenshot, nothing recorded.
    let onScreen = FixRig(fixChat, windows: window)
    onScreen.reader.texts = ["곧 갈게"]
    let fifth = FixTurn("카톡으로 엄마한테 곧 갈게 라고 보내 줘")
    fifth.ledger.noteBlindTyped(window: 9189, text: "곧 갈게")
    fifth.answer = .no
    onScreen.queue([("see", chat(nil, nil)), ("see", chat(nil, nil))])
    _ = onScreen.run(["press", "return", "--app", "카카오톡"], turn: fifth)
    check(fifth.cards.count == 1 && fifth.cards[0].detail.contains("곧 갈게") && fifth.ledger.latestLook(window: 9189) == nil,
          "desk-4: text that shows only on the screen is read from the screenshot for the card, and no look is recorded for it")
}

// MARK: - desk-10: a shortcut's key is the one that types its character on the layout in use

private func fixDeskKeyLayoutTests() {
    let azerty: [String: CGKeyCode] = ["a": 12, "q": 0, "z": 13, "w": 6, "m": 41]
    check(ArisKeyChord.parse("cmd+a", layout: { _ in azerty })?.key == 12 && ArisKeyChord.parse("cmd+z", layout: { _ in azerty })?.key == 13
          && ArisKeyChord.parse("cmd+shift+q", layout: { _ in azerty }) == ArisKeyChord(key: 0, command: true, shift: true, option: false, control: false),
          "desk-10: on AZERTY cmd+a presses the key that types “a” (never ⌘Q), and cmd+z the one that types “z”")
    check(ArisKeyChord.parse("cmd+a")?.key == 0 && ArisKeyChord.parse("cmd+v", layout: { _ in [:] })?.key == 9 && ArisKeyChord.parse("cmd+n", layout: { _ in azerty })?.key == 45,
          "desk-10: with no layout read, or a character it doesn't have, the US place is used as before")
    check(ArisKeyChord.parse("return", layout: { _ in ["return": 99, "tab": 98] })?.key == 36 && ArisKeyChord.parse("shift+tab", layout: { _ in ["tab": 98] })?.key == 48
          && ArisKeyChord.parse("cmd+left", layout: { _ in azerty })?.key == 123, "desk-10: return, tab and the arrows are the same key on every layout")
    let dvorak: [String: CGKeyCode] = ["v": 47], qwerty: [String: CGKeyCode] = ["v": 9]
    check(ArisKeyChord.parse("cmd+v", layout: { $0 ? qwerty : dvorak })?.key == 9 && ArisKeyChord.parse("v", layout: { $0 ? qwerty : dvorak })?.key == 47,
          "desk-10: a layout that types QWERTY while ⌘ is held (Dvorak – QWERTY ⌘) is read with ⌘ held for a ⌘ shortcut")
    check(ArisKeyChord.parse("cmd+é", layout: { _ in ["é": 19] })?.key == 19 && ArisKeyChord.parse("cmd+é") == nil && ArisKeyChord.parse("cmd+") == nil && ArisKeyChord.parse("hyper+a") == nil,
          "desk-10: a character only the layout in use has is found there; unknown keys and modifiers are still refused")
    let typed: [CGKeyCode: String] = [0: "q", 12: "A", 6: "w", 13: "z", 30: "", 31: "q"]
    let map = ArisKeyLayout.map { typed[$0] }
    check(map == ["q": 0, "a": 12, "w": 6, "z": 13], "desk-10: the layout's map is each character to the first key that types it, lowercased")
    check(!ArisKeyLayout.characterKeys.contains(36) && !ArisKeyLayout.characterKeys.contains(48) && !ArisKeyLayout.characterKeys.contains(49) && ArisKeyLayout.characterKeys.contains(10),
          "desk-10: the character keys are the main block (the ISO key too), never return, tab or space")
    check(fixSource("ArisTools/ArisWindows.swift").contains("ArisKeyChord.parse(written, layout: ArisKeyLayout.current)")
          && fixSource("ArisAgent/ArisInsert.swift").contains("ArisKeyLayout.current(command: true)[\"v\"] ?? 9")
          && fixSource("ArisTools/ArisNoteCommand.swift").contains("ArisKeyChord.parse(key, layout: ArisKeyLayout.current)"),
          "desk-10: the keys tool, a note's keys and dictation's paste all go by the layout in use")
}

// MARK: - desk-6: a batch goes on after its own typing renamed the window

private func fixDeskBatchRenameTests() {
    // "새 문서에 회의록 쓰고 저장해 줘": type into the empty 무제 document, then cmd+s. TextEdit names the window from its first
    // line, so the look after the type (and before the press) carries the new title.
    let batch = { (after: Data, target: ArisDesktopTarget) -> (ArisMCPOutcome, FixRig) in
        let rig = FixRig(target)
        let turn = FixTurn("새 \(target.name) 문서에 회의록 이라고 쓰고 저장해 줘")
        turn.ledger.remember(target.memoryKey ?? "", tainted: false)
        rig.apps.edited = [true, false]
        rig.queue([("see", fixDocument(title: "무제", text: ""))])
        let seen = rig.run(["see", "--app", target.name], turn: turn)
        rig.queue([("see", fixDocument(title: "무제", text: "")), ("type", fixSent), ("see", after), ("see", after), ("press", fixSent), ("see", after)])
        return (rig.run(["batch", "--app", target.name, "--stdin"], text: "type \(rig.ref("body", in: seen.output)) 회의록\npress cmd+s", turn: turn), rig)
    }
    let renamed = fixDocument(title: "회의록", text: "회의록")
    let (done, rig) = batch(renamed, fixEditor)
    check(done.status == 0 && rig.calls.contains { $0.hasPrefix("press cmd+s") },
          "desk-6: a batch's press after its own typing renamed the TextEdit window still runs: \(done.output.prefix(300))")
    // The limits stay: an app that doesn't rename its own one document, or a window with tabs, keeps the exact title.
    let other = fixTarget("Pages", bundle: "com.apple.iWork.Pages")
    let (stopped, otherRig) = batch(renamed, other)
    check(stopped.status != 0 && stopped.output.contains("title changed") && !otherRig.calls.contains { $0.hasPrefix("press") },
          "desk-6: in an app that keeps several documents under one window, a new title still stops the batch")
    let tabbed = fixSee(title: "회의록", elements: [fixElement(1, "textArea", "body", value: "회의록"), fixElement(2, "tabGroup", "tabs", x: 100, y: 360, width: 800, height: 30)], focus: 1)
    let (tabStopped, tabRig) = batch(tabbed, fixEditor)
    check(tabStopped.status != 0 && !tabRig.calls.contains { $0.hasPrefix("press") }, "desk-6: a TextEdit window with tabs still stops (another tab may be another document)")
    // The rule itself.
    let field = ArisDesktopElement(id: "elem_1", role: "textArea", label: "body", value: "회의록", bounds: CGRect(x: 100, y: 400, width: 800, height: 400))
    let look = ArisDesktopObservation(snapshot: "sfix6", peekaboo: "ps1_y", target: fixEditor, window: 9189, title: "회의록", elements: [field], focused: nil, isDialog: false, hidden: false)
    let basis = ArisDesktopBasis(title: "무제", window: 9189)
    let next = ArisDesktopFocus.afterOwnText(basis, look: look, field: field, target: fixEditor)
    check(next.title == "회의록" && next.field == field, "desk-6: after its own text step the batch holds the window by the field it typed into and the title it has now")
    let empty = ArisDesktopElement(id: "elem_1", role: "textArea", label: "body", value: "", bounds: field.bounds)
    check(ArisDesktopFocus.afterOwnText(basis, look: look, field: empty, target: fixEditor) == basis
          && ArisDesktopFocus.afterOwnText(ArisDesktopBasis(title: "무제", window: 9190), look: look, field: field, target: fixEditor) == ArisDesktopBasis(title: "무제", window: 9190)
          && ArisDesktopFocus.afterOwnText(basis, look: look, field: field, target: fixChat) == basis
          && ArisDesktopFocus.afterOwnText(basis, look: look, field: field, target: other) == basis,
          "desk-6: never from an empty field, another window, a sending app, or an app that isn't known to rename its one document")
}

// MARK: - desk-1 follow-up: the API brain's functions can name a window too

private func fixDeskCatalogTests() {
    check(ArisAPICatalog.argv(name: "desktop_press", arguments: #"{"app":"TextEdit","keys":"cmd+a delete","title":"무제"}"#) == ["desktop", "press", "cmd+a", "delete", "--app", "TextEdit", "--title", "무제"]
          && ArisAPICatalog.argv(name: "desktop_press", arguments: #"{"app":"TextEdit","keys":"return"}"#) == ["desktop", "press", "return", "--app", "TextEdit"],
          "desk-1: the API brain's desktop_press can name its window by title, and is as before without one")
    check(ArisAPICatalog.argv(name: "desktop_see", arguments: #"{"app":"TextEdit","title":"무제 2"}"#) == ["desktop", "see", "--app", "TextEdit", "--title", "무제 2"]
          && ArisAPICatalog.argv(name: "desktop_see", arguments: #"{"app":"TextEdit","ocr":true}"#) == ["desktop", "see", "--app", "TextEdit", "--ocr"],
          "desk-1: the API brain's desktop_see can look at a window by its title (the several-windows answer asks for one)")
    let words = ArisAPICatalog.argv(name: "desktop_press", arguments: #"{"app":"TextEdit","keys":"return","title":"무제"}"#).map { Array($0.dropFirst()) } ?? []
    check((try? ArisDesktopWords.parse(words).get())?.title == "무제", "desk-1: what the function makes is what the engine's words read")
}

// MARK: - desk-imp-4: an app name is resolved once, and that answer is the exact-name check too

private func fixDeskAppNameTests() {
    let installed = [ArisAppNames.App(display: "캘린더", file: "Calendar"), ArisAppNames.App(display: "텍스트 편집기", file: "TextEdit"), ArisAppNames.App(display: "Notes", file: "Notes")]
    let exact = { (said: String, shown: String, file: String) in
        ArisAppNames.isExactly(said, resolved: ArisAppNames.match(said, in: installed), localizedName: shown, fileName: file)
    }
    check(exact("달력", "캘린더", "Calendar") && exact("텍스트편집기", "텍스트 편집기", "TextEdit") && exact("메모", "Notes", "Notes") && exact("textedit", "텍스트 편집기", "TextEdit"),
          "desk-imp-4: an alias, another spacing or the other language's name is exactly the app it resolves to")
    check(!exact("Edit", "텍스트 편집기", "TextEdit") && !exact("달력", "Notes", "Notes") && !exact("", "Notes", "Notes"),
          "desk-imp-4: a name that only is part of the app's, or that resolves to another app, still isn't it")
    check(ArisAppIdentity.isNamed("텍스트편집기", among: ["텍스트 편집기", "textedit"]) && ArisAppIdentity.isNamed("메모", among: ["notes", "메모"])
          && !ArisAppIdentity.isNamed("메모장", among: ["notes", "메모"]) && !ArisAppIdentity.isNamed(" ", among: ["notes"]),
          "desk-imp-4: a running app is found by any of its own names, spacing and case aside")
}

// MARK: - desk-imp-5: Aside's CLI is found where it lives, and an installed Aside isn't offered for download

private func fixDeskAsideCLITests() {
    let own = "/Users/me/.aside/cli/Aside CLI.app/Contents/MacOS/aside"
    check(ArisAside.locate(home: "/Users/me", isExecutable: { $0 == own }, signed: { _ in true }) == .ready(own),
          "desk-imp-5: with no link in ~/.local/bin, the CLI is found inside Aside's own folder")
    check(ArisAside.locate(home: "/Users/me", isExecutable: { $0 == own }, signed: { _ in false }) == .untrusted(own)
          && ArisAside.locate(home: "/Users/me", isExecutable: { _ in false }, signed: { _ in true }) == .missing,
          "desk-imp-5: it runs only when Aside's team signed it; none anywhere is still missing")
    nonisolated(unsafe) var opened = 0
    let deps = { (hasApp: Bool) in
        ArisAsideDeps(locate: { .missing }, run: { _, _, _, _ in ArisSkillProcessResult(status: 0, stdout: "", stderr: "", timedOut: false) },
                      open: { _ in opened += 1; return true }, environment: [:], hasApp: { hasApp })
    }
    let installed = ArisAsideTool.answer("가격 찾아줘", turn: FixAsideTurn(.yes([:])), critical: false, deps: deps(true))
    check(installed.output == ArisAside.cliMissingOutput && opened == 0, "desk-imp-5: Aside's app here but no CLI: said as that, and no download page is opened")
    let absent = ArisAsideTool.answer("가격 찾아줘", turn: FixAsideTurn(.yes([:])), critical: false, deps: deps(false))
    check(absent.output == ArisAside.missingOutput(opened: true) && opened == 1, "desk-imp-5: with no Aside at all, the install card is as before")
}

// MARK: - desk-imp-3: `desktop app quit`, behind the user's card

private func fixDeskQuitTests() {
    let quit = try? ArisDesktopWords.parse(["app", "quit", "미리보기"]).get()
    check(quit?.verb == .app && quit?.operation == "quit" && quit?.app == "미리보기", "desk-imp-3: `desktop app quit \"<App>\"` is read")
    let preview = fixTarget("미리보기", bundle: "com.apple.Preview")
    let decide = { (target: ArisDesktopTarget, remembered: Bool) in
        quit.map { ArisDesktopGate.decide($0, target: target, context: ArisDesktopContext(), remembered: remembered, secureInput: false) }
    }
    check(decide(preview, false) == .ask(remember: false) && decide(preview, true) == .ask(remember: false), "desk-imp-3: quitting an app always asks on the user's card, never a remembered yes")
    let safari = ArisDesktopTarget(name: "Safari", bundle: "com.apple.Safari", pid: 3, known: true, never: false, browser: true, sending: false)
    let terminal = ArisDesktopTarget(name: "Terminal", bundle: "com.apple.Terminal", pid: 4, known: true, never: true, browser: false, sending: false)
    check(decide(safari, false) == .ask(remember: false) && decide(terminal, false) == .refuse(ArisDesktopGate.neverRefusal)
          && decide(fixTarget("Finder", bundle: "com.apple.finder"), false) == .refuse(ArisDesktopGate.quitSystemRefusal)
          && decide(fixTarget("Dock", bundle: "com.apple.dock"), false) == .refuse(ArisDesktopGate.quitSystemRefusal),
          "desk-imp-3: a browser can be quit on the card; the never-list and the system's own apps can't")
    check(ArisDesktopGate.menuRefusal.contains("desktop app quit") && ArisDesktopGate.refusesMenu("미리보기 > 미리보기 종료"), "desk-imp-3: the menu's Quit stays refused, and its refusal names the way that works")
    if let quit {
        let card = ArisDesktopCard.card(quit, target: preview, element: nil, remember: false, wiped: false)
        check(card.title == "미리보기 종료하기" && card.detail.contains("앱을 종료해요") && card.detail.contains("저장하지 않은 문서"), "desk-imp-3: the card says the app is quit and that unsaved documents are asked about: \(card.detail)")
    }
    // The engine: their yes, the quit asked of the app, done once the process is gone.
    let rig = FixRig(preview)
    let turn = FixTurn("미리보기 종료해 줘")
    rig.apps.running = [false]
    rig.queue([("app-quit", fixSent)])
    let done = rig.run(["app", "quit", "미리보기"], turn: turn)
    check(done.status == 0 && done.output.contains("has quit") && turn.cards.count == 1 && rig.calls == ["app quit --app com.apple.Preview --json"],
          "desk-imp-3: with the user's yes the app is asked to quit (never forced), and it is done once the process is gone: \(rig.calls) \(done.output.prefix(120))")
    let no = FixRig(preview)
    let second = FixTurn("미리보기 종료해 줘")
    second.answer = .no
    let kept = no.run(["app", "quit", "미리보기"], turn: second)
    check(kept.status != 0 && no.calls.isEmpty, "desk-imp-3: his no quits nothing")
    let absent = no.run(["app", "quit", "없는앱"], turn: second)
    check(absent.output.contains("nothing to quit"), "desk-imp-3: an app that isn't running is said as that")
}

private func fixDeskCatalogWindowTests() {
    check(ArisAPICatalog.argv(name: "desktop_window", arguments: #"{"app":"TextEdit","operation":"focus","title":"무제"}"#) == ["desktop", "window", "focus", "--app", "TextEdit", "--title", "무제"]
          && ArisAPICatalog.argv(name: "desktop_window", arguments: #"{"app":"TextEdit","operation":"erase"}"#) == nil
          && ArisAPICatalog.entry("desktop_window")?.sealed == true,
          "desk-1: every brain can bring the named window forward (the API brain's desktop_window), which a refused menu or dialog call asks for")
    let words = ArisAPICatalog.argv(name: "desktop_window", arguments: #"{"app":"TextEdit","operation":"close"}"#).map { Array($0.dropFirst()) } ?? []
    check((try? ArisDesktopWords.parse(words).get())?.operation == "close" && ArisSealedTools.allows(["desktop"] + words), "desk-1: its words are ones the engine and the sealed list read")
}
