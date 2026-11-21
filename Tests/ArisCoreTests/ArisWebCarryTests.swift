import XCTest
@testable import ArisCore

/// The outbound-read rule's pure half (ArisWebCarry): the sticky private read, and that only the owner's own words,
/// verbatim, account for what an outbound read sends after it.
final class ArisWebCarryTests: XCTestCase {
    private let file = ArisContentSource(kind: "file", source: "/Users/notes.txt")
    private let page = ArisContentSource(kind: "web", source: "https://news.example/story")

    func testNothingPrivateReadAtFirst() {
        var tracker = ArisProvenanceTracker()
        tracker.ownerTurn("뉴스 찾아 줘")
        _ = tracker.toolCall(id: "q1", capability: "web.search", effect: .observe, arguments: [], publicWeb: true)
        tracker.toolResult("headlines https://news.example/story", source: page, call: "q1")
        XCTAssertFalse(tracker.readPrivate, "Aris's own public fetch is no private read")
    }

    func testThePrivateReadIsStickyPastEviction() {
        var tracker = ArisProvenanceTracker()
        tracker.ownerTurn("https://news.example/story 열어 줘")
        tracker.toolResult("password hunter22", source: file, call: "r1")
        XCTAssertTrue(tracker.readPrivate)
        for index in 0...(ArisProvenanceTracker.keptContents + 5) {
            _ = tracker.toolCall(id: "f\(index)", capability: "web.fetch", effect: .observe, arguments: [], publicWeb: true)
            tracker.toolResult("page \(index)", source: page, call: "f\(index)")
        }
        XCTAssertFalse(tracker.contents.contains { $0.source == file }, "the file's content was evicted")
        XCTAssertTrue(tracker.readPrivate, "the flag survives eviction")
    }

    func testABrowserWindowOrAFocusIsPrivate() {
        var tracker = ArisProvenanceTracker()
        tracker.toolResult("Inbox", source: ArisContentSource(kind: "web", source: "Safari"), call: "d1")
        XCTAssertTrue(tracker.readPrivate, "a page Aris didn't fetch itself is private")
        var focused = ArisProvenanceTracker()
        focused.world = ArisWorldFacts(focus: ArisFocusObject(source: file, text: "draft"))
        focused.world = ArisWorldFacts()
        XCTAssertTrue(focused.readPrivate, "a focus with text at any point sets it")
        let decidedAway = { () -> Bool in
            var t = ArisProvenanceTracker()
            _ = t.toolCall(id: "x", capability: "web.fetch", effect: .outward, arguments: [], publicWeb: true)
            t.toolResult("echo", source: self.page, call: "x")
            return t.readPrivate
        }()
        XCTAssertTrue(decidedAway, "a fetch decided as a send is no public read")
    }

    func testOnlyTheOwnersWordsVerbatim() {
        var tracker = ArisProvenanceTracker()
        tracker.ownerTurn("파이썬   강좌 찾아 줘")
        tracker.ownerTurn("그리고 https://example.com/page 도")
        _ = tracker.toolCall(id: "q", capability: "web.search", effect: .observe, arguments: [], publicWeb: true)
        tracker.toolResult("Python Tutorial https://docs.python.org/3/", source: page, call: "q")
        tracker.toolResult("hunter22", source: file, call: "r")
        XCTAssertNil(tracker.unaccounted(ArisOutbound(queries: ["파이썬 강좌"])), "an earlier turn's words, white space collapsed")
        XCTAssertNil(tracker.unaccounted(ArisOutbound(urls: ["https://example.com/page"])))
        XCTAssertNil(tracker.unaccounted(ArisOutbound(queries: [""])), "nothing sent")
        for query in ["파이썬 강의", "파이썬 강좌를", "파이썬 강좌 hunter22", "Python Tutorial", "PYTHON"] {
            XCTAssertNotNil(tracker.unaccounted(ArisOutbound(queries: [query])), query)
        }
        for url in ["https://docs.python.org/3/", "https://EXAMPLE.com/page", "https://example.com/page?d=x"] {
            XCTAssertNotNil(tracker.unaccounted(ArisOutbound(urls: [url])), url)
        }
    }
}
