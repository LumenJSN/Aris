// Tests for the fixes of security review 3 (M1, L1-L4, I1, I2, I5) and of the leftovers handed over with it. Each pins
// the reviewer's own case: the look reads the browser it chose and no other, a brain can't name a pid to `screen`, a
// click on a card that has just appeared is no yes, an undo that is no to-do's leaves no to-do grant. Called from
// main.swift; uses its check(). Nothing is captured, clicked, typed or sent: only the rules and the words run.
import Foundation

private let s3Tools = "/Users/p/.config/aris/aris-tools"
private let s3Home = "/Users/p"

private func s3Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// M1: the look names the browser it reads, and the tool reads exactly that one.
private func secFix3Tab() {
    typealias T = ArisTabTarget
    let known = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"]
    let both: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.lumenjsn.aris"]
    // The reviewer's case: the user is in Chrome, Safari also runs, Aris is in front.
    check(T.choose(named: "com.google.chrome", front: "com.lumenjsn.aris", running: both, browsers: known) == .browser("com.google.Chrome"),
          "sec3 M1: with Aris in front the tab read is the named browser's (Chrome), not the first running one (Safari)")
    check(T.choose(named: nil, front: "com.lumenjsn.aris", running: both, browsers: known) == .browser("com.apple.Safari")
          && T.choose(named: nil, front: "com.google.Chrome", running: both, browsers: known) == .browser("com.google.Chrome"),
          "sec3 M1: a bare `tab` is as it was: the browser in front, else the first one running")
    check(T.choose(named: "com.google.Chrome", front: "com.apple.Safari", running: ["com.apple.Safari"], browsers: known) == .refused(T.notRunning("com.google.Chrome"))
          && T.notRunning("com.google.Chrome").contains("isn't running"),
          "sec3 M1: a named browser that isn't running fails plainly, and no other browser is read in its place")
    check(T.choose(named: "com.apple.TextEdit", front: "com.apple.Safari", running: both.union(["com.apple.TextEdit"]), browsers: known) == .refused(T.notBrowser("com.apple.TextEdit"))
          && T.choose(named: "", front: "com.apple.Safari", running: both, browsers: known) == .refused(T.notBrowser("")),
          "sec3 M1: a named app that is no known browser fails plainly")
    check(T.choose(named: nil, front: "com.apple.finder", running: ["com.apple.finder"], browsers: known) == .refused("no browser is open"),
          "sec3 M1: with no browser running a bare `tab` says so, as before")
    check(ArisLookTarget.tabArguments(bundleId: "com.google.chrome") == ["tab", "--text", "--app", "com.google.chrome"],
          "sec3 M1: the look asks for the tab of the app it chose, by its bundle id")
    let look = s3Source("ArisAgent/ArisLook.swift"), screen = s3Source("ArisTools/ArisScreen.swift")
    check(look.contains("tool(tools, ArisLookTarget.tabArguments(bundleId: id), environment)") && !look.contains(#"["tab", "--text"]"#),
          "sec3 M1: ArisLook runs the tab read with its target, never the bare one")
    check(screen.contains(#"option("--app", in: &args)"#) && screen.contains("ArisTabTarget.choose(named: named, front: front, running: running, browsers: browsers)"),
          "sec3 M1: aris-tools tab takes --app and picks through the one rule")
    // The owner's ruling of 2026-11-11 took the incognito refusal out again ("시크릿창 봐도 되지 뭐"): a private window's tab is
    // read like any other. The rest of M1 above stays; glass-tests.swift pins that nothing asks a window's mode.
    check(!screen.contains("mode of front window") && !screen.contains("privateRefusal"),
          "sec3 M1 (ruled 11-11): aris-tools tab reads an incognito window's tab like a normal one")
}

/// L1: `screen --pid` is the helper's alone, a pid that isn't running fails, and --around reads no private window.
private func secFix3Screen() {
    typealias S = ArisScreenTarget
    let helper = [S.helperKey: "1"]
    let runs: (Int32) -> Bool = { $0 == 4321 }
    check(S.named(flagged: true, value: "4321", around: false, environment: [:], runs: runs) == .refused(S.pidRefusal)
          && S.named(flagged: true, value: "4321", around: false, environment: [S.helperKey: "0"], runs: runs) == .refused(S.pidRefusal)
          && S.named(flagged: true, value: "4321", around: true, environment: ["ARIS_LOCAL_LOG": "1"], runs: runs) == .refused(S.pidRefusal),
          "sec3 L1: aris-tools screen takes --pid only with aris-agent's own mark in its environment")
    check(S.named(flagged: true, value: "4321", around: false, environment: helper, runs: runs) == .pid(4321),
          "sec3 L1: the helper's own look still names the app it reads")
    check(S.named(flagged: true, value: "999", around: false, environment: helper, runs: runs) == .refused(S.notRunning("999"))
          && S.named(flagged: true, value: "abc", around: false, environment: helper, runs: runs) == .refused(S.notRunning("abc"))
          && S.named(flagged: true, value: "-4321", around: false, environment: helper, runs: { _ in true }) == .refused(S.notRunning("-4321"))
          && S.named(flagged: true, value: nil, around: false, environment: helper, runs: runs) == .refused(S.pidUsage),
          "sec3 L1: a --pid that names no running app fails; it no longer reads whatever is in front")
    check(S.named(flagged: true, value: "4321", around: true, environment: helper, runs: runs) == .front,
          "sec3 L1: --around ignores --pid: the private check stays on the app in front")
    check(S.named(flagged: false, value: nil, around: false, environment: [:], runs: runs) == .front
          && S.named(flagged: false, value: nil, around: true, environment: [:], runs: runs) == .front,
          "sec3 L1: a plain `screen` and `screen --around` read as before")
    let isPrivate: (String?) -> Bool = ArisCaptureRules.isPrivate
    let vault = S.Window(bundleId: "com.1password.1password", frame: CGRect(x: 100, y: 100, width: 400, height: 300))
    let finder = S.Window(bundleId: "com.apple.finder", frame: CGRect(x: 0, y: 0, width: 1_000, height: 800))
    check(S.coversPrivate(CGRect(x: 0, y: 0, width: 2_000, height: 2_000), windows: [finder, vault], isPrivate: isPrivate)
          && S.coversPrivate(CGRect(x: 450, y: 350, width: 640, height: 240), windows: [finder, vault], isPrivate: isPrivate),
          "sec3 L1: --around reads nothing while a password manager's window is anywhere in the rectangle, whichever app is in front")
    check(!S.coversPrivate(CGRect(x: 600, y: 500, width: 640, height: 240), windows: [finder, vault], isPrivate: isPrivate)
          && !S.coversPrivate(CGRect(x: 0, y: 0, width: 2_000, height: 2_000), windows: [finder, S.Window(bundleId: nil, frame: finder.frame)], isPrivate: isPrivate),
          "sec3 L1: a rectangle no private window touches is read as before")
    // The gates: the reviewer's three commands, and the flag wherever it stands.
    for words in ["screen --pid 4321", "screen --pid 4321 --image", "screen --pid 4321 --around 0,0,2000,2000", "screen --image --pid 4321", "screen --pid"] {
        let command = "\(s3Tools) \(words)"
        check(ArisRiskPolicy.risk(of: .shell(command), tools: s3Tools, home: s3Home) == .never
              && ArisRiskPolicy.risk(of: .shell(command), tools: s3Tools, home: s3Home, critical: true, request: "read my screen") == .never,
              "sec3 L1: Codex's and the API brain's gate never runs `\(words)`")
        check(ArisTurnGate.verdict(tool: "Bash", command: command, tools: s3Tools, tainted: false) == .deny(ArisTurnGate.screenPidRefusal)
              && ArisTurnGate.verdict(tool: "Bash", command: command, tools: s3Tools, tainted: true) != .allow
              && ArisTurnGate.verdict(tool: "Bash", command: command, tools: s3Tools, tainted: true) != .allowMarking,
              "sec3 L1: the open Claude's gate refuses `\(words)`, clean turn or not")
        check(!ArisSealedTools.allows(words.split(separator: " ").map(String.init)), "sec3 L1: the sealed Claude never runs `\(words)`")
    }
    check(ArisRiskPolicy.risk(of: .shell("ARIS_HELPER_LOOK=1 \(s3Tools) screen --pid 4321"), tools: s3Tools, home: s3Home) != .auto
          && ArisTurnGate.verdict(tool: "Bash", command: "ARIS_HELPER_LOOK=1 \(s3Tools) screen --pid 4321", tools: s3Tools, tainted: false) != .allow
          && ArisTurnGate.verdict(tool: "Bash", command: "ARIS_HELPER_LOOK=1 \(s3Tools) screen --pid 4321", tools: s3Tools, tainted: false) != .allowMarking,
          "sec3 L1: the helper's mark written in front of the command gets it past neither gate")
    check(ArisRiskPolicy.risk(of: .shell("\(s3Tools) screen"), tools: s3Tools, home: s3Home) == .auto
          && ArisRiskPolicy.risk(of: .shell("\(s3Tools) screen --image"), tools: s3Tools, home: s3Home) == .auto
          && ArisTurnGate.verdict(tool: "Bash", command: "\(s3Tools) screen", tools: s3Tools, tainted: false) != .deny(ArisTurnGate.screenPidRefusal),
          "sec3 L1: a plain `screen` is a read as before: reading never asks")
    check(ArisLookTarget.helperKey == S.helperKey && ArisLookTarget.screenEnvironment(pid: 200) == [S.helperKey: "1"] && ArisLookTarget.screenEnvironment(pid: nil).isEmpty,
          "sec3 L1: the helper marks only its own read by pid, with the key the tool looks for")
    let look = s3Source("ArisAgent/ArisLook.swift"), tool = s3Source("ArisTools/ArisScreen.swift")
    check(look.contains("environment.merging(ArisLookTarget.screenEnvironment(pid: pid)) { $1 }"),
          "sec3 L1: wiring: the look's `screen --pid` runs with the helper's mark")
    check(tool.contains("ArisScreenTarget.named(flagged: flagged, value: value, around: around, environment: ProcessInfo.processInfo.environment,")
          && tool.contains("ArisScreenTarget.coversPrivate(part, windows: onScreenWindows(), isPrivate: ArisCaptureRules.isPrivate)")
          && tool.range(of: "ArisScreenTarget.coversPrivate(part")!.lowerBound < tool.range(of: #"["-x", "-R", parts.map(String.init)"#)!.lowerBound,
          "sec3 L1: wiring: the tool asks the rule who it reads, and checks the rectangle before it captures")
}

/// L4: an undo mints the to-do grant only when it is a to-do's undo, and an unused one goes when the tool returns.
private func secFix3UndoGrant() {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-sec3-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("activity.jsonl")
    let now = Date(), stamp = ISO8601DateFormatter()
    func line(_ id: String, _ summary: String, undo: [String: Any]?, minutesAgo: Double, undone: Bool = false) -> String {
        var object: [String: Any] = ["id": id, "summary": summary, "date": stamp.string(from: now.addingTimeInterval(-minutesAgo * 60))]
        if let undo { object["undo"] = undo }
        if undone { object["undone"] = true }
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    let added = UUID().uuidString, ticked = UUID().uuidString, moved = UUID().uuidString, event = UUID().uuidString, volume = UUID().uuidString, plain = UUID().uuidString
    let lines = [line(added, "할 일 추가: 우유", undo: ["removeTodo": ["id": "x-coredata://A/1"]], minutesAgo: 50),
                 line(ticked, "할 일 완료: 우유", undo: ["reopenTodo": ["id": "x-coredata://A/1"]], minutesAgo: 40),
                 line(moved, "옮김: a.pdf → 문서", undo: ["moveBack": ["from": "/Users/p/Documents/a.pdf", "to": "/Users/p/Desktop/a.pdf"]], minutesAgo: 30),
                 line(event, "일정 추가: Lunch", undo: ["deleteEvent": ["id": "E1"]], minutesAgo: 20),
                 line(volume, "볼륨 40", undo: ["setVolume": ["level": 30]], minutesAgo: 10),
                 line(plain, "메시지 보냄: 엄마", undo: nil, minutesAgo: 5)]
    try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    typealias B = ArisActivityBridge
    check(B.undoWritesTodo(ofEntry: added, file: file, now: now) && B.undoWritesTodo(ofEntry: ticked.lowercased(), file: file, now: now),
          "sec3 L4: an undo that removes or reopens a to-do is one that needs the to-do grant")
    check(!B.undoWritesTodo(ofEntry: moved, file: file, now: now) && !B.undoWritesTodo(ofEntry: event, file: file, now: now)
          && !B.undoWritesTodo(ofEntry: volume, file: file, now: now) && !B.undoWritesTodo(ofEntry: plain, file: file, now: now)
          && !B.undoWritesTodo(ofEntry: UUID().uuidString, file: file, now: now),
          "sec3 L4: a file moved back, an event deleted, the volume, an entry with no undo and an unknown one need none")
    check(!B.undoWritesTodo(ofEntry: nil, file: file, now: now), "sec3 L4: a bare undo is judged by the latest change, as aris-tools picks it (a message: no grant)")
    let todoLast = folder.appendingPathComponent("todo-last.jsonl")
    try? Data((lines.prefix(2).joined(separator: "\n") + "\n").utf8).write(to: todoLast)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: todoLast.path)
    check(B.undoWritesTodo(ofEntry: nil, file: todoLast, now: now) && !B.undoWritesTodo(ofEntry: nil, file: folder.appendingPathComponent("none.jsonl"), now: now),
          "sec3 L4: a bare undo whose latest change is a to-do's gets the grant; a log that can't be read gets none")

    let grants = ArisActionGrants()
    let reopen = "todo|reopen|id=x-coredata://A/1", remove = "todo|remove|id=x-coredata://A/2"
    check(!grants.consume(reopen, now: now), "sec3 L4: with no undo running no to-do write by id gets through")
    let unused = grants.mintUndo(now: now)
    check(grants.undoGrants(now: now) == 1, "sec3 L4: a to-do's undo mints one grant")
    grants.dropUndo(unused)
    check(grants.undoGrants(now: now) == 0 && !grants.consume(reopen, now: now) && !grants.consume(remove, now: now),
          "sec3 L4: a grant the run didn't use is gone when aris-tools returns, not good for two more minutes")
    let used = grants.mintUndo(now: now)
    check(grants.consume(reopen, now: now) && !grants.consume(remove, now: now), "sec3 L4: the undo's own to-do write still goes through, once")
    grants.dropUndo(used)
    grants.dropUndo(nil)
    let first = grants.mintUndo(now: now), second = grants.mintUndo(now: now)
    grants.dropUndo(first)
    check(grants.undoGrants(now: now) == 1 && grants.consume(remove, now: now) && grants.undoGrants(now: now) == 0,
          "sec3 L4: dropping one undo's grant leaves another undo's alone")
    grants.dropUndo(second)
    let agent = s3Source("ArisAgent/main.swift")
    check(agent.contains("undoGrant = arguments != nil && ArisActivityBridge.undoWritesTodo(ofEntry: object[\"id\"] as? String) ? ArisActionGrants.shared.mintUndo() : nil")
          && agent.contains("ArisActionGrants.shared.dropUndo(undoGrant)") && agent.components(separatedBy: "mintUndo()").count == 2,
          "sec3 L4: wiring: /undo mints only for a to-do's undo that will run, and drops the grant when the tool returns")
}

/// I1, I2, I5: the undo card shows its line whole and what the yes goes back with; a counted line keeps a file's name.
private func secFix3UndoWords() {
    typealias W = ArisUndoWords
    let long = "예약 취소: " + String(repeating: "아침마다 오늘 일정과 할 일을 정리해서 알려 주기 ", count: 6) + "(매일 07:30)"
    let entry = W.Candidate(id: "E", summary: long, action: "removed", asks: true)
    check(long.count > 120 && W.card(for: entry, newest: entry, doubt: false, korean: true).detail == "되돌릴 일: " + long
          && W.card(for: entry, newest: entry, doubt: false, korean: false).detail.hasSuffix("(every day at 07:30)"),
          "sec3 I1: Aris's own undo card shows the line whole: a schedule's line ends with its time, not with “…”")
    if case .card(let card, let echo) = ArisUndoSteps.next(after: .needsConfirm(id: "E", summary: long, revivesSchedule: true), entry: entry, newest: nil, doubt: false, korean: true) {
        check(card.detail == long && echo == long, "sec3 I1: the helper's Korean card shows exactly the line its yes goes back with, whole")
    } else {
        check(false, "sec3 I1: the helper's Korean card shows exactly the line its yes goes back with, whole")
    }
    if case .card(let card, let echo) = ArisUndoSteps.next(after: .needsConfirm(id: "E", summary: long, revivesSchedule: true), entry: entry, newest: nil, doubt: false, korean: false) {
        let rows = card.detail.components(separatedBy: "\n")
        check(rows.count == 2 && rows[0] == "Schedule cancelled: " + long.dropFirst("예약 취소: ".count).dropLast("(매일 07:30)".count) + "(every day at 07:30)" && rows[1] == "Logged as: " + long && echo == long,
              "sec3 I1: the helper's English card shows its words whole and, under them, the logged line the yes is bound to")
    } else {
        check(false, "sec3 I1: the helper's English card shows its words whole and, under them, the logged line the yes is bound to")
    }
    check(W.helperDetail("a\u{202E}b\u{0007}c", korean: true) == "abc" && W.helperDetail("something else", korean: false) == "something else",
          "sec3 I1: invisible characters are still taken out, and a line that reads the same in English is shown once")
    check(W.shown(long, korean: true).count == 121 && W.shown(long, korean: true).hasSuffix("…") && W.staysLine(entry, korean: true).contains("…"),
          "sec3 I1: a reply's line and the line about the entry that stays are short as before")

    typealias A = ArisActivityWords
    check(A.english("변환: 보고서 3개 최종.pdf → 보고서 3개 최종.png") == "Converted: 보고서 3개 최종.pdf → 보고서 3개 최종.png"
          && A.english("합침: 보고서 3개 최종.pdf 외 2개 → 사과 5개.pdf") == "Merged: 보고서 3개 최종.pdf and 2 more → 사과 5개.pdf"
          && A.english("나눔: 보고서 3개 최종.pdf → 4개") == "Split: 보고서 3개 최종.pdf → 4"
          && A.english("압축: 사진 12개 모음.zip 외 1개 → 2개") == "Made smaller: 사진 12개 모음.zip and 1 more → 2",
          "sec3 I2: a file's name keeps its digits and its 개 on an English line (“보고서 3개 최종.pdf” read “보고서 3 최종.pdf”)")
    check(A.english("변환: 3개 → PNG") == "Converted: 3 → PNG" && A.english("합침: a.pdf 외 2개 → all.pdf") == "Merged: a.pdf and 2 more → all.pdf"
          && A.english("합침: 3개 → PDF") == "Merged: 3 → PDF" && A.english("나눔: PDF 1개 → 4개") == "Split: PDF 1 → 4" && A.english("압축: 2개 → 2개") == "Made smaller: 2 → 2"
          && A.english("변환: a.heic → a.png") == "Converted: a.heic → a.png" && A.english("변환: 2개 (중간에 멈춤)") == "Converted: 2 (stopped partway)"
          && A.english("창 배치: Safari 3개") == "Windows arranged: Safari 3" && A.english("타이머: 25분") == "Timer: 25 min" && A.english("기억 지움: 2개") == "Memories cleared: 2",
          "sec3 I2: the tool's own counts are still said in English, by where the tool writes them")
    check(s3Source("Aris/private/Aris/ArisController+Undo.swift").contains(#"log.error("undo failed: \(message, privacy: .private)")"#),
          "sec3 I5: a failed undo's reason (it can hold a title or a file name) is logged private")
}

/// L2: a click on a card's yes counts only once the card has been still on screen for ArisCardTiming.clickHold.
private func secFix3CardHold() {
    typealias H = ArisCardHold
    let hold = ArisCardTiming.clickHold
    let up = H().shown("a", at: 100)
    check(!up.clickCounts(card: "a", at: 100) && !up.clickCounts(card: "a", at: 100 + hold - 0.01) && up.clickCounts(card: "a", at: 100 + hold),
          "sec3 L2: a click on yes within the hold of the card being put up is ignored; after it, it counts")
    let frame = CGRect(x: 4, y: 60, width: 600, height: 180)
    let placed = up.framed(card: "a", frame, at: 100.2)
    check(!placed.clickCounts(card: "a", at: 100 + hold) && placed.clickCounts(card: "a", at: 100.2 + hold),
          "sec3 L2: the hold counts from when the card's view was laid out")
    check(placed.framed(card: "a", frame, at: 150) == placed && placed.framed(card: "a", frame.offsetBy(dx: 0.3, dy: -0.4), at: 150) == placed
          && placed.framed(card: "a", frame, at: 150).clickCounts(card: "a", at: 150),
          "sec3 L2: the same frame measured again (or one a rounding away) starts no new hold")
    for (what, moved) in [("grew", CGRect(x: 4, y: 60, width: 600, height: 320)), ("moved down", frame.offsetBy(dx: 0, dy: 40)),
                          ("moved aside", frame.offsetBy(dx: -30, dy: 0)), ("got narrower", CGRect(x: 4, y: 60, width: 520, height: 180))] {
        let after = placed.framed(card: "a", moved, at: 150)
        check(!after.clickCounts(card: "a", at: 150) && !after.clickCounts(card: "a", at: 150 + hold - 0.01) && after.clickCounts(card: "a", at: 150 + hold),
              "sec3 L2: a card that \(what) takes no click-yes for the hold again")
    }
    check(placed.framed(card: "gone", frame.offsetBy(dx: 0, dy: 90), at: 150) == placed,
          "sec3 L2: the frame of a card that is going away is not this card's")
    check(!placed.shown("a", at: 200).clickCounts(card: "a", at: 200.5) && placed.shown("a", at: 200).clickCounts(card: "a", at: 200 + hold),
          "sec3 L2: a second card put up with the same id starts its own hold (a double click can't answer both)")
    check(!placed.shown("b", at: 200).clickCounts(card: "a", at: 300) && !placed.shown("b", at: 200).clickCounts(card: "b", at: 200.5),
          "sec3 L2: the next card's hold is its own, and the card before it takes no click any more")
    check(H().following("b", at: 5) == H().shown("b", at: 5) && placed.following("a", at: 500) == placed && placed.following(nil, at: 500) == H(),
          "sec3 L2: a card put up by any path gets a hold, the same card keeps its own, and no card clears it")
    check(!H().clickCounts(card: "a", at: 1_000_000) && !placed.clickCounts(card: "other", at: 1_000_000),
          "sec3 L2: a card the hold was never told of takes no click-yes")
    typealias S = ArisCardAnswer.Source
    check(H.applies(allow: true, source: .click) && !H.applies(allow: false, source: .click)
          && [S.key, .typed, .voice, .band, .countdown].allSatisfy { !H.applies(allow: true, source: $0) && !H.applies(allow: false, source: $0) },
          "sec3 L2: only a yes by click waits: No and Cancel, the Y and N keys, typed and spoken answers need no hold")
    let controller = s3Source("Aris/private/Aris/ArisController.swift")
    let gate = controller.range(of: "if ArisCardHold.applies(allow: allow, source: source), !ArisCardStill.shared.clickCounts(card: question.id) {")
    let taken = controller.range(of: "        typedAnswer = allow\n        cardAnswerSource = source")
    check(gate != nil && taken != nil && gate!.upperBound < taken!.lowerBound
          && controller.contains("if session.question?.id != oldValue.question?.id { ArisCardStill.shared.follow(session.question?.id) }"),
          "sec3 L2: wiring: the answer is not taken before the hold is asked, and the hold follows the session's card")
    check(s3Source("Aris/private/Aris/ArisController+Tasks.swift").contains("session = session.asking(ask)\n        // Its click hold starts now, also when the card before it had the same id (ArisCardHold).\n        ArisCardStill.shared.shown(ask.id)")
          && s3Source("Aris/private/Aris/ArisController+Countdown.swift").contains("ArisCardStill.shared.shown(ask.id)"),
          "sec3 L2: wiring: both ways a card is put up (the question, the countdown) start its hold")
    let card = s3Source("Aris/private/Aris/Home/ArisConfirmCard.swift"), countdown = s3Source("Aris/private/Aris/Home/ArisConfirmCard+Countdown.swift")
    let live = s3Source("Aris/private/Aris/Home/ArisCardStill.swift")
    check(card.contains(".opacity(ready && !held ? 1 : Self.restOpacity)") && card.contains(".animation(Self.wakeEase, value: held)") && card.contains(".cardStill(question.id)")
          && countdown.contains(".opacity(held ? Self.restOpacity : 1)") && countdown.contains(".cardStill(question.id)"),
          "sec3 L2: wiring: the yes button (허용, and the countdown's 보내기) is drawn at rest until the hold is over, and the card reports its frame")
    // (The countdown's own ring is drawn against the clock in its file; the hold adds no clock and no repeat anywhere.)
    check([card, live].allSatisfy { !$0.contains("repeatForever") && !$0.contains("TimelineView") && !$0.contains("autoreverses") } && live.contains("self.ready = card")
          && !countdown.contains("repeatForever") && !countdown.contains("autoreverses"),
          "sec3 L2: the button comes to full strength once, when the hold ends: nothing in it blinks or pulses")
    // The choice: the notch still takes a first click everywhere (see ArisNotchHostingView's note); the yes is held where it is taken.
    check(s3Source("Aris/private/Notch/ArisNotchWindows.swift").contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }"),
          "sec3 L2: the notch's first-click acceptance is as it was for the tag and the composer; the card's yes is guarded by the hold instead")
}

private final class S3Panel {}

/// L3: the composer's tap takes the keyboard only after the user's own (hardware) press in that panel.
private func secFix3ComposerTap() {
    let notch = S3Panel(), side = S3Panel()
    let here = ObjectIdentifier(notch), there = ObjectIdentifier(side)
    check(!ArisPanelPress.tapTakesKeyboard(nil, in: here), "sec3 L3: a tap with no press seen before it takes no keyboard")
    check(ArisPanelPress.tapTakesKeyboard(ArisPanelPress(window: here, hardware: true), in: here), "sec3 L3: a tap after the user's own press on the notch takes the keyboard, as before")
    check(!ArisPanelPress.tapTakesKeyboard(ArisPanelPress(window: here, hardware: false), in: here), "sec3 L3: a tap whose press another process posted takes nothing")
    check(!ArisPanelPress.tapTakesKeyboard(ArisPanelPress(window: there, hardware: true), in: here), "sec3 L3: a hardware press in another panel doesn't vouch for a tap in this one")
    let keys = s3Source("Aris/private/Aris/ArisPanelKeys.swift"), composer = s3Source("Aris/private/Aris/Home/ArisComposer.swift")
    let seen = keys.range(of: "lastPressSeen = ArisPanelPress(window: ObjectIdentifier(window), hardware: users)"), refused = keys.range(of: "guard users else {")
    check(seen != nil && refused != nil && seen!.upperBound < refused!.lowerBound,
          "sec3 L3: wiring: the press monitor records every press in a panel, a posted one too, before it turns that one away")
    let asks = composer.range(of: "if tapped, !ArisPanelKeys.tapTakesKeyboard(in: panel) { return }"), takes = composer.range(of: "ArisPanelKeys.take(panel)")
    check(composer.contains(".onTapGesture { takeKeyboard(tapped: true) }") && asks != nil && takes != nil && asks!.upperBound < takes!.lowerBound,
          "sec3 L3: wiring: the composer's tap asks before it brings Aris forward; files dropped on it are no click and take it as before")
}

/// Leftovers: the outside-text card keeps its rows, the undo reply names the right thing, input devices are inputs.
private func secFix3Leftovers() {
    let field = ArisCardField(key: "text", label: "내용", role: .text, value: "곧 갈게")
    let target = ArisCardTarget(pid: 77, bundle: "com.apple.TextEdit", started: 12)
    let ask = ArisConfirmation(id: "c", title: "메시지 보내기", detail: "받는 사람: 엄마\n내용: 곧 갈게", full: "전체", fields: [field], allow: "설치", memoryWrite: true, desktop: target)
    let after = ArisEscalation.card(for: ask, approvable: true, hardLine: nil, tainted: true)
    check(after.fields == [field] && after.allow == "설치" && after.memoryWrite && after.desktop == target && after.id == "c" && after.title == ask.title,
          "leftover: the card made after outside text keeps its rows to edit, its yes word and what it is about")
    check(after.detail == ArisEscalation.taintedReason + "\n" + ask.detail && after.full == ArisEscalation.taintedReason + "\n전체" && !after.countdown
          && ArisEscalation.card(for: after, approvable: true, hardLine: nil, tainted: true) == after,
          "leftover: it still says why it asks, once, and is never a countdown")

    typealias W = ArisUndoWords
    check(W.doneLine("할 일 추가: 우유 사기", korean: true) == "‘우유 사기’ 할 일을 되돌렸어요." && W.doneLine("할 일 완료: 우유 사기", korean: true) == "‘우유 사기’ 할 일을 되돌렸어요.",
          "leftover: the Korean reply after undoing a to-do names the to-do (it read “‘우유 사기’ 할을 되돌렸어요”)")
    let korean = ["옮김: a.pdf → 문서": "‘a.pdf → 문서’ 옮긴 것을 되돌렸어요.", "이름 바꿈: a.pdf → b.pdf": "‘a.pdf → b.pdf’ 이름 바꾼 것을 되돌렸어요.",
                  "새 폴더: qa-1111": "‘qa-1111’ 새 폴더를 되돌렸어요.", "휴지통으로: a.pdf": "‘a.pdf’ 휴지통에 넣은 것을 되돌렸어요.",
                  "일정 추가: 회의": "‘회의’ 일정을 되돌렸어요.", "예약: 아침 정리 (매일 07:30)": "‘아침 정리’ 예약을 되돌렸어요.",
                  "예약 취소: 저녁 할 일 알림 (매일 20:00)": "‘저녁 할 일 알림’ 예약을 되돌렸어요.", "변환: a.heic → a.png": "‘a.heic → a.png’ 변환을 되돌렸어요.",
                  "합침: a.pdf 외 2개 → all.pdf": "‘a.pdf 외 2개 → all.pdf’ 합친 것을 되돌렸어요.", "나눔: a.pdf → 4개": "‘a.pdf → 4개’ 나눈 것을 되돌렸어요.",
                  "압축: a.mov → 1개": "‘a.mov → 1개’ 압축을 되돌렸어요.", "타이머: 5분": "‘5분’ 타이머를 되돌렸어요.", "창 배치: Safari 2개": "‘Safari 2개’ 창 배치를 되돌렸어요.",
                  "볼륨 40": "‘볼륨 40’ 되돌렸어요.", "볼륨 올림": "‘볼륨 올림’ 되돌렸어요."]
    for (line, said) in korean.sorted(by: { $0.key < $1.key }) {
        check(W.doneLine(line, korean: true) == said, "leftover: undo reply, Korean: \(line) → \(W.doneLine(line, korean: true))")
    }
    let english = ["할 일 추가: buy milk": "Undid “buy milk” (To-do added).", "할 일 완료: buy milk": "Undid “buy milk” (To-do done).", "옮김: a.pdf → Docs": "Undid “a.pdf → Docs” (Moved).",
                   "새 폴더: qa-1111": "Undid “qa-1111” (New folder).", "휴지통으로: a.pdf": "Undid “a.pdf” (To the Trash).", "일정 추가: Lunch": "Undid “Lunch” (Event added).",
                   "예약: standup (매일 09:00)": "Undid “standup” (Scheduled).", "예약 취소: standup (매일 09:00)": "Undid “standup” (Schedule cancelled).",
                   "변환: 3개 → PNG": "Undid “3 → PNG” (Converted).", "타이머: 5분": "Undid “5 min” (Timer).", "볼륨 40": "Undid “Volume 40”.", "볼륨 올림": "Undid “Volume up”."]
    for (line, said) in english.sorted(by: { $0.key < $1.key }) {
        check(W.doneLine(line, korean: false) == said, "leftover: undo reply, English: \(line) → \(W.doneLine(line, korean: false))")
    }
    check(ArisActivityWords.kinds.count >= 26 && ArisActivityWords.kinds.allSatisfy { W.doneNouns[$0] != nil }
          && ArisActivityWords.kinds.allSatisfy { kind in
              let said = W.doneLine("\(kind): 것", korean: true)
              return said.hasPrefix("‘것’ ") && said.hasSuffix(" 되돌렸어요.") && !said.contains("할을") && !said.contains("으로를")
          },
          "leftover: every kind in the activity table has its own noun in the Korean undo reply")
    check(W.doneLine("할 일 추가: 보고서 (최종)", korean: true) == "‘보고서 (최종)’ 할 일을 되돌렸어요." && W.doneLine("새 폴더: qa (2)", korean: false) == "Undid “qa (2)” (New folder).",
          "leftover: only a schedule's time in brackets is left out of the reply; a title's own brackets stay")

    typealias M = ArisMicChoice
    let devices = [M.Device(id: 41, transport: .builtIn, hasInput: true), M.Device(id: 42, transport: .builtIn, hasInput: false),
                   M.Device(id: 43, transport: .bluetooth, hasInput: true), M.Device(id: 44, transport: .other, hasInput: false)]
    check(M.inputIds(devices) == [41, 43] && M.inputIds([devices[1], devices[3]]).isEmpty && !M.anyInput([devices[1], devices[3]]),
          "leftover: the input devices are the ones that can record: a Mac with only speakers and a display has none")
    check(ArisMicRestart.decide(restarts: 0, opened: 42, current: 42, present: M.inputIds(devices)) == .endTurn
          && ArisMicRestart.decide(restarts: 0, opened: 41, current: 41, present: M.inputIds(devices)) == .reinstall,
          "leftover: a turn whose device no longer records ends; one whose microphone is still there carries on")
    check(s3Source("Aris/private/Aris/ArisMicChoice.swift").contains("static func inputDeviceIds() -> Set<AudioDeviceID> { inputIds(devices()) }"),
          "leftover: wiring: the live list is filtered the same way")
}

/// Leftovers of the reader and the AI services dropdown: a short answer's panel fits it, a scrolling edge says so.
private func secFix3ReaderAndMenu() {
    typealias B = ArisBoardContent
    check(B.readerHeight(needed: 459, base: 428, tallest: 640) == 459 && B.readerHeight(needed: 458.2, base: 428, tallest: 640) == 459,
          "leftover: an answer a little taller than the reader gets a panel as tall as itself: its last line is not half under the lower edge")
    check(B.readerHeight(needed: 200, base: 428, tallest: 640) == 428 && B.readerHeight(needed: 428, base: 428, tallest: 640) == 428,
          "leftover: an answer that fits leaves the reader at its own height")
    check(B.readerHeight(needed: 641, base: 428, tallest: 640) == 428 && B.readerHeight(needed: 3_000, base: 428, tallest: 640) == 428 && B.readerHeight(needed: nil, base: 428, tallest: 640) == 428,
          "leftover: a long document, or one too long to measure, is read in the reader at its own height, scrolling")
    check(B.readerHeight(needed: 459, base: 400, tallest: 400) == 400, "leftover: on a small screen the reader never grows past the room it has")
    let board = s3Source("Aris/private/Aris/ArisBoard.swift")
    check(board.contains("ArisBoardContent.readerHeight(needed: ArisReaderView.neededHeight(document, width: width),")
          && board.contains("base: min(ArisReaderView.size.height, room), tallest: min(ArisReaderView.tallest, room)"),
          "leftover: wiring: the board sizes the reader by what its document needs")

    typealias E = ArisAIMenuEdges
    let top = E.more(listHeight: 420, visible: 236, offset: 0), middle = E.more(listHeight: 420, visible: 236, offset: -90), end = E.more(listHeight: 420, visible: 236, offset: -184)
    check(!top.above && top.below, "leftover: the Thinking list opened at its top says more rows are below (its API entries were out of sight with no sign)")
    check(middle.above && middle.below && end.above && !end.below, "leftover: scrolled, it says so above too; at its end only above")
    let fits = E.more(listHeight: 200, visible: 200, offset: 0), nearly = E.more(listHeight: 200.5, visible: 200, offset: 0)
    check(!fits.above && !fits.below && !nearly.above && !nearly.below, "leftover: a list that fits has no hint at either edge")
    let menu = s3Source("Aris/components/Settings/ArisAIServicesMenu.swift")
    check(menu.contains(#"edgeHint("chevron.compact.down", shown: edges.below, at: .bottom)"#) && menu.contains(#"edgeHint("chevron.compact.up", shown: edges.above, at: .top)"#)
          && menu.contains(".allowsHitTesting(false)") && !menu.contains("repeatForever"),
          "leftover: wiring: each edge that hides rows carries a still chevron that takes no click")
}

/// Leftover: Settings opened by a fix button while Aris already had the keyboard gets the menu bar.
private func secFix3SettingsFront() {
    typealias F = ArisSettingsFront
    check(F(wasRegular: false, wasActive: true).reactivates,
          "leftover: Aris turned into a regular app while it was already the active one: it steps back and comes forward again, so macOS draws its menus")
    check(!F(wasRegular: false, wasActive: false).reactivates && !F(wasRegular: true, wasActive: true).reactivates && !F(wasRegular: true, wasActive: false).reactivates,
          "leftover: in every other case Settings comes forward as before and nothing is taken from any app")
    check(F.comesBack(windowVisible: true, frontmost: F.between, own: "com.lumenjsn.aris") && F.comesBack(windowVisible: true, frontmost: "com.lumenjsn.aris", own: "com.lumenjsn.aris"),
          "leftover: Aris comes forward again from the in-between program (or when it is still in front itself)")
    check(!F.comesBack(windowVisible: true, frontmost: "com.apple.Safari", own: "com.lumenjsn.aris") && !F.comesBack(windowVisible: false, frontmost: F.between, own: "com.lumenjsn.aris")
          && !F.comesBack(windowVisible: true, frontmost: nil, own: nil),
          "leftover: if the user went to another app meanwhile, or the window was closed, nothing is taken back")
    let window = s3Source("Aris/components/Settings/ArisSettingsWindow.swift")
    let read = window.range(of: "let front = ArisSettingsFront(wasRegular: NSApp.activationPolicy() == .regular, wasActive: NSApp.isActive)")
    let policy = window.range(of: "NSApp.setActivationPolicy(.regular)\n        let wasVisible")
    check(read != nil && policy != nil && read!.upperBound < policy!.lowerBound && window.contains("if front.reactivates { takeMenuBar(for: window) }")
          && window.contains("guard window.isVisible, NSApp.isActive,"),
          "leftover: wiring: what Aris was is read before it changes, and the step back happens only in that one case and only while Aris is still in front")
}

// MARK: - The fourth VM run (vm4 bugs 1-6 and the smaller ones)

private func s3Day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func secFix3VM4() {
    // Bug 1: nothing holds the notch and the pointer is off it: it closes, whoever opened it.
    typealias N = ArisNotch
    check(N.ending(openedNotch: false, isOpen: true).whenFree(pointerAway: true) == .close,
          "vm4 bug 1: after a card's yes shrank the notch away from the pointer, the turn's end closes it (it stayed up for minutes)")
    check(N.ending(openedNotch: false, isOpen: true).whenFree(pointerAway: false) == .restoreTab && N.ending(openedNotch: true, isOpen: true).whenFree(pointerAway: false) == .close
          && N.ending(openedNotch: false, isOpen: false).whenFree(pointerAway: true) == .stay,
          "vm4 bug 1: a notch the pointer is on stays as before, one Aris opened closes as before, a closed one is left alone")
    check(N.pointerAway(free: true, measured: true, onNotch: false) && !N.pointerAway(free: true, measured: true, onNotch: true)
          && !N.pointerAway(free: false, measured: true, onNotch: false) && N.pointerAway(free: true, measured: false, onNotch: true),
          "vm4 bug 1: the pointer counts as away only when nothing holds the notch and it is not found on it; unmeasured, the hover's own word stands")
    let behaviour = s3Source("Aris/private/Notch/ArisNotchRoot+Behaviour.swift")
    let reading = behaviour.range(of: "ArisNotch.readingTime(for: controller.session.reply)"), free = behaviour.range(of: "ArisNotch.pointerAway(free: mayCloseAutomatically,")
    check(reading != nil && free != nil && reading!.upperBound < free!.lowerBound && behaviour.contains("switch ArisNotch.ending(openedNotch: opened, isOpen: isOpen).whenFree(pointerAway: away) {"),
          "vm4 bug 1: wiring: decided at the turn's end, after the answer's reading time and the card's wait")

    // Bug 2: no "still going" line while a card waits, and none taken for a step that was declined.
    check(!ArisAgentStatus.beatsLongJob(cardWaiting: true) && ArisAgentStatus.beatsLongJob(cardWaiting: false),
          "vm4 bug 2: the helper says nothing is still going while the job's card waits for its answer")
    let waiting = ArisSession(phase: .thinking, heard: "convert it", reply: "").working("영상·소리 변환하는 중")
    let asked = waiting.asking(ArisConfirmation(id: "c", title: "변환", detail: "noise.wav → m4a"))
    let declined = asked.answered(delivered: true, allowed: false)
    check(waiting.runningTools == ["영상·소리"] && declined.steps.isEmpty, "vm4 bug 2: a no drops the step that waited on the card")
    check(ArisSession.ignoresStatus(ArisAgentStatus.longJob(minutes: 1), declined: waiting.runningTools) && !ArisSession.ignoresStatus("웹 검색 중", declined: waiting.runningTools)
          && !ArisSession.ignoresStatus(ArisAgentStatus.longJob(minutes: 1), declined: []),
          "vm4 bug 2: a late “still converting (1 min)” for the declined step is left out; another tool's line, and any line once nothing was declined, is taken")
    let late = ArisSession.ignoresStatus(ArisAgentStatus.longJob(minutes: 1), declined: waiting.runningTools) ? declined : declined.working(ArisAgentStatus.longJob(minutes: 1))
    check(late.answering("안 할게요.").steps.isEmpty, "vm4 bug 2: so “OK, I won't convert it.” comes with no ticked “Converting…” chip")
    let controller = s3Source("Aris/private/Aris/ArisController.swift"), runner = s3Source("ArisAgent/ArisAgentRunner.swift")
    check(controller.contains("guard !ArisSession.ignoresStatus(ArisUIWords.status(status), declined: declinedTools) else { break }")
          && controller.contains("declinedTools = allow ? [] : declinedTools.union(waiting)")
          && runner.contains("if ArisAgentStatus.beatsLongJob(cardWaiting: cardWaiting) {"),
          "vm4 bug 2: wiring: the app leaves such a line out until a later yes, and the helper's beat asks whether a card waits")

    // Bug 3: the schedule-removal card names the schedule.
    let id = UUID()
    let job = ArisScheduledJob(id: id, title: "Orlando weather", prompt: "Say: weather", teammate: nil, rule: .daily(hour: 9, minute: 0), created: Date(), nextRun: nil, lastRun: nil, runningSince: nil, parked: [])
    let english = ArisScheduleCard.removal([id.uuidString], jobs: [job], english: true), korean = ArisScheduleCard.removal([id.uuidString], jobs: [job], english: false)
    check(english.0 == "Remove a schedule" && english.1 == "Title: Orlando weather\nWhen: every day at 09:00\nIt won't run any more." && !english.1.contains(id.uuidString),
          "vm4 bug 3: the card for removing a schedule names it and says when it runs, never its bare id (\(flat3(english.1)))")
    check(korean.0 == "예약 지우기" && korean.1 == "제목: Orlando weather\n언제: 매일 09:00\n더는 실행되지 않아요.", "vm4 bug 3: and in Korean (\(flat3(korean.1)))")
    check(ArisScheduleCard.removal([UUID().uuidString], jobs: [job], english: true).1.hasPrefix("No schedule has this id")
          && ArisScheduleCard.removal(["not-an-id"], jobs: [job], english: false).1.hasPrefix("이 id로 된 예약이 없어서")
          && ArisScheduleCard.removal([], jobs: [job], english: true).0 == "Remove a schedule",
          "vm4 bug 3: an id that names no schedule says so on the card")
    check(s3Source("ArisAgent/ArisCodexDriver.swift").contains("return ArisScheduleCard.removal(Array(words.dropFirst(3)), jobs: ArisScheduleStore.load(file: schedules), english: ArisScheduleCard.isEnglish(request))"),
          "vm4 bug 3: wiring: every brain's card for `schedule remove` is that card, read from the helper's own list")

    // Bug 4: the API brain's stop lines in English, and a made-up tool name is a tool error.
    check([ArisAPIDriver.offListStop, ArisAPIDriver.roundsStop, ArisAPIDriver.sealedStop].allSatisfy { line in
        let said = ArisGateWords.line(line)
        return said != line && !said.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    } && ArisGateWords.line(ArisAPIDriver.offListStop) == "The API model used a tool it isn't allowed, so I stopped.",
          "vm4 bug 4: the API brain's stop lines have their English (an English request read “API 브레인이 허용되지 않은 도구를 써서 멈췄어요.”)")
    check(runner.contains("finish(nil, said(message))"), "vm4 bug 4: wiring: a stop is said in the request's language")
    typealias U = ArisAPIUnknownTool
    let known: Set<String> = ["timer", "todo_add", "screen_read"], offered: Set<String> = ["timer", "todo_add"]
    check(U.answered(name: "find_file", known: known, offered: offered, sealed: false, soFar: 0) && U.answered(name: "find_file", known: known, offered: offered, sealed: false, soFar: 1)
          && !U.answered(name: "find_file", known: known, offered: offered, sealed: false, soFar: 2),
          "vm4 bug 4: a function Aris doesn't have is answered as a tool error twice a turn; the third stops the turn")
    check(!U.answered(name: "screen_read", known: known, offered: offered, sealed: false, soFar: 0) && !U.answered(name: "find_file", known: known, offered: offered, sealed: true, soFar: 0)
          && !U.answered(name: "timer", known: known, offered: offered, sealed: false, soFar: 0),
          "vm4 bug 4: a real tool this turn was not offered, and any off-list call of a sealed or hands-free turn, still stop the turn")
    check(U.reason(name: "find_file", offered: offered).hasPrefix("no such tool: find_file. Nothing ran.") && U.reason(name: "find_file", offered: offered).hasSuffix("The tools are: timer, todo_add.")
          && U.shown("x\n\"; rm -rf ~ #" + String(repeating: "a", count: 200)).count == 60 && !U.shown("a b\n\"c").contains(" ") && U.shown("") == "(unnamed)",
          "vm4 bug 4: the error names the tools there are, and the made-up name goes back as plain characters only")

    // Bug 5: an undo whose target is gone is not offered again, and "undo that" reaches back only so far.
    check(ArisActivity.targetGone("couldn't undo \"x\": a.m4a isn't there, or the folder it belongs in is gone") && ArisActivity.targetGone("those files are already gone")
          && ArisActivity.targetGone("that schedule is already gone (it ran, or was removed)") && ArisActivity.targetGone("that file isn't in the Trash")
          && !ArisActivity.targetGone("a.m4a already exists there, so nothing was overwritten") && !ArisActivity.targetGone("Calendar didn't answer in time")
          && !ArisActivity.targetGone("Operation not permitted"),
          "vm4 bug 5: an undo fails for good only when what it would put back is gone; a name in the way, a slow app or a missing permission may work later")
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-sec3-undo-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: folder) }
    let log = folder.appendingPathComponent("activity.jsonl"), home = folder.appendingPathComponent("home").path
    let made = home + "/Desktop/noise-long.m4a"
    let entry = ArisActivityEntry(id: UUID(), date: Date(), job: "대화", worker: "api", summary: "변환: noise-long.wav → noise-long.m4a", undo: .trashMade(paths: [made]),
                                  undone: false, teammate: nil)
    ArisActivity.append(entry, file: log)
    let first = Result { try ArisActivity.undo(id: entry.id, confirmed: false, file: log, home: home) }
    let after = ArisActivity.load(file: log, since: Date(timeIntervalSince1970: 0)).first { $0.id == entry.id }
    if case .failure(let error) = first {
        check(ArisActivity.targetGone(error.localizedDescription) && after != nil && after?.undo == nil && after?.undone == false && after?.summary == "변환: noise-long.wav → noise-long.m4a",
              "vm4 bug 5: an undo that found its files gone leaves the entry in the record with no undo: “undo that” doesn't come back to it")
    } else {
        check(false, "vm4 bug 5: an undo that found its files gone leaves the entry in the record with no undo")
    }
    typealias W = ArisUndoWords
    let now = s3Day(2026, 11, 11, 20, 0)
    check(W.reach(now: now, conversationBegan: nil) == now.addingTimeInterval(-15 * 60)
          && W.reach(now: now, conversationBegan: now.addingTimeInterval(-2 * 60)) == now.addingTimeInterval(-15 * 60)
          && W.reach(now: now, conversationBegan: now.addingTimeInterval(-50 * 60)) == now.addingTimeInterval(-55 * 60),
          "vm4 bug 5: “undo that” reaches this conversation's changes or the last 15 minutes', whichever is further back")
    check(now.addingTimeInterval(-2 * 3600) < W.reach(now: now, conversationBegan: now.addingTimeInterval(-60)), "vm4 bug 5: a two-hour-old change from another conversation is out of its reach")
    check(W.nothingRecent(korean: false) == "There's nothing recent to undo. Older changes can be undone from the Activity tab." && W.nothingRecent(korean: true).contains("한 일 탭"),
          "vm4 bug 5: with only older changes it says there is nothing recent and points at the Activity tab")
    let undo = s3Source("Aris/private/Aris/ArisController+Undo.swift")
    check(undo.contains("let candidates = undoable.filter { $0.date >= reach }") && undo.contains("guard !candidates.isEmpty || undoable.isEmpty else { return await undoSay(ArisUndoWords.nothingRecent(korean: korean)) }")
          && controller.contains("if conversationBeganAt == nil { conversationBeganAt = Date() }") && controller.contains("conversationBeganAt = nil"),
          "vm4 bug 5: wiring: the typed undo picks within that reach, and the conversation's start is kept and let go with it")

    // Bug 6: a due date the AI gives is read, or the add fails with a line that says so.
    var seoul = Calendar(identifier: .gregorian)
    seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let wednesday = s3Day(2026, 11, 11, 14, 0)
    func due(_ words: String) -> Date? { ArisTodoDate.due(words, now: wednesday, calendar: seoul) }
    func end(_ month: Int, _ day: Int, year: Int = 2026) -> Date { s3Day(year, month, day, 23, 59) }
    let days: [(String, Date)] = [("next week", end(11, 16)), ("in 3 days", end(11, 14)), ("in a week", end(11, 18)), ("in 2 weeks", end(11, 25)), ("this weekend", end(11, 14)),
                                  ("next weekend", end(11, 21)), ("next month", end(12, 1)), ("end of the month", end(11, 30)), ("by the end of this month", end(11, 30)),
                                  ("Nov 20", end(11, 20)), ("November 20th", end(11, 20)), ("20 Nov", end(11, 20)), ("the 20th of November", end(11, 20)), ("11/20", end(11, 20)),
                                  ("2026-11-20", end(11, 20)), ("Jan 5", end(1, 5, year: 2027)), ("11월 20일", end(11, 20)), ("다음 주", end(11, 16)), ("다음주", end(11, 16)),
                                  ("모레", end(11, 13)), ("이번 주말", end(11, 14)), ("다음 주말", end(11, 21)), ("다음 달", end(12, 1)), ("월말", end(11, 30)), ("3일 후", end(11, 14)),
                                  ("2주 뒤", end(11, 25)), ("tomorrow", end(11, 12)), ("friday", end(11, 13)), ("Fri", end(11, 13)), ("wed", end(11, 11)), ("next monday", end(11, 16)), ("다음 주 금요일", end(11, 20))]
    for (words, expected) in days {
        check(due(words) == expected, "vm4 bug 6: --due “\(words)” is read (\(due(words).map { "\(seoul.dateComponents([.month, .day, .hour, .minute], from: $0))" } ?? "not read"))")
    }
    check(due("Nov 20 at 3pm") == s3Day(2026, 11, 20, 15, 0) && due("11/20 9:30 am") == s3Day(2026, 11, 20, 9, 30) && due("next week at 10 am") == s3Day(2026, 11, 16, 10, 0),
          "vm4 bug 6: a date with a time after it keeps the time")
    check(due("whenever") == nil && due("soonish") == nil && due("") == nil && due("13/45") == nil && ArisTodoDate.unreadDue("whenever").contains("couldn't read the due date \"whenever\"")
          && ArisTodoDate.unreadDue("x").contains("nothing was changed"),
          "vm4 bug 6: words that are no date are not read, and the line for them says nothing was changed and how to write one")
    let text = ArisTodoDate.parse("call the dentist next week", now: wednesday, calendar: seoul), topic = ArisTodoDate.parse("다음 주제 정하기", now: wednesday, calendar: seoul)
    check(text.text == "call the dentist" && text.due == end(11, 16) && topic.due == nil && topic.text == "다음 주제 정하기"
          && ArisTodoDate.parse("go to the market 5 times", now: wednesday, calendar: seoul).due == nil && ArisTodoDate.parse("score 11/20 on the quiz", now: wednesday, calendar: seoul).due == nil,
          "vm4 bug 6: in a to-do's own words “next week” is its due day; “다음 주제”, “market 5” and “11/20” inside a title are left as words")
    let route = s3Source("Aris/private/Aris/ArisTodoRouteHandler.swift")
    check(route.components(separatedBy: "guard let parsed = ArisTodoDate.due(due, now: .now) else { return ArisTodoRoute.response(ok: false, message: ArisTodoDate.unreadDue(due)) }").count == 3
          && !route.contains("ArisTodoDate.parse(due"),
          "vm4 bug 6: wiring: an add or an edit whose --due can't be read fails with that line instead of going through without a date")

    // Smaller: Korean left in English lines.
    typealias A = ArisActivityWords
    check(A.english("예약: Orlando weather (매일 09:00)") == "Scheduled: Orlando weather (every day at 09:00)" && A.english("예약 취소: standup (매주 금 18:00)") == "Schedule cancelled: standup (every Friday at 18:00)"
          && A.english("예약: ping (30분마다)") == "Scheduled: ping (every 30 minutes)" && A.english("예약: ping (1시간마다)") == "Scheduled: ping (every hour)"
          && A.english("예약: once (11월 3일 14:05에 한 번)") == "Scheduled: once (once, 11/3 at 14:05)",
          "vm4 smaller: an English schedule line says its time in English (the undo card and Activity rows read “(매일 09:00)”)")
    check(A.english("예약: 회의 (준비)") == "Scheduled: 회의 (준비)" && A.english("예약: 매일 09:00 보고") == "Scheduled: 매일 09:00 보고" && A.english("할 일 추가: x (매일 09:00)") == "To-do added: x (매일 09:00)",
          "vm4 smaller: only a schedule's own time in the brackets that end its line is changed; a title's words and brackets stay")
    check(ArisActivityTab.jobTip("대화", english: true) == "Conversation" && ArisActivityTab.jobTip("대화", english: false) == "대화" && ArisActivityTab.jobTip("블랙홀 자료 정리", english: true) == "블랙홀 자료 정리"
          && s3Source("Aris/private/Aris/Side/ArisActivityView.swift").contains(".help(ArisActivityTab.jobTip(item.job))"),
          "vm4 smaller: an Activity row's tooltip says “Conversation” on an English Mac; a job's own title stays")
    check(controller.contains(#"log.notice("sent to aris-agent for \(brain.rawValue, privacy: .public) (\(tier.rawValue, privacy: .public))")"#) && !controller.contains(#"log.notice("asking \("#),
          "vm4 smaller: the log says the request was sent to the helper, not that an AI is being asked, before the helper has decided")
}

private func flat3(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: " / ") }

func runSecFix3Tests() {
    secFix3Tab()
    secFix3Screen()
    secFix3UndoGrant()
    secFix3UndoWords()
    secFix3CardHold()
    secFix3ComposerTap()
    secFix3Leftovers()
    secFix3ReaderAndMenu()
    secFix3SettingsFront()
    secFix3VM4()
}
