// jv-vmfix4 (VM run 2, H2): "이거 이름 앞에 날짜 붙여 줘" with two files selected in Finder. The focus must be
// those two files as full paths, read through Accessibility the way real Finder shows them: in icon view the items are
// AXImage elements in an AXGroup (not rows), each with AXFilename and AXURL; in list view they are AXRows of an
// AXOutline whose cells hold the name. The window's AXDocument is the folder. The turn gets the paths as data, with no
// `--finder` (an AppleScript to Finder, which puts up macOS's Automation question).
import XCTest
@testable import ArisCore

final class ArisFinderSelectionTests: XCTestCase {
    private func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> ArisFocusRect { ArisFocusRect(x: x, y: y, width: w, height: h) }
    private let folder = "file:///Users/admin/Desktop/vmcheck2/"
    private let finderApp = ArisFocusApp(name: "Finder", bundleID: "com.apple.finder", pid: 412)

    /// Finder's sidebar as macOS 26 shows it: a source list outline at the window's left edge.
    private var sidebar: ArisAXNode {
        ArisAXNode("AXScrollArea", frame: r(62, 110, 214, 500), children: [
            ArisAXNode("AXOutline", subrole: "AXSourceList", frame: r(62, 110, 214, 500), children: [
                ArisAXNode("AXRow", subrole: "AXOutlineRow", frame: r(70, 175, 190, 26), children: [ArisAXNode("AXCell", children: [ArisAXNode("AXStaticText", value: "Recents")])]),
                ArisAXNode("AXRow", subrole: "AXOutlineRow", frame: r(70, 325, 190, 26), children: [ArisAXNode("AXCell", children: [ArisAXNode("AXStaticText", value: "Desktop")])]),
            ]),
        ])
    }

    private var toolbar: ArisAXNode {
        ArisAXNode("AXToolbar", frame: r(276, 110, 862, 56), children: [
            ArisAXNode("AXRadioGroup", children: [
                ArisAXNode("AXRadioButton", label: "icon view", frame: r(670, 122, 36, 30), selected: true),
                ArisAXNode("AXRadioButton", label: "list view", frame: r(712, 122, 36, 30)),
            ]),
            ArisAXNode("AXStaticText", value: "vmcheck2", frame: r(386, 128, 90, 20)),
        ])
    }

    /// Icon view, as GUI scripting reaches it: image N of group 1 of scroll area 1 of splitter group 1 of window 1.
    private func iconView(itemURLs: Bool = true, document: Bool = true, markedSelected: Bool = true) -> ArisFocusObservation {
        func item(_ name: String, x: Double, selected: Bool) -> ArisAXNode {
            ArisAXNode("AXImage", title: name, url: itemURLs ? folder + name : nil, filename: name, frame: r(x, 180, 90, 110),
                       selected: selected && markedSelected)
        }
        let icons = ArisAXNode("AXScrollArea", frame: r(276, 166, 862, 452), children: [
            ArisAXNode("AXGroup", frame: r(276, 166, 862, 452), children: [
                item("a.txt", x: 310, selected: true), item("b.txt", x: 440, selected: true), item("c.txt", x: 570, selected: false),
            ]),
        ])
        let window = ArisAXNode("AXWindow", title: "vmcheck2", document: document ? folder : nil, frame: r(62, 110, 1076, 508), children: [
            ArisAXNode("AXSplitGroup", frame: r(62, 110, 1076, 508), children: [sidebar, ArisAXNode("AXSplitter", frame: r(276, 110, 1, 508)), icons]),
            toolbar,
        ])
        return ArisFocusObservation(app: finderApp, windowTitle: "vmcheck2", windowID: 88, tree: window)
    }

    /// List view: rows of an outline, the name in the first cell's text field, the icon an AXImage with the file's URL.
    private var listView: ArisFocusObservation {
        func row(_ name: String, y: Double, selected: Bool) -> ArisAXNode {
            ArisAXNode("AXRow", subrole: "AXOutlineRow", frame: r(276, y, 862, 24), selected: selected, children: [
                ArisAXNode("AXCell", children: [ArisAXNode("AXImage", url: folder + name, filename: name), ArisAXNode("AXTextField", value: name)]),
                ArisAXNode("AXCell", children: [ArisAXNode("AXStaticText", value: "Today at 4:30 AM")]),
                ArisAXNode("AXCell", children: [ArisAXNode("AXStaticText", value: "12 bytes")]),
            ])
        }
        let files = ArisAXNode("AXScrollArea", frame: r(276, 166, 862, 452), children: [
            ArisAXNode("AXOutline", frame: r(276, 166, 862, 452), children: [
                row("a.txt", y: 190, selected: true), row("b.txt", y: 214, selected: true), row("c.txt", y: 238, selected: false),
            ]),
        ])
        let window = ArisAXNode("AXWindow", title: "vmcheck2", document: folder, frame: r(62, 110, 1076, 508), children: [
            ArisAXNode("AXSplitGroup", frame: r(62, 110, 1076, 508), children: [sidebar, files]), toolbar,
        ])
        return ArisFocusObservation(app: finderApp, windowTitle: "vmcheck2", windowID: 88, tree: window)
    }

