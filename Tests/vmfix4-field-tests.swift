// VM run 2 (aris-vmcheck/notes2/h1-polite.log, cap2/h1-*.jpg), defect 1: "이거 더 정중하게 바꿔 줘" with a paragraph
// selected in TextEdit read the selection and then failed with "바꾸지 못했어요: won't type into Aris": the new text
// went to /insert, which pastes where the keyboard is, and typing the request into the notch had made that Aris. The
// write now goes into the element the look read (ArisFieldWrite), never into whatever has the keyboard.

import AppKit

/// TextEdit's text view as Accessibility shows it (AXTextArea): a value, a selected range, AXSelectedText settable
/// (setting it replaces the selection, as NSTextView does), and whether it is still TextEdit's focused element.
private final class FakeTextArea: ArisFieldWriteIO {
    var text: String
    var range: ArisTextRange
    var alive = true
    var insertable = true
    var takesInsert = true
    /// Says it took the insert and changes nothing.
    var ignoresInsert = false
    var focusedInApp = true
    var pasteReads = true
    var frontResult = ArisNativeFrontResult.sent
    private(set) var inserted: [String] = []
    private(set) var pasted: [String] = []
    private(set) var fronted: [String] = []
    private(set) var settles = 0

    init(_ text: String, selecting: String) {
        self.text = text
        let found = (text as NSString).range(of: selecting)
        range = ArisTextRange(location: found.location, length: found.length)
    }

    func value() -> String? { alive ? text : nil }
    func selectedRange() -> ArisTextRange? { alive ? range : nil }
    func selectedText() -> String? { alive ? (text as NSString).substring(with: NSRange(location: range.location, length: range.length)) : nil }
    func select(_ range: ArisTextRange) -> Bool {
        guard range.location + range.length <= (text as NSString).length else { return false }
        self.range = range
        return true
    }
    private func replace(_ new: String) {
        text = (text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: new)
        range = ArisTextRange(location: range.location + (new as NSString).length, length: 0)
    }
    func insertSelected(_ new: String) -> Bool {
        inserted.append(new)
        guard takesInsert else { return false }
        if !ignoresInsert { replace(new) }
        return true
    }
    func paste(_ new: String) -> Bool {
        pasted.append(new)
        replace(new)
        return pasteReads
    }
    func front(_ new: String, range: ArisTextRange?) -> ArisNativeFrontResult {
        fronted.append(new)
        if frontResult == .sent { if let range { self.range = range }; replace(new) }
        return frontResult
    }
    func settle() { settles += 1 }
}

private let vmfix4Paragraph = "The Lisbon city council voted on Tuesday to close three central streets to private cars every Sunday starting in March."
private let vmfix4Document = vmfix4Paragraph + "\n회의는 3시에 시작해요"
private let vmfix4Polite = "On Tuesday, the Lisbon city council kindly agreed to close three central streets to private cars on Sundays from March."

private func vmfix4Target(bundle: String? = "com.apple.TextEdit", app: String = "TextEdit", selection: String? = vmfix4Paragraph,
                          range: ArisTextRange? = ArisTextRange(location: 0, length: (vmfix4Paragraph as NSString).length),
                          secure: Bool = false) -> ArisFieldTarget {
    ArisFieldTarget(pid: 4242, bundleId: bundle, app: app, window: 51, element: NSObject(), selection: selection, range: range, secure: secure)
}

private func vmfix4Root() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..").standardizedFileURL
}

private func vmfix4Source(_ path: String) -> String {
    (try? String(contentsOf: vmfix4Root().appendingPathComponent(path), encoding: .utf8)) ?? ""
}

