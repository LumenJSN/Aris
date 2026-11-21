// Tests for jv-vmfix5 defect 3, the third VM run (aris-vmcheck notes3/I5c-replay-actions.txt, I5c-undo.log,
// cap3/I5c-undo-3s.jpg): right after a taught procedure's replay typed into TextEdit, "되돌려" offered to undo
// "할 일 추가: 우유 사기" from minutes before. The replay's app.type was recorded run-with-undo but had no undo, so its
// row was not undoable and the app's picker skipped every row that couldn't be undone. Here: the picker takes the newest
// change across both stores and says so when it can't be undone; a replay is one change; text app.type added has an
// undo that takes out only its own range; the record's /undo takes a run back newest first. Nothing here touches a real
// app. Called from main.swift; uses its check().
import Foundation

private let vmfix5UndoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func vmfix5UndoSource(_ path: String) -> String { (try? String(contentsOf: vmfix5UndoRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runVmfix5UndoTests() {
    vmfix5UndoPickerTests()
    vmfix5TextUndoTests()
    vmfix5UndoRunTests()
    vmfix5UndoWiringTests()
}

private let vmfix5Formatter = ISO8601DateFormatter()
private func vmfix5Date(_ text: String) -> Date { vmfix5Formatter.date(from: text)! }

/// The activity list as it stood at 07:51:10 (notes3/I2-rem-db.txt, I5c-replay-actions.txt), oldest first: the to-do
/// from the old log, then the replay's four record rows. `typeUndoable`: whether the replay's typing had an undo (the VM
/// run: it didn't).
private func vmfix5Changes(typeUndoable: Bool) -> [ArisUndoWords.Change] {
    let unit = "teach-a1b2c3d4"
    return [
        ArisUndoWords.Change(id: "log-1", date: vmfix5Date("2026-11-19T07:43:11Z"), summary: "할 일 추가: 우유 사기", action: "made", asks: false, undoable: true),
        ArisUndoWords.Change(id: "6bef880e-55d5-4dac-9258-a14ff76475bf", date: vmfix5Date("2026-11-19T07:50:43Z"), summary: "TextEdit 열기", action: nil, asks: false,
                             undoable: false, unit: unit),
        ArisUndoWords.Change(id: "0e107ae3-f569-4451-969e-120496bdbbb8", date: vmfix5Date("2026-11-19T07:50:43Z"), summary: "TextEdit에 입력", action: "changed",
                             asks: false, undoable: typeUndoable, unit: unit),
        ArisUndoWords.Change(id: "a81a9c7e-fa78-44d6-9070-78c0dba37560", date: vmfix5Date("2026-11-19T07:50:43Z"), summary: "TextEdit에서 Return", action: nil,
                             asks: false, undoable: false, unit: unit),
        ArisUndoWords.Change(id: "919b12b1-2450-468b-bc40-b00f4acefd4e", date: vmfix5Date("2026-11-19T07:50:43Z"), summary: "TextEdit에 입력", action: "changed",
                             asks: false, undoable: typeUndoable, unit: unit),
    ]
}

private func vmfix5UndoPickerTests() {
    let reach = vmfix5Date("2026-11-19T07:36:10Z")
    // The VM run's rows: the newest change (the replay) can't be undone, so that is said, and the to-do isn't offered.
    switch ArisUndoWords.reach(vmfix5Changes(typeUndoable: false), since: reach, kind: nil) {
    case .cannot(let summary):
        check(summary.contains("TextEdit"), "vmfix5 D3: the newest change can't be undone, and that is what is said")
        let line = ArisUndoWords.cannotLine(summary, korean: true)
        check(line.contains("되돌릴 수 없어요") && !line.contains("우유"), "vmfix5 D3: the line names the replay, never the older to-do")
    default:
        check(false, "vmfix5 D3: \"되돌려\" after a replay with no undo must not reach back to the to-do")
    }
    // With the typing's undo: the replay is one change, its undoable steps newest first.
    switch ArisUndoWords.reach(vmfix5Changes(typeUndoable: true), since: reach, kind: nil) {
    case .undo(let entry, _, let doubt):
        check(entry.unit == "teach-a1b2c3d4" && !doubt, "vmfix5 D3: \"되돌려\" takes the replay back as one change")
        check(!entry.summary.contains("우유"), "vmfix5 D3: the to-do stays")
    default:
        check(false, "vmfix5 D3: the replay with an undo is what \"되돌려\" offers")
    }
    // A kind named reaches the newest undoable change of that kind, as before ("만든 거" → the to-do).
    if case .undo(let entry, _, _) = ArisUndoWords.reach(vmfix5Changes(typeUndoable: false), since: reach, kind: "made") {
        check(entry.id == "log-1", "vmfix5 D3: a kind named still finds the newest change of that kind")
    } else {
        check(false, "vmfix5 D3: a kind named still finds the newest change of that kind")
    }
    // Nothing in reach, nothing said about older ones as if they were recent.
    check(ArisUndoWords.reach(vmfix5Changes(typeUndoable: true), since: vmfix5Date("2026-11-19T08:00:00Z"), kind: nil) == .nothing,
          "vmfix5 D3: nothing recent, nothing offered")
}

private func vmfix5TextUndoTests() {
    let before = "Existing line keep\n"
    guard let recipe = ArisApps.TextUndo.recipe(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "First Text View",
                                                before: before, inserted: "Milk and bread"),
          case .textInserted(let app, let element, let kept) = recipe, let mark = ArisApps.TextUndo.mark(element) else {
        return check(false, "vmfix5 D3: text app.type added has an undo recipe")
    }
    check(app == "TextEdit" && kept.isEmpty && !element.contains("Existing line keep"),
          "vmfix5 D3: the recipe keeps the added text and only the length and a hash of what was there")
    check(ArisApps.TextUndo.range(in: before + "Milk and bread", mark: mark) == NSRange(location: before.utf16.count, length: 14),
          "vmfix5 D3: the undo removes exactly the added range")
    check(ArisApps.TextUndo.range(in: before + "Milk and bread more", mark: mark) == nil
          && ArisApps.TextUndo.range(in: "Changed line keep\nMilk and bread", mark: mark) == nil,
          "vmfix5 D3: text changed since is left as it is")
    check(ArisUndoScope.effect(of: recipe) == .changeReversible, "vmfix5 D3: taking text back is a reversible change")
}

private func vmfix5UndoRunTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-vmfix5-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let home = folder.resolvingSymlinksInPath().path
    defer { try? FileManager.default.removeItem(atPath: home) }
    let session = "teach-a1b2c3d4", now = Date()
    func step(_ capability: String, _ seconds: Double, undo: ArisUndoRecipe?) -> ArisRecordEntry {
        ArisRecordEntry.call(at: now.addingTimeInterval(seconds), session: session, task: nil, capability: capability, effect: .changeReversible,
                             provenance: .ownStep, decision: .runWithUndo(announce: false), arguments: [.init(kind: .app, value: "TextEdit")],
                             result: "{}", ok: true, undo: undo)
    }
    let first = ArisApps.TextUndo.recipe(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "", before: "", inserted: "Milk")
    let second = ArisApps.TextUndo.recipe(app: "TextEdit", bundle: "com.apple.TextEdit", role: "textArea", label: "", before: "Milk", inserted: "\n")
    let entries = [step("app.open", -3, undo: nil), step("app.type", -2, undo: first), step("app.do", -1.5, undo: nil), step("app.type", -1, undo: second)]
    for entry in entries { _ = ArisRecordJournal.append(entry, home: home) }
    let rows = ArisRecord.activityRows(ArisRecordJournal.state(home: home))
    check(rows.count == 4 && rows.allSatisfy { $0["unit"] as? String == session }, "vmfix5 D3: every step of a replay is listed with its run")
    check(rows.filter { $0["undoable"] as? Bool == true }.count == 2, "vmfix5 D3: the replay's typing is undoable now")
    var removed: [String] = []
    var hands = ArisUndoHands()
    hands.setText = { _, element, _ in removed.append(ArisApps.TextUndo.mark(element)?.inserted ?? "?") }
    let answer = ArisRecordRoutes.undo(id: entries[3].id, unit: true, home: home, logLatest: nil, hands: hands)
    check(answer?.status == 200, "vmfix5 D3: the run is undone through the record")
    check(removed == ["\n", "Milk"], "vmfix5 D3: a run's steps are undone together, newest first")
    let after = ArisRecordJournal.state(home: home)
    check(after.isUndone(entries[1].id) && after.isUndone(entries[3].id), "vmfix5 D3: the record says both were undone")
}

private func vmfix5UndoWiringTests() {
    let executor = vmfix5UndoSource("ArisAgent/Mind/ArisMindExecutor.swift")
    check(executor.contains("content: tool.content.map { ArisContentSource(kind: $0.kind, source: $0.source) }, undo: tool.undo)"),
          "vmfix5 D3: a capability's undo reaches the record")
    let book = vmfix5UndoSource("ArisAgent/Apps/ArisAppsBook.swift")
    check(book.contains("undo: done.ok ? done.undo : nil)"), "vmfix5 D3: the app layer's undo goes with its result")
    let hands = vmfix5UndoSource("ArisAgent/Apps/ArisAppsHands+Read.swift")
    // Fourth VM run, D7: made from the field's value read back (an empty field reads as ""), only for an insertion.
    check(hands.contains("let before = element.value ?? \"\"") && hands.contains("undo = ArisApps.TextUndo.recipe(app: target.name, bundle: target.bundle, role: element.role, label: element.label, before: before, after: value)"),
          "vmfix5 D3: app.type has an undo only when everything the field held is still there, with the text added")
    let controller = vmfix5UndoSource("Aris/private/Aris/ArisController+Undo.swift")
    check(controller.contains("let changes = items.filter { !$0.undone }.map {") && !controller.contains("let undoable = items.filter { $0.undoable && !$0.undone }"),
          "vmfix5 D3: \"되돌려\" reads every change, not only the undoable ones")
    check(vmfix5UndoSource("ArisAgent/Mind/ArisMindLive.swift").contains("ArisAppsTextUndoLive.install()"),
          "vmfix5 D3: the helper can take text back")
    check(vmfix5UndoSource("ArisAgent/Trust/ArisCore2Trust.swift").contains("ArisRecordRoutes.undo(id: id, unit: unit, home: home, logLatest: logLatest)"),
          "vmfix5 D3: the app's unit undo reaches the record")
}
