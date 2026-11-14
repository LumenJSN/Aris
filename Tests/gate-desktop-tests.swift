//
//  gate-desktop-tests.swift
//  The 2026-11-10 audit's refusals in computer use and the Claude Code launch (gate-19, gate-20 in qa/audit-1110/gate.json)
//  and the Korean-only computer-use copy (desk-11 in desktop.json). A refusal became the user's card; each test of one also
//  tries the hostile variant that must not ride along. Nothing here touches a real app, key, clipboard or screen, and
//  Claude Code is never launched: a fake Peekaboo (a shell script answering from a queue of envelopes made in the
//  test), fake window lists, a fake front app and clipboard, temp folders, and the pure decision functions.
//

import CoreGraphics
import Foundation

// MARK: - The rig

/// The fake Peekaboo: logs its argv and answers each command from its queue in order, else from a standing reply.
private let gatePeekabooScript = """
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

private final class GateDownload: ArisDesktopDownloading {
    var archive: URL?
    func fetch(_ url: URL, to file: URL) -> String? {
        guard let archive else { return "offline" }
        do { try FileManager.default.copyItem(at: archive, to: file) } catch { return "copy failed" }
        return nil
    }
}

private final class GateApps: ArisDesktopApps {
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
    /// The clipboard's text, one value a read (the last repeats); empty: it holds no text.
    var clipboardTexts: [String] = []
    func clipboardText() -> String? { clipboardTexts.count > 1 ? clipboardTexts.removeFirst() : clipboardTexts.first }
    func documentEdited(pid: Int32, frame: CGRect) -> Bool? { edited.count > 1 ? edited.removeFirst() : edited.first }
}

private final class GateWindows: ArisDesktopWindows {
    var byPid: [Int32: [ArisDesktopWindow]] = [:]
    func windows(of pid: Int32) -> [ArisDesktopWindow] { byPid[pid] ?? [] }
    func topWindow(at point: CGPoint) -> (pid: Int32, id: Int)? { nil }
    func promptOnScreen() -> String? { nil }
}

private final class GateAccess: ArisDesktopAccess {
    var trusted = true
    var screenRecording = true
    var guided = 0, guidedScreen = 0
    func guide() { guided += 1 }
    func guideScreen() { guidedScreen += 1 }
}

private final class GatePointer: ArisDesktopPointer {
    func save() -> ArisDesktopPointerState { ArisDesktopPointerState(location: CGPoint(x: 5, y: 6), frontmost: 1) }
    func restore(_ state: ArisDesktopPointerState) {}
}

private final class GateVision: ArisDesktopVision {
    var pick: ArisDesktopPick?
    /// The brains that can look at a picture on this (fake) Mac.
    var sees: Set<ArisBrain> = [.claude]
    var asked: [ArisBrain] = []
    func locate(png: Data, width: Int, height: Int, target: String, marks: [String]) -> ArisDesktopPick? { pick }
    func available(for brain: ArisBrain) -> Bool { !sees.isEmpty }
    func locate(png: Data, width: Int, height: Int, target: String, marks: [String], brain: ArisBrain) -> ArisDesktopPick? { asked.append(brain); return pick }
}

private final class GateReader: ArisDesktopTextReader {
    var texts: [String] = []
    func read(png: Data) -> [(text: String, box: CGRect)] { texts.map { ($0, CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)) } }
}

private final class GateTurn: ArisDesktopTurn {
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
    /// The notch's lines for this turn: the quiet ones and the line shown while a window is worked in.
    var statuses: [String] = []
    func quiet(_ status: String) { statuses.append(status) }
    func audit(_ fields: [String: String]) { audits.append(fields) }
    func operating(_ target: ArisOperatingTarget) { statuses.append(target.line) }
    func desktopStep() -> Int { steps += 1; return steps }
    func noteDesktopAction(_ note: Result<ArisSavedStep, ArisSavedStepsRefusal>) {}
}

private func gateTarget(_ name: String, bundle: String, pid: Int32 = 4242, sending: Bool = false) -> ArisDesktopTarget {
    ArisDesktopTarget(name: name, bundle: bundle, pid: pid, known: true, never: false, browser: false, sending: sending)
}

private let gateEditor = gateTarget("TextEdit", bundle: "com.apple.TextEdit")
private let gateChat = gateTarget("카카오톡", bundle: "com.kakao.KakaoTalkMac", sending: true)
private let gateFrame = CGRect(x: 80, y: 329, width: 1040, height: 720)
private let gateIdentity = ArisDesktopIdentity(userName: "testuser", fullName: "Alex Tester", home: "/Users/testuser")

/// One element of a made-up `see`: Peekaboo's own keys.
private func gateElement(_ id: Int, _ role: String, _ label: String, value: String? = nil, x: Double = 100, y: Double = 400, width: Double = 800, height: Double = 400,
                        selected: (Int, Int)? = nil, actionable: Bool = false) -> [String: Any] {
    var element: [String: Any] = ["id": "elem_\(id)", "role": role, "label": label, "is_actionable": actionable,
                                  "bounds": ["x": x, "y": y, "width": width, "height": height],
                                  "ax_role": role == "textArea" ? "AXTextArea" : role == "textField" ? "AXTextField" : role == "button" ? "AXButton" : "AXStaticText"]
    if let value { element["value"] = value }
    if let selected { element["selected_text_range"] = ["location": selected.0, "length": selected.1] }
    return element
}

private var gateSnapshots = 0

/// A `see` envelope of one window, made in the test (`focus`: the element that has the keyboard focus).
private func gateSee(window: Int = 9189, title: String, elements: [[String: Any]], focus: Int? = nil, dialog: Bool = false) -> Data {
    gateSnapshots += 1
    var data: [String: Any] = ["snapshot_id": "ps1_" + String(format: "%032x", gateSnapshots), "window_title": title, "ui_elements": elements, "is_dialog": dialog,
                               "application_name": "Fake", "screenshot_raw": "__PATH__", "screenshot_annotated": "__ANNOTATED__"]
    if let focus, let element = elements.first(where: { $0["id"] as? String == "elem_\(focus)" }), let bounds = element["bounds"] as? [String: Double] {
        data["focused_element"] = ["frame": [[bounds["x"] ?? 0, bounds["y"] ?? 0], [bounds["width"] ?? 0, bounds["height"] ?? 0]], "role": element["ax_role"] ?? "",
                                   "processIdentifier": 4242, "windowID": window]
    }
    let object: [String: Any] = ["success": true, "data": data, "target_receipt": ["pid": 4242, "window_id": window]]
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
}

/// Keys, a click or typing that Peekaboo sent on (nothing verified: the controller reads the window back).
private let gateSent = Data(#"{"success":true,"data":{},"outcome":{"dispatch_state":"dispatched","mutation_dispatched":true,"retry_safe":false,"state":"dispatched_unverified"},"target_receipt":{"pid":4242,"window_id":9189}}"#.utf8)

/// A document window's look: one text area holding `text` (`selected`: its caret or selection), focused.
private func gateDocument(window: Int = 9189, title: String, text: String, selected: (Int, Int)? = nil) -> Data {
    gateSee(window: window, title: title, elements: [gateElement(1, "textArea", "body", value: text, selected: selected)], focus: 1)
}

private final class GateRig {
    let root: URL
    let apps = GateApps()
    let windows = GateWindows()
    let access = GateAccess()
    let vision = GateVision()
    let reader = GateReader()
    let installer: ArisDesktopInstaller
    private let download = GateDownload()
    lazy var engine = ArisDesktopEngine(installer: installer, apps: apps, access: access, windows: windows, pointer: GatePointer(), vision: vision,
                                        reader: reader, identity: gateIdentity, tools: "/tools/aris-tools")

    init(_ target: ArisDesktopTarget = gateEditor, windows list: [ArisDesktopWindow] = [ArisDesktopWindow(id: 9189, frame: gateFrame, title: "무제")]) {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aris-gate-desktop-\(UUID().uuidString)")
        let files = root.appendingPathComponent("archive-files/peekaboo-macos-test")
        try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let contents = [ArisDesktopRelease.binaryName: gatePeekabooScript, ArisDesktopRelease.libraryName: "not a real library", ArisDesktopRelease.licenceName: "MIT License"]
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

    func run(_ words: [String], text: String? = nil, turn: GateTurn) -> ArisMCPOutcome {
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


private func gateSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

func runGateDesktopTests() {
    gateCalendarTests()
    gateMenuQuitTests()
    gatePasteTests()
    gateFilePanelTests()
    gateLaunchArgumentTests()
    gateLaunchAliasTests()
    gateLaunchFolderTests()
    gateEnglishCardTests()
    gateEnglishStatusTests()
    gateEnglishAsideTests()
}

private let gateCalendar = gateTarget("캘린더", bundle: "com.apple.iCal")
private let gateReminders = gateTarget("미리 알림", bundle: "com.apple.reminders")
private let gateRef = ArisDesktopRef(snapshot: "s8f3k2", element: 5)

private func gateButton(_ label: String, role: String = "button") -> ArisDesktopElement { ArisDesktopElement(id: "elem_5", role: role, label: label) }

// MARK: - gate-19 (a): Calendar and Reminders can be looked around in; removing stays with the event and reminder tools

private func gateCalendarTests() {
    let decide = { (request: ArisDesktopRequest, target: ArisDesktopTarget, element: ArisDesktopElement?) in
        ArisDesktopGate.decide(request, target: target, context: ArisDesktopContext(home: "/Users/p", request: "캘린더 앱 월 보기로 바꿔 줘"), remembered: true,
                               secureInput: false, element: element)
    }
    for target in [gateCalendar, gateReminders] {
        // Looking around: the user's card, every time (never a remembered yes), where it was a flat refusal.
        check(decide(ArisDesktopRequest(verb: .click, ref: gateRef), target, gateButton("월")) == .ask(remember: false)
              && decide(ArisDesktopRequest(verb: .click, ref: gateRef), target, gateButton("장보기", role: "row")) == .ask(remember: false)
              && decide(ArisDesktopRequest(verb: .scroll, ref: gateRef, direction: "down"), target, gateButton("", role: "scrollArea")) == .ask(remember: false)
              && decide(ArisDesktopRequest(verb: .press, app: "X", keys: ["cmd+2"]), target, nil) == .ask(remember: false)
              && decide(ArisDesktopRequest(verb: .press, app: "X", keys: ["right"]), target, nil) == .ask(remember: false)
              && decide(ArisDesktopRequest(verb: .menuClick, app: "X", path: "보기 > 월별"), target, nil) == .ask(remember: false)
              && decide(ArisDesktopRequest(verb: .clickAt, app: "X", target: "오늘 버튼"), target, nil) == .ask(remember: false)
              && decide(ArisDesktopRequest(verb: .type, ref: gateRef, text: "회의"), target, gateButton("검색", role: "searchField")) == .ask(remember: false),
              "gate-19: looking around in \(target.name) (a view, a list, a date, a search) asks on the user's card every time, never refused and never a kept yes")
        check(decide(ArisDesktopRequest(verb: .see, app: "X"), target, nil) == .run, "gate-19: a look at \(target.name) still just runs on a clean turn")
        // The hostile ones: a delete or backspace key (alone, with a modifier, after another key, by another name), a cut.
        for keys in [["delete"], ["backspace"], ["forwarddelete"], ["cmd+delete"], ["cmd+backspace"], ["down", "delete"], ["del"], ["delete+cmd"], ["cmd+x"],
                     ["x+cmd"], ["command+x"], ["shift+backspace"], ["clear"]] {
            check(decide(ArisDesktopRequest(verb: .press, app: "X", keys: keys), target, nil) == .refuse(ArisDesktopGate.calendarRefusal),
                  "gate-19 (QA BUG-53): `press \(keys.joined(separator: " "))` in \(target.name) is still refused, with the event and reminder tools named")
        }
        // A click, a menu item, a dialog button or a looked-for spot named for deleting, cutting or sending.
        for label in ["삭제", "Delete", "Delete Event", "이벤트 삭제", "휴지통으로 이동", "Remove", "보내기", "Send Invitation", "오려두기", "Cut", "지움"] {
            check(decide(ArisDesktopRequest(verb: .click, ref: gateRef), target, gateButton(label)) == .refuse(ArisDesktopGate.calendarRefusal)
                  && decide(ArisDesktopRequest(verb: .menuClick, app: "X", path: "편집 > \(label)"), target, nil) == .refuse(ArisDesktopGate.calendarRefusal)
                  && decide(ArisDesktopRequest(verb: .dialogClick, app: "X", button: label), target, nil) == .refuse(ArisDesktopGate.calendarRefusal)
                  && decide(ArisDesktopRequest(verb: .clickAt, app: "X", target: "the \(label) button"), target, nil) == .refuse(ArisDesktopGate.calendarRefusal),
                  "gate-19 (QA BUG-53): “\(label)” clicked, picked from a menu, pressed in a dialog or looked for in \(target.name) is still refused")
        }
        // Full-width letters and a hidden character don't get a risky word past it.
        check(decide(ArisDesktopRequest(verb: .click, ref: gateRef), target, gateButton("Ｄｅｌｅｔｅ")) == .refuse(ArisDesktopGate.calendarRefusal)
              && decide(ArisDesktopRequest(verb: .menuClick, app: "X", path: "Edit > De\u{200B}lete"), target, nil) != .ask(remember: false),
              "gate-19: a risky word in full-width letters or split by a hidden character in \(target.name) is not let through")
    }
    // The app told by its name alone (no bundle id resolved) is held to the same rule.
    let unnamed = ArisDesktopTarget(name: "Calendar", bundle: nil, pid: 9, known: false, never: false, browser: false, sending: false)
    check(decide(ArisDesktopRequest(verb: .press, app: "X", keys: ["delete"]), unnamed, nil) == .refuse(ArisDesktopGate.calendarRefusal)
          && ArisDesktopGate.isCalendarApp(unnamed) && ArisDesktopGate.isCalendarApp(gateReminders) && !ArisDesktopGate.isCalendarApp(gateEditor),
          "gate-19: Calendar told only by its name is Calendar too")
    check(ArisDesktopGate.calendarRefusal.contains("aris-tools event") && ArisDesktopGate.calendarRefusal.contains("aris-tools remind")
          && ArisDesktopGate.calendarRefusal.contains("Nothing was done"), "gate-19: the refusal still names the event and reminder tools")
    // Another app's delete key is not caught by this rule (it keeps its own card).
    check(decide(ArisDesktopRequest(verb: .press, app: "X", keys: ["delete"]), gateEditor, nil) == .run, "gate-19: a delete key in another app is that app's own business, as before")

    // The engine: a click on Calendar's 월 button goes to one card that names it; a delete key never reaches a card or Peekaboo.
    let window = [ArisDesktopWindow(id: 9189, frame: gateFrame, title: "캘린더")]
    let month = gateSee(title: "캘린더", elements: [gateElement(1, "button", "월", x: 300, y: 340, width: 40, height: 24, actionable: true),
                                                  gateElement(2, "staticText", "QA 회의", x: 300, y: 500, width: 120, height: 20)])
    let rig = GateRig(gateCalendar, windows: window)
    let turn = GateTurn("캘린더 앱 월 보기로 바꿔 줘")
    rig.queue([("see", month)])
    let look = rig.run(["see", "--app", "캘린더"], turn: turn)
    turn.answer = .no
    let clicked = rig.run(["click", rig.ref("월", in: look.output)], turn: turn)
    check(turn.cards.count == 1 && turn.cards[0].title == "캘린더에서 누르기" && turn.cards[0].detail.contains("대상: 버튼 “월”") && !turn.cards[0].detail.contains("다시 묻지 않아요")
          && clicked.output.hasPrefix(ArisDesktopEngine.noLine),
          "gate-19: “캘린더 월 보기로 바꿔 줘” shows one card that names the button, and promises no kept yes: \(turn.cards.first?.detail ?? clicked.output)")
    let cards = turn.cards.count, calls = rig.calls.count
    let pressed = rig.run(["press", "delete", "--app", "캘린더"], turn: turn)
    check(pressed.output == ArisDesktopGate.calendarRefusal && turn.cards.count == cards && rig.calls.count == calls,
          "gate-19 (QA BUG-53): a delete key in Calendar's window shows no card and presses nothing")
    // A batch there goes a step at a time: its one card couldn't hold each step to this rule.
    let batched = rig.run(["batch", "--app", "캘린더", "--stdin"], text: "click \"월\"\npress delete", turn: turn)
    check(batched.output == ArisDesktopBatch.calendarStepLine && turn.cards.count == cards && rig.calls.count == calls
          && ArisDesktopBatch.calendarStepLine.contains("aris-tools event"), "gate-19: a batch in Calendar is sent back to single calls, nothing done")
}

// MARK: - gate-19 (b): only the app's own Quit item is sent to `desktop app quit`; other items with those letters ask

private func gateMenuQuitTests() {
    let decide = { (path: String, target: ArisDesktopTarget, remembered: Bool) in
        ArisDesktopGate.decide(ArisDesktopRequest(verb: .menuClick, app: "X", path: path), target: target, context: ArisDesktopContext(home: "/Users/p"),
                               remembered: remembered, secureInput: false)
    }
    // The app's own Quit, in every form the menu writes it: refused with the way that asks on a card.
    for path in ["TextEdit > Quit TextEdit", "TextEdit > TextEdit 종료", "텍스트 편집기 > 텍스트 편집기 종료", "TextEdit > Quit", "TextEdit > 종료", "File > Quit and Keep Windows",
                 "TextEdit > 종료 및 윈도우 유지", "TextEdit > Quit TextEdit…", "Quit TextEdit", "TextEdit 종료", "TextEdit > Force Quit TextEdit", "TextEdit > 강제 종료",
                 "TextEdit > Ｑｕｉｔ TextEdit", "TextEdit > QUIT  TEXTEDIT", "TextEdit >  Quit TextEdit "] {
        check(decide(path, gateEditor, true) == .refuse(ArisDesktopGate.menuRefusal), "gate-19: the app's own Quit (\(path)) is sent to `desktop app quit`, never clicked")
    }
    check(ArisDesktopGate.menuRefusal.contains("desktop app quit") && ArisDesktopGate.menuRefusal.contains("asked on a card"), "gate-19: that line names the command that asks the user")
    // Other items that only contain the letters: the user's card every time, where they were refused.
    for path in ["보기 > 발표 종료 후 보기", "View > Acquittal Mode", "보기 > 전체 화면 종료", "Game > Quit Match", "재생 > 슬라이드쇼 종료"] {
        check(decide(path, gateEditor, true) == .ask(remember: false) && decide(path, gateEditor, false) == .ask(remember: false),
              "gate-19: “\(path)” is asked on the user's card every time (it was refused for its letters)")
    }
    check(decide("File > Export > PDF…", gateEditor, true) == .run, "gate-19: an ordinary menu item still runs on a remembered yes")
    // Still never: the Apple menu, Recent Items, Services, logging out.
    for path in ["Apple > Force Quit…", "\u{F8FF} > 강제 종료…", "Apple > Log Out the user…", "Apple > 로그아웃", "TextEdit > Log Out", "File > Open Recent > a.txt", "TextEdit > Services > x"] {
        check(decide(path, gateEditor, true) == .refuse(ArisDesktopGate.menuRefusal), "gate-19: \(path) is still refused")
    }
    // Hostile: any item that names quitting in one of the system's own apps never reaches a card.
    for system in [gateTarget("Finder", bundle: "com.apple.finder"), gateTarget("Dock", bundle: "com.apple.dock"), gateTarget("loginwindow", bundle: "com.apple.loginwindow")] {
        for path in ["Finder > Quit Finder", "Finder > Finder 종료", "파일 > 세션 종료", "View > Acquittal Mode", "Finder > Relaunch and Quit All"] {
            if case .refuse = decide(path, system, true) {} else { check(false, "gate-19: “\(path)” in \(system.name) (the system's own app) never reaches a card") }
        }
    }
    check(decide("파일 > 세션 종료", gateTarget("Finder", bundle: "com.apple.finder"), false) == .refuse(ArisDesktopGate.quitSystemRefusal),
          "gate-19: a quit-like item in Finder is refused as quitting the system's own app")
    check(ArisDesktopGate.refusesMenu("미리보기 > 미리보기 종료") && ArisDesktopGate.refusesMenu("Preview > Quit Preview") && !ArisDesktopGate.refusesMenu("보기 > 발표 종료 후 보기")
          && !ArisDesktopGate.refusesMenu("View > Acquittal Mode") && !ArisDesktopGate.refusesMenu("File > Close"), "gate-19: the Quit item is told by what it is, not by its letters")
}

// MARK: - gate-19 (c): a paste in a messaging app goes to a card that shows exactly what is pasted

private func gatePasteTests() {
    let paste = ArisDesktopRequest(verb: .press, app: "X", keys: ["cmd+v"])
    let decide = { (request: ArisDesktopRequest, clipboard: String?) -> ArisDesktopDecision in
        var context = ArisDesktopContext(home: "/Users/p")
        context.clipboard = clipboard
        return ArisDesktopGate.decide(request, target: gateChat, context: context, remembered: true, secureInput: false)
    }
    check(decide(paste, "곧 갈게") == .ask(remember: false) && decide(ArisDesktopRequest(verb: .menuClick, app: "X", path: "편집 > 붙여넣기"), "곧 갈게") == .ask(remember: false)
          && decide(ArisDesktopRequest(verb: .menuClick, app: "X", path: "Edit > Paste and Match Style"), "a\nb") == .ask(remember: false),
          "gate-19: a paste in a messaging app asks on the user's card every time (it was refused)")
    // What the card can't show is still refused: no text read, nothing on the clipboard, too much, hidden characters.
    check(decide(paste, nil) == .refuse(ArisDesktopGate.pasteRefusal) && decide(paste, "") == .refuse(ArisDesktopGate.pasteRefusal)
          && decide(paste, String(repeating: "가", count: ArisDesktopGate.maxPaste + 1)) == .refuse(ArisDesktopGate.pasteLongRefusal)
          && decide(paste, String(repeating: "가", count: ArisDesktopGate.maxPaste)) == .ask(remember: false)
          && decide(paste, "안녕\u{202E}하세요") == .refuse(ArisDesktopGate.hiddenRefusal),
          "gate-19: a paste the card couldn't show in full (no text, too long, hidden characters) is still refused")
    // A paste rides with nothing: not with a send, a select-all or any other key in the same press.
    check(decide(ArisDesktopRequest(verb: .press, app: "X", keys: ["cmd+v", "return"]), "곧 갈게") == .refuse(ArisDesktopGate.pasteAloneRefusal)
          && decide(ArisDesktopRequest(verb: .press, app: "X", keys: ["cmd+a", "cmd+v"]), "곧 갈게") == .refuse(ArisDesktopGate.pasteAloneRefusal)
          && decide(ArisDesktopRequest(verb: .press, app: "X", keys: ["cmd+v", "cmd+v"]), "곧 갈게") == .refuse(ArisDesktopGate.pasteAloneRefusal)
          && decide(ArisDesktopRequest(verb: .press, app: "X", keys: ["v+cmd"]), nil) == .refuse(ArisDesktopGate.pasteRefusal)
          && decide(ArisDesktopRequest(verb: .press, app: "X", keys: ["shift+insert"]), nil) == .refuse(ArisDesktopGate.pasteRefusal),
          "gate-19: in a messaging app a paste is pressed alone, never with a send or another key")
    // The card: the clipboard's own text, word for word, with anything invisible written out.
    let card = ArisDesktopCard.card(paste, target: gateChat, element: nil, window: "엄마", composer: "", paste: "곧 갈게\n10분", remember: false, wiped: false)
    check(card.detail.contains("붙여넣을 글 (지금 클립보드에 있는 그대로):\n곧 갈게\n10분") && card.detail.contains("메시지 앱이라 매번 물어봐요") && card.title == "카카오톡에서 붙여넣기",
          "gate-19: the paste card shows exactly what is on the clipboard: \(card.detail)")
    let long = ArisDesktopCard.card(paste, target: gateChat, element: nil, paste: String(repeating: "가나다라마바사 ", count: 200), remember: false, wiped: false)
    check(long.full?.contains(String(repeating: "가나다라마바사 ", count: 200)) == true, "gate-19: a long paste is whole behind the card's full view")
    // Held to it: what the clipboard holds when the keys go must be what the card showed.
    check(ArisDesktopGate.pasteHolds(card: "곧 갈게", now: "곧 갈게") && !ArisDesktopGate.pasteHolds(card: "곧 갈게", now: "곧 갈게 ") && !ArisDesktopGate.pasteHolds(card: "곧 갈게", now: nil)
          && !ArisDesktopGate.pasteHolds(card: "곧 갈게", now: "계좌번호 110-…") && ArisDesktopGate.pasteHolds(card: nil, now: "무엇이든"),
          "gate-19: a paste is held to the card's text, exactly; with no paste card there is nothing to hold")

    // The engine: the card carries the clipboard's text; with the user's yes the keys go.
    let chat = gateSee(title: "엄마", elements: [gateElement(1, "staticText", "엄마: 언제 와?", x: 120, y: 420, width: 300, height: 20),
                                                gateElement(2, "textArea", "메시지 입력", value: "", x: 120, y: 980, width: 800, height: 40)], focus: 2)
    let pasted = gateSee(title: "엄마", elements: [gateElement(1, "staticText", "엄마: 언제 와?", x: 120, y: 420, width: 300, height: 20),
                                                  gateElement(2, "textArea", "메시지 입력", value: "곧 갈게", x: 120, y: 980, width: 800, height: 40)], focus: 2)
    let window = [ArisDesktopWindow(id: 9189, frame: gateFrame, title: "엄마")]
    let rig = GateRig(gateChat, windows: window)
    rig.apps.clipboardTexts = ["곧 갈게"]
    let turn = GateTurn("카톡 엄마 방에 방금 복사한 거 붙여넣어 줘")
    rig.queue([("see", chat), ("see", chat), ("press", gateSent), ("see", pasted)])
    let done = rig.run(["press", "cmd+v", "--app", "카카오톡"], turn: turn)
    check(done.status == 0 && turn.cards.count == 1 && turn.cards[0].detail.contains("붙여넣을 글 (지금 클립보드에 있는 그대로):\n곧 갈게") && rig.calls.contains { $0.hasPrefix("press cmd+v") },
          "gate-19: “붙여넣어 줘” in KakaoTalk shows the clipboard's text on one card and pastes after the yes: \(turn.cards.first?.detail ?? done.output)")
    // Hostile: the clipboard is something else by the time the keys would go. Nothing is pasted.
    let swapped = GateRig(gateChat, windows: window)
    swapped.apps.clipboardTexts = ["곧 갈게", "계좌번호 110-123-456789"]
    let second = GateTurn("카톡 엄마 방에 붙여넣어 줘")
    swapped.queue([("see", chat), ("see", chat)])
    let held = swapped.run(["press", "cmd+v", "--app", "카카오톡"], turn: second)
    check(held.status != 0 && held.output.contains(ArisDesktopSession.pasteChangedLine) && second.cards.count == 1 && !second.cards[0].detail.contains("계좌번호")
          && !swapped.calls.contains { $0.hasPrefix("press") },
          "gate-19: a clipboard changed after the user's card is never pasted: \(held.output.prefix(160))")
    // Nothing on the clipboard to show (an image, a file): no card, nothing pressed.
    let empty = GateRig(gateChat, windows: window)
    let third = GateTurn("카톡에 붙여넣어 줘")
    let none = empty.run(["press", "cmd+v", "--app", "카카오톡"], turn: third)
    check(none.output == ArisDesktopGate.pasteRefusal && third.cards.isEmpty && empty.calls.isEmpty, "gate-19: with no text on the clipboard a paste shows no card and presses nothing")
    // A batch's one card can't show it: a paste step there is sent back to its own call.
    let batchRig = GateRig(gateChat, windows: window)
    batchRig.apps.clipboardTexts = ["곧 갈게"]
    let fourth = GateTurn("카톡에 붙여넣고 보내 줘")
    batchRig.queue([("see", chat)])
    _ = batchRig.run(["see", "--app", "카카오톡"], turn: fourth)
    let batched = batchRig.run(["batch", "--app", "카카오톡", "--stdin"], text: "press cmd+v\npress return", turn: fourth)
    check(batched.output == ArisDesktopGate.pasteRefusal && fourth.cards.isEmpty && !batchRig.calls.contains { $0.hasPrefix("press") },
          "gate-19: a paste inside a batch in a messaging app is still refused (its card couldn't show the text)")
    // A message field that gives no value (KakaoTalk's): the pasted text, once the window shows it, is kept as text Aris
    // typed there is, so the send goes to the card that says it (audit desk-4's rule) and not to a refusal.
    let blindChat = { (shown: String?) -> Data in
        var elements = [gateElement(1, "staticText", "엄마: 언제 와?", x: 120, y: 420, width: 300, height: 20),
                        gateElement(2, "textArea", "메시지 입력", x: 120, y: 980, width: 800, height: 40)]
        if let shown { elements.append(gateElement(3, "staticText", shown, x: 124, y: 984, width: 200, height: 20)) }
        return gateSee(title: "엄마", elements: elements, focus: 2)
    }
    let blind = GateRig(gateChat, windows: window)
    blind.apps.clipboardTexts = ["곧 갈게"]
    let fifth = GateTurn("카톡 엄마 방에 붙여넣고 보내 줘")
    blind.queue([("see", blindChat(nil)), ("see", blindChat(nil)), ("press", gateSent), ("see", blindChat("곧 갈게"))])
    let blindPaste = blind.run(["press", "cmd+v", "--app", "카카오톡"], turn: fifth)
    check(blindPaste.status == 0 && fifth.cards.count == 1 && fifth.ledger.blindTyped(window: 9189) == "곧 갈게",
          "gate-19: a paste into a field that gives no value is kept for its send once the window shows it: \(blindPaste.output.prefix(120))")
    fifth.answer = .no
    blind.queue([("see", blindChat("곧 갈게"))])
    _ = blind.run(["press", "return", "--app", "카카오톡"], turn: fifth)
    check(fifth.cards.count == 2 && fifth.cards[1].title == "카카오톡에서 보내기" && fifth.cards[1].detail.contains("곧 갈게") && fifth.cards[1].detail.contains("입력 칸을 읽을 수 없어요"),
          "gate-19: and its send is asked on a card that says the text and that the field can't be read: \(fifth.cards.last?.detail ?? "")")
    // Hostile: the window doesn't show the pasted text afterwards (it went somewhere else): nothing is kept, so a send stays refused.
    let lost = GateRig(gateChat, windows: window)
    lost.access.screenRecording = false
    lost.apps.clipboardTexts = ["곧 갈게"]
    let sixth = GateTurn("카톡 엄마 방에 붙여넣고 보내 줘")
    lost.queue([("see", blindChat(nil)), ("see", blindChat(nil)), ("press", gateSent), ("see", blindChat("다른 글")), ("see", blindChat("다른 글"))])
    _ = lost.run(["press", "cmd+v", "--app", "카카오톡"], turn: sixth)
    let unsent = lost.run(["press", "return", "--app", "카카오톡"], turn: sixth)
    check(sixth.ledger.blindTyped(window: 9189) == nil && unsent.output == ArisDesktopEngine.unreadSendLine && sixth.cards.count == 1,
          "gate-19: a paste the window doesn't show afterwards vouches for nothing: its send is still refused")
    // The clipboard's text is for the user's card only: it is never handed to the brain.
    check(!done.output.contains("클립보드") && !held.output.contains("계좌번호"), "gate-19: what the clipboard holds is never told to the brain")
    let actions = gateSource("ArisAgent/ArisDesktopActions.swift")
    let holdAt = actions.range(of: "if let refused = pasteHeld() { return refused }")?.lowerBound
    let pressAt = actions.range(of: "var envelope = run(ArisPeekabooCommands.press(request.keys, snapshot: fresh.peekaboo))")?.lowerBound
    check(holdAt != nil && pressAt != nil && holdAt! < pressAt!, "gate-19: the clipboard is read again right before the keys go")
    // In another app a paste is that app's ordinary key press, as before.
    check(ArisDesktopGate.decide(paste, target: gateEditor, context: ArisDesktopContext(home: "/Users/p"), remembered: true, secureInput: false) == .run,
          "gate-19: a paste in a document app is unchanged")
}

// MARK: - gate-19 (d): a file panel the user's words didn't name goes to a card that says which document and where

private func gateFilePanelTests() {
    let save = { (words: [String]) in try? ArisDesktopWords.parse(["dialog", "file", "--app", "TextEdit"] + words).get() }
    let decide = { (request: ArisDesktopRequest?, context: ArisDesktopContext) in
        request.map { ArisDesktopGate.decide($0, target: gateEditor, context: context, remembered: true, secureInput: false) }
    }
    let unnamed = ArisDesktopContext(home: "/Users/p", request: "방금 답을 파일로 저장해 줘")
    check(decide(save(["--path", "~/Desktop", "--name", "답.txt"]), unnamed) == .ask(remember: false),
          "gate-19: a file panel the user's words named no app or document for asks on his card (it was refused), never a kept yes")
    // The card must be able to say where: with no folder given, the brain is told to say one.
    check(decide(save(["--name", "답.txt"]), unnamed) == .refuse(ArisDesktopGate.dialogFolderRefusal) && ArisDesktopGate.dialogFolderRefusal.contains("--path"),
          "gate-19: with neither a named document nor a folder, the card couldn't say where it saves: the folder is asked for")
    var named = unnamed
    named.userNamedApp = true
    check(decide(save(["--name", "답.txt"]), named) == .ask(remember: false), "gate-19: with the app named, a file name alone still asks as before")
    // Hostile: a protected place is refused whoever named what, and a background job never brings the panel up.
    for place in ["~/.ssh", "~/.config/aris", "~/Library/LaunchAgents", "~/.zshrc"] {
        check(decide(save(["--path", place, "--name", "x"]), unnamed) == .refuse(ArisDesktopGate.placeRefusal), "gate-19: saving into \(place) is still refused")
    }
    check(decide(save(["--path", "~/", "--name", ".zshrc"]), unnamed) == .refuse(ArisDesktopGate.placeRefusal), "gate-19: a protected file named by its folder and name is still refused")
    var job = unnamed
    job.job = true
    check(decide(save(["--path", "~/Desktop", "--name", "답.txt"]), job) == .refuse(ArisDesktopGate.jobRefusal), "gate-19: a background job still never brings a file panel forward")
    // The card: which document, where, under what name, and that their words named neither the app nor the document.
    if let request = save(["--path", "~/Desktop", "--name", "답.txt"]) {
        let card = ArisDesktopCard.card(request, target: gateEditor, element: nil, window: "회의록", unnamedDocument: true, remember: false, wiped: false)
        check(card.detail.contains("창: “회의록”") && card.detail.contains("폴더: 바탕화면") && card.detail.contains("파일 이름: 답.txt") && card.detail.contains("이 문서를 저장하거나 열어요")
              && card.detail.hasPrefix(ArisDesktopCard.unnamedDocumentLine), "gate-19: the card says the document, the folder, the name, and warns first: \(card.detail)")
        let plain = ArisDesktopCard.card(request, target: gateEditor, element: nil, window: "회의록", remember: false, wiped: false)
        check(!plain.detail.contains(ArisDesktopCard.unnamedDocumentLine), "gate-19: a document the user named gets no such warning")
    } else { check(false, "gate-19: the file panel's words parse") }
    if let request = save(["--name", "답.txt"]) {
        let card = ArisDesktopCard.card(request, target: gateEditor, element: nil, window: "회의록", remember: false, wiped: false)
        check(card.detail.contains("폴더: 파일 창에 지금 열려 있는 폴더"), "gate-19: with no folder given the card says the panel's own folder is used: \(card.detail)")
    }
    // The engine: "방금 답을 파일로 저장해 줘" with a TextEdit document in front: one card, warning first, nothing done on a no.
    let rig = GateRig()
    let turn = GateTurn("방금 답을 파일로 저장해 줘")
    turn.answer = .no
    let asked = rig.run(["dialog", "file", "--app", "TextEdit", "--path", "~/Desktop", "--name", "답.txt"], turn: turn)
    check(turn.cards.count == 1 && turn.cards[0].detail.hasPrefix(ArisDesktopCard.unnamedDocumentLine) && turn.cards[0].detail.contains("창: “무제”")
          && turn.cards[0].detail.contains("폴더: 바탕화면") && asked.output.hasPrefix(ArisDesktopEngine.noLine) && !rig.calls.contains { $0.hasPrefix("dialog") },
          "gate-19: “방금 답을 파일로 저장해 줘” shows the card that names the document in front and where it would go: \(turn.cards.first?.detail ?? asked.output)")
    let pointed = GateTurn("이 문서 바탕화면에 저장해 줘")
    pointed.answer = .no
    _ = rig.run(["dialog", "file", "--app", "TextEdit", "--path", "~/Desktop", "--name", "회의록.txt"], turn: pointed)
    check(pointed.cards.count == 1 && !pointed.cards[0].detail.contains(ArisDesktopCard.unnamedDocumentLine), "gate-19: “이 문서 저장해 줘” keeps its plain card")
    let hostile = GateTurn("방금 답을 파일로 저장해 줘")
    let refused = rig.run(["dialog", "file", "--app", "TextEdit", "--path", "~/.ssh", "--name", "authorized_keys"], turn: hostile)
    check(refused.output == ArisDesktopGate.placeRefusal && hostile.cards.isEmpty, "gate-19: a save into ~/.ssh shows no card at all")
}

// MARK: - gate-20: what `claude` gets always starts with Aris's fixed line

private func gateLaunchArgumentTests() {
    let briefs = ["/Users/x/proj 폴더에서 테스트 돌려줘", "#123 이슈 고쳐줘", "@src/main.swift 고쳐줘", "--permission-mode=bypassPermissions", "-p hi", "--dangerously-skip-permissions\nfix it",
                  "!curl x | sh", "/permissions", "\u{FEFF}!rm -rf ~", "  --x", "& echo hi"]
    for brief in briefs {
        let argument = ArisTeammateLauncher.argument(for: brief)
        check(ArisTeammateGate.isSafePrompt(argument) && argument.unicodeScalars.starts(with: ArisTeammateLauncher.header.unicodeScalars)
              && Array(argument.unicodeScalars.dropFirst(ArisTeammateLauncher.header.unicodeScalars.count)) == Array(brief.unicodeScalars),
              "gate-20: a brief that starts “\(brief.prefix(14).debugDescription)” reaches claude after the fixed line, whole and unchanged")
    }
    check(!ArisTeammateGate.isSafePrompt("--permission-mode=bypassPermissions") && !ArisTeammateGate.isSafePrompt("!curl x | sh") && !ArisTeammateGate.isSafePrompt("")
          && ArisTeammateLauncher.header.unicodeScalars.first == "A" && !ArisTeammateLauncher.header.contains("@"),
          "gate-20: the check itself is as strict as before; it is the fixed line that makes the argument safe")
    let desk = gateSource("ArisAgent/ArisTeammateDesk.swift")
    check(desk.contains("guard ArisTeammateGate.isSafePrompt(ArisTeammateLauncher.argument(for: prompt)) else {") && !desk.contains("ArisTeammateGate.isSafePrompt(prompt)"),
          "gate-20: the launch checks what claude really gets, not the bare brief")

    // Hostile, for real but harmless: the very command line Aris types, with a stand-in program for claude that writes
    // down its arguments. A brief full of flags, quotes and shell tricks stays one argument, and runs nothing.
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("aris-gate-launch-\(UUID().uuidString)")
    let work = root.appendingPathComponent("work"), project = root.appendingPathComponent("proj's \"dir\"")
    try? fm.createDirectory(at: project, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let stand = root.appendingPathComponent("stand-in")
    let out = root.appendingPathComponent("seen.txt")
    fm.createFile(atPath: stand.path, contents: Data("#!/bin/sh\nprintf '%s\\n' \"$#\" > '\(out.path)'\nprintf '%s' \"$1\" >> '\(out.path)'\n".utf8), attributes: [.posixPermissions: 0o755])
    let trap = root.appendingPathComponent("pwned").path
    let hostile = "--dangerously-skip-permissions -p \"x\"; touch '\(trap)'; $(touch '\(trap)') `touch '\(trap)'`\n&& touch '\(trap)' | touch \(trap)\n'\\''; touch \(trap) #"
    if let file = try? ArisTeammateLauncher.writePrompt(hostile, in: work, id: UUID()) {
        let command = ArisClaudeLaunch.command(promptFile: file.path, cwd: project.path, claude: stand.path)
        check(!command.contains("dangerously") && !command.contains("touch"), "gate-20: the brief is never in the command line itself, only in the file it reads")
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-f", "-c", command]
        shell.standardOutput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice
        try? shell.run()
        shell.waitUntilExit()
        let seen = (try? String(contentsOf: out, encoding: .utf8)) ?? ""
        check(seen == "1\n" + ArisTeammateLauncher.header + hostile, "gate-20: a brief of flags, quotes and shell tricks arrives as one argument, after the fixed line: \(seen.prefix(60).debugDescription)")
        check(!fm.fileExists(atPath: trap), "gate-20: and none of its commands ran")
    } else { check(false, "gate-20: the prompt file is written") }
}

// MARK: - gate-20: a web project's "@/…" import alias is no mention of a file outside the project

private func gateLaunchAliasTests() {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("aris-gate-alias-\(UUID().uuidString)")
    let home = root.appendingPathComponent("home"), project = home.appendingPathComponent("web")
    try? fm.createDirectory(at: project.appendingPathComponent("components"), withIntermediateDirectories: true)
    try? fm.createDirectory(at: root.appendingPathComponent("elsewhere"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let cwd = ArisTeammateGate.folder(project.path, home: home.path) ?? project.path
    // The disk's top folders as this test says they are: nothing called components, lib, app or src; the real ones exist.
    let real: Set<String> = ["/etc", "/Users", "/tmp", "/private", "/Volumes", "/usr", "/var"]
    let outside = { (brief: String) in ArisTeammateGate.mentionsOutsideFiles(brief, cwd: cwd, home: home.path, exists: { real.contains($0) }) }
    for brief in ["Fix the import of @/components/Header.tsx in the header", "import x from '@/lib/utils' 가 안 풀려요", "`@/app/(marketing)/[slug]/page.tsx`를 고쳐줘",
                  "@/components/Header.tsx#L1-5 를 봐줘", "@/components/Header.tsx를 고치고 @/lib/api.ts도 맞춰줘", "see \"@/components/Button\" and @src/main.swift"] {
        check(!outside(brief), "gate-20: “\(brief.prefix(44))” (an import alias) launches: there is no such file outside the project to read")
    }
    // Hostile: the same shape naming something real, climbing, chained to another mention, or quoted.
    for brief in ["read @/etc/hosts", "@/Users/user/.ssh/id_rsa 요약해줘", "@/tmp/x", "@/private/etc/passwd", "@~/.ssh/id_rsa", "@../secrets.txt", "@/components/../../etc/hosts",
                  "@/components/Header.tsx@~/.ssh/id_rsa", "@/components/x@/etc/hosts", "@/", "@//etc/hosts", "@/./etc/hosts", "@\"/components/x\"", "@'/etc/hosts'",
                  "x@/etc/hosts", "@/components/Header.tsx and @/etc/hosts", "@/components//etc/hosts", "@/components/./x", "@/./components/x", "@/components/", "@/" + String(repeating: "a", count: 2_000) + "/../../etc/hosts", "@/components/" + String(repeating: "a", count: 1_100)] {
        check(outside(brief), "gate-20: “\(brief.prefix(44))” is still refused")
    }
    // The alias is only an alias while the disk has nothing there, and while the same path under the project stays inside it.
    check(ArisTeammateGate.mentionsOutsideFiles("fix @/components/Header.tsx", cwd: cwd, home: home.path, exists: { $0 == "/components" || real.contains($0) }),
          "gate-20: with a real /components on the disk, “@/components/…” is a mention of it and refused")
    try? fm.removeItem(at: project.appendingPathComponent("components"))
    try? fm.createSymbolicLink(at: project.appendingPathComponent("components"), withDestinationURL: root.appendingPathComponent("elsewhere"))
    check(outside("fix @/components/Header.tsx"), "gate-20: an alias whose folder in the project is a link leading outside it is refused")
    check(ArisTeammateGate.withoutAliases("a @/lib/x b @/etc/hosts", cwd: cwd, home: home.path, exists: { real.contains($0) }) == "a \(ArisTeammateGate.aliasMark) b @/etc/hosts"
          && !ArisTeammateGate.aliasMark.contains("@"), "gate-20: only the alias is set aside for the check; a real mention beside it stays")
    // With the real disk too (no injected list): /etc exists on every Mac.
    check(ArisTeammateGate.mentionsOutsideFiles("read @/etc/hosts", cwd: cwd, home: home.path) && ArisTeammateGate.existsOnDisk("/etc") && !ArisTeammateGate.existsOnDisk("/aris-no-such-folder-\(UUID().uuidString)"),
          "gate-20: on the real disk “@/etc/hosts” is refused")
    let desk = gateSource("ArisAgent/ArisTeammateDesk.swift")
    check(desk.components(separatedBy: "ArisTeammateGate.mentionsOutsideFiles(prompt, cwd: cwd, home: home)").count == 3,
          "gate-20: the brief is checked when the launch is asked for and again right before the window opens")
}

// MARK: - gate-20: a folder outside the home folder goes to the user's card, which names it

private func gateLaunchFolderTests() {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("aris-gate-folder-\(UUID().uuidString)")
    let home = root.appendingPathComponent("home"), outside = root.appendingPathComponent("disk/project")
    for folder in [home.appendingPathComponent("Desktop/proj"), home.appendingPathComponent("Library/x"), home.appendingPathComponent(".ssh"), outside] {
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    fm.createFile(atPath: root.appendingPathComponent("disk/file.txt").path, contents: Data())
    try? fm.createSymbolicLink(at: home.appendingPathComponent("ext"), withDestinationURL: outside)
    defer { try? fm.removeItem(at: root) }
    let h = home.path
    let resolved = ArisTeammateGate.outsideFolder(outside.path, home: h)
    check(resolved != nil && resolved?.hasSuffix("/disk/project") == true && ArisTeammateGate.folder(outside.path, home: h) == nil,
          "gate-20: a real folder outside the home folder is told as that (it was only refused)")
    let place = ArisTeammateGate.place(outside.path, home: h)
    check(place?.outsideHome == true && place?.path == resolved && ArisTeammateGate.place(h + "/Desktop/proj", home: h)?.outsideHome == false
          && ArisTeammateGate.place(h + "/ext", home: h) == place, "gate-20: a folder under home is as before; one outside, or a link in home that leads outside, is marked outside")
    // Never accepted silently: even a launch the user's own turn vouches for asks, and the card names the folder.
    check(ArisTeammateGate.needsYes(vouched: true, outbound: [], outsideHome: true) && !ArisTeammateGate.needsYes(vouched: true, outbound: [], outsideHome: false)
          && ArisTeammateGate.needsYes(vouched: false, outbound: [], outsideHome: false), "gate-20: a folder outside home always asks, vouched or not")
    let note = ArisTeammateGate.cardNote(outsideHome: true, version: "버전 메모")
    let card = ArisTeammateGate.card(id: "teammate-x", cwd: resolved ?? "", prompt: "테스트 돌려줘", outbound: [], note: note)
    check(card.detail.contains("폴더: \(resolved ?? "?")") && card.detail.contains(ArisTeammateGate.outsideHomeNote) && card.detail.contains("버전 메모")
          && card.full?.contains(ArisTeammateGate.outsideHomeNote) == true && ArisTeammateGate.cardNote(outsideHome: false, version: nil) == nil
          && ArisTeammateGate.cardNote(outsideHome: false, version: "v") == "v",
          "gate-20: the launch card names the folder and says it is outside the home folder: \(card.detail)")
    // Hostile: the system's own places, anything that holds the home folder, and what `folder` already refuses.
    let parents = [(h as NSString).deletingLastPathComponent, ((h as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent]
    for bad in ["/", "/Users", "/System", "/System/Library", "/usr/bin", "/Applications", "/Library", "/Volumes", "/private", "/private/var", "/private/etc", "/etc", "/dev",
                h, h + "/Library/x", h + "/.ssh", h + "/nope", root.appendingPathComponent("disk/file.txt").path, "disk/project", "", "/tmp/aris-no-such-\(UUID().uuidString)"] + parents {
        check(ArisTeammateGate.place(bad, home: h) == nil, "gate-20: Claude Code is never opened in \(bad.isEmpty ? "(no folder)" : bad)")
    }
    // Held to it when the window opens: the same folder, still outside; a swap or a removal stops the launch.
    let checked = resolved ?? ""
    check(ArisTeammateGate.isUnchanged(checked, home: h, outsideHome: true) && !ArisTeammateGate.isUnchanged(checked, home: h),
          "gate-20: an outside folder is checked again as an outside folder before the window opens")
    try? fm.removeItem(at: outside)
    try? fm.createSymbolicLink(at: outside, withDestinationURL: URL(fileURLWithPath: "/etc"))
    check(!ArisTeammateGate.isUnchanged(checked, home: h, outsideHome: true), "gate-20: an outside folder swapped for a link to /etc before launch is refused")
    let desk = gateSource("ArisAgent/ArisTeammateDesk.swift")
    check(desk.contains("ArisTeammateGate.needsYes(vouched: vouched, outbound: outbound, outsideHome: place.outsideHome)")
          && desk.contains("ArisTeammateGate.isUnchanged(cwd, home: home, outsideHome: place.outsideHome)") && desk.contains("ArisTeammateGate.cardNote(outsideHome: place.outsideHome"),
          "gate-20: the launch asks for an outside folder, says so on the card, and checks it again before opening")
}

// MARK: - desk-11: computer use's and Aside's cards and status lines are English for an English request

/// Any Hangul (syllables or jamo) in what the user would read.
private func gateHasKorean(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x1100...0x11FF).contains($0.value) || (0x3130...0x318F).contains($0.value) }
}

private func gateWhole(_ card: ArisMCPCard) -> String { [card.title, card.detail, card.full ?? "", card.allow ?? ""].joined(separator: "\n") }

private func gateEnglishCardTests() {
    check(ArisDesktopCopy.isEnglish("Press the Save button in Notes") && !ArisDesktopCopy.isEnglish("Notes에서 저장 눌러 줘") && !ArisDesktopCopy.isEnglish("")
          && !ArisDesktopCopy.isEnglish("  ") && !ArisDesktopCopy.isEnglish("save 눌러"), "desk-11: one switch, the user's own words: English only when they have words and no Korean")
    let notes = gateTarget("메모", bundle: "com.apple.Notes"), slack = gateTarget("Slack", bundle: "com.tinyspeck.slackmacgap", sending: true)
    let save = ArisDesktopElement(id: "elem_5", role: "button", label: "Save")
    // The Korean card is word for word what it was.
    let click = ArisDesktopRequest(verb: .click, ref: gateRef)
    let korean = ArisDesktopCard.card(click, target: notes, element: save, window: "Untitled", remember: true, wiped: false, mayRaise: true)
    check(korean.title == "메모에서 누르기"
          && korean.detail == "창: “Untitled”\n대상: 버튼 “Save”\n백그라운드로 안 되면 ‘Untitled’ 창을 앞으로 가져와서 누르기 (끝나면 원래 앱으로 돌아가요)\n허용하면 이 대화에서 메모는 다시 묻지 않아요",
          "desk-11: the Korean card is unchanged: \(korean.detail)")
    let english = ArisDesktopCard.card(click, target: gateTarget("Notes", bundle: "com.apple.Notes"), element: save, window: "Untitled", remember: true, wiped: false, mayRaise: true, english: true)
    check(english.title == "Click in Notes"
          && english.detail == "Window: “Untitled”\nTarget: button “Save”\nIf it can't be done in the background, the window “Untitled” is brought to the front for it "
          + "(then the app you were in comes back)\nIf you allow it, Aris won't ask again for Notes in this conversation",
          "desk-11: the same card for an English request is English: \(english.detail)")
    // No half-translated card: every kind of step, with every optional line on, in both kinds of app.
    var file = ArisDesktopRequest(verb: .dialogFile, app: "Notes", path: "~/Desktop", name: "notes.txt")
    file.select = "Save"
    var bare = ArisDesktopRequest(verb: .dialogFile, app: "Notes")
    bare.name = "token"
    var drag = ArisDesktopRequest(verb: .drag, ref: gateRef)
    drag.to = ArisDesktopRef(snapshot: "s8f3k2", element: 9)
    var input = ArisDesktopRequest(verb: .dialogInput, app: "Notes", text: "hello")
    input.field = "Name"
    var quit = ArisDesktopRequest(verb: .app, app: "Notes")
    quit.operation = "quit"
    var hide = ArisDesktopRequest(verb: .app, app: "Notes")
    hide.operation = "hide"
    var close = ArisDesktopRequest(verb: .window, app: "Notes")
    close.operation = "close"
    let every: [ArisDesktopRequest] = [
        click, ArisDesktopRequest(verb: .type, ref: gateRef, text: "hello\nthere"), ArisDesktopRequest(verb: .setValue, ref: gateRef, text: "hello"),
        ArisDesktopRequest(verb: .press, app: "Notes", keys: ArisDesktopCopy.keyMeanings.keys.sorted() + ["f5"]), ArisDesktopRequest(verb: .press, app: "Notes", keys: ["cmd+a", "delete"]),
        ArisDesktopRequest(verb: .scroll, ref: gateRef, direction: "down"), drag, ArisDesktopRequest(verb: .menuClick, app: "Notes", path: "File > Export"),
        ArisDesktopRequest(verb: .dialogClick, app: "Notes", button: "OK"), input, file, bare, close, quit, hide,
        ArisDesktopRequest(verb: .clickAt, app: "Notes", target: "the blue button"), ArisDesktopRequest(verb: .see, app: "Notes"), ArisDesktopRequest(verb: .batch, app: "Notes"),
    ]
    let roles = ["textField", "textArea", "searchField", "AXSecureTextField", "comboBox", "button", "popUpButton", "menuButton", "checkbox", "radioButton", "link", "menuItem",
                 "menu", "tab", "tabGroup", "slider", "staticText", "text", "image", "row", "cell", "table", "list", "outline", "scrollArea", "window", "group", "toolbar",
                 "webArea", "heading", "disclosureTriangle", "somethingNew", ""]
    var mixed: [String] = []
    for request in every {
        for target in [gateTarget("Notes", bundle: "com.apple.Notes"), slack] {
            for flags in 0..<8 {
                let on = { (bit: Int) in flags & (1 << bit) != 0 }
                let element = on(0) ? ArisDesktopElement(id: "elem_5", role: roles[(flags * 5) % roles.count], label: on(1) ? "Save" : "") : nil
                let card = ArisDesktopCard.card(request, target: target, element: element, window: on(1) ? "Untitled" : nil, composer: on(2) ? "draft" : on(0) ? "" : nil,
                                                send: on(2), blindField: on(1), blindSend: on(0) && on(2) ? "typed" : nil, searchFocus: on(1) ? "Search" : nil,
                                                paste: on(2) ? "pasted text" : nil, unnamedDocument: on(0), remember: on(1), wiped: on(2), mayRaise: on(0), english: true)
                if gateHasKorean(gateWhole(card)) { mixed.append("\(request.verb.rawValue)/\(target.name)/\(flags): \(gateWhole(card))") }
            }
        }
    }
    check(mixed.isEmpty, "desk-11: no English card of any step carries a Korean line: \(mixed.prefix(2))")
    for role in roles {
        let word = ArisDesktopCard.roleWord(role, english: true)
        check(!gateHasKorean(word) && !word.isEmpty && gateHasKorean(ArisDesktopCard.roleWord(role)), "desk-11: a control's kind (\(role.isEmpty ? "none" : role)) has an English word and keeps its Korean one")
    }
    check(ArisDesktopCard.roleWord("AXButton", english: true) == "button" && ArisDesktopCard.roleWord("somethingNew", english: true) == "item" && ArisDesktopCard.roleWord("AXButton") == "버튼"
          && ArisDesktopCard.roleWord("somethingNew") == "요소", "desk-11: an unknown kind of control is an “item” (요소)")
    check(ArisDesktopCard.keyWords(["cmd+a", "delete", "f5"], english: true) == "cmd+a (select all) delete (deletes what is selected) f5"
          && ArisDesktopCard.keyWords(["cmd+a", "delete", "f5"]) == "cmd+a (전체 선택) delete (선택한 것을 지워요) f5", "desk-11: the keys say what they do in the card's language")
    check(ArisDesktopCard.friendlyPath("~/Desktop/a", english: true) == "Desktop › a" && ArisDesktopCard.friendlyPath("~/x/a", english: true) == "Home › x › a"
          && ArisDesktopCard.friendlyPath("~/Desktop/a") == "바탕화면 › a" && ArisDesktopCard.friendlyPath("~/x/a") == "홈 › x › a", "desk-11: a folder is named as Finder names it in that language")
    for verb in ArisDesktopVerb.allCases {
        check(!gateHasKorean(ArisDesktopCard.verbLabel(verb, english: true)) && gateHasKorean(ArisDesktopCard.verbLabel(verb)), "desk-11: “\(verb.rawValue)” has a title word in both languages")
    }
    // Titles: a send, a quit, a paste.
    let send = ArisDesktopCard.card(ArisDesktopRequest(verb: .press, app: "Slack", keys: ["return"]), target: slack, element: nil, composer: "on my way", send: true, remember: false, wiped: false, english: true)
    let pasted = ArisDesktopCard.card(ArisDesktopRequest(verb: .press, app: "Slack", keys: ["cmd+v"]), target: slack, element: nil, paste: "on my way", remember: false, wiped: false, english: true)
    let quitCard = ArisDesktopCard.card(quit, target: gateTarget("Notes", bundle: "com.apple.Notes"), element: nil, remember: false, wiped: false, english: true)
    check(send.title == "Send in Slack" && send.detail.contains("Text to send (exactly what the field holds now):\non my way") && send.detail.hasSuffix("This is a messaging app, so Aris asks every time")
          && pasted.title == "Paste in Slack" && pasted.detail.contains("Text to paste (exactly what is on the clipboard now):\non my way") && quitCard.title == "Quit Notes"
          && quitCard.detail.contains("the app asks first"), "desk-11: a send, a paste and a quit say so in English: \(send.detail) / \(pasted.detail)")
    let unnamed = ArisDesktopCard.card(file, target: gateTarget("Notes", bundle: "com.apple.Notes"), element: nil, window: "Untitled", unnamedDocument: true, remember: false, wiped: false, english: true)
    check(unnamed.detail.hasPrefix("⚠️ Your request named neither this app nor a document") && unnamed.detail.contains("Folder: Desktop") && unnamed.detail.contains("File name: notes.txt")
          && unnamed.detail.contains("Button to press: Save"), "desk-11: the file panel's card says the document, the folder and the name in English: \(unnamed.detail)")
    // The batch card.
    let steps = [ArisDesktopStep(verb: .click, target: .label("New Note")), ArisDesktopStep(verb: .press, keys: ["cmd+a"]), ArisDesktopStep(verb: .type, target: .ref(gateRef), text: "hello"),
                 ArisDesktopStep(verb: .scroll, target: .ref(gateRef), direction: "down"), ArisDesktopStep(verb: .press, keys: ["return"])]
    let elements: [ArisDesktopElement?] = [nil, nil, ArisDesktopElement(id: "elem_5", role: "textArea", label: "Body"), nil, nil]
    for target in [gateTarget("Notes", bundle: "com.apple.Notes"), slack] {
        for flags in 0..<8 {
            let on = { (bit: Int) in flags & (1 << bit) != 0 }
            let card = ArisDesktopCard.batch(steps, elements: elements, target: target, window: on(0) ? "Untitled" : nil, composer: on(1) ? "" : "draft", sends: on(2) ? "drafthello" : nil,
                                             remember: on(0), wiped: on(1), mayRaise: on(2), english: true)
            check(!gateHasKorean(gateWhole(card)), "desk-11: an English batch card in \(target.name) (\(flags)) has no Korean line: \(card.detail)")
        }
    }
    let batchEnglish = ArisDesktopCard.batch(steps, elements: elements, target: gateTarget("Notes", bundle: "com.apple.Notes"), window: "Untitled", composer: nil, sends: nil, remember: false, wiped: false, english: true)
    let batchKorean = ArisDesktopCard.batch(steps, elements: elements, target: notes, window: "Untitled", composer: nil, sends: nil, remember: false, wiped: false)
    check(batchEnglish.title == "5 steps in Notes" && batchEnglish.detail.hasPrefix("⚠️ This deletes everything in the document and puts ‘hello’ in its place\nWindow: “Untitled”\n1. Click: “New Note”\n2. Press keys: cmd+a (select all)\n3. Type: text field “Body”\nText to type:\nhello\n4. Scroll: item (down)"),
          "desk-11: the English batch card lists each step in English: \(batchEnglish.detail)")
    check(batchKorean.title == "메모에서 5단계 하기" && batchKorean.detail == "⚠️ 문서 내용을 모두 지우고 ‘hello’로 바꿔요\n창: “Untitled”\n1. 누르기: “New Note”\n2. 키 누르기: cmd+a (전체 선택)\n3. 입력하기: 입력칸 “Body”\n입력하는 글:\nhello\n4. 스크롤: 요소 (down)\n5. 키 누르기: return (확인 (엔터))",
          "desk-11: the Korean batch card is unchanged: \(batchKorean.detail)")
    // The small consent cards: each title has its English, and each detail is one language.
    for title in [ArisDesktopSession.foregroundCard, ArisDesktopSession.pointerCard, ArisDesktopSession.spotCard, ArisDesktopSession.settingsCard] {
        let said = ArisDesktopCopy.consentTitle(title, english: true)
        check(!gateHasKorean(said) && !said.isEmpty && ArisDesktopCopy.consentTitle(title, english: false) == title, "desk-11: the consent card “\(title)” has an English title (\(said))")
    }
    let details = [ArisDesktopCopy.settingsDetail(title: "Wi-Fi", english: true), ArisDesktopCopy.forwardKeysDetail(title: "Untitled", keys: ["cmd+s"], english: true),
                   ArisDesktopCopy.forwardTypeDetail(title: "Untitled", text: "hello", english: true), ArisDesktopCopy.pointerDetail(title: "Untitled", label: "Save", english: true),
                   ArisDesktopCopy.spotDetail(title: "Canvas", wanted: "the blue button", label: "Save", role: "button", point: CGPoint(x: 10.4, y: 20.6), english: true),
                   ArisDesktopCopy.spotDetail(title: "Canvas", wanted: "the blue button", label: "", role: "", point: nil, english: true)]
    check(details.allSatisfy { !gateHasKorean($0) && $0.hasPrefix("Window: “") }, "desk-11: the consent cards' details are English through and through: \(details)")
    check(ArisDesktopCopy.settingsDetail(title: "Wi-Fi", english: false) == "창: “Wi-Fi”\n어떤 설정 화면인지 확실히 알 수 없어서 물어봐요"
          && ArisDesktopCopy.forwardKeysDetail(title: "무제", keys: ["cmd+s"], english: false) == "창: “무제”\n키: cmd+s\n백그라운드로는 안 돼서 창을 앞으로 가져와 누르고, 끝나면 원래 앱으로 돌아가요"
          && ArisDesktopCopy.forwardTypeDetail(title: "무제", text: "안녕", english: false) == "창: “무제”\n입력하는 글:\n안녕\n백그라운드 입력이 안 돼서 창을 앞으로 가져와 실제로 입력해요"
          && ArisDesktopCopy.pointerDetail(title: "무제", label: "저장", english: false) == "창: “무제”\n대상: “저장”\n백그라운드로 안 눌러져서 실제 마우스로 그 자리를 눌러요 (끝나면 제자리로)"
          && ArisDesktopCopy.spotDetail(title: "Canvas", wanted: "파란 버튼", label: "저장", role: "button", point: CGPoint(x: 10.4, y: 20.6), english: false)
              == "창: “Canvas”\n찾던 것: 파란 버튼\n고른 자리: button “저장”\n창 안 위치: 10, 21"
          && ArisDesktopCopy.spotDetail(title: "Canvas", wanted: "x", label: "", role: "", point: nil, english: false) == "창: “Canvas”\n찾던 것: x\n고른 자리: 이름 없는 곳",
          "desk-11: the consent cards' Korean details are word for word what they were")
    let ladder = gateSource("ArisAgent/ArisDesktopTextLadder.swift"), look = gateSource("ArisAgent/ArisDesktopLook.swift"), actions = gateSource("ArisAgent/ArisDesktopActions.swift")
    check(ladder.contains("ArisDesktopCopy.consentTitle(title, english: english)") && ladder.contains("ArisDesktopCopy.forwardTypeDetail(title: look.title, text: text, english: english)")
          && look.contains("ArisDesktopCopy.pointerDetail(title: look.title, label: label, english: english)") && look.components(separatedBy: "english: english)").count == 5
          && actions.contains("ArisDesktopCopy.settingsDetail(title: look?.title ?? \"\", english: english)") && actions.contains("ArisDesktopCopy.forwardKeysDetail(title: look.title, keys: keys, english: english)"),
          "desk-11: every consent card takes its title and its detail from the same switch")
}

private func gateEnglishStatusTests() {
    check(ArisDesktopEngine.statusLine(.see, app: "TextEdit") == "TextEdit 보는 중…" && ArisDesktopEngine.statusLine(.type, app: "TextEdit") == "TextEdit에서 입력 중…"
          && ArisDesktopEngine.statusLine(.click, app: "TextEdit") == "TextEdit에서 누르는 중…", "desk-11: the notch's Korean status lines are unchanged")
    check(ArisDesktopEngine.statusLine(.see, app: "TextEdit", english: true) == "Looking at TextEdit…" && ArisDesktopEngine.statusLine(.type, app: "TextEdit", english: true) == "Typing in TextEdit…"
          && ArisDesktopEngine.statusLine(.click, app: "TextEdit", english: true) == "Working in TextEdit…", "desk-11: and are English for an English request")
    let lines = [ArisDesktopCopy.needsAccessibility(english: true), ArisDesktopCopy.needsScreenRecording(english: true), ArisDesktopCopy.installing(english: true)]
    check(lines.allSatisfy { !gateHasKorean($0) && !$0.isEmpty } && ArisDesktopCopy.needsAccessibility(english: false) == "Aris에 손쉬운 사용 권한을 켜 주세요"
          && ArisDesktopCopy.needsScreenRecording(english: false) == "Aris에 화면 기록 권한을 켜 주세요" && ArisDesktopCopy.installing(english: false) == "컴퓨터 사용 도구 설치 중…",
          "desk-11: the permission and install status lines have both languages")
    // What a brain is told to say: the user's language, never "in Korean", for an English request.
    for (english, korean) in [(ArisDesktopEngine.accessLine(english: true), ArisDesktopEngine.accessLine), (ArisDesktopEngine.screenLine(english: true), ArisDesktopEngine.screenLine),
                              (ArisDesktopEngine.blindLine(english: true), ArisDesktopEngine.blindLine)] {
        check(!gateHasKorean(english) && !english.contains("in Korean") && english.contains("in their language") && korean.contains("in Korean") && gateHasKorean(korean),
              "desk-11: an English turn's brain is told to say it in the user's language: \(english.prefix(60))")
    }
    check(ArisDesktopEngine.accessLine(english: false) == ArisDesktopEngine.accessLine && ArisDesktopEngine.screenLine(english: false) == ArisDesktopEngine.screenLine
          && ArisDesktopEngine.blindLine(english: false) == ArisDesktopEngine.blindLine, "desk-11: a Korean turn's lines are the ones it had")

    // The engine: the same click for an English and a Korean request.
    let doc = gateSee(title: "Untitled", elements: [gateElement(1, "button", "Save", x: 300, y: 340, width: 60, height: 24, actionable: true)])
    let window = [ArisDesktopWindow(id: 9189, frame: gateFrame, title: "Untitled")]
    let rig = GateRig(gateEditor, windows: window)
    let asked = GateTurn("Press the Save button in TextEdit")
    rig.queue([("see", doc)])
    let seen = rig.run(["see", "--app", "TextEdit"], turn: asked)
    asked.answer = .no
    _ = rig.run(["click", rig.ref("Save", in: seen.output)], turn: asked)
    check(asked.cards.count == 1 && asked.cards[0].title == "Click in TextEdit" && !gateHasKorean(gateWhole(asked.cards[0])) && asked.cards[0].detail.contains("Target: button “Save”")
          && asked.statuses.contains("Looking at TextEdit…") && asked.statuses.contains("Working in TextEdit…") && !asked.statuses.contains(where: gateHasKorean),
          "desk-11: an English request gets an English card and English status lines: \(asked.cards.first?.detail ?? "") \(asked.statuses)")
    let other = GateRig(gateEditor, windows: window)
    let said = GateTurn("TextEdit에서 Save 버튼 눌러 줘")
    other.queue([("see", doc)])
    let again = other.run(["see", "--app", "TextEdit"], turn: said)
    said.answer = .no
    _ = other.run(["click", other.ref("Save", in: again.output)], turn: said)
    check(said.cards.count == 1 && said.cards[0].title == "TextEdit에서 누르기" && said.cards[0].detail.contains("대상: 버튼 “Save”") && said.statuses.contains("TextEdit 보는 중…")
          && said.statuses.contains("TextEdit에서 누르는 중…"), "desk-11: the same call for a Korean request is Korean as before: \(said.cards.first?.detail ?? "") \(said.statuses)")
    // An English batch.
    let batchRig = GateRig(gateEditor, windows: window)
    let batchTurn = GateTurn("Press Save in TextEdit, then press return")
    batchRig.queue([("see", doc)])
    _ = batchRig.run(["see", "--app", "TextEdit"], turn: batchTurn)
    batchTurn.answer = .no
    _ = batchRig.run(["batch", "--app", "TextEdit", "--stdin"], text: "click \"Save\"\npress escape", turn: batchTurn)
    check(batchTurn.cards.count == 1 && batchTurn.cards[0].title == "2 steps in TextEdit" && !gateHasKorean(gateWhole(batchTurn.cards[0])),
          "desk-11: an English request's batch card is English: \(batchTurn.cards.first?.detail ?? "")")
    // No Accessibility: the status line and what the brain is told follow the request too.
    let locked = GateRig(gateEditor, windows: window)
    locked.access.trusted = false
    let first = GateTurn("Look at TextEdit"), second = GateTurn("TextEdit 봐 줘")
    let englishOut = locked.run(["see", "--app", "TextEdit"], turn: first), koreanOut = locked.run(["see", "--app", "TextEdit"], turn: second)
    check(englishOut.output == ArisDesktopCopy.accessLine && first.statuses == ["Turn on Accessibility for Aris"] && koreanOut.output == ArisDesktopEngine.accessLine
          && second.statuses == ["Aris에 손쉬운 사용 권한을 켜 주세요"], "desk-11: with no Accessibility the line for the user and the line for the brain follow his language")
}

/// A turn for the Aside tool whose request is English or Korean.
private final class GateAsideTurn: ArisAsideTurn {
    let brainName = "Claude"
    var taint = ArisTaint.none
    var handsFree = false, isTask = false, screen = false, relayed = false
    var answers: [ArisMCPAnswer] = []
    var cards: [ArisMCPCard] = []
    var statuses: [String] = []
    let asideTurnKey = "gate-" + UUID().uuidString
    var asideLive = true
    let asideEnglish: Bool
    init(english: Bool, answers: [ArisMCPAnswer] = []) { asideEnglish = english; self.answers = answers }
    func takeOutsideText() { taint = .outsideText }
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) { cards.append(card); answer(answers.isEmpty ? .no : answers.removeFirst()) }
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { done(.blocked(.undecided)) }
    func quiet(_ status: String) {}
    func audit(_ fields: [String: String]) {}
    func asideRunning(_ brief: String) { statuses.append(ArisAside.runningStatus(brief, english: asideEnglish)) }
    func asideWaiting(_ status: String) { statuses.append(status) }
    func asideEnded() {}
}

private func gateEnglishAsideTests() {
    // Each of Aside's lines and cards: English with no Korean in it, and the Korean one exactly as it was.
    let english = [ArisAside.cardTitle(english: true), ArisAside.workingStatus(english: true), ArisAside.codeWaitingStatus(english: true), ArisAside.loginStatus("WDJB-MJHT", english: true),
                   gateWhole(ArisAside.loginCard(english: true)), ArisAside.signedOutLine(english: true), ArisAside.loginOutput(approved: true, code: "X", timedOut: false, english: true),
                   ArisAside.loginOutput(approved: false, code: nil, timedOut: false, english: true), ArisAside.loginOutput(approved: false, code: "X", timedOut: true, english: true),
                   ArisAside.loginOutput(approved: false, code: "X", timedOut: false, english: true), ArisAside.missingLine(english: true), gateWhole(ArisAside.missingCard(english: true)),
                   ArisAside.untrustedLine(english: true), ArisAside.cliMissingLine(english: true), ArisAside.cliMissingOutput(english: true), ArisAside.missingOutput(opened: true, english: true),
                   ArisAside.missingOutput(opened: false, english: true), ArisAside.runningStatus("find the cheapest earbuds", english: true)]
    check(english.allSatisfy { !gateHasKorean($0) && !$0.isEmpty }, "desk-11: every Aside card and line has an English form with no Korean in it: \(english.filter(gateHasKorean))")
    check(ArisAside.cardTitle(english: false) == ArisAside.cardTitle && ArisAside.workingStatus(english: false) == ArisAside.workingStatus && ArisAside.codeWaitingStatus(english: false) == "Aside 로그인 코드를 받는 중"
          && ArisAside.loginStatus("X", english: false) == ArisAside.loginStatus("X") && ArisAside.loginCard(english: false) == ArisAside.loginCard
          && ArisAside.signedOutLine(english: false) == ArisAside.signedOutLine && ArisAside.missingLine(english: false) == ArisAside.missingLine
          && ArisAside.missingCard(english: false) == ArisAside.missingCard && ArisAside.untrustedLine(english: false) == ArisAside.untrustedLine
          && ArisAside.cliMissingOutput(english: false) == ArisAside.cliMissingOutput && ArisAside.missingOutput(opened: true, english: false) == ArisAside.missingOutput(opened: true)
          && ArisAside.loginOutput(approved: false, code: "X", timedOut: true, english: false) == ArisAside.loginOutput(approved: false, code: "X", timedOut: true)
          && ArisAside.runningStatus("가격 찾아줘") == ArisAside.workingStatus + ": 가격 찾아줘", "desk-11: Aside's Korean cards and lines are the ones it had")
    check(ArisAside.loginCard(english: true).allow == "Sign in" && ArisAside.missingCard(english: true).allow == "Install" && ArisAside.missingCard(english: true).detail.contains("aside.com/download")
          && ArisAside.loginStatus("WDJB-MJHT", english: true).contains("WDJB-MJHT") && ArisAside.missingOutput(opened: true, english: true).contains(ArisAside.missingLine(english: true))
          && ArisAside.runningStatus("find the cheapest earbuds", english: true) == "Aside is working in the browser: find the cheapest earbuds",
          "desk-11: Aside's English cards keep their button, the download page, the sign-in code and the brief")

    // The tool itself, for an English turn and a Korean one.
    let none = { (_: String, _: [String], _: [String: String], _: TimeInterval) in ArisSkillProcessResult(status: 0, stdout: "The cheapest is $12.", stderr: "", timedOut: false) }
    let missing = ArisAsideDeps(locate: { .missing }, run: none, open: { _ in true }, environment: [:], ownData: { _ in false })
    let englishTurn = GateAsideTurn(english: true, answers: [.no]), koreanTurn = GateAsideTurn(english: false, answers: [.no])
    let englishOut = ArisAsideTool.answer("order earbuds on the shop site", turn: englishTurn, critical: false, deps: missing)
    let koreanOut = ArisAsideTool.answer("쇼핑몰에서 이어폰 주문해줘", turn: koreanTurn, critical: false, deps: missing)
    check(englishTurn.cards.first?.title == "Install Aside" && englishTurn.cards.first?.allow == "Install" && !gateHasKorean(gateWhole(englishTurn.cards[0]) + englishOut.output)
          && koreanTurn.cards.first == ArisAside.missingCard && koreanOut.output == ArisAside.missingOutput(opened: false),
          "desk-11: with Aside missing, an English turn gets the English install card and line, a Korean one its own: \(englishOut.output.prefix(120))")
    let ready = ArisAsideDeps(locate: { .ready("/x/aside") }, run: none, open: { _ in true }, environment: [:], verify: { _ in true }, ownData: { _ in false })
    let orderEnglish = GateAsideTurn(english: true, answers: [.yes([:])]), orderKorean = GateAsideTurn(english: false, answers: [.no])
    _ = ArisAsideTool.answer("order earbuds on the shop site", turn: orderEnglish, critical: true, deps: ready)
    _ = ArisAsideTool.answer("쇼핑몰에서 이어폰 주문해줘", turn: orderKorean, critical: true, deps: ready)
    check(orderEnglish.cards.first?.title == "Hand this to Aside" && orderEnglish.cards.first?.detail == "order earbuds on the shop site"
          && orderEnglish.statuses == ["Aside is working in the browser: order earbuds on the shop site"] && orderKorean.cards.first?.title == ArisAside.cardTitle,
          "desk-11: the Aside task card and its status line follow the request's language: \(orderEnglish.cards.first?.title ?? "") \(orderEnglish.statuses)")
    let signedOut = ArisAsideDeps(locate: { .signedOut("/x/aside") }, run: none, open: { _ in true }, environment: [:], verify: { _ in true }, ownData: { _ in false })
    let signEnglish = GateAsideTurn(english: true, answers: [.no])
    let declined = ArisAsideTool.answer("check my orders on the shop site", turn: signEnglish, critical: false, deps: signedOut)
    check(signEnglish.cards.first?.title == "Sign in to Aside" && signEnglish.cards.first?.allow == "Sign in" && declined.output == ArisAside.signedOutLine(english: true),
          "desk-11: the Aside sign-in card and its line are English for an English turn")
    let tool = gateSource("ArisAgent/ArisAsideTool.swift"), routes = gateSource("ArisAgent/ArisAsideRoutes.swift")
    check(tool.components(separatedBy: "english: turn.asideEnglish").count == 12 && routes.components(separatedBy: "var asideEnglish: Bool").count == 4
          && routes.components(separatedBy: "ArisAside.runningStatus(brief, english: asideEnglish)").count == 3,
          "desk-11: every line the Aside tool says for the user goes through the one switch, on each kind of turn")
}