func runVmfix4FieldTests() {
    // The h1 case: TextEdit's paragraph selected, Aris (the notch) has the keyboard. The new text replaces exactly the
    // selection, through Accessibility on that element; nothing is pasted anywhere and the front is never taken.
    let area = FakeTextArea(vmfix4Document, selecting: vmfix4Paragraph)
    let outcome = ArisFieldWrite.run(vmfix4Polite, target: vmfix4Target(), io: area)
    check(outcome == .written(.axInsert), "field write: a typed rewrite lands in TextEdit's selection by its element")
    check(area.text == vmfix4Polite + "\n회의는 3시에 시작해요", "field write: only the selection is replaced, the rest of the document stays")
    check(area.pasted.isEmpty && area.fronted.isEmpty, "field write: nothing is pasted where the keyboard is, the front is not taken")

    // The selection moved since the look (a click in the document): it is put back before the write.
    let moved = FakeTextArea(vmfix4Document, selecting: vmfix4Paragraph)
    moved.range = ArisTextRange(location: 3, length: 0)
    check(ArisFieldWrite.run(vmfix4Polite, target: vmfix4Target(), io: moved) == .written(.axInsert)
          && moved.text.hasPrefix(vmfix4Polite), "field write: a moved selection is put back where it was read first")

    // The text there changed since the look: nothing is written.
    let changed = FakeTextArea("Something else entirely, typed after the look.\n" + vmfix4Document, selecting: "Something")
    let before = changed.text
    let stale = ArisFieldWrite.run(vmfix4Polite, target: vmfix4Target(), io: changed)
    check(stale == .refused(ArisFieldWrite.moved) && changed.text == before && changed.inserted.isEmpty,
          "field write: text that changed since the look is never overwritten")

    // An app whose field refuses AXSelectedText but still has its focus: ⌘V to that app's process, not to the front.
    let electron = FakeTextArea(vmfix4Document, selecting: vmfix4Paragraph)
    electron.insertable = false
    check(ArisFieldWrite.run(vmfix4Polite, target: vmfix4Target(bundle: "com.tinyspeck.slackmacgap", app: "Slack"), io: electron) == .written(.paste)
          && electron.fronted.isEmpty && electron.pasted == [vmfix4Polite], "field write: no Accessibility insert, focused: pasted into that app's process")

    // An insert the app says it took but that left the field unchanged: the next way goes (the field is as it was).
    let ignoring = FakeTextArea(vmfix4Document, selecting: vmfix4Paragraph)
    ignoring.ignoresInsert = true
    check(ArisFieldWrite.run(vmfix4Polite, target: vmfix4Target(), io: ignoring) == .written(.paste) && ignoring.text.hasPrefix(vmfix4Polite),
          "field write: an insert that changed nothing falls to the paste, once")
    let refusing = FakeTextArea(vmfix4Document, selecting: vmfix4Paragraph)
    refusing.takesInsert = false
    check(ArisFieldWrite.run(vmfix4Polite, target: vmfix4Target(), io: refusing) == .written(.paste), "field write: a refused insert falls to the paste")

    // Neither: the app comes forward in a gap, that element focused, the selection put back, pasted.
    let away = FakeTextArea(vmfix4Document, selecting: vmfix4Paragraph)
    away.insertable = false
    away.focusedInApp = false
    check(ArisFieldWrite.run(vmfix4Polite, target: vmfix4Target(), io: away) == .written(.front) && away.pasted.isEmpty && away.fronted.count == 1,
          "field write: neither way: the app is brought forward for that element only")
    let busy = FakeTextArea(vmfix4Document, selecting: vmfix4Paragraph)
    busy.insertable = false
    busy.focusedInApp = false
    busy.frontResult = .busy(waited: 8)
    if case .refused = ArisFieldWrite.run(vmfix4Polite, target: vmfix4Target(), io: busy) {} else { check(false, "field write: no gap in his input: refused") }
    check(busy.text == vmfix4Document, "field write: no gap in his input: nothing typed")

    // The guard that refuses to type into Aris stays; a password field is never written; a gone field is said.
    let own = FakeTextArea(vmfix4Document, selecting: vmfix4Paragraph)
    check(ArisFieldWrite.run(vmfix4Polite, target: vmfix4Target(bundle: "com.lumenjsn.aris", app: "Aris"), io: own) == .refused("won't type into Aris")
          && own.inserted.isEmpty && own.pasted.isEmpty, "field write: never into Aris itself")
    check(ArisFieldWrite.run("x", target: vmfix4Target(secure: true), io: FakeTextArea("pw", selecting: "pw")) == .refused(ArisFieldWrite.secureField),
          "field write: never into a password field")
    let gone = FakeTextArea(vmfix4Document, selecting: vmfix4Paragraph)
    gone.alive = false
    check(ArisFieldWrite.run(vmfix4Polite, target: vmfix4Target(), io: gone) == .refused(ArisFieldWrite.gone), "field write: a closed window is said, nothing typed")

    // A draft ("여기에 답장 써 줘"): the caret, nothing selected; the text goes in at the caret.
    let caret = FakeTextArea("Hi Minsu,\n", selecting: "")
    caret.range = ArisTextRange(location: 10, length: 0)
    check(ArisFieldWrite.run("Tomorrow afternoon works.", target: vmfix4Target(selection: nil, range: ArisTextRange(location: 10, length: 0)), io: caret)
          == .written(.axInsert) && caret.text == "Hi Minsu,\nTomorrow afternoon works.", "field write: a draft goes in at the caret it read")

    // The desk: a token is used once and goes stale.
    let desk = ArisFieldTargetDesk()
    let start = Date()
    let token = desk.keep(vmfix4Target(), at: start)
    check(desk.take(token, now: start.addingTimeInterval(5)) != nil && desk.take(token, now: start.addingTimeInterval(6)) == nil,
          "field desk: a look's field is written once")
    let old = desk.keep(vmfix4Target(), at: start)
    check(desk.take(old, now: start.addingTimeInterval(ArisFieldTargetDesk.freshFor + 1)) == nil, "field desk: a field older than a turn is not written")

    // Typed and spoken alike: the look reads the app he was in (typed: the notch's field took the keyboard from TextEdit;
    // spoken: TextEdit is in front), and the write uses that look's field, never /insert's "where the keyboard is".
    check(ArisUserApp.pick(front: 386, own: 386, previous: 4242) == 4242 && ArisUserApp.pick(front: 4242, own: 386, previous: nil) == 4242,
          "field write: typed or spoken, the look is of TextEdit")
    let look = vmfix4Source("Aris/private/Aris/ArisController+Look.swift")
    check(look.contains("ArisAgentClient.insert(new, target: look.target)") && look.contains("ArisAgentClient.typeAtCaret(new, target: target)"),
          "field write: the rewrite and the draft send the look's field back")
    let client = vmfix4Source("Aris/private/Aris/ArisAgentClient.swift")
    check(client.contains("target: line(\"target\")") && client.contains("\"target\": target"), "field write: the app reads the look's field and hands it to /insert")
    let main = vmfix4Source("ArisAgent/main.swift")
    let route = main.range(of: "case \"/insert\":").map { String(main[$0.lowerBound...].prefix(2_500)) } ?? ""
    let targetAt = route.range(of: "ArisTypeHereRoutes.writeField")?.lowerBound, pasteAt = route.range(of: "ArisInsert.paste")?.lowerBound
    check(targetAt != nil && pasteAt != nil && targetAt! < pasteAt!, "field write: /insert with a field writes into it before any paste where the keyboard is")
    check(main.contains("\"target\": look.fieldToken ?? \"\""), "field write: /look hands the field's token to the app")
    let lookSource = vmfix4Source("ArisAgent/ArisLook.swift")
    check(lookSource.contains("ArisFieldTargetLive.capture(field: field") && lookSource.contains("if look.confirmed, let field = look.field"),
          "field write: the look keeps the focused field by its element, for a confirmed look only")
}
