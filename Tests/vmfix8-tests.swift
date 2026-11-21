// Tests for jv-vmfix8, the sixth VM run (aris-vmcheck notes5/I1-taught.json, cap5/I1-replay-allow1.jpg): "줄 추가"
// taught into an empty document replayed as "Existing line keepAdded line". The pure parts (the lesson's mark, the
// call it makes, the cards, old lessons) are in Tests/ArisCoreTests/ArisTeachNewLineTests; these drive app.type in the
// helper's app layer against a fake TextEdit: the line break the trust gate rated is typed only into a text area whose
// text doesn't already end a line, a one-line field or a field it can't read gets none, and the undo takes the break
// back with the text.
// Called from main.swift; uses its check().
import Foundation

func runVmfix8Tests() {
    vmfix8TypeTests()
    vmfix8UndoTests()
}

// MARK: - Fakes: TextEdit with one text element of a given role

private final class V8System: ArisAppsSystem {
    let editor = ArisAppsRunning(bundle: "com.apple.TextEdit", name: "TextEdit", pid: 801)
    func installedApps() -> [ArisApps.AppRecord] { [.init(bundle: "com.apple.TextEdit", names: ["TextEdit"], path: "/System/Applications/TextEdit.app")] }
    func runningApps() -> [ArisAppsRunning] { [editor] }
    func frontmost() -> ArisAppsRunning? { nil }
    func defaultBrowser() -> String? { "com.apple.Safari" }
    func open(_ request: ArisAppsOpenRequest) -> (ok: Bool, message: String) { (true, "opened") }
    func quit(pid: Int32) -> Bool { true }
    func hide(pid: Int32) -> Bool { true }
    func activate(pid: Int32) -> Bool { true }
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

private final class V8AX: ArisAppsAccessibility {
    func menuBar(pid: Int32) -> ArisApps.MenuBar? { nil }
    func pressMenu(pid: Int32, path: [String]) -> (ok: Bool, message: String) { (true, "pressed") }
    func setFullScreen(pid: Int32, window: Int, on: Bool) -> Bool { true }
    func focusedRole(pid: Int32) -> String? { "textArea" }
    func caretToEnd(pid: Int32, at point: (x: Double, y: Double)?) -> ArisApps.CaretEnd { .moved }
}

/// One text element, `role`, holding `text`; what is typed goes at its end.
private final class V8Engine: ArisAppsEngine {
    var typed: [String] = []
    var text: String?
    var role = "textArea"
    func run(_ arguments: [String], background: Bool) -> ArisApps.JSON {
        switch (arguments.first ?? "", arguments.dropFirst().first ?? "") {
        case ("window", "list"):
            return .object(["success": .bool(true), "data": .object(["windows": .array([.object([
                "window_id": .number(80), "window_title": .string("Untitled"), "is_frontmost": .bool(true),
                "bounds": .object(["x": .number(100), "y": .number(100), "width": .number(800), "height": .number(600)])])])])])
        case ("see", _):
            var area: [String: ArisApps.JSON] = ["id": .string("elem_1"), "role": .string(role), "label": .string("First Text View"),
                                                 "bounds": .object(["x": .number(100), "y": .number(150), "width": .number(800), "height": .number(400)])]
            if let text, !text.isEmpty { area["value"] = .string(text) }
            return .object(["success": .bool(true), "data": .object(["snapshot_id": .string("ps_v8"), "window_title": .string("Untitled"),
                                                                     "ui_elements": .array([.object(area)])])])
        case ("type", _):
            typed.append(arguments[2])
            text = (text ?? "") + arguments[2]
            return .object(["success": .bool(true), "data": .object(["delivery": .string("typed")])])
        case ("set-value", _):
            text = arguments[6]
            return .object(["success": .bool(true), "data": .object([:])])
        default:
            return .object(["success": .bool(true), "data": .object([:])])
        }
    }
}

private func v8Hands(text: String?, role: String = "textArea") -> (ArisAppsHands, V8Engine) {
    let engine = V8Engine()
    engine.text = text
    engine.role = role
    let hands = ArisAppsHands(system: V8System(), ax: V8AX(), engine: engine, store: ArisAppsMemoryStore())
    hands.pollSeconds = 0
    return (hands, engine)
}

/// The call "줄 추가"'s replay makes now: the break in the text the gate rated, and the mark.
private func v8Call(target: String? = "First Text View 칸", at: String = "end", line: Bool = true) -> ArisApps.JSON {
    var object: [String: ArisApps.JSON] = ["app": .string("TextEdit"), "text": .string("\nAdded line"), "at": .string(at)]
    if let target { object["target"] = .string(target) }
    if line { object["line"] = .string("new") }
    return .object(object)
}

// MARK: - app.type

private func vmfix8TypeTests() {
    do {
        let (hands, engine) = v8Hands(text: "Existing line keep")
        let done = hands.call("app.type", v8Call())
        check(done.ok && engine.text == "Existing line keep\nAdded line" && engine.typed == ["\nAdded line"],
              "vmfix8: a replay into a line that isn't empty puts its text on a new line (\(String(describing: engine.text)))")
        check(done.did.contains("typed 11 characters") && done.verified, "vmfix8: the account counts the break it typed (\(done.did))")
    }
    do {
        let (hands, engine) = v8Hands(text: nil)
        let done = hands.call("app.type", v8Call())
        check(done.ok && engine.text == "Added line" && done.verified, "vmfix8: an empty document gets no break before the text (\(String(describing: engine.text)))")
    }
    do {
        let (hands, engine) = v8Hands(text: "Existing line keep\n")
        _ = hands.call("app.type", v8Call())
        check(engine.text == "Existing line keep\nAdded line", "vmfix8: text that already ends a line gets no second break (\(String(describing: engine.text)))")
    }
    do {
        let (hands, engine) = v8Hands(text: "Existing", role: "textField")
        _ = hands.call("app.type", v8Call())
        check(engine.typed == ["Added line"], "vmfix8: a one-line field never gets a break (\(engine.typed))")
    }
    do {
        // No field named: the focused one takes the text, and nothing about it was read, so no break.
        let (hands, engine) = v8Hands(text: "Existing")
        _ = hands.call("app.type", v8Call(target: nil))
        check(engine.typed == ["Added line"], "vmfix8: a field it can't read gets no break (\(engine.typed))")
    }
    do {
        let (hands, engine) = v8Hands(text: "Existing")
        _ = hands.call("app.type", v8Call(at: "caret"))
        check(engine.typed == ["Added line"], "vmfix8: at the caret, where the text before can't be told, no break (\(engine.typed))")
    }
    do {
        // Without the mark the text is his, line break and all, exactly as before.
        let (hands, engine) = v8Hands(text: nil)
        _ = hands.call("app.type", v8Call(line: false))
        check(engine.typed == ["\nAdded line"], "vmfix8: an unmarked text is typed as given (\(engine.typed))")
    }
}

// MARK: - Undo

private func vmfix8UndoTests() {
    let (hands, engine) = v8Hands(text: "Existing line keep")
    let done = hands.call("app.type", v8Call())
    guard case .textInserted(_, let element, _)? = done.undo, let mark = ArisApps.TextUndo.mark(element) else {
        check(false, "vmfix8: the replay's typing has an undo")
        return
    }
    check(mark.inserted == "\nAdded line" && mark.location == 18, "vmfix8: the undo covers the break and the text (\(mark.inserted.debugDescription))")
    let now = engine.text ?? ""
    let range = ArisApps.TextUndo.range(in: now, mark: mark)
    check(range.map { (now as NSString).replacingCharacters(in: $0, with: "") } == "Existing line keep",
          "vmfix8: undoing it leaves the document as it was, with no stray line break")
}
