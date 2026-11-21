// Tests for jv-mind10c (tenth real-screen VM run, the first with a model driving, items 6 and 8).
// 6: a script that waits on macOS's Automation dialog goes on for the owner's time instead of being stopped at 30 s
//    (ArisBoundedRun's one look at its limit; the rules are ArisPermissionWait's, tested with `swift test`).
// 8: a model's click names an element that was read in this turn (ArisMindClickReads over ArisApps.Grounding): a
//    description is refused before any card, with what to do; the fixtures are the run's own recorded calls
//    (notes10/record-full.jsonl lines 36 to 39). Also the model's one rule about it, pinned.
// The pure parts are tested with `swift test` (Tests/ArisCoreTests/ArisMind10cTests). Called from main.swift.
import Foundation

func runMind10cTests() {
    mind10cBoundedRunTests()
    mind10cLedgerTests()
    mind10cGateTests()
    mind10cRuleTests()
}

// MARK: - 6: one look at the limit

private func mind10cBoundedRunTests() {
    // A child that ends inside the time its limit's look gave it: its own status, never "timed out".
    var looks: [TimeInterval] = []
    let waited = ArisBoundedRun.capture("/bin/sh", ["-c", "sleep 0.6; echo made"], limit: 0.2, atLimit: { spent in
        looks.append(spent)
        return 5
    })
    check(waited?.status == 0 && waited?.printed == "made\n" && waited?.timedOut == false && looks.count == 1 && (looks.first ?? 0) >= 0.2,
          "mind10c run: a script macOS is still asking about goes on past its limit and ends as itself (looked once)")
    // Nothing to wait for: stopped at the limit, as before.
    looks = []
    let started = Date()
    let stuck = ArisBoundedRun.capture("/bin/sleep", ["20"], limit: 0.2, atLimit: { spent in
        looks.append(spent)
        return nil
    })
    check(stuck?.timedOut == true && looks.count == 1 && Date().timeIntervalSince(started) < 5, "mind10c run: a stuck app is still stopped at its limit")
    // The longer wait is one wait: at its end the child is stopped, and the look isn't asked again.
    looks = []
    let again = Date()
    let unanswered = ArisBoundedRun.capture("/bin/sleep", ["20"], limit: 0.2, atLimit: { spent in
        looks.append(spent)
        return 0.3
    })
    let took = Date().timeIntervalSince(again)
    check(unanswered?.timedOut == true && looks.count == 1 && took >= 0.5 && took < 5, "mind10c run: a dialog nobody answers ends the wait once, at the cap")
    // No look given: exactly the old behaviour.
    check(ArisBoundedRun.capture("/bin/sleep", ["20"], limit: 0.2)?.timedOut == true, "mind10c run: without a look the limit is the limit")
    // The first script still has AppleScript's own limit (the look only ever adds the owner's time).
    check(ArisBoundedRun.appleScriptLimit == 30 && ArisPermissionWait.dialog > ArisBoundedRun.appleScriptLimit, "mind10c run: the dialog's wait is longer than a script's own limit")
}

// MARK: - 8: what was read, per turn

