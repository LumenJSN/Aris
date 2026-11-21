import XCTest
@testable import ArisCore

/// The trust gate's own yes for the face's calls of one turn (jv-webabort). The driver's web-result check that reads it is
/// tested in tests/webabort-tests.swift.
final class ArisFaceDecisionsTests: XCTestCase {
    func testOnlyTheCurrentTurnsExactCallIsTakenOnce() {
        let store = ArisFaceDecisions()
        store.ran(turn: "", id: "toolu_1", function: "web_fetch", arguments: ["url": "https://a.io"])
        XCTAssertFalse(store.take(id: "toolu_1", function: "web_fetch", arguments: ["url": "https://a.io"]), "nothing between turns")
        store.begin(turn: "t1")
        store.ran(turn: "t0", id: "toolu_1", function: "web_fetch", arguments: ["url": "https://a.io"])
        XCTAssertFalse(store.take(id: "toolu_1", function: "web_fetch", arguments: ["url": "https://a.io"]), "another turn's credential")
        store.ran(turn: "t1", id: "toolu_1", function: "web_fetch", arguments: ["url": "https://a.io", "n": 2])
        XCTAssertFalse(store.take(id: "toolu_1", function: "web_search", arguments: ["url": "https://a.io", "n": 2]))
        XCTAssertFalse(store.take(id: "toolu_1", function: "web_fetch", arguments: ["url": "https://b.io", "n": 2]))
        XCTAssertFalse(store.take(id: "toolu_2", function: "web_fetch", arguments: ["url": "https://a.io", "n": 2]))
        XCTAssertTrue(store.take(id: "toolu_1", function: "web_fetch", arguments: ["n": 2, "url": "https://a.io"]))
        XCTAssertFalse(store.take(id: "toolu_1", function: "web_fetch", arguments: ["n": 2, "url": "https://a.io"]), "taken once")
        store.ran(turn: "t1", id: "toolu_3", function: "web_fetch", arguments: [:])
        store.begin(turn: "t2")
        XCTAssertFalse(store.take(id: "toolu_3", function: "web_fetch", arguments: [:]), "a new turn starts empty")
    }

    func testIdsAndTheLimit() {
        XCTAssertTrue(ArisFaceDecisions.wellFormed("toolu_01SWrVmaqHpy7uufBr3Twcne"))
        XCTAssertFalse(ArisFaceDecisions.wellFormed(""))
        XCTAssertFalse(ArisFaceDecisions.wellFormed("a b"))
        XCTAssertFalse(ArisFaceDecisions.wellFormed("é"))
        XCTAssertFalse(ArisFaceDecisions.wellFormed(String(repeating: "a", count: ArisFaceDecisions.longestID + 1)))
        let store = ArisFaceDecisions()
        store.begin(turn: "t")
        for index in 0..<(ArisFaceDecisions.most + 3) { store.ran(turn: "t", id: "c\(index)", function: "f", arguments: [:]) }
        XCTAssertTrue(store.take(id: "c0", function: "f", arguments: [:]))
        XCTAssertFalse(store.take(id: "c\(ArisFaceDecisions.most + 2)", function: "f", arguments: [:]))
    }

    func testTheWireReadsClaudeCodesToolUseId() {
        let call = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ping","arguments":{"word":"hi"},"_meta":{"claudecode/toolUseId":"toolu_01SWrVmaqHpy7uufBr3Twcne","progressToken":2}}}"#
        XCTAssertEqual(ArisMCPServerWire.toolUseId(Data(call.utf8)), "toolu_01SWrVmaqHpy7uufBr3Twcne")
        XCTAssertNil(ArisMCPServerWire.toolUseId(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ping"}}"#.utf8)))
        XCTAssertNil(ArisMCPServerWire.toolUseId(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ping","_meta":{"claudecode/toolUseId":"a b"}}}"#.utf8)))
        XCTAssertNil(ArisMCPServerWire.toolUseId(Data(#"{"jsonrpc":"2.0","id":2,"method":"ping","params":{"_meta":{"claudecode/toolUseId":"toolu_1"}}}"#.utf8)))
    }
}
