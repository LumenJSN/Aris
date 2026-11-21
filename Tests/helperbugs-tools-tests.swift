// Tests for jv-helperbugs (tools): a shortcut and a Spotlight search have a time limit; `window` says "moved" only
// when the app took it; a rename never over anything also on a disk without RENAME_EXCL (exFAT); Excel, PowerPoint and
// HWPX documents are read; the clipboard history is a protected, secret place; the short Korean word for a password
// counts only as a word of its own. Fake files in a temp folder only. Called from main.swift; uses its check().
import Foundation

private func toolsHome() -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-helperbugs-tools-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.resolvingSymlinksInPath().path
}

private func write(_ text: String, _ path: String) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try? text.write(toFile: path, atomically: true, encoding: .utf8)
}

func runHelperbugsToolsTests() {
    toolsLimitTests()
    toolsWindowTests()
    toolsRenameTests()
    toolsOfficeTests()
    toolsClipboardTests()
    toolsKoreanSecretTests()
}

// MARK: - 15: shortcut and find have a limit

private func toolsLimitTests() {
    check(ArisBoundedRun.defaultLimit(for: "/usr/bin/shortcuts") == ArisBoundedRun.shortcutLimit
          && ArisBoundedRun.defaultLimit(for: "/usr/bin/mdfind") == ArisBoundedRun.spotlightLimit
          && ArisBoundedRun.defaultLimit(for: "/usr/bin/osascript") == ArisBoundedRun.appleScriptLimit
          && ArisBoundedRun.defaultLimit(for: "/bin/echo") == nil,
          "helperbugs 15: a shortcut and a Spotlight search get a time limit, as AppleScript does; other programs don't")
    check(ArisBoundedRun.shortcutLimit < 120 && ArisBoundedRun.shortcutLimit > ArisBoundedRun.appleScriptLimit,
          "helperbugs 15: a shortcut may run for minutes, but stops before the brain's own two-minute command limit")
    let stopped = ArisBoundedRun.shortcutStoppedLine("Morning")
    check(stopped.contains("\"Morning\"") && stopped.contains("stopped") && stopped.contains("don't run it again")
          && !stopped.lowercased().contains("ran morning") && !stopped.lowercased().contains("done:"),
          "helperbugs 15: a shortcut stopped at its limit is told as stopped and not to be run again, never as ran")
    check(ArisBoundedRun.spotlightStoppedNote().contains("still searching") && ArisBoundedRun.spotlightStoppedNote().contains("there may be more"),
          "helperbugs 15: a search stopped at its limit keeps what it found and says there may be more")
    // A child that never ends is still stopped at the limit it is given, with what it printed by then.
    let started = Date()
    let partial = ArisBoundedRun.capture("/bin/sh", ["-c", "echo first; exec sleep 20"], limit: 0.5)
    check(partial?.timedOut == true && partial?.printed == "first\n" && Date().timeIntervalSince(started) < 5,
          "helperbugs 15: a search stopped at its limit hands back the lines it printed before")
}

// MARK: - 15: window moved only when it moved

private func toolsWindowTests() {
    let done = ArisWindowMoveReport.report(app: "Safari", layout: "left", placed: true, sized: true)
    check(done.done && done.line == "moved Safari left", "helperbugs 15: a window that took its place and size is moved")
    let neither = ArisWindowMoveReport.report(app: "Safari", layout: "left", placed: false, sized: false)
    let place = ArisWindowMoveReport.report(app: "Safari", layout: "left", placed: false, sized: true)
    let size = ArisWindowMoveReport.report(app: "Safari", layout: "left", placed: true, sized: false)
    check(!neither.done && !place.done && !size.done && ![neither, place, size].contains { $0.line.hasPrefix("moved") }
          && neither.line.contains("didn't move") && place.line.contains("refused to move") && size.line.contains("refused the new size"),
          "helperbugs 15: a window the app wouldn't move or size is a failure in words, never \"moved\"")
}

// MARK: - 15: exclusive rename on a disk without RENAME_EXCL

