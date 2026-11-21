import XCTest
@testable import ArisCore

/// Tenth VM run, item 12: a turn whose focus was read whole through Accessibility is not told to turn on Screen
/// Recording, and gets no button for it.
final class ArisScreenFixNeedTests: XCTestCase {
    private let app = ArisFocusApp(name: "TextEdit", bundleID: "com.apple.TextEdit", pid: 1)

    private func resolution(_ kind: ArisFocus.Kind, text: String? = nil, items: [String] = []) -> ArisFocusResolution {
        ArisFocusResolution(pointing: ArisFocusWords.parse("이거"), focus: ArisFocus(kind: kind, app: app, text: text, items: items, how: "test"))
    }

    func testAFocusWithItsOwnWordsNeedsNoScreen() {
        for kind in [ArisFocus.Kind.text, .field, .document, .mail, .event, .chat, .pointer] {
            XCTAssertFalse(ArisFocusContext.missesScreen(resolution(kind, text: "첫 줄")), "\(kind)")
        }
        XCTAssertFalse(ArisFocusContext.missesScreen(resolution(.files, items: ["a.txt"])))
        XCTAssertFalse(ArisFocusContext.missesScreen(resolution(.items, items: ["row"])))
    }

    func testWithoutWordsOrForAWholeWindowTheScreenIsMissed() {
        XCTAssertTrue(ArisFocusContext.missesScreen(nil))
        XCTAssertTrue(ArisFocusContext.missesScreen(resolution(.field, text: "  ")))
        XCTAssertTrue(ArisFocusContext.missesScreen(resolution(.pointer)))
        // The window as a whole, a circled region and a page are what the screen is read for.
        for kind in [ArisFocus.Kind.window, .region, .page] {
            XCTAssertTrue(ArisFocusContext.missesScreen(resolution(kind, text: "words")), "\(kind)")
        }
    }
}