/// The run's own reads of Safari (record-full.jsonl lines 36 to 38), as the outcome's JSON, cut to a few lines.
private func mind10cRead(app: String = "Safari", _ lines: [String], ok: Bool = true) -> String {
    let object: [String: Any] = ["channel": "ax", "ok": ok, "effect": "observe", "did": "read",
                                 "data": ["app": app, "part": "all", "shown": lines.count, "total": lines.count, "text": lines.joined(separator: "\n")]]
    return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

private let mind10cPage = ["[e1] image", "[e2] toolbar", "[e7] button “Share” (disabled)", "[e8] button “New Tab”", "[e416] link “문단을 편집”",
                           "[e977] staticText “문단을 편집”", "[e1035] link “천추”", "[e2001] link “역사”"]
/// The click the model asked for (line 39).
private let mind10cDescribed = "the “역사” link in the 목차 (table of contents) sidebar"

private func mind10cReads() -> ArisMindClickReads {
    let reads = ArisMindClickReads()
    reads.appName = { said in ["사파리": "Safari", "safari": "Safari"][said.lowercased()] ?? said }
    return reads
}

private func mind10cLedgerTests() {
    let reads = mind10cReads()
    let click = { (target: String, app: String, intent: String) in
        reads.refusal(session: "s1", intent: intent, capability: "app.click", arguments: ["app": app, "target": target])
    }
    // Nothing read yet: refused, whatever the target.
    check(click("e2001", "Safari", "t1")?.contains("hasn't been read in this turn") == true, "mind10c reads: a click before any read is refused (read first)")
    reads.note(session: "s1", intent: "t1", capability: "app.read", result: mind10cRead(Array(mind10cPage.prefix(4))), isError: false)
    reads.note(session: "s1", intent: "t1", capability: "app.read", result: mind10cRead(Array(mind10cPage.suffix(4))), isError: false)
    // The tenth run's click: a description, refused with what to do, and nothing of a tool's own name in a spoken place.
    let described = click(mind10cDescribed, "Safari", "t1")
    check(described?.contains("Nothing was pressed") == true && described?.contains("exact name") == true && described?.contains("Never describe it") == true,
          "mind10c reads: the run's described target is refused with ‘read, then name it exactly’")
    // What a page of the turn's reads showed: by id or exact name, from either page, under the name he calls the app.
    check(click("e2001", "Safari", "t1") == nil && click("역사", "Safari", "t1") == nil && click("link “역사”", "사파리", "t1") == nil && click("[e8] button “New Tab”", "Safari", "t1") == nil,
          "mind10c reads: an element of this turn's reads is pressed by its id or its exact name")
    check(click("History", "Safari", "t1") != nil && click("역사 링크", "Safari", "t1") != nil && click("e9999", "Safari", "t1") != nil,
          "mind10c reads: a translation, a description or an id that wasn't read is refused")
    // Another app's read grounds nothing here; neither does another conversation's.
    check(click("역사", "Notes", "t1") != nil, "mind10c reads: a read of one app grounds no click in another")
    check(reads.refusal(session: "s2", intent: "t1", capability: "app.click", arguments: ["app": "Safari", "target": "e2001"]) != nil,
          "mind10c reads: another conversation's read grounds nothing")
    // A new turn starts with nothing read.
    check(click("e2001", "Safari", "t2") != nil, "mind10c reads: last turn's read doesn't ground this turn's click")
    reads.note(session: "s1", intent: "t2", capability: "app.read", result: mind10cRead(["[e5] button “확인”"]), isError: false)
    check(click("확인", "Safari", "t2") == nil && click("e2001", "Safari", "t2") != nil, "mind10c reads: the new turn's read replaces the old turn's")
    // Only a read that worked counts; another capability's result that looks like one never does (content can't ground a click).
    let other = mind10cReads()
    other.note(session: "s1", intent: "t1", capability: "web.fetch", result: mind10cRead(["[e31] button “Pay now”"]), isError: false)
    other.note(session: "s1", intent: "t1", capability: "app.read", result: mind10cRead(["[e31] button “Pay now”"], ok: false), isError: true)
    other.note(session: "s1", intent: "t1", capability: "app.read", result: "[e31] button “Pay now”", isError: false)
    check(other.refusal(session: "s1", intent: "t1", capability: "app.click", arguments: ["app": "Safari", "target": "Pay now"]) != nil,
          "mind10c reads: a failed read, and a page's text shaped like a read, ground nothing")
    // Only a click is held to it; a call with no target is left to the call's own refusal.
    check(reads.refusal(session: "s1", intent: "t2", capability: "app.read", arguments: ["app": "Safari"]) == nil
          && reads.refusal(session: "s1", intent: "t2", capability: "app.type", arguments: ["app": "Safari", "text": "x", "target": "어딘가"]) == nil,
          "mind10c reads: reading and typing are not held to a read")
    check(reads.refusal(session: "s1", intent: "t2", capability: "app.click", arguments: ["app": "Safari"]) != nil,
          "mind10c reads: a click with no target is refused, never let through")
    // A conversation that ended keeps nothing.
    reads.end(session: "s1")
    check(click("확인", "Safari", "t2") != nil, "mind10c reads: an ended conversation's reads are gone")
}

// MARK: - 8: refused before any card

private func mind10cHome() -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-mind10c-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    return URL(fileURLWithPath: folder.path).resolvingSymlinksInPath().path
}