private func toolsRenameTests() {
    let home = toolsHome()
    let a = home + "/a.txt", b = home + "/b.txt"
    write("A", a)
    check(ArisExclusiveRename.rename(a, b) == 0 && FileManager.default.fileExists(atPath: b) && !FileManager.default.fileExists(atPath: a),
          "helperbugs 15: on APFS the rename is the one exclusive step, as before")
    write("A", a)
    check(ArisExclusiveRename.rename(a, b) == EEXIST && (try? String(contentsOfFile: b, encoding: .utf8)) == "A" && FileManager.default.fileExists(atPath: a),
          "helperbugs 15: on APFS a name that is taken is never overwritten")

    // A disk that answers ENOTSUP (exFAT, FAT): a link then unlink where links work.
    var exfat = ArisExclusiveRename.System()
    exfat.exclusive = { _, _ in ENOTSUP }
    let c = home + "/c.txt"
    check(ArisExclusiveRename.rename(a, c, system: exfat) == 0 && (try? String(contentsOfFile: c, encoding: .utf8)) == "A" && !FileManager.default.fileExists(atPath: a),
          "helperbugs 15: without RENAME_EXCL a file is moved by a link and an unlink")
    write("other", a)
    check(ArisExclusiveRename.rename(a, c, system: exfat) == EEXIST && (try? String(contentsOfFile: c, encoding: .utf8)) == "A"
          && (try? String(contentsOfFile: a, encoding: .utf8)) == "other",
          "helperbugs 15: without RENAME_EXCL a taken name is still never overwritten (link refuses it)")

    // And where links are missing too (exFAT): a check that nothing is there, then a plain rename.
    var nolinks = exfat
    nolinks.link = { _, _ in ENOTSUP }
    let d = home + "/d.txt"
    check(ArisExclusiveRename.rename(a, d, system: nolinks) == 0 && (try? String(contentsOfFile: d, encoding: .utf8)) == "other" && !FileManager.default.fileExists(atPath: a),
          "helperbugs 15: on a disk with neither, a free name is renamed into")
    write("third", a)
    check(ArisExclusiveRename.rename(a, d, system: nolinks) == EEXIST && (try? String(contentsOfFile: d, encoding: .utf8)) == "other",
          "helperbugs 15: on a disk with neither, a taken name is seen and left alone")
    let folder = home + "/folder", moved = home + "/moved"
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    check(ArisExclusiveRename.rename(folder, moved, system: exfat) == 0 && FileManager.default.fileExists(atPath: moved),
          "helperbugs 15: a folder (which can't be linked) is moved by the existence check")
    var gone = exfat
    gone.unlink = { path in path.hasSuffix("/e-source.txt") ? EACCES : Darwin.unlink(path) == 0 ? 0 : errno }
    write("E", home + "/e-source.txt")
    check(ArisExclusiveRename.rename(home + "/e-source.txt", home + "/e.txt", system: gone) == EACCES && !FileManager.default.fileExists(atPath: home + "/e.txt")
          && FileManager.default.fileExists(atPath: home + "/e-source.txt"),
          "helperbugs 15: an old name that can't be taken away leaves no second name behind")
    check(ArisExclusiveRename.rename(home + "/none.txt", home + "/f.txt", system: nolinks) == ENOENT,
          "helperbugs 15: a file that isn't there is ENOENT, as before")
    // The undo's move and its words go through it.
    write("G", home + "/g.txt")
    check((try? ArisActivity.moveWithoutOverwriting(from: home + "/g.txt", to: home + "/h.txt")) != nil && FileManager.default.fileExists(atPath: home + "/h.txt"),
          "helperbugs 15: the activity undo's move still moves")
    try? FileManager.default.removeItem(atPath: home)
}

// MARK: - 16: Excel, PowerPoint and HWPX