    private let expected = ["/Users/admin/Desktop/vmcheck2/a.txt", "/Users/admin/Desktop/vmcheck2/b.txt"]

    func testIconViewSelectionIsTheTwoFilesWithPaths() {
        let focus = try! XCTUnwrap(ArisFocusResolver.resolve("이거 이름 앞에 날짜 붙여 줘", iconView()).focus)
        XCTAssertEqual(focus.kind, .files, "icon view's selected items are AXImages, not rows: they are still the selection")
        XCTAssertEqual(focus.items, ["a.txt", "b.txt"])
        XCTAssertEqual(focus.paths, expected)
        XCTAssertEqual(focus.path, "/Users/admin/Desktop/vmcheck2")
    }

    func testListViewSelectionCarriesPaths() {
        let focus = try! XCTUnwrap(ArisFocusResolver.resolve("이거 이름 앞에 날짜 붙여 줘", listView).focus)
        XCTAssertEqual(focus.kind, .files)
        XCTAssertEqual(focus.items, ["a.txt", "b.txt"])
        XCTAssertEqual(focus.paths, expected)
    }

    func testPathsFromNameAndFolderWhenItemsHaveNoURL() {
        let focus = ArisFocusResolver.resolve("이거", iconView(itemURLs: false)).focus
        XCTAssertEqual(focus?.paths, expected, "AXFilename joined to the window's folder")
    }

    func testFolderFromTheItemsWhenTheWindowHasNoDocument() {
        let focus = ArisFocusResolver.resolve("이거", iconView(document: false)).focus
        XCTAssertEqual(focus?.paths, expected)
        XCTAssertEqual(focus?.path, "/Users/admin/Desktop/vmcheck2")
    }

    func testNothingSelectedIsNotFiles() {
        let focus = ArisFocusResolver.resolve("이거", iconView(markedSelected: false)).focus
        XCTAssertNotEqual(focus?.kind, .files, "no selected item, no files (the toolbar's selected view button is no file)")
    }

    func testTheTurnGetsThePathsAndNoFinderScript() {
        let resolution = ArisFocusResolver.resolve("이거 이름 앞에 날짜 붙여 줘", iconView())
        let block = try! XCTUnwrap(ArisFocusContext.lines(resolution, nonce: "n0nce"))
        XCTAssertTrue(block.contains("paths (one per line):\n  /Users/admin/Desktop/vmcheck2/a.txt\n  /Users/admin/Desktop/vmcheck2/b.txt"), block)
        XCTAssertFalse(block.contains("--finder"), "never steered to a script that asks Finder (macOS's Automation question)")
        XCTAssertTrue(block.contains("ask Finder for the selection by a script"), block)
        let object = ArisFocusContext.trustObject(try! XCTUnwrap(resolution.focus))
        XCTAssertEqual(object.source, ArisContentSource(kind: "file", source: "/Users/admin/Desktop/vmcheck2/a.txt"))
    }

    func testAPathKeepsItsBrackets() {
        var observation = iconView()
        observation.tree = observation.tree.map { tree in
            var tree = tree
            tree.children[0].children[2].children[0].children[0].url = folder + "photo%20%5B1%5D.jpg"
            tree.children[0].children[2].children[0].children[0].filename = "photo [1].jpg"
            return tree
        }
        let resolution = ArisFocusResolver.resolve("이거", observation)
        XCTAssertEqual(resolution.focus?.paths.first, "/Users/admin/Desktop/vmcheck2/photo [1].jpg")
        XCTAssertTrue(ArisFocusContext.lines(resolution, nonce: "n0nce")?.contains("  /Users/admin/Desktop/vmcheck2/photo [1].jpg") == true)
    }

    func testSelectedFilesNeedNoWindowText() {
        XCTAssertFalse(ArisFocusContext.needsWindowText(ArisFocusResolver.resolve("이거 이름 앞에 날짜 붙여 줘", iconView())),
                       "with the selected files in hand the look reads no window text, so no Screen Recording line or button")
        XCTAssertTrue(ArisFocusContext.needsWindowText(ArisFocusResolver.resolve("이거", iconView(markedSelected: false))))
        XCTAssertTrue(ArisFocusContext.needsWindowText(nil))
    }
}