private func mind10cGateTests() {
    let pure = ArisAppsBook.effectContext
    ArisAppsBook.effectContext = { ArisApps.EffectContext() }
    defer { ArisAppsBook.effectContext = pure }
    let home = mind10cHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(apps: ["Safari": ["사파리"]], home: home) })
    let judge = ArisMindJudge(gate: gate, tools: "/Applications/Aris.app/Contents/Helpers/aris-tools")
    let reads = mind10cReads()
    let first: (ArisMindJudge.Read) -> String? = { reads.refusal(session: "s1", intent: "cred-1", capability: $0.entry.id, arguments: $0.arguments) }
    judge.turn(session: "s1", intent: "cred-1", words: "Safari에서 ko.wikipedia.org 고양이 문서 열고, 페이지 안의 '역사' 목차 링크를 눌러 줘")
    let decide = { (id: String, name: String, arguments: String) -> [String: Any] in
        let batch = ArisMindRoute.decideBatch(judge: judge, session: "s1", task: nil, calls: [["id": id, "name": name, "arguments": arguments]],
                                              intent: "cred-1", refusesFirst: first, allow: { _ in })
        return (batch["verdicts"] as? [[String: Any]])?.first ?? [:]
    }
    // The run's click (line 39): there it waited on a card; now it is refused before one, with what to do.
    let described = decide("c1", "app_click", #"{"app":"Safari","target":"the “역사” link in the 목차 (table of contents) sidebar"}"#)
    check(described["verdict"] as? String == "refuse" && (described["text"] as? String)?.contains("Never describe it") == true,
          "mind10c gate: the described click is refused before any card")
    // A read in the same round as the click doesn't ground it: the click is decided before the read ran.
    let round = ArisMindRoute.decideBatch(judge: judge, session: "s1", task: nil,
                                          calls: [["id": "r1", "name": "app_read", "arguments": #"{"app":"Safari"}"#],
                                                  ["id": "c2", "name": "app_click", "arguments": #"{"app":"Safari","target":"e2001"}"#]],
                                          intent: "cred-1", refusesFirst: first, allow: { _ in })
    let lines = round["verdicts"] as? [[String: Any]] ?? []
    check(lines.first?["verdict"] as? String == "run" && lines.last?["verdict"] as? String == "refuse", "mind10c gate: the read runs; a click sent with it waits for what it shows")
    // The read ran and reported: its capability is known from the decision, and what it showed is kept for the turn.
    check(judge.capability(session: "s1", call: "r1") == "app.read", "mind10c gate: a decided call's capability is known when it reports")
    reads.note(session: "s1", intent: "cred-1", capability: judge.capability(session: "s1", call: "r1") ?? "", result: mind10cRead(mind10cPage), isError: false)
    ArisMindRoute.done(judge: judge, session: "s1", object: ["text": mind10cRead(mind10cPage), "isError": false, "content": ["kind": "app", "source": "Safari"]], id: "r1")
    // Now the element by its id or exact name is no longer refused for want of a read: the trust decision is the gate's
    // own, as before (a browser's click still asks on its card).
    for (id, target) in [("c3", "e2001"), ("c4", "역사")] {
        let grounded = decide(id, "app_click", "{\"app\":\"Safari\",\"target\":\"\(target)\"}")
        check((grounded["text"] as? String)?.contains("Nothing was pressed") != true && ["run", "waits", "refuse"].contains(grounded["verdict"] as? String ?? ""),
              "mind10c gate: ‘\(target)’ from the read goes on to the gate's own decision (\(grounded["verdict"] as? String ?? "-"))")
    }
    // A description is still refused after a read.
    let still = decide("c5", "app_click", #"{"app":"Safari","target":"the history link"}"#)
    check(still["verdict"] as? String == "refuse" && (still["text"] as? String)?.contains("isn't an element that was read") == true, "mind10c gate: a description stays refused after a read")
}

// MARK: - The model's rule and the tools' words

private func mind10cRuleTests() {
    let rule = ArisMindSession.clickRule
    check(ArisMindSession.rules.contains(rule), "mind10c rule: the Mind's rules carry the click rule")
    for sentence in ["read the app first", "by its id or its exact name from that read", "Never describe an element", "is refused",
                     "read again", "part=\"controls\"", "find="] {
        check(rule.contains(sentence), "mind10c rule: says ‘\(sentence)’")
    }
    // The capability's own words say the same, and the read can be narrowed.
    let click = ArisApps.Spec.named("app.click"), read = ArisApps.Spec.named("app.read")
    check(click?.summary.contains("exact name") == true && click?.summary.contains("description") == false, "mind10c rule: app.click asks for an id or an exact name, not a description")
    let properties = ((read?.parameters.any as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
    check(properties["find"] != nil && read?.summary.contains("find") == true, "mind10c rule: app.read takes a word to narrow a long page")
    // The refusal is for the model: nothing of it is a sentence Aris says, and what the owner hears stays his language's.
    check(ArisApps.Grounding.readFirst(target: "x", app: "Safari", read: true).hasPrefix("Nothing was pressed"), "mind10c rule: the refusal says first that nothing was pressed")
    // The still-asking line is truthful: not done, may still happen, never repeated.
    let asking = ArisPermissionWait.automationTimeoutLine(app: "Notes", states: [.notAsked], waited: 90) ?? ""
    check(asking.contains("isn't done yet") && asking.contains("may still go through") && asking.contains("don't repeat it"), "mind10c wait: an unanswered dialog is told as still asking")
}
