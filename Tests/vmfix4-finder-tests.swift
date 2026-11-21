// jv-vmfix4 (VM run 2, H2): "이거 이름 앞에 날짜 붙여 줘" with two files selected in Finder's icon view did nothing.
// The look read only the window: the tree reader never asked a list for its selected children (Finder's icon view keeps
// its selection there, on AXImage items that are no rows) nor an item's AXFilename, so no files focus came of it; the
// window's words needed Screen Recording, so the model was told to ask for it; and the focus line steered file tools to
// `--finder`, an AppleScript to Finder (macOS's Automation question). The resolution itself is tested with Finder-shaped
// trees in Tests/ArisCoreTests/ArisFinderSelectionTests.swift; here the helper's reader on a fake Finder and the look's
// wiring.
import Foundation

private func finderSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// A fake Finder in icon view: its group says which items are selected (AXSelectedChildren); the items themselves don't.
private struct FakeFinder: ArisFocusElements {
    var reads: [Int: ArisFocusElementRead]
    var kids: [Int: [Int]]
    var chosen: [Int: [Int]]
    func read(_ element: Int) -> ArisFocusElementRead? { reads[element] }
    func children(_ element: Int) -> [Int] { kids[element] ?? [] }
    func same(_ a: Int, _ b: Int) -> Bool { a == b }
    func selectedChildren(_ element: Int, role: String) -> [Int] { chosen[element] ?? [] }
}

private func finderReaderTests() {
    let folder = "file:///Users/admin/Desktop/vmcheck2/"
    func item(_ name: String) -> ArisFocusElementRead {
        var read = ArisFocusElementRead(role: "AXImage", title: name, url: folder + name)
        read.filename = name
        return read
    }
    let reads: [Int: ArisFocusElementRead] = [
        0: ArisFocusElementRead(role: "AXWindow", title: "vmcheck2", document: folder),
        1: ArisFocusElementRead(role: "AXScrollArea"),
        2: ArisFocusElementRead(role: "AXGroup"),
        3: item("a.txt"), 4: item("b.txt"), 5: item("c.txt"),
    ]
    let source = FakeFinder(reads: reads, kids: [0: [1], 1: [2], 2: [3, 4, 5]], chosen: [2: [3, 4], 1: [2]])
    let tree = ArisFocusReader(source: source, exhausted: { false }).tree(0, focused: nil).tree
    let items = tree?.children.first?.children.first?.children ?? []
    check(items.map(\.selected) == [true, true, false], "finder reader: a group's selected children are marked selected")
    check(tree?.children.first?.children.first?.selected == false, "finder reader: only list-like elements' selections count (a scroll area's says nothing)")
    check(items.first?.filename == "a.txt" && items.first?.url == folder + "a.txt", "finder reader: an item's AXFilename and AXURL are kept")
    let observation = ArisFocusObservation(app: ArisFocusApp(name: "Finder", bundleID: "com.apple.finder"), windowTitle: "vmcheck2", tree: tree)
    let focus = ArisFocusResolver.resolve("이거 이름 앞에 날짜 붙여 줘", observation).focus
    check(focus?.kind == .files && focus?.paths == ["/Users/admin/Desktop/vmcheck2/a.txt", "/Users/admin/Desktop/vmcheck2/b.txt"],
          "finder reader: the two selected files become the focus, with their paths")
    check(ArisFocusReader<FakeFinder>.selectionHolders.contains("AXGroup") && ArisFocusReader<FakeFinder>.selectionHolders.contains("AXOutline"),
          "finder reader: icon view's group and list view's outline are asked")
}

private func finderLookTests() {
    let live = finderSource("ArisAgent/Focus/ArisFocusLive.swift")
    check(live.contains("kAXFilenameAttribute") && live.contains("kAXSelectedChildrenAttribute") && live.contains("kAXSelectedRowsAttribute"),
          "finder look: the live reader asks for AXFilename, AXSelectedChildren and AXSelectedRows")
    let look = finderSource("ArisAgent/ArisLook.swift")
    let resolved = look.range(of: "let windowText = ArisFocusContext.needsWindowText(resolution)")?.lowerBound
    let seen = look.range(of: "var look = seen(app: front.name")?.lowerBound
    check(resolved != nil && seen != nil && resolved! < seen!, "finder look: the focus is resolved before the window's words are read")
    check(look.contains("if !windowText {") && look.contains("screen: windowText ? allowed : nil"),
          "finder look: with the files in hand nothing is captured and no Screen Recording need is reported")
}

/// H2's second half: the model reached for `osascript … get selection` because the look gave it no files. The focus now
/// carries them, and shell.run's description sends "what is selected or in front" to the focus, never a script. (The
/// card's title for an osascript line is in vmfix4-script-tests; its class stays the base's.)
private func finderOsascriptTests() {
    check(ArisCapabilityBook.core2.first { $0.id == "shell.run" }?.description.contains("use the focus that comes with the turn") == true,
          "osascript: shell.run's description sends what is selected or in front to the focus, never a script")
    check(ArisCore2.shellEffect(#"osascript -e 'tell application "Finder" to get selection'"#, tools: "/opt/aris-tools") == .outward,
          "osascript: its class is the base's (outward: it asks)")
}

func runVMFix4FinderTests() {
    finderReaderTests()
    finderLookTests()
    finderOsascriptTests()
}