/// A zip of these files (path inside → text), made with /usr/bin/zip; `stored`: without compression.
private func makeZip(_ files: [String: String], at path: String, stored: Bool = false) -> Bool {
    let folder = toolsHome()
    for (name, text) in files { write(text, folder + "/" + name) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = URL(fileURLWithPath: folder)
    process.arguments = (stored ? ["-0"] : []) + ["-q", "-X", path] + files.keys.sorted()
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    try? FileManager.default.removeItem(atPath: folder)
    return process.terminationStatus == 0
}

private func toolsOfficeTests() {
    let home = toolsHome()
    let xlsx = home + "/budget.xlsx"
    let made = makeZip([
        "xl/workbook.xml": """
        <?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="예산" sheetId="1" r:id="rId2"/><sheet name="Notes" sheetId="2" r:id="rId1"/></sheets></workbook>
        """,
        "xl/_rels/workbook.xml.rels": """
        <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="x" Target="worksheets/sheet2.xml"/><Relationship Id="rId2" Type="x" Target="/xl/worksheets/sheet1.xml"/></Relationships>
        """,
        "xl/sharedStrings.xml": """
        <?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>항목</t></si><si><r><t>금</t></r><r><t>액</t></r><rPh><t>きん</t></rPh></si><si><t>식비</t></si></sst>
        """,
        "xl/worksheets/sheet1.xml": """
        <?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row><row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2"><v>32000</v></c></row><row r="3"><c r="A3" t="inlineStr"><is><t>합계</t></is></c><c r="B3" t="b"><v>1</v></c><c r="D3"><f>SUM(C2)</f><v>32000</v></c></row></sheetData></worksheet>
        """,
        "xl/worksheets/sheet2.xml": """
        <?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>메모</t></is></c></row></sheetData></worksheet>
        """,
    ], at: xlsx)
    let sheet = ArisOfficeText.text(ofFile: xlsx)
    check(made && sheet == "[Sheet: 예산]\n항목\t금액\n식비\t\t32000\n합계\tTRUE\t\t32000\n\n[Sheet: Notes]\n메모",
          "helperbugs 16: an Excel workbook is read sheet by sheet in the workbook's order, shared and inline strings, columns kept, no phonetic runs (\(sheet ?? "nil"))")

    let pptx = home + "/deck.pptx"
    let deckMade = makeZip([
        "ppt/presentation.xml": """
        <?xml version="1.0"?><p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst><p:sldId id="256" r:id="rId3"/><p:sldId id="257" r:id="rId2"/></p:sldIdLst></p:presentation>
        """,
        "ppt/_rels/presentation.xml.rels": """
        <?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId2" Target="slides/slide1.xml"/><Relationship Id="rId3" Target="slides/slide2.xml"/></Relationships>
        """,
        "ppt/slides/slide1.xml": """
        <?xml version="1.0"?><p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>두 번째</a:t></a:r></a:p><a:p><a:r><a:t>Line</a:t></a:r><a:br/><a:r><a:t>break</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>
        """,
        "ppt/slides/slide2.xml": """
        <?xml version="1.0"?><p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Title &amp; </a:t></a:r><a:r><a:t>more</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>
        """,
    ], at: pptx, stored: true)
    let deck = ArisOfficeText.text(ofFile: pptx)
    check(deckMade && deck == "[Slide 1]\nTitle & more\n\n[Slide 2]\n두 번째\nLine\nbreak",
          "helperbugs 16: a PowerPoint deck is read slide by slide in the deck's order, a stored (uncompressed) zip too (\(deck ?? "nil"))")

    let hwpx = home + "/보고서.hwpx"
    let hwpxMade = makeZip([
        "mimetype": "application/hwp+zip",
        "Contents/section0.xml": """
        <?xml version="1.0" encoding="UTF-8"?><hs:sec xmlns:hs="hs" xmlns:hp="hp"><hp:p><hp:run><hp:t>첫 문단</hp:t></hp:run></hp:p><hp:p><hp:run><hp:t>둘째<hp:tab/>칸</hp:t></hp:run></hp:p></hs:sec>
        """,
        "Contents/section1.xml": """
        <?xml version="1.0" encoding="UTF-8"?><hs:sec xmlns:hs="hs" xmlns:hp="hp"><hp:p><hp:run><hp:t>다음 구역</hp:t></hp:run></hp:p></hs:sec>
        """,
    ], at: hwpx)
    let hangul = ArisOfficeText.text(ofFile: hwpx)
    check(hwpxMade && hangul == "첫 문단\n둘째\t칸\n\n다음 구역", "helperbugs 16: a HWPX document is read section by section (\(hangul ?? "nil"))")

    // Bounded, and nothing for what isn't one.
    let long = ArisOfficeText.text(ofFile: pptx, limit: 5)
    check(long != nil && long!.count < 40, "helperbugs 16: the text stops near its limit")
    write("not a zip", home + "/fake.xlsx")
    check(ArisOfficeText.text(ofFile: home + "/fake.xlsx") == nil && ArisOfficeText.text(ofFile: home + "/none.pptx") == nil,
          "helperbugs 16: a file that isn't a zip, or isn't there, has no text (never a crash)")
    let empty = home + "/empty.pptx"
    check(makeZip(["ppt/presentation.xml": "<p:presentation xmlns:p=\"p\"/>"], at: empty) && ArisOfficeText.text(ofFile: empty) == nil,
          "helperbugs 16: a deck with no slides has no text")
    let entity = home + "/entity.hwpx"
    check(makeZip(["Contents/section0.xml": "<?xml version=\"1.0\"?><!DOCTYPE s [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><s xmlns:hp=\"hp\"><hp:p><hp:t>a&x;b</hp:t></hp:p></s>"], at: entity)
          && ArisOfficeText.text(ofFile: entity).map { !$0.contains("root") } ?? true,
          "helperbugs 16: an outside entity in a document's XML is never loaded")

    // The rules: these kinds are read; an old binary HWP is refused with what to do.
    check(ArisFileText.kind("/x/a.xlsx") == .office && ArisFileText.kind("/x/a.PPTX") == .office && ArisFileText.kind("/x/a.hwpx") == .office
          && ArisFileText.kind("/x/a.hwp") == nil && ArisFileText.kind("/x/a.docx") == .rich,
          "helperbugs 16: xlsx, pptx and hwpx are read as office documents; Word stays rich text")
    let user = toolsHome()
    let old = ArisFileText.refusal(user + "/Documents/보고서.hwp", home: user, isFolder: false, size: 100, isKeynote: { _ in false }, disks: ArisExternalDisks(root: "/Volumes", kind: { _ in .system }))
    let fine = ArisFileText.refusal(user + "/Documents/budget.xlsx", home: user, isFolder: false, size: 100, isKeynote: { _ in false }, disks: ArisExternalDisks(root: "/Volumes", kind: { _ in .system }))
    check(old?.contains("HWPX or PDF") == true && fine == nil, "helperbugs 16: a binary HWP is refused with how to make it readable; an xlsx is read")
    try? FileManager.default.removeItem(atPath: home)
    try? FileManager.default.removeItem(atPath: user)
}

// MARK: - 17: the clipboard history is protected

private func toolsClipboardTests() {
    let home = "/Users/nobody-\(UUID().uuidString.prefix(8))"
    let history = home + "/" + ArisProtectedPlaces.clipboardHistory
    let unsandboxed = home + "/Library/Application Support/Aris/clipboard.json"
    check(ArisProtectedPlaces.blocks(history, home: home) && ArisProtectedPlaces.blocks(unsandboxed, home: home)
          && !ArisProtectedPlaces.blocks(home + "/Library/Containers/com.lumenjsn.aris/Data/Library/Application Support/Aris/history.json", home: home),
          "helperbugs 17: the app's clipboard history is a protected place (never read by files read, moved, trashed or edited)")
    let work = home + "/.config/aris/aris/work"
    check(ArisRiskPolicy.isSecret(history, work: work) && ArisRiskPolicy.isSecret(unsandboxed, work: work)
          && ArisRiskPolicy.isSecret(history + ".corrupt-1", work: work) && !ArisRiskPolicy.isSecret(home + "/Documents/clipboard.json", work: work),
          "helperbugs 17: reading the clipboard history (or its corrupt copy) through a command asks first; a clipboard.json of the user's own doesn't")
    check(ArisDropGuard.inProtectedPlace(history, home: home) && ArisDropGuard.protectedPlaces == ArisProtectedPlaces.relative,
          "helperbugs 17: the app's drop guard knows the same place")
}

// MARK: - 10: the short Korean word for a password, as a word

private func toolsKoreanSecretTests() {
    let secret = ["/x/비번.txt", "/x/와이파이비번.txt", "/x/비번모음.csv", "/x/내 비번 2024.txt", "/x/비밀번호.txt", "/x/회사패스워드목록.txt"]
    let plain = ["/x/준비번호.txt", "/x/예비번호 목록.csv", "/x/경비번호표.xlsx"]
    let noKeynote: (String) -> Bool = { _ in false }
    check(secret.allSatisfy { ArisFiles.looksSecret($0, isKeynote: noKeynote) }, "helperbugs 10: 비번 as a word, at a word's start or end, still looks like a password file")
    check(!plain.contains { ArisFiles.looksSecret($0, isKeynote: noKeynote) }, "helperbugs 10: 비번 inside another word (준비번호, 예비번호) is not a password file")
    check((secret + plain).allSatisfy { ArisDropGuard.looksSecret($0, isKeynote: noKeynote) == ArisFiles.looksSecret($0, isKeynote: noKeynote) },
          "helperbugs 10: the app's drop guard reads these names the same way")
}
